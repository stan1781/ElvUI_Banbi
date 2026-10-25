# ElvUI Banbi

ElvUI 增强插件（WotLK 3.3.5a）。设置：`/banbi` 或 ElvUI 选项 → **Banbi**。

## 功能

| 分类 | 功能 | 替代 |
|------|------|------|
| 通用 | 移动速度 | MotionSpeed |
| 通用 | 代币条 | BagSync_TokenBar |
| 聊天 | 频道缩写 / 时间戳 / Tab / 历史 / 快捷栏 / 表情 | ChatBar |
| 工具 | 装备列表（TinyInspect 布局 + DragonUI 金边） | ElvUI_TinyInspect（不含出处） |
| 工具 | 符文动作条 / 装备助手 / 好友同步 | ElvUI_bbTools 子集 |
| 工具 | 玩家右键菜单 | FriendsMenuXP |

聊天栏按钮大小/间距/文字偏移：ElvUI → 插件美化 → **ChatBar**（需启用 ChatBar 皮肤开关）。

## 建议禁用的旧插件

功能验收后在角色选择 → 插件中禁用（不删 SavedVariables）：

- `MotionSpeed`
- `ChatBar`
- `FriendsMenuXP`
- `ElvUI_TinyInspect`
- `ElvUI_bbTools`（Unitscan 等未迁功能本阶段不做；需要时另装）
- `BagSync`（若只用代币条；若仍需背包搜索可保留并忽略重复代币条提示）

命令：`/banbilegacy` 复查冲突。

## 数据迁移

首次启用时从旧表只读导入一次（`ElvUI_BanbiDB.global.migrated.*`）：

- `bbToolsDB` → 符文 / 装备助手 / 好友同步
- `TinyInspectConfig` → 装备列表
- `BagSyncTokenBarDB` → 代币条开关
- `DragonUI_EnhancedDB` → 补缺

## 依赖

- Required: `ElvUI`
- Optional: `ElvUI_AddOnSkins`、`BagSync`（跨角色代币数量）

## 非目标

- ElvUI_Unitscan
- bbTools 竞技场截图 / WhisperInvite / Memories / 配置导入等
