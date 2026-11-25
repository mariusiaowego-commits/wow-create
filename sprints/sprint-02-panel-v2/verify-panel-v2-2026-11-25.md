---
type: sprint
title: Sprint 02 — 验收
status: 已完成
created: 2026-11-25
---

# 验收

## 命令与输出

- `./Scripts/build.sh` → `built: build/WoWCreate.app`。
- `PlistBuddy -c 'Print :CFBundleShortVersionString'` → `0.2.1`。
- `./Scripts/test-classify.sh /tmp/wow-fixtures` → `9 passed, 0 failed, 0 skipped`。

## UI 实测

- 面板窗口 `480×534`，无标题栏按钮；截图确认圆角、深色背景。
- 状态行 `状态：已停止` 白色加粗；`识别` / `第 N 轮` 为 `0.76` 灰阶，日志正文 `0.92`。
- 版本三行：
  `当前  v0.2.1 · <sha> · <时间>`
  `磁盘  …  ✓ 已是最新`
  `权限  辅助功能 ✓/✗ · 屏幕录制 ✓/✗`
- 锚定：状态栏按钮未布局（`{{0,-11}}`）时拒绝锚定，改为 50ms 轮询，避免首帧闪到屏幕左缘。
- 运行期间面板 `orderFrontRegardless` 常驻，失焦/点击/切换 App 不收起；停止后恢复自动收起。

## 数字

- 分类样本 9 张，9 通过。
- 面板尺寸 480×534；垂直占屏 534/1084。

## failed / skipped

- `skipped`：真实建号端到端（需用户在 WoW 在线时执行）。
- `skipped`：签名稳定化（无可用签名证书，`security find-identity` 为 0）。
- 已知：ad-hoc 签名导致每次重建后需重新授权辅助功能/屏幕录制；本轮最后一次构建后只需授权一次。
