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
  double luminance;
} PixelCounts;

static BOOL StringMatchesTarget(NSString *value, NSString *targetAlias, BOOL allowShortAlias) {
  if (value.length == 0) return NO;
  NSMutableArray<NSString *> *aliases = [NSMutableArray arrayWithArray:@[@"world of warcraft", @"魔兽世界"]];
  for (NSString *alias in aliases) {
    if (alias.length == 0) continue;
    if ([value.lowercaseString containsString:alias]) return YES;
  }
  if (allowShortAlias && [value caseInsensitiveCompare:@"wow"] == NSOrderedSame) return YES;
  if (targetAlias.length > 0 && [value caseInsensitiveCompare:targetAlias] == NSOrderedSame) return YES;
  return NO;
}

- (PixelCounts)countsInRect:(CGRect)rect image:(CGImageRef)image {
  PixelCounts counts = {0, 0, 0, 0};
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
  unsigned long long luminanceSum = 0;
  for (NSUInteger index = 0; index < counts.total; index++) {
    unsigned char red = bytes[index * 4];
    unsigned char green = bytes[index * 4 + 1];
    unsigned char blue = bytes[index * 4 + 2];
    if (red > 80 && red > green * 2 && red > blue * 2) counts.red++;
    if (abs(red - green) < 12 && abs(green - blue) < 12 && red >= 30 && red <= 90) counts.gray++;
    luminanceSum += (unsigned long long)(0.299 * red + 0.587 * green + 0.114 * blue);
  }
  if (counts.total > 0) counts.luminance = (double)luminanceSum / counts.total;
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
  return [self snapshotForTargetAlias:processName];
}

- (nullable WindowSnapshot *)snapshotForTargetAlias:(NSString *)targetAlias {
  NSArray *pids = [self processIDsForName:targetAlias];
  NSMutableSet *pidSet = [NSMutableSet setWithArray:pids ?: @[]];
  pid_t selfPid = NSProcessInfo.processInfo.processIdentifier;

  CFArrayRef windows = CGWindowListCopyWindowInfo(
    kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
    kCGNullWindowID
  );
  if (!windows) return nil;

  for (NSDictionary *window in (__bridge NSArray *)windows) {
    NSNumber *owner = window[(__bridge NSString *)kCGWindowOwnerPID];
    if (owner && owner.intValue == selfPid) continue;
    NSString *ownerName = window[(__bridge NSString *)kCGWindowOwnerName] ?: @"";
    NSString *title = window[(__bridge NSString *)kCGWindowName] ?: @"";
    NSNumber *layer = window[(__bridge NSString *)kCGWindowLayer];
    NSNumber *sharing = window[(__bridge NSString *)kCGWindowSharingState];
    BOOL ownerMatch = owner && [pidSet containsObject:owner];
    BOOL metadataMatch = StringMatchesTarget(ownerName, targetAlias, YES) || StringMatchesTarget(title, targetAlias, NO);
    if (!ownerMatch && !metadataMatch) continue;
    if (layer.integerValue != 0) continue;
    (void)sharing;

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

- (double)redRatioInRect:(CGRect)rect image:(CGImageRef)image {
  PixelCounts counts = [self countsInRect:rect image:image];
  return counts.total > 0 ? (double)counts.red / counts.total : 0.0;
}

- (double)brightnessInRect:(CGRect)rect image:(CGImageRef)image {
  PixelCounts counts = [self countsInRect:rect image:image];
  return counts.luminance;
}
@end
