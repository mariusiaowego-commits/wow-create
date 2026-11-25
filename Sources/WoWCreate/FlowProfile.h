#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FlowScreen) {
  FlowScreenUnknown = 0,
  FlowScreenLogin,
  FlowScreenCharacterList,
  FlowScreenRuleSet,
  FlowScreenCreation,
  FlowScreenNaming,
  FlowScreenFailureDialog,
  FlowScreenPvPList,
};

typedef double (^FlowRatioBlock)(CGRect normalizedRect);

typedef NS_ENUM(NSInteger, FlowRegion) {
  FlowRegionLoginButton,
  FlowRegionListEnter,
  FlowRegionListBack,
  FlowRegionListCreate,
  FlowRegionRuleCancel,
  FlowRegionRuleSelect,
  FlowRegionHordeBanner,
  FlowRegionDialogOk,
  FlowRegionNameField,
  FlowRegionBottomRight,
  FlowRegionBottomLeft,
  FlowRegionCount,
};

typedef NS_ENUM(NSInteger, FlowPoint) {
  FlowPointReconnect,
  FlowPointRuleSetTab,
  FlowPointPvPCard,
  FlowPointRuleSelect,
  FlowPointRuleCancel,
  FlowPointMale,
  FlowPointUndead,
  FlowPointPriest,
  FlowPointCustomAppearance,
  FlowPointNameMain,
  FlowPointNameSecondary,
  FlowPointSubmit,
  FlowPointBackBottom,
  FlowPointBackList,
  FlowPointDialogOk,
  FlowPointCount,
};

FOUNDATION_EXPORT CGRect FlowRegionRect(FlowRegion region);
FOUNDATION_EXPORT CGPoint FlowPointValue(FlowPoint point);

FOUNDATION_EXPORT FlowScreen FlowClassifyScreen(FlowRatioBlock redRatio, FlowRatioBlock brightness);
FOUNDATION_EXPORT NSString *FlowScreenName(FlowScreen screen);

NS_ASSUME_NONNULL_END
