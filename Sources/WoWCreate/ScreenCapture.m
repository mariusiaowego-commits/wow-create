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

typedef struct {
  NSUInteger red;
  NSUInteger gray;
  NSUInteger total;
} PixelCounts;

- (PixelCounts)countsInRect:(CGRect)rect image:(CGImageRef)image {
  PixelCounts counts = {0, 0, 0};
  CGRect pixelRect = CGRectMake(
    rect.origin.x * CGImageGetWidth(image),
    rect.origin.y * CGImageGetHeight(image),
    rect.size.width * CGImageGetWidth(image),
    rect.size.height * CGImageGetHeight(image)
  );
  CGImageRef cropped = CGImageCreateWithImageInRect(image, pixelRect);
  if (!cropped) return counts;

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
  counts.total = width * height;
  for (NSUInteger index = 0; index < counts.total; index++) {
    unsigned char red = bytes[index * 4];
    unsigned char green = bytes[index * 4 + 1];
    unsigned char blue = bytes[index * 4 + 2];
    if (red > 80 && red > green * 2 && red > blue * 2) counts.red++;
    if (abs(red - green) < 12 && abs(green - blue) < 12 && red >= 30 && red <= 90) counts.gray++;
  }
  return counts;
}

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
  PixelCounts counts = [self countsInRect:rect image:image];
  return counts.red > counts.total / 8 && counts.gray < counts.total / 4;
}

- (BOOL)isRect:(CGRect)rect grayDominantInImage:(CGImageRef)image {
  PixelCounts counts = [self countsInRect:rect image:image];
  return counts.gray > counts.total / 2;
}
@end
