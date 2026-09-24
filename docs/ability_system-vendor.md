# 官方技能包 ability_system（vendored）

- **来源**：网易官方「技能系统」作者版技能包。包内模块路径写死 `server/packages/ability_system/…`，因此三端各放一棵同名的 `packages/ability_system/` 子树。
- **入库方式**：`feat/ability-system-package` 分支整包导入（commit `9382ad8`，58 个文件约 1 万行），2026-09-22 合并进 `main`。
- **版本**：包内没有版本号、变更记录或来源 URL，只能以导入 commit 为准（`9382ad8` 的作者日期是 2026-09-19，合并日期 2026-09-22）。升级时拿官方新包整包替换，再 diff 本仓库的三棵 `packages/ability_system/`。
- **纪律**：包内代码一行不改（issue #6 的决定）。定制只发生在双端根聚合入口 `server/AbilityAPI.lua` / `client/AbilityAPI.lua` 与业务层；业务代码不直接 require 包内模块。
- **唯一的包外接口**：`AbilityAPI.AttachAnchor`（仅服务端根入口）是 #7 回执后 #6 拍板接受的偏离——根入口除转发 `api.lua` 导出名单外，代做锚点壳在本编辑器里做不了的事（加载 `anchor_logic` 框架 + 按名挂 `anchors/` 行为），理由与拒绝「改走内建 Ability/AbilityManager」的论证留在 issue #6。它触碰的包内模块有单测的文件存在性兜底（`tests/ability_api_test.lua`）。
- **本编辑器的限制**：编辑器不认包内的 `---@export_prefab_type` 自定义预设类型（`preset create-asset ability|ability_manager|ability_anchor` 只能建出空预设），所以编辑器侧资产不走「按类型新建」；预设的建法、两个硬假设的结论与命令记录见 issue #7。验证期建好的五个预设（技能背包 / 加速技能 / 加速锚点 / 挥砍技能 / 挥砍锚点）不进 git，一键重建用 `lua tools/cli.lua ability-presets`（issue #9，规格与锚点壳源码在 `tools/ability_presets.lua` 与 `tools/ability_presets/`）。
- **首期启用范围**：启用 `speed_add`（加速）与 `melee_hit`（挥砍，issue #8 的成果）两个锚点，启用清单以 `common/GameCfg.lua` 的 `GameCfg.Ability.InitialAbilities` 为准。其余 14 种锚点、子技能组（`sub_ability`）、道具箱（`item_box`）、包内技能栏 UI 随包入库但未启用。
- **挥砍告警适配（issue #65）**：本图通过 `server/AbilityAPI.lua` 将 `melee_hit` 路由到 `server/AbilityBehaviors/melee_hit.lua`。该业务副本基于官方导入版本 `9382ad8`，仅把两处 `TakeDamage(damage, owner)` 改成 `TakeDamage(damage)`；`EggyAPI.lua` 的 `BaseController` 只声明一个 `damage` 参数，实测多传 `owner` 会在命中鱼受击体时产生 `framecore1::Instance` 类型告警。升级官方包时对比这份副本的命中、动画及回收逻辑。
