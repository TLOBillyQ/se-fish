# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。编辑器同步规则、CLI 用法、技能路由见 `.claude/CLAUDE.md` 与 `.claude/rules/`（teamai 下发，已 gitignore）。

## 代码结构

- `server/main.lua`：服务端入口，把 `server/Mgr/` 下的管理器注册进 `MgrMap`，统一分发 `OnPlayerAdded` / `OnPlayerRemoving` / `Update`。新增服务端管理器时加进 `MgrMap`。
- `client/main.lua`：客户端入口；界面由 `MgrGameUI` 管理，每个界面一个 `client/ScreenHandlers/Screen*.lua`。
- `common/GameCfg.lua`：双端共享的数值配置（鱼等级、鱼竿等级等）。
- `data/`：编辑器插件导出的 Prefab / UI 节点 ID，只读，改动通过编辑器重新导出。
- `EggyAPI.lua` / `EggyEditorAPI.lua`：运行时 / 编辑时 API 声明，查 API 先 grep 这两个文件。

## 设计文档

`design` 是指向 `eggitor/1_开发中/渔力全开` 的符号链接，玩法与系统设计以它为准；不在本仓库管理。
