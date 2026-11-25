---
type: sprint
title: Sprint 01 — 验收
status: 进行中
created: 2026-11-25
---

# 验收

详细命令输出见 `docs/verify.md`。

## 已通过

- `./Scripts/build.sh` 成功。
- 画面分类回归 9/9（0 failed / 0 skipped）。
- 源码无 `CGEventPostToPid`。

## 未执行

- 真实 WoW 端到端（等待用户在线实测）。
- 成功画面识别（无样本）。

## 结论

代码与离线验收完成，实机验收待用户执行。
