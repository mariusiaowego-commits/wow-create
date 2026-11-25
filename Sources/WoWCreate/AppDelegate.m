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
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  self.statusItem.button.title = @"W";
  self.statusItem.button.toolTip = @"WoWCreate - 点击开启/停止自动创建角色";

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"WoWCreate"];
  self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"开启自动化" action:@selector(toggleAutomation:) keyEquivalent:@""];
  self.toggleItem.target = self;
  [menu addItem:self.toggleItem];
  self.statusLineItem = [[NSMenuItem alloc] initWithTitle:@"状态：已停止" action:NULL keyEquivalent:@""];
  self.statusLineItem.enabled = NO;
  [menu addItem:self.statusLineItem];
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *hotKeyItem = [[NSMenuItem alloc] initWithTitle:@"全局停止：⌃⌥⌘W" action:NULL keyEquivalent:@""];
  hotKeyItem.enabled = NO;
  [menu addItem:hotKeyItem];
  [menu addItem:[[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(quitApp:) keyEquivalent:@"q"]];
  self.statusItem.menu = menu;

  self.engine = [[AutomationEngine alloc] init];
  __weak AppDelegate *weakSelf = self;
  self.engine.onStateChange = ^(BOOL running, NSString *status) {
    dispatch_async(dispatch_get_main_queue(), ^{
      weakSelf.toggleItem.title = running ? @"停止自动化" : @"开启自动化";
      weakSelf.statusLineItem.title = [NSString stringWithFormat:@"状态：%@", status];
      weakSelf.statusItem.button.title = running ? @"W●" : @"W";
    });
  };

  self.hotKey = [[HotKeyMonitor alloc] init];
  self.hotKey.onStop = ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf.engine stop];
    });
  };
  [self.hotKey start];
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
@end
