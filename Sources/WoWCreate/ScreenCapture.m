#import "ScreenCapture.h"
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>
#import <dlfcn.h>

typedef CGImageRef (*CreateWindowImageFunction)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);

static CGImageRef CreateWindowImage(CGRect bounds, CGWindowID windowID) {
  static CreateWindowImageFunction function = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    void *coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
    function = (CreateWindowImageFunction)dlsym(coreGraphics, "CGWindowListCreateImage");
  });
  return function ? function(bounds, kCGWindowListOptionIncludingWindow, windowID, kCGWindowImageBoundsIgnoreFraming) : NULL;
}

@implementation WindowSnapshot
- (instancetype)initWithPid:(pid_t)pid bounds:(CGRect)bounds image:(nullable CGImageRef)image {
  self = [super init];
  if (self) {
    _pid = pid;
    _bounds = bounds;
    _image = image;
  }
  return self;
}

- (void)dealloc {
  if (_image) CGImageRelease(_image);
}
@end

@implementation ScreenCapture

- (NSArray<NSNumber *> *)processIDsForName:(NSString *)processName {
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSMutableArray *matches = [NSMutableArray array];
  for (NSRunningApplication *app in workspace.runningApplications) {
    if ([app.localizedName caseInsensitiveCompare:processName] == NSOrderedSame ||
        [app.bundleIdentifier caseInsensitiveCompare:processName] == NSOrderedSame) {
      [matches addObject:@(app.processIdentifier)];
    }
  }
  return matches;
}

- (nullable WindowSnapshot *)snapshotForProcessName:(NSString *)processName {
  NSArray *pids = [self processIDsForName:processName];
  if (pids.count == 0) return nil;
  NSMutableSet *pidSet = [NSMutableSet setWithArray:pids];

  CFArrayRef windows = CGWindowListCopyWindowInfo(
    kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
    kCGNullWindowID
  );
  if (!windows) return nil;

  for (NSDictionary *window in (__bridge NSArray *)windows) {
    NSNumber *owner = window[(__bridge NSString *)kCGWindowOwnerPID];
    NSNumber *layer = window[(__bridge NSString *)kCGWindowLayer];
    NSNumber *sharing = window[(__bridge NSString *)kCGWindowSharingState];
    if (!owner || ![pidSet containsObject:owner]) continue;
    if (layer.integerValue != 0) continue;
    if (sharing && sharing.integerValue != 0) continue;

    CGRect bounds;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(__bridge NSString *)kCGWindowBounds], &bounds);
    if (bounds.size.width < 400 || bounds.size.height < 300) continue;

    CGWindowID windowID = (CGWindowID)[window[(__bridge NSString *)kCGWindowNumber] unsignedIntValue];
    CGImageRef image = CreateWindowImage(CGRectNull, windowID);
    if (!image) continue;
    WindowSnapshot *snapshot = [[WindowSnapshot alloc] initWithPid:owner.intValue bounds:bounds image:image];
    CFRelease(windows);
    return snapshot;
  }

  CFRelease(windows);
  return nil;
}

- (BOOL)isRect:(CGRect)rect redDominantInImage:(CGImageRef)image {
  CGRect pixelRect = CGRectMake(
    rect.origin.x * CGImageGetWidth(image),
    rect.origin.y * CGImageGetHeight(image),
    rect.size.width * CGImageGetWidth(image),
    rect.size.height * CGImageGetHeight(image)
  );
  CGImageRef cropped = CGImageCreateWithImageInRect(image, pixelRect);
  if (!cropped) return NO;

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  size_t width = CGImageGetWidth(cropped);
  size_t height = CGImageGetHeight(cropped);
  size_t bytesPerRow = width * 4;
  NSMutableData *data = [NSMutableData dataWithLength:bytesPerRow * height];
  CGContextRef context = CGBitmapContextCreate(
    data.mutableBytes, width, height, 8, bytesPerRow, colorSpace,
    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
  );
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), cropped);
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);
  CGImageRelease(cropped);

  const unsigned char *bytes = data.bytes;
  NSUInteger red = 0, gray = 0, total = width * height;
  for (NSUInteger index = 0; index < total; index++) {
    unsigned char r = bytes[index * 4];
    unsigned char g = bytes[index * 4 + 1];
    unsigned char b = bytes[index * 4 + 2];
    if (r > 80 && r > g * 2 && r > b * 2) red++;
    if (abs(r - g) < 12 && abs(g - b) < 12 && r >= 30 && r <= 90) gray++;
  }
  return red > total / 8 && gray < total / 4;
}
@end
