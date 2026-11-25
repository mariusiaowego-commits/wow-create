#import "HotKeyMonitor.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

@implementation HotKeyMonitor {
  EventHotKeyRef _hotKeyRef;
}

static OSStatus HotKeyHandler(EventHandlerCallRef handler, EventRef event, void *userData) {
  (void)handler;
  (void)event;
  HotKeyMonitor *monitor = (__bridge HotKeyMonitor *)userData;
  if (monitor.onStop) monitor.onStop();
  return noErr;
}

- (void)start {
  EventTypeSpec eventSpec = { kEventClassKeyboard, kEventHotKeyPressed };
  InstallEventHandler(
    GetApplicationEventTarget(),
    HotKeyHandler,
    1,
    &eventSpec,
    (__bridge void *)self,
    NULL
  );

  EventHotKeyID hotKeyID;
  hotKeyID.signature = 'wowk';
  hotKeyID.id = 1;
  RegisterEventHotKey(
    kVK_ANSI_W,
    controlKey | optionKey | cmdKey,
    hotKeyID,
    GetApplicationEventTarget(),
    0,
    &_hotKeyRef
  );
}
@end
