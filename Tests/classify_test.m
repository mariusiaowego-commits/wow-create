#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "ScreenCapture.h"
#import "FlowProfile.h"

typedef struct {
  const char *file;
  FlowScreen expected;
} ClassifyCase;

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *directory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"Tests/fixtures";
    ScreenCapture *capture = [[ScreenCapture alloc] init];
    ClassifyCase cases[] = {
      {"login.png", FlowScreenLogin},
      {"character-list.png", FlowScreenCharacterList},
      {"rule-set.png", FlowScreenRuleSet},
      {"creation.png", FlowScreenCreation},
      {"naming.png", FlowScreenNaming},
      {"failure-dialog.png", FlowScreenFailureDialog},
      {"back-creation.png", FlowScreenCreation},
      {"back-list.png", FlowScreenPvPList},
      {"back-login.png", FlowScreenLogin},
    };
    size_t total = sizeof(cases) / sizeof(cases[0]);
    int passed = 0;
    int failed = 0;
    int skipped = 0;

    for (size_t i = 0; i < total; i++) {
      NSString *path = [directory stringByAppendingPathComponent:@(cases[i].file)];
      NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
      if (!image) {
        printf("SKIP  %-18s (not found)\n", cases[i].file);
        skipped++;
        continue;
      }
      CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
      FlowRatioBlock red = ^double(CGRect rect) {
        return [capture redRatioInRect:rect image:cgImage];
      };
      FlowRatioBlock bright = ^double(CGRect rect) {
        return [capture brightnessInRect:rect image:cgImage];
      };
      FlowScreen actual = FlowClassifyScreen(red, bright);
      BOOL ok = actual == cases[i].expected;
      printf("%s  %-18s expected=%-16s actual=%s\n",
             ok ? "PASS" : "FAIL",
             cases[i].file,
             FlowScreenName(cases[i].expected).UTF8String,
             FlowScreenName(actual).UTF8String);
      if (ok) passed++; else failed++;
    }

    printf("\nclassify: %d passed, %d failed, %d skipped (total %zu)\n",
           passed, failed, skipped, total);
    return failed == 0 ? 0 : 1;
  }
}
