#import <AppKit/AppKit.h>

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    id delegate = [[NSClassFromString(@"AppDelegate") alloc] init];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
