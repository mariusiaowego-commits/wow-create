---
type: sprint
title: 验收报告
status: 进行中
created: 2026-11-25
---

# 验收报告

## 命令与输出

```
$ ./Scripts/build.sh
built: /Users/mt16/dev/wow-create/build/WoWCreate.app
```

```
$ ./Scripts/test-classify.sh /tmp/wow-fixtures
PASS  login.png          expected=登录界面     actual=登录界面
PASS  character-list.png expected=普通服务器角色列表 actual=普通服务器角色列表
PASS  rule-set.png       expected=规则集选择  actual=规则集选择
PASS  creation.png       expected=角色创建     actual=角色创建
PASS  naming.png         expected=命名界面     actual=命名界面
PASS  failure-dialog.png expected=阵营不平衡弹窗 actual=阵营不平衡弹窗
PASS  back-creation.png  expected=角色创建     actual=角色创建
PASS  back-list.png      expected=PvP 角色列表 actual=PvP 角色列表
PASS  back-login.png     expected=登录界面     actual=登录界面

classify: 9 passed, 0 failed, 0 skipped (total 9)
```

```
$ rg -n "CGEventPostToPid|CGEventPostToPSN" Sources/
none
```

## UI 实测

- 启动后 `W` 状态栏图标存在；面板为 `NSPanel`，`level=3`（floating），锚点由状态栏按钮 rect 计算。
- 多显示器实测：状态栏按钮在 `{{2663,1161},{33,22}}`，面板 origin `{{2439,633},{480,524}}`，顶边紧贴按钮下方；日志确认 `visible=1`。
- 运行中打开面板只暂停输入，不误判焦点切出；关闭面板后重新激活 WoW 继续。
- 启动时用 `orderFrontRegardless` 显示面板，不取 key、不激活 App；只有点击状态栏/Dock 才激活。实测启动后前台仍是原 App。
- 菜单栏布局有延迟：锚点在 0.3/0.8/1.5/2.5 秒重算四次，避免落在旧位置。

## failed / skipped

- `failed`：无。
- `skipped`：真实 WoW 端到端（需要用户游戏在线与服务器状态）；`pstack` 采样（本机不可用，wrapper 报 `ModuleNotFoundError`）；成功画面证据（用户从未成功创建，无法提供）。

## 独立审计（Herdr agy，只读）

- 结论：`REQUEST CHANGES`，主流程/焦点保护/非激活面板/无后台注入均通过。
- MEDIUM：
  1. 提交重试判断顺序导致 10 秒提前停止 — 已修（重试 12 秒，第 4 次后 20 秒停止）。
  2. 清空输入仅 Backspace 且阻塞主线程 — 已修（Cmd+A + 双向删除，移入输入队列）。
  3. `sanitizedName` 丢弃大写字母 — 已修（先 `lowercaseString`）。
- NIT：
  4. 单步模式在打字中丢暂停 — 已修（`stepOnce` 打字中直接返回）。
  5. 演练模式弹窗触发 25 秒回退超时 — 已修（演练不进入回退状态）。
- 修复提交：`04d1615`；修复后分类回归仍为 9/9。
- 复检（agy，`0ce6e5b`）：5/5 `FIXED`，结论 `APPROVE`。

## 待用户验证

1. 辅助功能 + 屏幕录制权限是否已勾选。
2. 实机跑一轮：重点看“规则集”顶部点击与命名输入是否被游戏接受。
3. 若某一步点偏，记录日志里的“识别”行与分辨率，再调 `FlowProfile.m`。

## 面板 v2（2026-11-25）

- 无标题栏：`NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel`，
  `canBecomeKeyWindow=YES`、`canBecomeMainWindow=NO`；截图确认左上角无关闭/最小化按钮。
- 失焦收起：`windowDidResignKey:` + 全局鼠标监视（点面板外）+ `NSWorkspaceDidActivateApplicationNotification`。
  点状态栏图标本身不算失焦（`statusItemScreenRect` 命中则跳过），保证图标可切换开关。
- 版本行实测（内建屏截图）：
  `当前  v0.2.0 · 7cd20a4-dirty · 2026-11-25 15:02`
  `磁盘  v0.2.0 · 7cd20a4-dirty · 2026-11-25 15:02  ✓ 已是最新`
- 状态栏图标：原文字 `W` 在内建屏深色菜单栏不可见（外接屏可见），改为模板图 `w.circle`；
  外接屏截图确认图标正常显示。
- 锚定实测（外接屏）：状态栏按钮 `{{2703,1158},{32.5,29}}`，面板 `{{2479,633},{480,520}}`，
  顶边在菜单栏下方 4px，水平中心与图标中心对齐。
- 启动首帧：状态栏按钮尚未布局（`status={{0,-11}}`）时先不显示面板，50ms 轮询至布局完成再显示，避免左下角闪帧。
- 模拟点击（CGEvent）在本机被系统丢弃：`AXIsProcessTrusted=false`，属权限问题，不计入 App 失败。
