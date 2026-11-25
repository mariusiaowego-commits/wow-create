#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HotKeyMonitor : NSObject
@property (nonatomic, copy) void (^onStop)(void);
@property (nonatomic, readonly) UInt32 keyCode;
@property (nonatomic, readonly) UInt32 modifiers;
- (instancetype)initWithKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers;
- (void)setKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers;
- (void)start;
- (void)stop;
+ (NSString *)displayStringForKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers;
@end

NS_ASSUME_NONNULL_END
