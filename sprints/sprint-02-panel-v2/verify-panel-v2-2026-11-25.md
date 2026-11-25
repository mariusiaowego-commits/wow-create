---
type: sprint
title: Sprint 02 — 验收
status: 已完成
created: 2026-11-25
---

# 验收

## 命令与输出

- `./Scripts/build.sh` → `built: build/WoWCreate.app`。
- `PlistBuddy -c 'Print :CFBundleShortVersionString'` → `0.2.2`。
- `./Scripts/test-classify.sh /tmp/wow-fixtures` → `9 passed, 0 failed, 0 skipped`。

## UI 实测

- 面板窗口 `480×534`，无标题栏按钮；截图确认圆角、深色背景。
- 状态行改为胶囊：浅色底（白 10%）、8pt 状态圆点、白色加粗 13pt；运行中绿点、等待/暂停橙点、停止灰点。
- 日志行改为写入时带显式属性（白 0.92 + 等宽 11pt）。此前用无属性字符串 append，
  NSTextStorage 用默认黑色渲染，这是“日志文字看不清”的真正原因。
- 选中文字属性固定为白字 + 系统选中底色，选中后不再变黑。
- `识别` / `第 N 轮` 为 `0.76` 灰阶。
- 版本三行：
  `当前  v0.2.2 · <sha> · <时间>`
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
