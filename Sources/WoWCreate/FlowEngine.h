#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FlowEngine : NSObject
@property (nonatomic, copy, nullable) void (^onStateChange)(BOOL running, NSString *status);
@property (nonatomic, copy, nullable) void (^onFlowUpdate)(NSString *screenName, NSInteger cycle, NSInteger failures, NSInteger actions);
@property (nonatomic, assign) BOOL stopWhenFocusLeaves;
@property (nonatomic, assign) BOOL panelOpen;
@property (nonatomic, assign) BOOL dryRun;
@property (nonatomic, assign) BOOL singleStep;
@property (nonatomic, copy) NSString *mainName;
@property (nonatomic, copy) NSString *secondaryName;

- (void)startWithProcessName:(NSString *)processName;
- (void)stop;
- (void)stepOnce;

@property (atomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSInteger cycleCount;
@property (nonatomic, readonly) NSInteger failureCount;
@property (nonatomic, readonly) NSInteger actionCount;
@end

NS_ASSUME_NONNULL_END
