#import "AppDelegate.h"
#import "AutomationEngine.h"
#import "HotKeyMonitor.h"
#import <AppKit/AppKit.h>

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) AutomationEngine *engine;
@property (nonatomic, strong) HotKeyMonitor *hotKey;
@property (nonatomic, strong) NSMenuItem *toggleItem;
@property (nonatomic, strong) NSMenuItem *statusLineItem;
@property (nonatomic, strong) NSMenuItem *successDetectionItem;
@property (nonatomic, strong) NSWindow *panelWindow;
@property (nonatomic, strong) NSButton *panelToggleButton;
@property (nonatomic, strong) NSTextField *panelStatusLabel;
@property (nonatomic, strong) NSTextView *panelLogView;
@property (nonatomic, copy, nullable) NSString *lastStatus;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  self.statusItem.button.title = @"W";
  self.statusItem.button.toolTip = @"WoWCreate - 点击开启/停止自动创建角色";

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"WoWCreate"];
  NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"打开控制面板" action:@selector(showPanel) keyEquivalent:@""];
  openItem.target = self;
  [menu addItem:openItem];
  self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"开启自动化" action:@selector(toggleAutomation:) keyEquivalent:@""];
  self.toggleItem.target = self;
  [menu addItem:self.toggleItem];
  self.statusLineItem = [[NSMenuItem alloc] initWithTitle:@"状态：已停止" action:NULL keyEquivalent:@""];
  self.statusLineItem.enabled = NO;
  [menu addItem:self.statusLineItem];
  [menu addItem:[NSMenuItem separatorItem]];
  self.successDetectionItem = [[NSMenuItem alloc] initWithTitle:@"创建界面消失即停止（保守）" action:@selector(toggleSuccessDetection:) keyEquivalent:@""];
  self.successDetectionItem.target = self;
  self.successDetectionItem.state = NSControlStateValueOn;
  [menu addItem:self.successDetectionItem];
  NSMenuItem *hotKeyItem = [[NSMenuItem alloc] initWithTitle:@"全局停止：⌃⌥⌘W" action:NULL keyEquivalent:@""];
  hotKeyItem.enabled = NO;
  [menu addItem:hotKeyItem];
  [menu addItem:[[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(quitApp:) keyEquivalent:@"q"]];
  self.statusItem.menu = menu;

  self.engine = [[AutomationEngine alloc] init];
  self.engine.stopWhenCreationScreenDisappears = YES;
  __weak AppDelegate *weakSelf = self;
  self.engine.onStateChange = ^(BOOL running, NSString *status) {
    dispatch_async(dispatch_get_main_queue(), ^{
      weakSelf.toggleItem.title = running ? @"停止自动化" : @"开启自动化";
      weakSelf.statusLineItem.title = [NSString stringWithFormat:@"状态：%@", status];
      weakSelf.statusItem.button.title = running ? @"W●" : @"W";
      weakSelf.panelToggleButton.title = running ? @"停止自动化" : @"开启自动化";
      weakSelf.panelStatusLabel.stringValue = [NSString stringWithFormat:@"状态：%@", status];
      if (![status isEqualToString:weakSelf.lastStatus]) {
        weakSelf.lastStatus = status;
        [weakSelf appendLog:status];
      }
    });
  };

  self.hotKey = [[HotKeyMonitor alloc] init];
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

  NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 300)
                                                 styleMask:NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskMiniaturizable
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  panel.title = @"WoWCreate";
  panel.minSize = NSMakeSize(380, 240);
  panel.delegate = self;

  NSView *content = panel.contentView;

  self.panelToggleButton = [NSButton buttonWithTitle:@"开启自动化" target:self action:@selector(toggleAutomation:)];
  self.panelToggleButton.frame = NSMakeRect(20, 248, 150, 32);
  self.panelToggleButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.panelToggleButton];

  self.panelStatusLabel = [NSTextField labelWithString:@"状态：已停止"];
  self.panelStatusLabel.frame = NSMakeRect(184, 255, 250, 20);
  self.panelStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [content addSubview:self.panelStatusLabel];

  NSTextField *hint = [NSTextField labelWithString:@"启动后请保持 WoW 创建角色界面；⌃⌥⌘W 立即停止。"];
  hint.frame = NSMakeRect(20, 226, 420, 18);
  hint.font = [NSFont systemFontOfSize:11];
  hint.textColor = [NSColor secondaryLabelColor];
  [content addSubview:hint];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 420, 194)];
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

- (void)showPanel {
  [self buildPanelIfNeeded];
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
  self.successDetectionItem.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
}

- (void)toggleAutomation:(id)sender {
  (void)sender;
  if (self.engine.isRunning) {
    [self.engine stop];
  } else {
    [self.engine startWithProcessName:@"World of Warcraft"];
  }
}

- (void)quitApp:(id)sender {
  (void)sender;
  [NSApp terminate:nil];
}

- (BOOL)windowShouldClose:(NSWindow *)window {
  [window orderOut:nil];
  return NO;
}
@end
