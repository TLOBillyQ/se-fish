# 官方技能包 ability_system（vendored）

- **来源**：网易官方「技能系统」作者版技能包。包内模块路径写死 `server/packages/ability_system/…`，因此三端各放一棵同名的 `packages/ability_system/` 子树。
- **入库方式**：`feat/ability-system-package` 分支整包导入（commit `9382ad8`，58 个文件约 1 万行），2026-09-22 合并进 `main`。
- **版本**：包内没有版本号、变更记录或来源 URL，只能以导入 commit 与时间（2026-09-19 导入）为准。升级时拿官方新包整包替换，再 diff 本仓库的三棵 `packages/ability_system/`。
- **纪律**：包内代码一行不改（issue #6 的决定）。定制只发生在双端根聚合入口 `server/AbilityAPI.lua` / `client/AbilityAPI.lua` 与业务层；业务代码不直接 require 包内模块。
- **本编辑器的限制**：编辑器不认包内的 `---@export_prefab_type` 自定义预设类型（`preset create-asset ability|ability_manager|ability_anchor` 只能建出空预设），所以编辑器侧资产不走「按类型新建」；预设的建法、两个硬假设的结论与命令记录见 issue #7。
- **首期启用范围**：只启用 `speed_add` 锚点（加速小样）。其余 15 种锚点、子技能组（`sub_ability`）、道具箱（`item_box`）、包内技能栏 UI 随包入库但未启用。
