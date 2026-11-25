#import "HotKeyMonitor.h"
#import <Carbon/Carbon.h>

@interface HotKeyMonitor ()
@property (nonatomic, assign) UInt32 keyCode;
@property (nonatomic, assign) UInt32 modifiers;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) EventHotKeyRef hotKeyRef;
@property (nonatomic, assign) EventHandlerRef handlerRef;
@end

static OSStatus HotKeyHandler(EventHandlerCallRef handler, EventRef event, void *userData) {
  (void)handler;
  (void)event;
  HotKeyMonitor *monitor = (__bridge HotKeyMonitor *)userData;
  if (monitor.onStop) monitor.onStop();
  return noErr;
}

static NSDictionary<NSNumber *, NSString *> *HotKeyNames(void) {
  static dispatch_once_t onceToken;
  static NSDictionary<NSNumber *, NSString *> *names = nil;
  dispatch_once(&onceToken, ^{
    names = @{
      @(kVK_ANSI_A): @"A", @(kVK_ANSI_B): @"B", @(kVK_ANSI_C): @"C",
      @(kVK_ANSI_D): @"D", @(kVK_ANSI_E): @"E", @(kVK_ANSI_F): @"F",
      @(kVK_ANSI_G): @"G", @(kVK_ANSI_H): @"H", @(kVK_ANSI_I): @"I",
      @(kVK_ANSI_J): @"J", @(kVK_ANSI_K): @"K", @(kVK_ANSI_L): @"L",
      @(kVK_ANSI_M): @"M", @(kVK_ANSI_N): @"N", @(kVK_ANSI_O): @"O",
      @(kVK_ANSI_P): @"P", @(kVK_ANSI_Q): @"Q", @(kVK_ANSI_R): @"R",
      @(kVK_ANSI_S): @"S", @(kVK_ANSI_T): @"T", @(kVK_ANSI_U): @"U",
      @(kVK_ANSI_V): @"V", @(kVK_ANSI_W): @"W", @(kVK_ANSI_X): @"X",
      @(kVK_ANSI_Y): @"Y", @(kVK_ANSI_Z): @"Z",
      @(kVK_ANSI_0): @"0", @(kVK_ANSI_1): @"1", @(kVK_ANSI_2): @"2",
      @(kVK_ANSI_3): @"3", @(kVK_ANSI_4): @"4", @(kVK_ANSI_5): @"5",
      @(kVK_ANSI_6): @"6", @(kVK_ANSI_7): @"7", @(kVK_ANSI_8): @"8",
      @(kVK_ANSI_9): @"9",
      @(kVK_Return): @"Return", @(kVK_Tab): @"Tab", @(kVK_Space): @"Space",
      @(kVK_Delete): @"Delete", @(kVK_ForwardDelete): @"Forward Delete",
      @(kVK_LeftArrow): @"←", @(kVK_RightArrow): @"→",
      @(kVK_UpArrow): @"↑", @(kVK_DownArrow): @"↓",
      @(kVK_F1): @"F1", @(kVK_F2): @"F2", @(kVK_F3): @"F3", @(kVK_F4): @"F4",
      @(kVK_F5): @"F5", @(kVK_F6): @"F6", @(kVK_F7): @"F7", @(kVK_F8): @"F8",
      @(kVK_F9): @"F9", @(kVK_F10): @"F10", @(kVK_F11): @"F11", @(kVK_F12): @"F12",
    };
  });
  return names;
}

@implementation HotKeyMonitor

- (instancetype)initWithKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
  self = [super init];
  if (self) {
    _keyCode = keyCode;
    _modifiers = modifiers;
  }
  return self;
}

- (void)dealloc {
  [self stop];
}

- (void)start {
  if (self.running) return;
  EventTypeSpec eventSpec = { kEventClassKeyboard, kEventHotKeyPressed };
  OSStatus status = InstallEventHandler(
    GetApplicationEventTarget(),
    HotKeyHandler,
    1,
    &eventSpec,
    (__bridge void *)self,
    &_handlerRef
  );
  if (status != noErr) {
    _handlerRef = NULL;
    return;
  }

  self.running = YES;
  [self registerHotKey];
}

- (void)stop {
  if (self.hotKeyRef) {
    UnregisterEventHotKey(self.hotKeyRef);
    self.hotKeyRef = NULL;
  }
  if (self.handlerRef) {
    RemoveEventHandler(self.handlerRef);
    self.handlerRef = NULL;
  }
  self.running = NO;
}

- (void)setKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
  if (self.hotKeyRef) {
    UnregisterEventHotKey(self.hotKeyRef);
    self.hotKeyRef = NULL;
  }
  self.keyCode = keyCode;
  self.modifiers = modifiers;
  if (self.running) [self registerHotKey];
}

- (void)registerHotKey {
  EventHotKeyID hotKeyID;
  hotKeyID.signature = 'wowk';
  hotKeyID.id = 1;
  RegisterEventHotKey(
    self.keyCode,
    self.modifiers,
    hotKeyID,
    GetApplicationEventTarget(),
    0,
    &_hotKeyRef
  );
}

+ (NSString *)displayStringForKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
  NSMutableString *display = [NSMutableString string];
  if (modifiers & controlKey) [display appendString:@"⌃"];
  if (modifiers & optionKey) [display appendString:@"⌥"];
  if (modifiers & shiftKey) [display appendString:@"⇧"];
  if (modifiers & cmdKey) [display appendString:@"⌘"];
  NSString *keyName = HotKeyNames()[@(keyCode)] ?: [NSString stringWithFormat:@"%u", keyCode];
  [display appendString:keyName];
  return display;
}
@end
