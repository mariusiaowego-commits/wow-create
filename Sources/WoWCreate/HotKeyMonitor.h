#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HotKeyMonitor : NSObject
@property (nonatomic, copy) void (^onStop)(void);
- (void)start;
@end

NS_ASSUME_NONNULL_END
