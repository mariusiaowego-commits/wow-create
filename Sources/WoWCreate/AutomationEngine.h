#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AutomationEngine : NSObject
@property (nonatomic, copy, nullable) void (^onStateChange)(BOOL running, NSString *status);
@property (nonatomic, assign) BOOL stopWhenCreationScreenDisappears;
@property (nonatomic, assign) BOOL requireManualConfirmation;
- (void)startWithProcessName:(NSString *)processName;
- (void)stop;
- (void)confirmNextAction;
- (BOOL)hasPendingConfirmation;
@property (nonatomic, assign) BOOL stopWhenFocusLeaves;
@property (nonatomic, readonly) BOOL isRunning;
@end

NS_ASSUME_NONNULL_END
