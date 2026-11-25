#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AutomationEngine : NSObject
@property (nonatomic, copy, nullable) void (^onStateChange)(BOOL running, NSString *status);
- (void)startWithProcessName:(NSString *)processName;
- (void)stop;
@property (nonatomic, readonly) BOOL isRunning;
@end

NS_ASSUME_NONNULL_END
