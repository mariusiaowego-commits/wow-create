#import "AutomationEngine.h"
#import "ScreenCapture.h"
#import <ApplicationServices/ApplicationServices.h>

@interface AutomationEngine ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, copy) NSString *processName;
@property (nonatomic, strong) ScreenCapture *capture;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, assign) NSInteger waitTicks;
@property (nonatomic, strong, nullable) NSDate *lastClickDate;
@property (nonatomic, assign) NSInteger creationAbsenceTicks;
@end

@implementation AutomationEngine

- (instancetype)init {
  self = [super init];
  if (self) {
    _capture = [[ScreenCapture alloc] init];
    _stopWhenCreationScreenDisappears = YES;
  }
  return self;
}

- (void)startWithProcessName:(NSString *)processName {
  if (self.isRunning) return;
  self.processName = processName;
  self.isRunning = YES;
  self.waitTicks = 0;
  self.lastClickDate = nil;
  self.creationAbsenceTicks = 0;
  [self emit:@"已启动，等待 WoW 窗口…"];
  self.timer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                target:self
                                              selector:@selector(tick)
                                              userInfo:nil
                                               repeats:YES];
}

- (void)stop {
  if (!self.isRunning) return;
  [self stopWithStatus:@"已停止"];
}

- (void)stopWithStatus:(NSString *)status {
  if (!self.isRunning) return;
  [self.timer invalidate];
  self.timer = nil;
  self.isRunning = NO;
  [self emitStatus:status];
}

- (void)tick {
  if (!self.isRunning) return;

  WindowSnapshot *snapshot = [self.capture snapshotForProcessName:self.processName];
  if (!snapshot) {
    [self emit:@"未找到 WoW 窗口"];
    return;
  }

  CGRect doneRect = CGRectMake(0.79, 0.91, 0.18, 0.06);
  CGRect dialogRect = CGRectMake(0.42, 0.55, 0.16, 0.07);
  CGRect backRect = CGRectMake(0.035, 0.91, 0.17, 0.055);

  if ([self.capture isRect:dialogRect redDominantInImage:snapshot.image]) {
    [self emit:@"失败弹窗：按 Enter 关闭"];
    [self postKeyCode:36];
    self.waitTicks = 2;
    self.lastClickDate = nil;
    self.creationAbsenceTicks = 0;
    return;
  }

  if (self.stopWhenCreationScreenDisappears && self.lastClickDate &&
      -self.lastClickDate.timeIntervalSinceNow >= 1.0) {
    BOOL backVisible = [self.capture isRect:backRect redDominantInImage:snapshot.image];
    BOOL doneRed = [self.capture isRect:doneRect redDominantInImage:snapshot.image];
    BOOL doneGray = [self.capture isRect:doneRect grayDominantInImage:snapshot.image];
    if (!backVisible && !doneRed && !doneGray) {
      self.creationAbsenceTicks++;
      if (self.creationAbsenceTicks >= 8) {
        [self stopWithStatus:@"疑似成功：创建界面消失，已停止"];
        return;
      }
    } else {
      self.creationAbsenceTicks = 0;
    }
  }

  if (self.waitTicks > 0) {
    self.waitTicks--;
    return;
  }

  if ([self.capture isRect:doneRect redDominantInImage:snapshot.image]) {
    [self emit:@"检测到可创建：点击右下角完成"];
    CGPoint center = CGPointMake(
      snapshot.bounds.origin.x + snapshot.bounds.size.width * (doneRect.origin.x + doneRect.size.width / 2),
      snapshot.bounds.origin.y + snapshot.bounds.size.height * (doneRect.origin.y + doneRect.size.height / 2)
    );
    [self postMouseAtPoint:center];
    self.waitTicks = 4;
    self.lastClickDate = [NSDate date];
    self.creationAbsenceTicks = 0;
  } else {
    [self emit:@"完成按钮灰态/等待服务器响应"];
  }
}

- (void)postKeyCode:(CGKeyCode)keyCode {
  CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
  CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
  WindowSnapshot *target = [self.capture snapshotForProcessName:self.processName];
  if (target) {
    CGEventPostToPid(target.pid, down);
    CGEventPostToPid(target.pid, up);
  } else {
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
  }
  CFRelease(down);
  CFRelease(up);
}

- (void)postMouseAtPoint:(CGPoint)point {
  CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, point, kCGMouseButtonLeft);
  CGEventSetLocation(move, point);
  CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
  CGEventSetLocation(down, point);
  CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
  WindowSnapshot *target = [self.capture snapshotForProcessName:self.processName];
  if (target) {
    CGEventPostToPid(target.pid, move);
    CGEventPostToPid(target.pid, down);
    CGEventPostToPid(target.pid, up);
  } else {
    CGEventPost(kCGHIDEventTap, move);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
  }
  CFRelease(move);
  CFRelease(down);
  CFRelease(up);
}

- (void)emit:(NSString *)status {
  [self emitStatus:status];
}

- (void)emitStatus:(NSString *)status {
  if (self.onStateChange) self.onStateChange(self.isRunning, status);
}
@end
