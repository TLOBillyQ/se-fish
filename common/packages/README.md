# packages/ —— vendored 官方包

本目录是网易官方作者版包的整包 vendor；`server/` / `client/` / `common/` 三端各有一棵同名子树（包内模块路径写死这个布局）。当前 vendor 的包：

- `ability_system`：技能系统
- `attr_rule`：属性规则
- `modifier_system`：效果（Buff）系统
- `official_ai_feature`：生物 AI（依赖 `ability_system` 服务端门面）

- **纪律**：包内代码一行不改。定制只发生在双端根聚合入口（`server/AbilityAPI.lua`、`client/AbilityAPI.lua` 等）与业务层；业务代码不直接 require 包内模块。
- **来源与版本**：包内没有版本号、变更记录或来源 URL，以整包导入为准；升级拿官方新包整包替换再 diff 三棵子树。各包导入信息与其依赖的编辑器预设（AssetKey 清单）详见 `docs/packages-vendor.md`。
- **编辑器侧预设**：包依赖的预设建在地图里、不进 git；技能包预设一键重建用 `lua tools/cli.lua ability-presets`（规格在 `tools/ability_presets.lua`），用法另见 AGENTS.md「工具链」。
