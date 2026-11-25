#import "FlowEngine.h"
#import "FlowProfile.h"
#import "ScreenCapture.h"
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>

@interface FlowEngine ()
@property (atomic, assign, readwrite) BOOL isRunning;
@property (atomic, assign) BOOL typing;
@property (nonatomic, copy) NSString *processName;
@property (nonatomic, strong) ScreenCapture *capture;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, strong) dispatch_queue_t inputQueue;

@property (nonatomic, assign) FlowScreen lastScreen;
@property (nonatomic, strong, nullable) NSDate *nextActionAt;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, strong, nullable) NSDate *focusGraceUntil;
@property (nonatomic, assign) BOOL focusAcquired;
@property (nonatomic, strong, nullable) id focusObserver;
@property (nonatomic, assign) CGRect windowBounds;

@property (nonatomic, assign) NSInteger creationStep;
@property (nonatomic, assign) NSInteger namingStep;
@property (nonatomic, assign) BOOL rulePvPClicked;
@property (nonatomic, assign) BOOL dialogHandled;
@property (nonatomic, assign) BOOL singleStepPaused;
@property (nonatomic, assign, readwrite) NSInteger cycleCount;
@property (nonatomic, assign, readwrite) NSInteger failureCount;
@property (nonatomic, assign, readwrite) NSInteger actionCount;
@property (nonatomic, strong, nullable) NSDate *submittedAt;
@property (nonatomic, assign) NSInteger submitCount;

@property (nonatomic, assign) NSInteger backoutRemaining;
@property (nonatomic, assign) BOOL backoutActive;
@property (nonatomic, strong, nullable) NSDate *backoutStartedAt;
@property (nonatomic, assign) FlowScreen backoutLastScreen;
@property (nonatomic, strong, nullable) NSDate *backoutLastClickAt;
@end

static const NSInteger MaxActionCount = 400;
static const NSInteger MaxFailureCount = 40;
static const NSInteger MaxCycleCount = 30;
static const NSTimeInterval MaxRunDuration = 1800.0;

static double RandomBetween(double low, double high) {
  return low + (high - low) * (double)arc4random_uniform(10001) / 10000.0;
}

static CGKeyCode KeyCodeForCharacter(unichar character) {
  switch (character) {
    case 'a': return 0;
    case 's': return 1;
    case 'd': return 2;
    case 'f': return 3;
    case 'h': return 4;
    case 'g': return 5;
    case 'z': return 6;
    case 'x': return 7;
    case 'c': return 8;
    case 'v': return 9;
    case 'b': return 11;
    case 'q': return 12;
    case 'w': return 13;
    case 'e': return 14;
    case 'r': return 15;
    case 'y': return 16;
    case 't': return 17;
    case '1': return 18;
    case '2': return 19;
    case '3': return 20;
    case '4': return 21;
    case '6': return 22;
    case '5': return 23;
    case '=': return 24;
    case '9': return 25;
    case '7': return 26;
    case '-': return 27;
    case '8': return 28;
    case '0': return 29;
    case 'o': return 31;
    case 'u': return 32;
    case 'i': return 34;
    case 'p': return 35;
    case 'l': return 37;
    case 'j': return 38;
    case 'k': return 40;
    case 'n': return 45;
    case 'm': return 46;
    case ' ': return 49;
    default: return UINT16_MAX;
  }
}

@implementation FlowEngine

- (instancetype)init {
  self = [super init];
  if (self) {
    _capture = [[ScreenCapture alloc] init];
    _stopWhenFocusLeaves = YES;
    _mainName = @"ask";
    _secondaryName = @"timemachine";
    _inputQueue = dispatch_queue_create("local.wowcreate.input", DISPATCH_QUEUE_SERIAL);
    _lastScreen = FlowScreenUnknown;
    _backoutLastScreen = FlowScreenUnknown;
    __weak FlowEngine *weakSelf = self;
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
  self.typing = NO;
  self.lastScreen = FlowScreenUnknown;
  self.nextActionAt = nil;
  self.startedAt = [NSDate date];
  self.focusGraceUntil = [NSDate dateWithTimeIntervalSinceNow:3.0];
  self.focusAcquired = NO;
  self.creationStep = 0;
  self.namingStep = 0;
  self.rulePvPClicked = NO;
  self.dialogHandled = NO;
  self.singleStepPaused = NO;
  self.cycleCount = 0;
  self.failureCount = 0;
  self.actionCount = 0;
  self.submittedAt = nil;
  self.submitCount = 0;
  self.backoutRemaining = 0;
  self.backoutActive = NO;
  self.backoutStartedAt = nil;
  self.backoutLastScreen = FlowScreenUnknown;
  self.backoutLastClickAt = nil;
  [self emitStatus:@"已启动，等待 WoW 窗口…"];
  [self emitFlow];
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
  self.typing = NO;
  [self emitStatus:status];
}

- (void)stepOnce {
  if (!self.isRunning) return;
  self.nextActionAt = nil;
  self.singleStepPaused = NO;
  [self tick];
}

- (void)tick {
  if (!self.isRunning) return;
  if (self.startedAt && -self.startedAt.timeIntervalSinceNow >= MaxRunDuration) {
    [self stopWithStatus:[NSString stringWithFormat:@"达到最长运行时间 %.0f 分钟，已停止", MaxRunDuration / 60.0]];
    return;
  }
  if (self.typing) return;

  WindowSnapshot *snapshot = [self.capture snapshotForTargetAlias:self.processName];
  if (!snapshot) {
    [self emitStatus:@"未找到 WoW 窗口"];
    return;
  }
  self.windowBounds = snapshot.bounds;

  if (![self isTargetFrontmost]) {
    if (self.panelOpen && [self isOwnAppFrontmost]) {
      [self emitStatus:@"控制面板已打开，已暂停输入（关闭面板后自动继续）"];
      return;
    }
    if (!self.focusAcquired && self.focusGraceUntil.timeIntervalSinceNow > 0) {
      [self emitStatus:@"等待切回 WoW（3 秒后仍未切回将停止）"];
    } else if (self.stopWhenFocusLeaves) {
      [self stopWithStatus:@"WoW 失去前台焦点，已停止"];
    } else {
      [self emitStatus:@"WoW 不在前台，已暂停输入"];
    }
    return;
  }
  self.focusAcquired = YES;

  if (self.singleStepPaused) {
    [self emitStatus:@"单步模式：等待“执行一步”"];
    return;
  }
  if (self.nextActionAt && [self.nextActionAt timeIntervalSinceNow] > 0) return;

  FlowScreen screen = [self classifySnapshot:snapshot];
  FlowScreen previous = self.lastScreen;
  if (screen != previous) {
    self.lastScreen = screen;
    [self didEnterScreen:screen from:previous];
    if (!self.isRunning) return;
  }
  [self emitFlow];

  if (screen == FlowScreenUnknown) {
    [self emitStatus:@"未识别当前界面，等待…"];
    return;
  }

  if (self.submittedAt && !self.backoutActive &&
      (screen == FlowScreenCharacterList || screen == FlowScreenPvPList)) {
    [self stopWithStatus:@"疑似创建成功：已回到角色列表，已停止"];
    return;
  }

  if (self.backoutActive) {
    if (self.backoutStartedAt && -self.backoutStartedAt.timeIntervalSinceNow > 25.0) {
      [self stopWithStatus:@"失败回退超时（25 秒未回到登录界面），已停止"];
      return;
    }
    [self handleBackoutForScreen:screen];
    return;
  }

  switch (screen) {
    case FlowScreenLogin: [self handleLogin]; break;
    case FlowScreenCharacterList: [self handleCharacterList]; break;
    case FlowScreenRuleSet: [self handleRuleSet]; break;
    case FlowScreenCreation: [self handleCreation]; break;
    case FlowScreenNaming: [self handleNaming]; break;
    case FlowScreenFailureDialog: [self handleFailureDialog]; break;
    case FlowScreenPvPList: [self handlePvPList]; break;
    case FlowScreenUnknown: break;
  }
}

- (FlowScreen)classifySnapshot:(WindowSnapshot *)snapshot {
  CGImageRef image = snapshot.image;
  ScreenCapture *capture = self.capture;
  FlowRatioBlock red = ^double(CGRect rect) {
    return [capture redRatioInRect:rect image:image];
  };
  FlowRatioBlock bright = ^double(CGRect rect) {
    return [capture brightnessInRect:rect image:image];
  };
  return FlowClassifyScreen(red, bright);
}

- (void)didEnterScreen:(FlowScreen)screen from:(FlowScreen)previous {
  switch (screen) {
    case FlowScreenLogin:
      self.submittedAt = nil;
      self.backoutActive = NO;
      self.backoutRemaining = 0;
      self.backoutLastScreen = FlowScreenUnknown;
      self.cycleCount++;
      if (self.cycleCount > MaxCycleCount) {
        [self stopWithStatus:[NSString stringWithFormat:@"达到轮次上限 %ld，已停止", (long)MaxCycleCount]];
      }
      break;
    case FlowScreenRuleSet:
      self.rulePvPClicked = NO;
      break;
    case FlowScreenCreation:
      self.creationStep = 0;
      break;
    case FlowScreenNaming:
      if (previous == FlowScreenCreation) {
        self.namingStep = 0;
        self.submitCount = 0;
        self.submittedAt = nil;
      }
      break;
    case FlowScreenFailureDialog:
      self.dialogHandled = NO;
      break;
    default:
      break;
  }
}

- (void)handleLogin {
  [self clickRegion:FlowRegionLoginButton label:@"识别：登录界面 → 点击“重新连接”" cooldown:RandomBetween(4.5, 6.0)];
}

- (void)handleCharacterList {
  [self clickPoint:FlowPointRuleSetTab label:@"识别：角色列表 → 点击顶部“规则集”" cooldown:RandomBetween(2.4, 3.4)];
}

- (void)handleRuleSet {
  if (!self.rulePvPClicked) {
    self.rulePvPClicked = YES;
    [self clickPoint:FlowPointPvPCard label:@"识别：规则集选择 → 选中 PvP" cooldown:RandomBetween(0.8, 1.3)];
    return;
  }
  [self clickRegion:FlowRegionRuleSelect label:@"识别：规则集选择 → 点击“选择”" cooldown:RandomBetween(2.6, 3.6)];
}

- (void)handleCreation {
  FlowPoint points[] = {FlowPointMale, FlowPointUndead, FlowPointPriest, FlowPointCustomAppearance};
  NSString *labels[] = {
    @"识别：角色创建 → 选择男性",
    @"识别：角色创建 → 选择部落·亡灵",
    @"识别：角色创建 → 选择牧师",
    @"识别：角色创建 → 点击“自定义外观”",
  };
  NSInteger step = self.creationStep;
  if (step >= 4) {
    [self emitStatus:@"角色创建：等待界面切换…"];
    return;
  }
  self.creationStep = step + 1;
  [self clickPoint:points[step] label:labels[step] cooldown:RandomBetween(0.9, 1.5)];
}

- (void)handleNaming {
  switch (self.namingStep) {
    case 0:
      self.namingStep = 1;
      [self clickPoint:FlowPointNameMain label:@"识别：命名界面 → 点击主名输入框" cooldown:RandomBetween(0.5, 0.8)];
      break;
    case 1: {
      self.namingStep = 2;
      NSString *name = [self sanitizedName:self.mainName fallback:@"ask"];
      [self clearTextField];
      [self typeText:name];
      [self emitStatus:[NSString stringWithFormat:@"识别：命名界面 → 填写主名 %@", name]];
      [self pauseIfSingleStep];
      break;
    }
    case 2:
      self.namingStep = 3;
      [self clickPoint:FlowPointNameSecondary label:@"识别：命名界面 → 点击副名输入框" cooldown:RandomBetween(0.5, 0.8)];
      break;
    case 3: {
      self.namingStep = 4;
      NSString *name = [self sanitizedName:self.secondaryName fallback:@"timemachine"];
      [self clearTextField];
      [self typeText:name];
      [self emitStatus:[NSString stringWithFormat:@"识别：命名界面 → 填写副名 %@", name]];
      [self pauseIfSingleStep];
      break;
    }
    case 4:
      self.namingStep = 5;
      self.submitCount = 1;
      self.submittedAt = [NSDate date];
      [self clickPoint:FlowPointSubmit label:@"识别：命名界面 → 点击“完成”" cooldown:RandomBetween(2.4, 3.4)];
      break;
    default: {
      NSTimeInterval sinceSubmit = self.submittedAt ? -self.submittedAt.timeIntervalSinceNow : 999;
      if (sinceSubmit > 12 && self.submitCount < 4) {
        self.submitCount++;
        self.submittedAt = [NSDate date];
        [self clickPoint:FlowPointSubmit
                   label:[NSString stringWithFormat:@"命名界面未变化 → 重试“完成” (%ld/4)", (long)self.submitCount]
                 cooldown:RandomBetween(3.0, 4.2)];
      } else if (sinceSubmit > 10) {
        [self stopWithStatus:@"提交后界面未变化，已停止（请检查是否被其他弹窗拦截）"];
      }
      break;
    }
  }
}

- (void)handleFailureDialog {
  if (self.dialogHandled) {
    [self emitStatus:@"等待失败弹窗关闭…"];
    return;
  }
  self.dialogHandled = YES;
  self.submittedAt = nil;
  self.failureCount++;
  if (self.failureCount >= MaxFailureCount) {
    [self stopWithStatus:[NSString stringWithFormat:@"达到失败弹窗上限 %ld，已停止", (long)MaxFailureCount]];
    return;
  }
  [self clickRegion:FlowRegionDialogOk
              label:[NSString stringWithFormat:@"识别：阵营不平衡弹窗 → 点击“确定”（第 %ld 次失败）", (long)self.failureCount]
            cooldown:RandomBetween(1.8, 2.4)];
  self.backoutRemaining = 3;
  self.backoutActive = YES;
  self.backoutStartedAt = [NSDate date];
  self.backoutLastScreen = FlowScreenFailureDialog;
  self.backoutLastClickAt = [NSDate date];
}

- (void)handlePvPList {
  [self clickPoint:FlowPointRuleSetTab label:@"识别：PvP 角色列表 → 点击顶部“规则集”" cooldown:RandomBetween(2.4, 3.4)];
}

- (void)handleBackoutForScreen:(FlowScreen)screen {
  if (screen == FlowScreenLogin) {
    self.backoutActive = NO;
    self.backoutRemaining = 0;
    self.backoutLastScreen = FlowScreenUnknown;
    [self emitStatus:@"已回退到登录界面，准备下一轮"];
    return;
  }

  CGRect rect;
  NSString *label;
  switch (screen) {
    case FlowScreenNaming:
    case FlowScreenCreation:
      rect = FlowRegionRect(FlowRegionBottomLeft);
      label = @"失败回退 → 点击“后退”";
      break;
    case FlowScreenPvPList:
    case FlowScreenCharacterList:
      rect = FlowRegionRect(FlowRegionListBack);
      label = @"失败回退 → 点击“后退”";
      break;
    case FlowScreenRuleSet:
      rect = FlowRegionRect(FlowRegionRuleCancel);
      label = @"失败回退 → 点击“取消”";
      break;
    default:
      [self emitStatus:@"失败回退：等待界面切换…"];
      return;
  }

  if (screen == self.backoutLastScreen && self.backoutLastClickAt &&
      -self.backoutLastClickAt.timeIntervalSinceNow < 3.0) {
    return;
  }

  self.backoutLastScreen = screen;
  self.backoutLastClickAt = [NSDate date];
  self.backoutRemaining = MAX(0, self.backoutRemaining - 1);
  [self clickRect:rect
            label:[NSString stringWithFormat:@"%@（剩余 %ld 步）", label, (long)self.backoutRemaining]
          cooldown:RandomBetween(1.3, 1.9)];
}

- (void)clickRegion:(FlowRegion)region label:(NSString *)label cooldown:(NSTimeInterval)cooldown {
  [self clickRect:FlowRegionRect(region) label:label cooldown:cooldown];
}

- (void)clickRect:(CGRect)rect label:(NSString *)label cooldown:(NSTimeInterval)cooldown {
  CGPoint point = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
  [self clickPointValue:point label:label cooldown:cooldown];
}

- (void)clickPoint:(FlowPoint)point label:(NSString *)label cooldown:(NSTimeInterval)cooldown {
  [self clickPointValue:FlowPointValue(point) label:label cooldown:cooldown];
}

- (void)clickPointValue:(CGPoint)normalized label:(NSString *)label cooldown:(NSTimeInterval)cooldown {
  if (self.dryRun) {
    [self emitStatus:[NSString stringWithFormat:@"%@｜演练，不点击", label]];
    self.nextActionAt = [NSDate dateWithTimeIntervalSinceNow:1.6];
    return;
  }
  self.actionCount++;
  if (self.actionCount > MaxActionCount) {
    [self stopWithStatus:[NSString stringWithFormat:@"达到操作上限 %ld，已停止", (long)MaxActionCount]];
    return;
  }
  [self emitStatus:label];
  CGPoint global = CGPointMake(
    self.windowBounds.origin.x + self.windowBounds.size.width * normalized.x,
    self.windowBounds.origin.y + self.windowBounds.size.height * normalized.y
  );
  [self postMouseAtPoint:global];
  self.nextActionAt = [NSDate dateWithTimeIntervalSinceNow:cooldown];
  [self pauseIfSingleStep];
}

- (void)pauseIfSingleStep {
  if (self.singleStep && !self.dryRun) self.singleStepPaused = YES;
}

- (NSString *)sanitizedName:(NSString *)input fallback:(NSString *)fallback {
  NSMutableString *cleaned = [NSMutableString string];
  for (NSUInteger i = 0; i < input.length; i++) {
    unichar c = [input characterAtIndex:i];
    if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
      [cleaned appendFormat:@"%C", c];
    }
  }
  return cleaned.length > 0 ? cleaned : fallback;
}

- (void)clearTextField {
  if (self.dryRun) return;
  for (int i = 0; i < 16; i++) {
    [self postKeyCode:51];
    usleep(18 * 1000);
  }
  usleep(60 * 1000);
}

- (void)typeText:(NSString *)text {
  if (self.dryRun || text.length == 0) return;
  self.typing = YES;
  __weak FlowEngine *weakSelf = self;
  dispatch_async(self.inputQueue, ^{
    FlowEngine *engine = weakSelf;
    if (!engine) return;
    for (NSUInteger i = 0; i < text.length; i++) {
      if (!engine.isRunning) break;
      if (![engine isTargetFrontmost]) break;
      unichar character = [text characterAtIndex:i];
      CGKeyCode keyCode = KeyCodeForCharacter(character);
      if (keyCode == UINT16_MAX) {
        [engine postUnicodeCharacter:character];
      } else {
        [engine postKeyCode:keyCode];
      }
      usleep((useconds_t)(RandomBetween(90, 170) * 1000));
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      engine.typing = NO;
    });
  });
}

- (BOOL)isTargetFrontmost {
  NSRunningApplication *frontmost = NSWorkspace.sharedWorkspace.frontmostApplication;
  return [self applicationIsTarget:frontmost];
}

- (BOOL)applicationIsTarget:(nullable NSRunningApplication *)application {
  if (!application) return NO;
  NSArray<NSString *> *candidates = @[
    application.localizedName ?: @"",
    application.bundleIdentifier ?: @"",
    self.processName ?: @""
  ];
  for (NSString *candidate in candidates) {
    NSString *value = candidate.lowercaseString;
    if ([value containsString:@"world of warcraft"] ||
        [value containsString:@"魔兽世界"] ||
        [value isEqualToString:@"wow"]) {
      return YES;
    }
  }
  return NO;
}

- (void)handleApplicationActivation:(NSNotification *)notification {
  if (!self.isRunning) return;
  NSRunningApplication *application = notification.userInfo[NSWorkspaceApplicationKey];
  if ([self applicationIsTarget:application]) {
    self.focusAcquired = YES;
    return;
  }
  if ([self isOwnApplication:application]) return;
  if (!self.stopWhenFocusLeaves) return;
  if (self.focusAcquired || self.focusGraceUntil.timeIntervalSinceNow <= 0) {
    [self stopWithStatus:@"检测到焦点切出，已停止"];
  }
}

- (BOOL)isOwnApplication:(nullable NSRunningApplication *)application {
  if (!application) return NO;
  return [application.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier];
}

- (BOOL)isOwnAppFrontmost {
  return [self isOwnApplication:NSWorkspace.sharedWorkspace.frontmostApplication];
}

- (void)postUnicodeCharacter:(unichar)character {
  UniChar buffer[1] = {character};
  CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true);
  CGEventKeyboardSetUnicodeString(down, 1, buffer);
  CGEventRef up = CGEventCreateKeyboardEvent(NULL, 0, false);
  CGEventKeyboardSetUnicodeString(up, 1, buffer);
  CGEventPost(kCGHIDEventTap, down);
  CGEventPost(kCGHIDEventTap, up);
  CFRelease(down);
  CFRelease(up);
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
  CGPoint jittered = CGPointMake(
    point.x + ((double)arc4random_uniform(401) / 100.0 - 2.0),
    point.y + ((double)arc4random_uniform(401) / 100.0 - 2.0)
  );
  CGPoint start = jittered;
  CGEventRef current = CGEventCreate(NULL);
  if (current) {
    start = CGEventGetLocation(current);
    CFRelease(current);
  }
  const int steps = 4;
  for (int i = 1; i <= steps; i++) {
    double t = (double)i / steps;
    CGPoint step = CGPointMake(start.x + (jittered.x - start.x) * t,
                               start.y + (jittered.y - start.y) * t);
    CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, step, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, move);
    CFRelease(move);
    usleep((useconds_t)(RandomBetween(8, 16) * 1000));
  }
  CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, jittered, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, down);
  usleep((useconds_t)(RandomBetween(55, 105) * 1000));
  CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, jittered, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, up);
  CFRelease(down);
  CFRelease(up);
}

- (void)emitFlow {
  if (!self.onFlowUpdate) return;
  self.onFlowUpdate(FlowScreenName(self.lastScreen), self.cycleCount, self.failureCount, self.actionCount);
}

- (void)emitStatus:(NSString *)status {
  if (self.onStateChange) self.onStateChange(self.isRunning, status);
}

@end
