#import "AutomationEngine.h"
#import "ScreenCapture.h"
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>

@interface AutomationEngine ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, copy) NSString *processName;
@property (nonatomic, strong) ScreenCapture *capture;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, assign) NSInteger waitTicks;
@property (nonatomic, strong, nullable) NSDate *lastClickDate;
@property (nonatomic, assign) NSInteger creationAbsenceTicks;
@property (nonatomic, assign) NSInteger actionCount;
@property (nonatomic, assign) NSInteger dialogCount;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, strong, nullable) NSDate *nextActionAllowedAt;
@property (nonatomic, assign) BOOL awaitingConfirmation;
@property (nonatomic, copy, nullable) NSString *pendingActionKind;
@property (nonatomic, copy, nullable) NSString *confirmedActionKind;
@property (nonatomic, strong, nullable) id focusObserver;
@property (nonatomic, assign) BOOL focusAcquired;
@property (nonatomic, strong, nullable) NSDate *focusGraceUntil;
@end

static const NSInteger MaxActionCount = 20;
static const NSInteger MaxDialogCount = 12;
static const NSTimeInterval MaxRunDuration = 300.0;
static const NSTimeInterval MinActionInterval = 0.8;
static const NSTimeInterval MaxActionInterval = 2.2;

@implementation AutomationEngine

- (instancetype)init {
  self = [super init];
  if (self) {
    _capture = [[ScreenCapture alloc] init];
    _stopWhenCreationScreenDisappears = YES;
    _requireManualConfirmation = NO;
    _stopWhenFocusLeaves = YES;
    __weak AutomationEngine *weakSelf = self;
    _focusObserver = [NSWorkspace.sharedWorkspace.notificationCenter
      addObserverForName:NSWorkspaceDidActivateApplicationNotification
      object:nil
      queue:NSOperationQueue.mainQueue
      usingBlock:^(NSNotification *note) {
        [weakSelf handleApplicationActivation:note];
      }];
  }
  return self;
}

- (void)dealloc {
  if (_focusObserver) {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_focusObserver];
  }
}

- (void)startWithProcessName:(NSString *)processName {
  if (self.isRunning) return;
  self.processName = processName;
  self.isRunning = YES;
  self.waitTicks = 0;
  self.lastClickDate = nil;
  self.creationAbsenceTicks = 0;
  self.actionCount = 0;
  self.dialogCount = 0;
  self.startedAt = [NSDate date];
  self.nextActionAllowedAt = nil;
  self.awaitingConfirmation = NO;
  self.pendingActionKind = nil;
  self.confirmedActionKind = nil;
  self.focusAcquired = NO;
  self.focusGraceUntil = [NSDate dateWithTimeIntervalSinceNow:3.0];
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

  if (self.startedAt && -self.startedAt.timeIntervalSinceNow >= MaxRunDuration) {
    [self stopWithStatus:[NSString stringWithFormat:@"达到最长运行时间 %.0f 秒，已停止", MaxRunDuration]];
    return;
  }

  WindowSnapshot *snapshot = [self.capture snapshotForProcessName:self.processName];
  if (!snapshot) {
    [self emit:@"未找到 WoW 窗口"];
    return;
  }

  if (![self isTargetFrontmost]) {
    if (!self.focusAcquired && self.focusGraceUntil.timeIntervalSinceNow > 0) {
      [self emit:@"等待切回 WoW 创建界面（3 秒后仍未切回将停止）"];
    } else if (self.stopWhenFocusLeaves) {
      [self stopWithStatus:@"WoW 失去前台焦点，已停止"];
    } else {
      [self emit:@"WoW 不在前台，已暂停输入"];
    }
    return;
  }
  self.focusAcquired = YES;

  CGRect doneRect = CGRectMake(0.79, 0.91, 0.18, 0.06);
  CGRect dialogRect = CGRectMake(0.42, 0.55, 0.16, 0.07);
  CGRect backRect = CGRectMake(0.035, 0.91, 0.17, 0.055);

  if (self.awaitingConfirmation && !self.confirmedActionKind) {
    [self emit:@"等待你按“确认下一步”"];
    return;
  }

  if ([self.capture isRect:dialogRect redDominantInImage:snapshot.image]) {
    if ([self canActNow:@"dialog" displayText:@"检测到失败弹窗"]) {
      [self emit:@"失败弹窗：按 Enter 关闭"];
      [self postKeyCode:36];
      self.dialogCount++;
      self.waitTicks = [self randomWaitTicks];
      self.lastClickDate = nil;
      self.creationAbsenceTicks = 0;
      self.pendingActionKind = nil;
      self.confirmedActionKind = nil;
      if (self.dialogCount >= MaxDialogCount) {
        [self stopWithStatus:[NSString stringWithFormat:@"达到失败弹窗上限 %ld，已停止", (long)MaxDialogCount]];
      }
    }
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

  if (self.waitTicks > 0 || (self.nextActionAllowedAt && [self.nextActionAllowedAt timeIntervalSinceNow] > 0)) {
    if (self.waitTicks > 0) self.waitTicks--;
    return;
  }

  if ([self.capture isRect:doneRect redDominantInImage:snapshot.image]) {
    if (![self canActNow:@"done" displayText:@"检测到可创建按钮"]) return;
    [self emit:@"检测到可创建：点击右下角完成"];
    CGPoint center = CGPointMake(
      snapshot.bounds.origin.x + snapshot.bounds.size.width * (doneRect.origin.x + doneRect.size.width / 2),
      snapshot.bounds.origin.y + snapshot.bounds.size.height * (doneRect.origin.y + doneRect.size.height / 2)
    );
    CGPoint jittered = CGPointMake(
      center.x + ((arc4random_uniform(9) - 4) * 0.5),
      center.y + ((arc4random_uniform(9) - 4) * 0.5)
    );
    [self postMouseAtPoint:jittered];
    self.actionCount++;
    self.waitTicks = [self randomWaitTicks];
    self.nextActionAllowedAt = [NSDate dateWithTimeIntervalSinceNow:MinActionInterval + arc4random_uniform((uint32_t)((MaxActionInterval - MinActionInterval) * 100)) / 100.0];
    self.lastClickDate = [NSDate date];
    self.creationAbsenceTicks = 0;
    self.awaitingConfirmation = NO;
    self.pendingActionKind = nil;
    self.confirmedActionKind = nil;
    if (self.actionCount >= MaxActionCount) {
      [self stopWithStatus:[NSString stringWithFormat:@"达到点击上限 %ld，已停止", (long)MaxActionCount]];
    }
  } else {
    [self emit:@"完成按钮灰态/等待服务器响应"];
  }
}

- (BOOL)canActNow:(NSString *)kind displayText:(NSString *)displayText {
  if (self.requireManualConfirmation) {
    if (self.confirmedActionKind && [self.confirmedActionKind isEqualToString:kind]) {
      self.confirmedActionKind = nil;
      self.awaitingConfirmation = NO;
      self.pendingActionKind = nil;
      return YES;
    }
    if (!self.pendingActionKind) {
      self.awaitingConfirmation = YES;
      self.pendingActionKind = kind;
      self.confirmedActionKind = nil;
      [self emit:[NSString stringWithFormat:@"%@；不会自动执行，请确认", displayText]];
    }
    return NO;
  }
  if (self.nextActionAllowedAt && [self.nextActionAllowedAt timeIntervalSinceNow] > 0) return NO;
  return YES;
}

- (void)confirmNextAction {
  if (!self.awaitingConfirmation) return;
  NSString *kind = self.pendingActionKind ?: @"任意动作";
  self.confirmedActionKind = kind;
  self.awaitingConfirmation = NO;
  [self emit:[NSString stringWithFormat:@"已确认：%@ 将执行一次", kind]];
}

- (BOOL)hasPendingConfirmation {
  return self.awaitingConfirmation;
}

- (BOOL)isTargetFrontmost {
  NSRunningApplication *frontmost = NSWorkspace.sharedWorkspace.frontmostApplication;
  return [self applicationIsTarget:frontmost];
}

- (BOOL)applicationIsTarget:(nullable NSRunningApplication *)application {
  if (!application) return NO;
  return [application.localizedName caseInsensitiveCompare:self.processName] == NSOrderedSame ||
         [application.bundleIdentifier caseInsensitiveCompare:self.processName] == NSOrderedSame;
}

- (void)handleApplicationActivation:(NSNotification *)notification {
  if (!self.isRunning) return;
  NSRunningApplication *application = notification.userInfo[NSWorkspaceApplicationKey];
  if ([self applicationIsTarget:application]) {
    self.focusAcquired = YES;
    return;
  }
  if (!self.stopWhenFocusLeaves) return;
  if (self.focusAcquired || self.focusGraceUntil.timeIntervalSinceNow <= 0) {
    [self stopWithStatus:@"检测到焦点切出，已停止"];
  }
}

- (NSInteger)randomWaitTicks {
  return 3 + arc4random_uniform(4);
}

- (void)postKeyCode:(CGKeyCode)keyCode {
  CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
  CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
  CGEventPost(kCGHIDEventTap, down);
  CGEventPost(kCGHIDEventTap, up);
  CFRelease(down);
  CFRelease(up);
}

- (void)postMouseAtPoint:(CGPoint)point {
  CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, point, kCGMouseButtonLeft);
  CGEventSetLocation(move, point);
  CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
  CGEventSetLocation(down, point);
  CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, move);
  CGEventPost(kCGHIDEventTap, down);
  CGEventPost(kCGHIDEventTap, up);
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
