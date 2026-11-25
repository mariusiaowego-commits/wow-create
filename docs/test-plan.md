---
type: sprint
title: 测试计划
status: 已完成
created: 2026-11-25
---

# 测试计划

## 自动化

1. `./Scripts/build.sh` 编译零错误。
2. `./Scripts/test-classify.sh /tmp/wow-fixtures` 对 9 张截图逐一分类，要求 9/9。
3. `rg "CGEventPostToPid|CGEventPostToPSN" Sources/` 必须无命中。
4. `plutil -lint build/WoWCreate.app/Contents/Info.plist`。

## 手动

1. 启动 App：菜单栏出现 `W`，Dock 出现图标，面板吸附在 `W` 下方。
2. 关闭面板再点 `W`/Dock 图标，面板重新出现。
3. 勾选“演练”，开启自动化：日志应逐屏打印识别结果与“演练，不点击”。
4. 勾选“单步模式”，每按一次“执行一步”只发生一个动作。
5. 运行中点击 `W`：面板出现且自动化不因自身面板抢焦点而停止。
6. 运行中切到其它 App：3 秒宽限后立即停止。
7. 按 `⌃⌥⌘⇧K`：立即停止。
8. 真实 WoW：跑完 重新连接 → 规则集 PvP → 创建 → 命名 → 弹窗 → 回退 → 重试。

## 判据

- 自动化测试必须给出通过/失败数量。
- 手动项未执行记 `skipped` 并写原因，不记为通过。
