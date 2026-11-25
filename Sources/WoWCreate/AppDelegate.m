#import "AppDelegate.h"
#import "AutomationEngine.h"
#import "HotKeyMonitor.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) AutomationEngine *engine;
@property (nonatomic, strong) HotKeyMonitor *hotKey;
@property (nonatomic, strong) NSWindow *panelWindow;
@property (nonatomic, strong) NSButton *panelToggleButton;
@property (nonatomic, strong) NSTextField *panelStatusLabel;
@property (nonatomic, strong) NSTextView *panelLogView;
@property (nonatomic, strong) NSButton *successDetectionCheckbox;
@property (nonatomic, strong) NSButton *manualConfirmationCheckbox;
@property (nonatomic, strong) NSButton *confirmButton;
@property (nonatomic, strong) NSButton *hotKeyButton;
@property (nonatomic, strong) NSWindow *hotKeyRecordWindow;
@property (nonatomic, strong) NSTextField *hotKeyRecordLabel;
@property (nonatomic, strong) id localKeyMonitor;
@property (nonatomic, strong) id globalKeyMonitor;
@property (nonatomic, copy, nullable) NSString *lastStatus;
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
  self.statusItem.button.title = @"W";
  self.statusItem.button.toolTip = @"WoWCreate - 点击打开控制面板";
  self.statusItem.button.target = self;
  self.statusItem.button.action = @selector(showPanel);

  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  UInt32 keyCode = (UInt32)[defaults integerForKey:@"StopHotKeyKeyCode"];
  if (keyCode == 0) keyCode = kVK_ANSI_K;
  UInt32 modifiers = (UInt32)[defaults integerForKey:@"StopHotKeyModifiers"];
  if (modifiers == 0) modifiers = controlKey | optionKey | cmdKey;

  self.engine = [[AutomationEngine alloc] init];
  self.engine.stopWhenCreationScreenDisappears = YES;
  self.engine.requireManualConfirmation = NO;
  self.engine.stopWhenFocusLeaves = YES;
  __weak AppDelegate *weakSelf = self;
  self.engine.onStateChange = ^(BOOL running, NSString *status) {
    dispatch_async(dispatch_get_main_queue(), ^{
      weakSelf.panelToggleButton.title = running ? @"停止自动化" : @"开启自动化";
      weakSelf.panelStatusLabel.stringValue = [NSString stringWithFormat:@"状态：%@", status];
      weakSelf.statusItem.button.title = running ? @"W●" : @"W";
      if (![status isEqualToString:weakSelf.lastStatus]) {
        weakSelf.lastStatus = status;
        [weakSelf appendLog:status];
      }
      [weakSelf updateConfirmationButton];
    });
  };

  self.hotKey = [[HotKeyMonitor alloc] initWithKeyCode:keyCode modifiers:modifiers];
  self.hotKey.onStop = ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf.engine stop];
    });
  };
  [self.hotKey start];

  [self showPanel];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  (void)notification;
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

  NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 390)
                                                 styleMask:NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskMiniaturizable
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  panel.title = @"WoWCreate";
  panel.minSize = NSMakeSize(420, 300);
  panel.delegate = self;

  NSView *content = panel.contentView;

  self.panelToggleButton = [NSButton buttonWithTitle:@"开启自动化" target:self action:@selector(toggleAutomation:)];
  self.panelToggleButton.frame = NSMakeRect(20, 302, 140, 30);
  self.panelToggleButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.panelToggleButton];

  self.hotKeyButton = [NSButton buttonWithTitle:@"停止键" target:self action:@selector(changeStopHotKey:)];
  self.hotKeyButton.frame = NSMakeRect(170, 302, 190, 30);
  self.hotKeyButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.hotKeyButton];
  [self updateHotKeyButton];

  NSButton *quitButton = [NSButton buttonWithTitle:@"退出" target:self action:@selector(quitApp:)];
  quitButton.frame = NSMakeRect(370, 302, 70, 30);
  quitButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:quitButton];

  self.panelStatusLabel = [NSTextField labelWithString:@"状态：已停止"];
  self.panelStatusLabel.frame = NSMakeRect(20, 274, 420, 20);
  self.panelStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [content addSubview:self.panelStatusLabel];

  self.successDetectionCheckbox = [NSButton checkboxWithTitle:@"创建界面消失即停止（保守）"
                                                       target:self
                                                       action:@selector(toggleSuccessDetection:)];
  self.successDetectionCheckbox.frame = NSMakeRect(20, 250, 420, 20);
  self.successDetectionCheckbox.state = self.engine.stopWhenCreationScreenDisappears ? NSControlStateValueOn : NSControlStateValueOff;
  [content addSubview:self.successDetectionCheckbox];

  self.manualConfirmationCheckbox = [NSButton checkboxWithTitle:@"手动确认每一步（可选，默认关闭）"
                                                         target:self
                                                         action:@selector(toggleManualConfirmation:)];
  self.manualConfirmationCheckbox.frame = NSMakeRect(20, 226, 420, 20);
  self.manualConfirmationCheckbox.state = self.engine.requireManualConfirmation ? NSControlStateValueOn : NSControlStateValueOff;
  [content addSubview:self.manualConfirmationCheckbox];

  self.confirmButton = [NSButton buttonWithTitle:@"确认下一步" target:self action:@selector(confirmNextAction:)];
  self.confirmButton.frame = NSMakeRect(20, 194, 140, 28);
  self.confirmButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.confirmButton];
  [self updateConfirmationButton];

  NSTextField *hint = [NSTextField labelWithString:@"安全限制：仅 WoW 前台可操作；切出焦点即停；最多 20 次点击/12 次弹窗/5 分钟。"];
  hint.frame = NSMakeRect(170, 198, 270, 18);
  hint.font = [NSFont systemFontOfSize:11];
  hint.textColor = [NSColor secondaryLabelColor];
  [content addSubview:hint];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 420, 160)];
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
  self.panelWindow = panel;
}

- (void)anchorPanelToStatusItem {
  NSWindow *statusWindow = self.statusItem.button.window;
  if (!statusWindow) return;

  NSRect statusFrame = statusWindow.frame;
  NSRect panelFrame = self.panelWindow.frame;
  CGFloat x = NSMidX(statusFrame) - NSWidth(panelFrame) / 2;
  CGFloat y = NSMinY(statusFrame) - NSHeight(panelFrame) - 4;
  NSRect screenFrame = (statusWindow.screen ?: NSScreen.mainScreen).visibleFrame;
  x = MAX(NSMinX(screenFrame), MIN(x, NSMaxX(screenFrame) - NSWidth(panelFrame)));
  y = MAX(NSMinY(screenFrame), MIN(y, NSMaxY(screenFrame) - NSHeight(panelFrame)));
  [self.panelWindow setFrameOrigin:NSMakePoint(x, y)];
}

- (void)showPanel {
  [self buildPanelIfNeeded];
  [self anchorPanelToStatusItem];
  [self.panelWindow makeKeyAndOrderFront:nil];
  SEL activateSelector = @selector(activateWithOptions:);
  if ([NSApp respondsToSelector:activateSelector]) {
    NSMethodSignature *signature = [NSApp methodSignatureForSelector:activateSelector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = NSApp;
    invocation.selector = activateSelector;
    NSUInteger options = 1 << 1;
    [invocation setArgument:&options atIndex:2];
    [invocation invoke];
  }
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

- (void)toggleSuccessDetection:(id)sender {
  (void)sender;
  BOOL enabled = self.engine.stopWhenCreationScreenDisappears;
  self.engine.stopWhenCreationScreenDisappears = !enabled;
  self.successDetectionCheckbox.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
}

- (void)toggleManualConfirmation:(id)sender {
  (void)sender;
  BOOL enabled = self.engine.requireManualConfirmation;
  self.engine.requireManualConfirmation = !enabled;
  self.manualConfirmationCheckbox.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
  [self updateConfirmationButton];
}

- (void)confirmNextAction:(id)sender {
  (void)sender;
  [self.engine confirmNextAction];
  [self updateConfirmationButton];
}

- (void)updateConfirmationButton {
  if (!self.confirmButton) return;
  BOOL pending = [self.engine hasPendingConfirmation];
  self.confirmButton.enabled = pending;
  self.confirmButton.bezelStyle = pending ? NSBezelStyleRounded : NSBezelStyleRounded;
  self.confirmButton.title = pending ? @"确认下一步" : @"等待检测";
}

- (void)toggleAutomation:(id)sender {
  (void)sender;
  if (self.engine.isRunning) {
    [self.engine stop];
  } else {
    [self.engine startWithProcessName:@"World of Warcraft"];
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
  [defaults setInteger:(NSInteger)keyCode forKey:@"StopHotKeyKeyCode"];
  [defaults setInteger:(NSInteger)modifiers forKey:@"StopHotKeyModifiers"];
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
  [window orderOut:nil];
  return NO;
}
@end
