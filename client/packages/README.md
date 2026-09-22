# packages/ —— vendored 官方技能包

本目录是网易官方「技能系统」作者版技能包 `ability_system` 的整包 vendor；`server/` / `client/` / `common/` 三端各有一棵同名子树（包内模块路径写死这个布局）。

- **纪律**：包内代码一行不改（issue #6 的决定）。定制只发生在双端根聚合入口 `server/AbilityAPI.lua` / `client/AbilityAPI.lua` 与业务层；业务代码不直接 require 包内模块。
- **来源与版本**：包内没有版本号、变更记录或来源 URL，以整包导入 commit `9382ad8`（作者日期 2026-09-19）为准；升级拿官方新包整包替换再 diff 三棵子树。详见 `docs/ability_system-vendor.md`。
- **编辑器侧预设**：技能 / 技能背包 / 锚点预设建在地图里、不进 git；一键重建用 `lua tools/cli.lua ability-presets`（规格在 `tools/ability_presets.lua`，锚点壳源码在 `tools/ability_presets/`），用法另见 AGENTS.md「工具链」。
