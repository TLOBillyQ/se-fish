# 官方包 vendor 说明

三端 `packages/` 是网易官方作者版包的整包 vendor；`server/` / `client/` / `common/` 三端各有一棵同名子树（包内模块路径写死这个布局，所以三端都要放）。

## 纪律

- **包内代码一行不改**。定制只发生在双端根聚合入口与业务层；业务代码不直接 require 包内模块。
- 包内没有版本号、变更记录或来源 URL，以整包导入为准；升级拿官方新包整包替换，再 diff 三棵子树确认改动面。
- 官方包从宿主回灌用 `lua tools/cli.lua sync --packages`：三端按原始字节镜像，删除宿主已不存在的包文件，保留仓库三端根现有 README；源三端任一目录缺失或为空则整次同步在写入前失败。普通 `sync` 不回灌 packages。
- `client/packages/`、`common/packages/`、`server/packages/` 及全部子内容排除出 `deploy` 镜像和 `--clean`；仓库与宿主已有包均保留。运行代码仍依赖这些包，宿主须自行保持所需官方包可用；仓库 vendor 用于查阅与接缝校对，部署不负责安装或升级它们。
- 部署收尾只执行 validate 与只读 diff，不执行全工作区 `code push`。editor-cli 0.19.1 的 CLI 同步不读取 `excludePatterns`，且没有目录排除参数；有本地新增或不同文件时报告尚未同步并返回失败，地图侧独有文件只提示保留。
- 包说明统一写在本文件；三端 packages 目录内现有 README 保留，不再新增 README。

## 包清单

| 包 | 用途 | 导入时间 | 根聚合入口 |
|---|---|---|---|
| `ability_system` | 技能系统 | 2026-09-19（整包导入 commit `9382ad8`） | `server/AbilityAPI.lua`、`client/AbilityAPI.lua`（名单在 `common/AbilityAPIBase.lua`） |
| `attr_rule` | 属性规则（属性单位 / 属性Buff单位） | 2026-10-08（#153） | `server/AttrAPI.lua`、`client/AttrAPI.lua`（名单在 `common/AttrAPIBase.lua`） |
| `modifier_system` | 效果（Buff）系统 | 2026-10-08（#153） | `server/ModifierAPI.lua`、`client/ModifierAPI.lua`（名单在 `common/ModifierAPIBase.lua`） |
| `official_ai_feature` | 生物 AI（依赖 `ability_system` 服务端门面） | 2026-10-08（#153） | `server/AiAPI.lua`（名单在 `common/AiAPIBase.lua`，client 侧无 api.lua） |
| `win_rule` | 胜负结算规则 | 2026-10-09（从宿主整包回灌） | 尚未接入业务聚合入口 |

`win_rule` 暂缓接入正式结算：结算枚举遮蔽会造成异常与半结算状态（[GitHub #58](https://github.com/TLOBillyQ/se-fish/issues/58)，独立模拟已复现）；未结算玩家离开后缺少全员结算重判（[GitHub #59](https://github.com/TLOBillyQ/se-fish/issues/59)，静态审查发现，待编辑器验证）。包内保持原文，优先等待官方整包修正版，业务接缝方案另行评估。

接缝契约：聚合入口的转发名单与包内 `api.lua` 导出由单测拿源码文本校对（`tests/gameplay/ability_api_test.lua`、`tests/gameplay/package_api_test.lua`），包升级改名/删名时在加载期与单测同时暴露。

## 编辑器侧预设依赖

包经 `map://preset/...` AssetKey 引用地图内预设；预设建在地图里、不进 git，随地图存档。各包依赖的预设类型与模板：

| 包 | 预设类型 | 标题 | template_id |
|---|---|---|---|
| `ability_system` | `ability` | 技能 | `map://preset/uc57b9f26db1463083f9ace34d6db0d5` |
| `ability_system` | `ability_manager` | 技能背包 | `map://preset/u014968df4aa4427aebac4388ed79bf7` |
| `ability_system` | `ability_anchor` | 锚点 | `map://preset/uccfb9dbe3f4428bb972096ba01f1f25` |
| `attr_rule` | `AttrUnit` | 属性单位 | `map://preset/u801ef1a3a924db391741602e6eee295` |
| `attr_rule` | `AttrBuffUnit` | 属性Buff单位 | `map://preset/u95e3ac002304b8483aa099a955e14a8` |
| `modifier_system` | `modifier` | 效果 | `map://preset/u1b5be6f141c4898956df10e229c33c3` |

另：`attr_rule` 在编辑器里导出「全局默认属性」配置（`List<attr_rule.AttrConfig>`）；`official_ai_feature` 无预设引用。

预设丢失时在编辑器里按上表类型手动重建；技能包预设另有一键重建工具 `lua tools/cli.lua ability-presets`（规格在 `tools/ability_presets.lua`）。
