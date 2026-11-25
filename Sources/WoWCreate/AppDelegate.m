#import "AppDelegate.h"
#import "FlowEngine.h"
#import "HotKeyMonitor.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>

@interface WoWPanel : NSPanel
@end

@implementation WoWPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) FlowEngine *engine;
@property (nonatomic, strong) HotKeyMonitor *hotKey;
@property (nonatomic, strong) NSPanel *panelWindow;
@property (nonatomic, strong) NSButton *panelToggleButton;
@property (nonatomic, strong) NSTextField *panelStatusLabel;
@property (nonatomic, strong) NSTextField *panelScreenLabel;
@property (nonatomic, strong) NSTextField *panelCountersLabel;
@property (nonatomic, strong) NSTextView *panelLogView;
@property (nonatomic, strong) NSButton *dryRunCheckbox;
@property (nonatomic, strong) NSButton *singleStepCheckbox;
@property (nonatomic, strong) NSButton *stepButton;
@property (nonatomic, strong) NSTextField *mainNameField;
@property (nonatomic, strong) NSTextField *secondaryNameField;
@property (nonatomic, strong) NSButton *hotKeyButton;
@property (nonatomic, strong) NSTextField *versionLabel;
@property (nonatomic, copy) NSString *currentVersion;
@property (nonatomic, strong) NSWindow *hotKeyRecordWindow;
@property (nonatomic, strong) NSTextField *hotKeyRecordLabel;
@property (nonatomic, strong) id localKeyMonitor;
@property (nonatomic, strong) id globalKeyMonitor;
@property (nonatomic, strong) id panelDismissMonitor;
@property (nonatomic, strong) id appActivationObserver;
@property (nonatomic, copy, nullable) NSString *lastStatus;
@property (nonatomic, assign) BOOL pendingShowActivating;
@property (nonatomic, assign) NSInteger pendingShowAttempts;
@property (nonatomic, assign) BOOL anchorToClickPoint;
@end

static UInt32 CarbonModifiersFromEvent(NSEvent *event) {
  NSUInteger flags = event.modifierFlags;
  UInt32 modifiers = 0;
  if (flags & NSEventModifierFlagCommand) modifiers |= cmdKey;
  if (flags & NSEventModifierFlagOption) modifiers |= optionKey;
  if (flags & NSEventModifierFlagControl) modifiers |= controlKey;
  if (flags & NSEventModifierFlagShift) modifiers |= shiftKey;
  return modifiers;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  self.statusItem.button.toolTip = @"WoWCreate - 点击打开控制面板";
  self.statusItem.button.target = self;
  self.statusItem.button.action = @selector(togglePanel);
  [self updateStatusIconRunning:NO];

  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  UInt32 keyCode = (UInt32)[defaults integerForKey:@"StopHotKeyV2KeyCode"];
  if (keyCode == 0) keyCode = kVK_ANSI_K;
  UInt32 modifiers = (UInt32)[defaults integerForKey:@"StopHotKeyV2Modifiers"];
  if (modifiers == 0) modifiers = controlKey | optionKey | cmdKey | shiftKey;

  self.engine = [[FlowEngine alloc] init];
  __weak AppDelegate *weakSelf = self;
  self.engine.onStateChange = ^(BOOL running, NSString *status) {
    dispatch_async(dispatch_get_main_queue(), ^{
      weakSelf.panelToggleButton.title = running ? @"停止自动化" : @"开启自动化";
      weakSelf.panelStatusLabel.stringValue = [NSString stringWithFormat:@"状态：%@", status];
      [weakSelf updateStatusIconRunning:running];
      weakSelf.stepButton.enabled = running && weakSelf.engine.singleStep;
      if (![status isEqualToString:weakSelf.lastStatus]) {
        weakSelf.lastStatus = status;
        [weakSelf appendLog:status];
      }
    });
  };
  self.engine.onFlowUpdate = ^(NSString *screenName, NSInteger cycle, NSInteger failures, NSInteger actions) {
    dispatch_async(dispatch_get_main_queue(), ^{
      weakSelf.panelScreenLabel.stringValue = [NSString stringWithFormat:@"识别：%@", screenName];
      weakSelf.panelCountersLabel.stringValue =
        [NSString stringWithFormat:@"第 %ld 轮 · 失败 %ld · 操作 %ld",
                                   (long)cycle, (long)failures, (long)actions];
    });
  };

  self.hotKey = [[HotKeyMonitor alloc] initWithKeyCode:keyCode modifiers:modifiers];
  self.hotKey.onStop = ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf.engine stop];
    });
  };
  [self.hotKey start];

  self.currentVersion = [self versionStringFromInfo:NSBundle.mainBundle.infoDictionary];
  self.appActivationObserver = [NSWorkspace.sharedWorkspace.notificationCenter
    addObserverForName:NSWorkspaceDidActivateApplicationNotification
    object:nil
    queue:NSOperationQueue.mainQueue
    usingBlock:^(NSNotification *note) {
      NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
      if (app.bundleIdentifier && ![app.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier] &&
          weakSelf.panelWindow.isVisible) {
        [weakSelf hidePanel];
      }
    }];

  [self showPanelActivating:NO];
}

- (void)updateStatusIconRunning:(BOOL)running {
  NSImage *image = [NSImage imageWithSystemSymbolName:(running ? @"w.circle.fill" : @"w.circle")
                             accessibilityDescription:@"WoWCreate"];
  image.template = YES;
  self.statusItem.button.image = image;
  self.statusItem.button.imagePosition = NSImageOnly;
  self.statusItem.button.toolTip = running ? @"WoWCreate - 自动化运行中" : @"WoWCreate - 点击打开控制面板";
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  (void)notification;
  if (self.appActivationObserver) {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self.appActivationObserver];
  }
  [self removePanelDismissMonitor];
  [self.engine stop];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
  (void)sender;
  (void)hasVisibleWindows;
  [self showPanel];
  return YES;
}

- (void)buildPanelIfNeeded {
  if (self.panelWindow) return;

  WoWPanel *panel = [[WoWPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 520)
                                                styleMask:NSWindowStyleMaskBorderless |
                                                          NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  panel.opaque = NO;
  panel.backgroundColor = NSColor.clearColor;
  panel.hasShadow = YES;
  panel.delegate = self;
  panel.becomesKeyOnlyIfNeeded = YES;
  panel.floatingPanel = YES;
  panel.hidesOnDeactivate = NO;

  NSView *content = panel.contentView;
  content.wantsLayer = YES;
  content.layer.cornerRadius = 12;
  content.layer.masksToBounds = YES;
  content.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
  content.layer.borderWidth = 1;
  content.layer.borderColor = NSColor.separatorColor.CGColor;
  CGFloat width = 480;

  self.panelToggleButton = [NSButton buttonWithTitle:@"开启自动化" target:self action:@selector(toggleAutomation:)];
  self.panelToggleButton.frame = NSMakeRect(20, 472, 140, 32);
  self.panelToggleButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.panelToggleButton];

  self.hotKeyButton = [NSButton buttonWithTitle:@"停止键" target:self action:@selector(changeStopHotKey:)];
  self.hotKeyButton.frame = NSMakeRect(168, 472, 192, 32);
  self.hotKeyButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.hotKeyButton];
  [self updateHotKeyButton];

  NSButton *quitButton = [NSButton buttonWithTitle:@"退出" target:self action:@selector(quitApp:)];
  quitButton.frame = NSMakeRect(width - 80, 472, 60, 32);
  quitButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:quitButton];

  self.panelStatusLabel = [NSTextField labelWithString:@"状态：已停止"];
  self.panelStatusLabel.frame = NSMakeRect(20, 444, width - 40, 20);
  self.panelStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [content addSubview:self.panelStatusLabel];

  self.panelScreenLabel = [NSTextField labelWithString:@"识别：等待启动"];
  self.panelScreenLabel.frame = NSMakeRect(20, 420, 210, 20);
  self.panelScreenLabel.font = [NSFont systemFontOfSize:12];
  self.panelScreenLabel.textColor = [NSColor secondaryLabelColor];
  [content addSubview:self.panelScreenLabel];

  self.panelCountersLabel = [NSTextField labelWithString:@"第 0 轮 · 失败 0 · 操作 0"];
  self.panelCountersLabel.frame = NSMakeRect(230, 420, width - 250, 20);
  self.panelCountersLabel.alignment = NSTextAlignmentRight;
  self.panelCountersLabel.font = [NSFont systemFontOfSize:12];
  self.panelCountersLabel.textColor = [NSColor secondaryLabelColor];
  [content addSubview:self.panelCountersLabel];

  NSTextField *mainLabel = [NSTextField labelWithString:@"主名"];
  mainLabel.frame = NSMakeRect(20, 391, 34, 18);
  [content addSubview:mainLabel];
  self.mainNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(56, 386, 120, 24)];
  self.mainNameField.stringValue = [NSUserDefaults.standardUserDefaults stringForKey:@"MainName"] ?: @"ask";
  self.mainNameField.placeholderString = @"ask";
  [content addSubview:self.mainNameField];

  NSTextField *secondaryLabel = [NSTextField labelWithString:@"副名"];
  secondaryLabel.frame = NSMakeRect(196, 391, 34, 18);
  [content addSubview:secondaryLabel];
  self.secondaryNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(232, 386, 180, 24)];
  self.secondaryNameField.stringValue = [NSUserDefaults.standardUserDefaults stringForKey:@"SecondaryName"] ?: @"timemachine";
  self.secondaryNameField.placeholderString = @"timemachine";
  [content addSubview:self.secondaryNameField];

  self.dryRunCheckbox = [NSButton checkboxWithTitle:@"演练（不点击）" target:self action:@selector(toggleDryRun:)];
  self.dryRunCheckbox.frame = NSMakeRect(20, 356, 130, 20);
  self.dryRunCheckbox.state = NSControlStateValueOff;
  [content addSubview:self.dryRunCheckbox];

  self.singleStepCheckbox = [NSButton checkboxWithTitle:@"单步模式" target:self action:@selector(toggleSingleStep:)];
  self.singleStepCheckbox.frame = NSMakeRect(154, 356, 100, 20);
  self.singleStepCheckbox.state = NSControlStateValueOff;
  [content addSubview:self.singleStepCheckbox];

  self.stepButton = [NSButton buttonWithTitle:@"执行一步" target:self action:@selector(stepOnce:)];
  self.stepButton.frame = NSMakeRect(width - 140, 350, 120, 28);
  self.stepButton.bezelStyle = NSBezelStyleRounded;
  self.stepButton.enabled = NO;
  [content addSubview:self.stepButton];

  NSTextField *hint = [NSTextField labelWithString:
    @"仅 WoW 前台时操作，切出焦点立即停止。默认停止键 ⌃⌥⌘⇧K，可在上方重录。\n上限：30 轮 / 40 次失败 / 30 分钟；不会读取或保存账号密码。"];
  hint.frame = NSMakeRect(20, 308, width - 40, 36);
  hint.font = [NSFont systemFontOfSize:11];
  hint.textColor = [NSColor secondaryLabelColor];
  hint.lineBreakMode = NSLineBreakByWordWrapping;
  hint.maximumNumberOfLines = 2;
  [content addSubview:hint];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 40, width - 40, 248)];
  scroll.hasVerticalScroller = YES;
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scroll.borderType = NSBezelBorder;

  NSTextView *logView = [[NSTextView alloc] initWithFrame:scroll.bounds];
  logView.editable = NO;
  logView.selectable = YES;
  logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
  logView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scroll.documentView = logView;
  [content addSubview:scroll];

  self.panelLogView = logView;
  self.versionLabel = [NSTextField labelWithString:@"版本：读取中…"];
  self.versionLabel.frame = NSMakeRect(20, 8, width - 40, 28);
  self.versionLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
  self.versionLabel.textColor = [NSColor secondaryLabelColor];
  self.versionLabel.maximumNumberOfLines = 2;
  self.versionLabel.lineBreakMode = NSLineBreakByWordWrapping;
  [content addSubview:self.versionLabel];
  self.panelWindow = panel;
}

- (BOOL)anchorPanelToStatusItem {
  NSRect panelFrame = self.panelWindow.frame;
  NSPoint anchorPoint = NSZeroPoint;
  NSScreen *screen = nil;
  if (self.anchorToClickPoint) {
    anchorPoint = NSEvent.mouseLocation;
    for (NSScreen *candidate in NSScreen.screens) {
      if (NSPointInRect(anchorPoint, candidate.frame) &&
          anchorPoint.y > NSMaxY(candidate.visibleFrame)) {
        screen = candidate;
        break;
      }
    }
    if (!screen) anchorPoint = NSZeroPoint;
  }
  if (!screen) {
    NSWindow *statusWindow = self.statusItem.button.window;
    if (!statusWindow) return NO;
    NSRect buttonRect = [self.statusItem.button convertRect:self.statusItem.button.bounds toView:nil];
    NSRect statusFrame = [statusWindow convertRectToScreen:buttonRect];
    NSPoint statusMid = NSMakePoint(NSMidX(statusFrame), NSMidY(statusFrame));
    NSScreen *statusScreen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
      if (NSPointInRect(statusMid, candidate.frame)) {
        statusScreen = candidate;
        break;
      }
    }
    if (!statusScreen) return NO;
    screen = statusScreen;
    NSPoint mouse = NSEvent.mouseLocation;
    for (NSScreen *candidate in NSScreen.screens) {
      if (NSPointInRect(mouse, candidate.frame)) {
        screen = candidate;
        break;
      }
    }
    CGFloat localX = NSMidX(statusFrame) - NSMinX(statusScreen.frame);
    anchorPoint = NSMakePoint(NSMinX(screen.frame) + localX, NSMinY(statusFrame));
  }

  NSRect screenFrame = screen.visibleFrame;
  CGFloat x = anchorPoint.x - NSWidth(panelFrame) / 2;
  CGFloat y = NSMaxY(screenFrame) - NSHeight(panelFrame) - 4;
  x = MAX(NSMinX(screenFrame), MIN(x, NSMaxX(screenFrame) - NSWidth(panelFrame)));
  y = MAX(NSMinY(screenFrame), y);
  [self.panelWindow setFrameOrigin:NSMakePoint(x, y)];
  return YES;
}

- (NSRect)statusItemScreenRect {
  NSWindow *statusWindow = self.statusItem.button.window;
  if (!statusWindow) return NSZeroRect;
  NSRect buttonRect = [self.statusItem.button convertRect:self.statusItem.button.bounds toView:nil];
  return [statusWindow convertRectToScreen:buttonRect];
}

- (void)togglePanel {
  if (self.panelWindow.isVisible) {
    [self hidePanel];
  } else {
    self.anchorToClickPoint = YES;
    [self showPanel];
    self.anchorToClickPoint = NO;
  }
}

- (void)showPanel {
  [self showPanelActivating:YES];
}

- (void)showPanelActivating:(BOOL)activating {
  [self buildPanelIfNeeded];
  self.engine.panelOpen = YES;
  [self refreshVersionInfo];
  if (![self anchorPanelToStatusItem]) {
    [self.panelWindow orderOut:nil];
    self.pendingShowActivating = activating;
    self.pendingShowAttempts = 0;
    [self schedulePendingShow];
    return;
  }
  self.pendingShowAttempts = 0;
  if (self.engine.isRunning) {
    [self.panelWindow orderFrontRegardless];
  } else if (activating) {
    [self.panelWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  } else {
    [self.panelWindow orderFrontRegardless];
  }
  [self installPanelDismissMonitor];
  [self scheduleReanchor];
}

- (void)schedulePendingShow {
  if (self.pendingShowAttempts >= 40) return;
  self.pendingShowAttempts += 1;
  __weak AppDelegate *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    AppDelegate *strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.pendingShowAttempts) return;
    if ([strongSelf anchorPanelToStatusItem]) {
      BOOL activating = strongSelf.pendingShowActivating;
      strongSelf.pendingShowAttempts = 0;
      if (strongSelf.engine.isRunning || !activating) {
        [strongSelf.panelWindow orderFrontRegardless];
      } else {
        [strongSelf.panelWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
      }
      [strongSelf installPanelDismissMonitor];
      [strongSelf scheduleReanchor];
    } else {
      [strongSelf schedulePendingShow];
    }
  });
}

- (void)scheduleReanchor {
  __weak AppDelegate *weakSelf = self;
  for (NSNumber *delay in @[@0.2, @0.6, @1.2]) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      AppDelegate *strongSelf = weakSelf;
      if (!strongSelf || !strongSelf.panelWindow.isVisible) return;
      [strongSelf anchorPanelToStatusItem];
    });
  }
}

- (void)hidePanel {
  self.pendingShowAttempts = 0;
  [self removePanelDismissMonitor];
  [self.panelWindow orderOut:nil];
  self.engine.panelOpen = NO;
  if (self.engine.isRunning && NSApp.isActive) {
    [self activateTargetApplication];
  }
}

- (void)installPanelDismissMonitor {
  if (self.panelDismissMonitor) return;
  __weak AppDelegate *weakSelf = self;
  self.panelDismissMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown |
                                                                          NSEventMaskRightMouseDown
                                                                   handler:^(NSEvent *event) {
    (void)event;
    dispatch_async(dispatch_get_main_queue(), ^{
      AppDelegate *strongSelf = weakSelf;
      if (!strongSelf || !strongSelf.panelWindow.isVisible) return;
      NSPoint mouse = NSEvent.mouseLocation;
      if (NSPointInRect(mouse, strongSelf.panelWindow.frame)) return;
      NSRect statusRect = [strongSelf statusItemScreenRect];
      if (!NSIsEmptyRect(statusRect) && NSPointInRect(mouse, statusRect)) return;
      [strongSelf hidePanel];
    });
  }];
}

- (void)removePanelDismissMonitor {
  if (!self.panelDismissMonitor) return;
  [NSEvent removeMonitor:self.panelDismissMonitor];
  self.panelDismissMonitor = nil;
}

- (void)windowDidResignKey:(NSNotification *)notification {
  if (notification.object != self.panelWindow) return;
  if (self.hotKeyRecordWindow && self.hotKeyRecordWindow.isVisible) return;
  NSRect statusRect = [self statusItemScreenRect];
  if (!NSIsEmptyRect(statusRect) && NSPointInRect(NSEvent.mouseLocation, statusRect)) return;
  [self hidePanel];
}

- (NSString *)versionStringFromInfo:(NSDictionary *)info {
  NSString *version = info[@"CFBundleShortVersionString"] ?: @"?";
  NSString *build = info[@"CFBundleVersion"] ?: @"?";
  NSString *time = info[@"WoWCreateBuildTime"] ?: @"?";
  return [NSString stringWithFormat:@"v%@ · %@ · %@", version, build, time];
}

- (void)refreshVersionInfo {
  if (!self.versionLabel) return;
  if (!self.currentVersion) {
    self.currentVersion = [self versionStringFromInfo:NSBundle.mainBundle.infoDictionary];
  }
  NSString *plistPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"];
  NSDictionary *diskInfo = [NSDictionary dictionaryWithContentsOfFile:plistPath];
  NSMutableString *text = [NSMutableString stringWithFormat:@"当前  %@", self.currentVersion];
  if (!diskInfo) {
    [text appendString:@"\n磁盘  读取失败（可能正在重建）"];
    self.versionLabel.textColor = [NSColor systemOrangeColor];
  } else {
    NSString *diskVersion = [self versionStringFromInfo:diskInfo];
    if ([diskVersion isEqualToString:self.currentVersion]) {
      [text appendFormat:@"\n磁盘  %@  ✓ 已是最新", diskVersion];
      self.versionLabel.textColor = [NSColor secondaryLabelColor];
    } else {
      [text appendFormat:@"\n磁盘  %@  ⚠ 已更新，重启 App", diskVersion];
      self.versionLabel.textColor = [NSColor systemOrangeColor];
    }
  }
  self.versionLabel.stringValue = text;
}

- (void)appendLog:(NSString *)message {
  if (!self.panelLogView || !message) return;
  NSString *line = [NSString stringWithFormat:@"%@  %@\n",
                    [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                  dateStyle:NSDateFormatterNoStyle
                                                  timeStyle:NSDateFormatterMediumStyle],
                    message];
  [self.panelLogView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:line]];
  [self.panelLogView scrollToEndOfDocument:nil];
}

- (void)toggleDryRun:(id)sender {
  (void)sender;
  self.engine.dryRun = self.dryRunCheckbox.state == NSControlStateValueOn;
}

- (void)toggleSingleStep:(id)sender {
  (void)sender;
  self.engine.singleStep = self.singleStepCheckbox.state == NSControlStateValueOn;
  self.stepButton.enabled = self.engine.isRunning && self.engine.singleStep;
}

- (void)stepOnce:(id)sender {
  (void)sender;
  [self.engine stepOnce];
}

- (void)toggleAutomation:(id)sender {
  (void)sender;
  if (self.engine.isRunning) {
    [self.engine stop];
    return;
  }

  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:self.mainNameField.stringValue forKey:@"MainName"];
  [defaults setObject:self.secondaryNameField.stringValue forKey:@"SecondaryName"];
  [defaults synchronize];

  self.engine.mainName = self.mainNameField.stringValue;
  self.engine.secondaryName = self.secondaryNameField.stringValue;
  self.engine.dryRun = self.dryRunCheckbox.state == NSControlStateValueOn;
  self.engine.singleStep = self.singleStepCheckbox.state == NSControlStateValueOn;
  self.stepButton.enabled = self.engine.singleStep;

  if (!AXIsProcessTrusted()) {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    [self appendLog:@"缺少辅助功能权限，已弹出系统授权提示。勾选 WoWCreate 后再点“开启自动化”"];
    return;
  }
  if (!CGPreflightScreenCaptureAccess()) {
    CGRequestScreenCaptureAccess();
    [self appendLog:@"缺少屏幕录制权限，已弹出系统授权提示。授权后请重启 App"];
    return;
  }

  [self activateTargetApplication];
  self.engine.panelOpen = NO;
  [self.panelWindow orderOut:nil];
  [self.engine startWithProcessName:@"World of Warcraft"];
}

- (void)activateTargetApplication {
  for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
    NSString *name = application.localizedName.lowercaseString ?: @"";
    if ([name containsString:@"world of warcraft"] ||
        [name containsString:@"魔兽世界"] ||
        [name isEqualToString:@"wow"]) {
      [application unhide];
      if (@available(macOS 14.0, *)) {
        [application activateFromApplication:NSRunningApplication.currentApplication options:0];
      } else {
        [application activateWithOptions:NSApplicationActivateIgnoringOtherApps];
      }
      return;
    }
  }
}

- (void)updateHotKeyButton {
  if (!self.hotKeyButton || !self.hotKey) return;
  NSString *display = [HotKeyMonitor displayStringForKeyCode:self.hotKey.keyCode modifiers:self.hotKey.modifiers];
  self.hotKeyButton.title = [NSString stringWithFormat:@"停止键：%@", display];
}

- (void)changeStopHotKey:(id)sender {
  (void)sender;
  [self stopHotKeyRecordingMonitors];

  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 130)
                                                 styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  window.title = @"设置全局停止键";
  window.delegate = self;

  NSTextField *label = [NSTextField labelWithString:@"按下新组合键（Esc 取消）"];
  label.frame = NSMakeRect(20, 76, 340, 34);
  label.lineBreakMode = NSLineBreakByWordWrapping;
  [[window contentView] addSubview:label];

  NSTextField *note = [NSTextField labelWithString:@"至少包含 Command / Control / Option 之一"];
  note.frame = NSMakeRect(20, 48, 340, 18);
  note.font = [NSFont systemFontOfSize:11];
  note.textColor = [NSColor secondaryLabelColor];
  [[window contentView] addSubview:note];

  self.hotKeyRecordWindow = window;
  self.hotKeyRecordLabel = label;
  [window center];
  [window makeKeyAndOrderFront:nil];

  __weak AppDelegate *weakSelf = self;
  self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    if ([weakSelf handleRecordedKeyEvent:event]) return nil;
    return event;
  }];
  self.globalKeyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) {
    [weakSelf handleRecordedKeyEvent:event];
  }];
}

- (BOOL)handleRecordedKeyEvent:(NSEvent *)event {
  if (!self.hotKeyRecordWindow.isVisible) return NO;

  UInt32 keyCode = (UInt32)event.keyCode;
  if (keyCode == kVK_Escape) {
    [self cancelHotKeyRecording];
    return YES;
  }

  UInt32 modifiers = CarbonModifiersFromEvent(event);
  if (!(modifiers & (controlKey | optionKey | cmdKey))) {
    self.hotKeyRecordLabel.stringValue = @"请至少带 Command / Control / Option，再按一次";
    return YES;
  }

  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setInteger:(NSInteger)keyCode forKey:@"StopHotKeyV2KeyCode"];
  [defaults setInteger:(NSInteger)modifiers forKey:@"StopHotKeyV2Modifiers"];
  [defaults synchronize];
  [self.hotKey setKeyCode:keyCode modifiers:modifiers];
  [self updateHotKeyButton];
  [self appendLog:[NSString stringWithFormat:@"全局停止键已改为 %@",
                   [HotKeyMonitor displayStringForKeyCode:keyCode modifiers:modifiers]]];
  [self cancelHotKeyRecording];
  return YES;
}

- (void)stopHotKeyRecordingMonitors {
  if (self.localKeyMonitor) {
    [NSEvent removeMonitor:self.localKeyMonitor];
    self.localKeyMonitor = nil;
  }
  if (self.globalKeyMonitor) {
    [NSEvent removeMonitor:self.globalKeyMonitor];
    self.globalKeyMonitor = nil;
  }
}

- (void)cancelHotKeyRecording {
  [self stopHotKeyRecordingMonitors];
  [self.hotKeyRecordWindow orderOut:nil];
  self.hotKeyRecordWindow = nil;
  self.hotKeyRecordLabel = nil;
}

- (void)quitApp:(id)sender {
  (void)sender;
  [NSApp terminate:nil];
}

- (BOOL)windowShouldClose:(NSWindow *)window {
  if (window == self.hotKeyRecordWindow) {
    [self cancelHotKeyRecording];
    return NO;
  }
  [self hidePanel];
  return NO;
}
@end
