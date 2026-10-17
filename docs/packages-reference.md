# 官方包接入参考

三端 `packages/` 保存网易官方作者版包；包内模块路径依赖 `server/`、`client/`、`common/` 同名子树布局。

## 镜像与升级

- `deploy` 以仓库为源，三端 `packages/` 与业务一级子树一起字节镜像；宿主多余文件会删除。`deploy --clean` 也删除对应包子树。
- `sync --packages` 以宿主为源，按原始字节回灌三端包并删除仓库多余文件，根 `README.md` 同样参与镜像。任一端来源缺失或为空时，整次同步在写入前失败；普通 `sync` 不回灌包。
- 回灌前先确认工作区已提交。部署前确认需要保留的宿主包修改已回灌，避免被仓库覆盖。
- 部署收尾执行 validate → 有差异时 push → diff 复核。push 后复核失败、离线、无 changelist 或仍有差异均返回失败；地图侧独有文件只提示保留。
- 包内没有版本号、变更记录或来源 URL，升级以整包导入为准，替换后 diff 三端子树确认改动面。
- 业务层通过根聚合入口接入。转发名单与包内 `api.lua` 导出由 `tests/native/ability_api_test.lua`、`tests/native/package_api_test.lua` 校对，升级改名或删名时须重新核对契约。

## 包清单

| 包 | 用途 | 导入时间 | 根聚合入口 |
|---|---|---|---|
| `ability_system` | 技能系统 | 2026-09-19（commit `9382ad8`） | `server/AbilityAPI.lua`、`client/AbilityAPI.lua`；名单在 `common/AbilityAPIBase.lua` |
| `attr_rule` | 属性规则 | 2026-10-08（#153） | `server/AttrAPI.lua`、`client/AttrAPI.lua`；名单在 `common/AttrAPIBase.lua` |
| `modifier_system` | 效果（Buff）系统 | 2026-10-08（#153） | `server/ModifierAPI.lua`、`client/ModifierAPI.lua`；名单在 `common/ModifierAPIBase.lua` |
| `official_ai_feature` | 生物 AI | 2026-10-08（#153） | `server/AiAPI.lua`；名单在 `common/AiAPIBase.lua`，client 侧无 api.lua |

`win_rule` 于 2026-10-09 从宿主删除并经回灌移除，删除前未接入业务聚合入口或正式结算。原包有结算枚举遮蔽（[GitHub #58](https://github.com/qinyuanj/se-fish/issues/58)）及未结算玩家离开后缺少全员结算重判（[GitHub #59](https://github.com/qinyuanj/se-fish/issues/59)）的问题。删除不代表缺陷已修复，重新引入须取得官方修正版并验证结算与玩家离开时序。

## 架构图上的位置

图上三棵树只画业务源码，三端 `packages/` 不建类；业务代码对这些包的 `require` 收成外部椭圆，由 `policy.edn` 的 `:foreign` 三个端级前缀（`client.packages`、`common.packages`、`server.packages`）匹配，每端一个椭圆；新增包无需改 policy。决策与后果见 [ADR-0005](adr/0005-packages-as-external.md)；指标仍全量采集包内代码，只是没有对应类可上色。

## 编辑器预设依赖

包通过 `map://preset/...` AssetKey 引用地图内预设；预设随地图存档，不进 git。代码部署不能替代预设创建。

| 包 | 预设类型 | 标题 | template_id |
|---|---|---|---|
| `ability_system` | `ability` | 技能 | `map://preset/uc57b9f26db1463083f9ace34d6db0d5` |
| `ability_system` | `ability_manager` | 技能背包 | `map://preset/u014968df4aa4427aebac4388ed79bf7` |
| `ability_system` | `ability_anchor` | 锚点 | `map://preset/uccfb9dbe3f4428bb972096ba01f1f25` |
| `attr_rule` | `AttrUnit` | 属性单位 | `map://preset/u801ef1a3a924db391741602e6eee295` |
| `attr_rule` | `AttrBuffUnit` | 属性Buff单位 | `map://preset/u95e3ac002304b8483aa099a955e14a8` |
| `modifier_system` | `modifier` | 效果 | `map://preset/u1b5be6f141c4898956df10e229c33c3` |

`attr_rule` 还需编辑器导出的「全局默认属性」（`List<attr_rule.AttrConfig>`）；`official_ai_feature` 无预设引用。

预设丢失时按上表类型在编辑器重建；技能包可用 `lua tools/cli.lua ability-presets`，规格见 `tools/ability_presets.lua`。
