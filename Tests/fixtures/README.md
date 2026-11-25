# 分类回归夹具

把以下 9 张 1660×1094 的游戏窗口截图放到本目录（不要提交，已 gitignore）：

| 文件名 | 画面 |
| --- | --- |
| `login.png` | 登录界面（重新连接/退出） |
| `character-list.png` | 普通服务器角色列表（顶部有“规则集”） |
| `rule-set.png` | 规则集选择（PvP 卡片 + 取消/选择） |
| `creation.png` | 角色创建（联盟/部落/职业） |
| `naming.png` | 命名界面（主名/副名 + 完成） |
| `failure-dialog.png` | 阵营不平衡弹窗（确定） |
| `back-creation.png` | 弹窗关闭后第一次后退（角色创建） |
| `back-list.png` | 第二次后退（PvP 角色列表） |
| `back-login.png` | 第三次后退（回到登录界面） |

运行：

```bash
./Scripts/test-classify.sh
```

缺图会显示 `SKIP`，不会记为通过。
