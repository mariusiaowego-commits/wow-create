---
type: sprint
title: FlowEngine 技术规格
status: 已完成
created: 2026-11-25
---

# 技术规格

## 模块

| 文件 | 职责 |
| --- | --- |
| `Sources/WoWCreate/FlowProfile.{h,m}` | 归一化探针矩形、点击点、`FlowClassifyScreen` 纯函数 |
| `Sources/WoWCreate/FlowEngine.{h,m}` | 0.4s 轮询状态机、动作节律、回退、计数与安全上限 |
| `Sources/WoWCreate/ScreenCapture.{h,m}` | 窗口定位/截图、矩形红色占比与亮度统计 |
| `Sources/WoWCreate/AppDelegate.m` | 菜单栏/Dock、非激活面板、热键、演练/单步、日志 |
| `Tests/classify_test.m` | 对 9 张截图跑分类回归 |

## 状态机

`tick` 每 0.4s：

1. 超时/打字中直接返回。
2. 取 WoW 窗口截图；优先按 owner/title 匹配 `Wow`/`魔兽世界`，排除自身 PID。
3. 前台校验：必须是 WoW；自身面板在前台时暂停输入，其它 App 切出即停。
4. 单步/冷却门控。
5. `FlowClassifyScreen` 分类。
6. 先判成功，再判失败回退，最后分派当前界面的前进动作。

## 分类阈值（归一化）

| 界面 | 判据 |
| --- | --- |
| 失败弹窗 | `dialogOk` 红占比 > 0.30 |
| 登录 | `loginButton` 红占比 > 0.40 |
| 规则集 | `ruleCancel` 与 `ruleSelect` 同时 > 0.50 |
| 角色创建 | `hordeBanner` 红占比 > 0.20 |
| 普通列表 | `listEnter` 红占比 > 0.45 |
| PvP 列表 | `listBack` 与 `listCreate` 同时 > 0.50 |
| 命名 | `bottomRight` 与 `bottomLeft` 同时 > 0.50，且 `nameField` 亮度 < 45 |

判定顺序避免共享红色元素的误判；9/9 回归见 `verify.md`。

## 输入与节律

- 鼠标：4 段移动插值 + 55–105ms 按下 + ±2pt 抖动。
- 键盘：真实键码逐字输入，90–170ms/字；清空用 16 次 Backspace（不依赖 Cmd+A）。
- 失败回退：命名/创建用左下“后退”，PvP 列表用左下方更低的“后退”。

## 成功判定

`submittedAt` 在点“完成”时置位；出现失败弹窗即清空。未清空且回到任一角色列表 → “疑似创建成功”并停止。

## 限制

- 坐标按 1660×1094 窗口标定，依赖固定宽高比。
- 截图权限缺失时窗口截图为空 → 状态“未找到 WoW 窗口”/“未识别”。
- 成功判定是保守近似，缺少成功截图证据。
