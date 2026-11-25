#import "FlowProfile.h"

static const CGRect kRegions[FlowRegionCount] = {
  // Coordinates are normalized against the WoW window image (title bar included).
  [FlowRegionLoginButton] = {{0.425, 0.503}, {0.148, 0.040}},
  [FlowRegionListEnter] = {{0.425, 0.894}, {0.148, 0.036}},
  [FlowRegionListBack] = {{0.017, 0.953}, {0.111, 0.022}},
  [FlowRegionListCreate] = {{0.757, 0.872}, {0.122, 0.019}},
  [FlowRegionRuleCancel] = {{0.014, 0.934}, {0.150, 0.037}},
  [FlowRegionRuleSelect] = {{0.831, 0.934}, {0.150, 0.037}},
  [FlowRegionHordeBanner] = {{0.145, 0.200}, {0.090, 0.600}},
  [FlowRegionDialogOk] = {{0.430, 0.546}, {0.135, 0.020}},
  [FlowRegionNameField] = {{0.290, 0.096}, {0.140, 0.022}},
  [FlowRegionBottomRight] = {{0.805, 0.912}, {0.150, 0.039}},
  [FlowRegionBottomLeft] = {{0.041, 0.912}, {0.150, 0.039}},
};

static const CGPoint kPoints[FlowPointCount] = {
  [FlowPointReconnect] = {0.4988, 0.5229},
  [FlowPointRuleSetTab] = {0.6157, 0.0841},
  [FlowPointPvPCard] = {0.4060, 0.5484},
  [FlowPointRuleSelect] = {0.9072, 0.9543},
  [FlowPointRuleCancel] = {0.0904, 0.9543},
  [FlowPointMale] = {0.4807, 0.1024},
  [FlowPointUndead] = {0.1867, 0.3108},
  [FlowPointPriest] = {0.5964, 0.7898},
  [FlowPointCustomAppearance] = {0.8807, 0.9324},
  [FlowPointNameMain] = {0.3675, 0.1060},
  [FlowPointNameSecondary] = {0.6325, 0.1060},
  [FlowPointSubmit] = {0.8807, 0.9324},
  [FlowPointBackBottom] = {0.1169, 0.9324},
  [FlowPointBackList] = {0.0735, 0.9653},
  [FlowPointDialogOk] = {0.4988, 0.5576},
};

CGRect FlowRegionRect(FlowRegion region) {
  if (region < 0 || region >= FlowRegionCount) return CGRectZero;
  return kRegions[region];
}

CGPoint FlowPointValue(FlowPoint point) {
  if (point < 0 || point >= FlowPointCount) return CGPointZero;
  return kPoints[point];
}

FlowScreen FlowClassifyScreen(FlowRatioBlock redRatio, FlowRatioBlock brightness) {
  // Order matters: modal, then screens that share red accents, then icon-only screens.
  if (redRatio(FlowRegionRect(FlowRegionDialogOk)) > 0.30) return FlowScreenFailureDialog;
  if (redRatio(FlowRegionRect(FlowRegionLoginButton)) > 0.40) return FlowScreenLogin;
  if (redRatio(FlowRegionRect(FlowRegionRuleCancel)) > 0.50 &&
      redRatio(FlowRegionRect(FlowRegionRuleSelect)) > 0.50) {
    return FlowScreenRuleSet;
  }
  if (redRatio(FlowRegionRect(FlowRegionHordeBanner)) > 0.20) return FlowScreenCreation;
  if (redRatio(FlowRegionRect(FlowRegionListEnter)) > 0.45) return FlowScreenCharacterList;
  if (redRatio(FlowRegionRect(FlowRegionListBack)) > 0.50 &&
      redRatio(FlowRegionRect(FlowRegionListCreate)) > 0.50) {
    return FlowScreenPvPList;
  }
  if (redRatio(FlowRegionRect(FlowRegionBottomRight)) > 0.50 &&
      redRatio(FlowRegionRect(FlowRegionBottomLeft)) > 0.50 &&
      brightness(FlowRegionRect(FlowRegionNameField)) < 45.0) {
    return FlowScreenNaming;
  }
  return FlowScreenUnknown;
}

NSString *FlowScreenName(FlowScreen screen) {
  switch (screen) {
    case FlowScreenLogin: return @"登录界面";
    case FlowScreenCharacterList: return @"普通服务器角色列表";
    case FlowScreenRuleSet: return @"规则集选择";
    case FlowScreenCreation: return @"角色创建";
    case FlowScreenNaming: return @"命名界面";
    case FlowScreenFailureDialog: return @"阵营不平衡弹窗";
    case FlowScreenPvPList: return @"PvP 角色列表";
    case FlowScreenUnknown: return @"未识别界面";
  }
  return @"未知";
}
