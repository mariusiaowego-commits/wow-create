#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface WindowSnapshot : NSObject
@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) CGRect bounds;
@property (nonatomic, readonly, nullable) CGImageRef image;
@end

@interface ScreenCapture : NSObject
- (nullable WindowSnapshot *)snapshotForProcessName:(NSString *)processName;
- (BOOL)isRect:(CGRect)rect redDominantInImage:(CGImageRef)image;
- (BOOL)isRect:(CGRect)rect grayDominantInImage:(CGImageRef)image;
@end

NS_ASSUME_NONNULL_END
