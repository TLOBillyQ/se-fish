# #65 P3 七区灰盒布局施工：口径、配方与施工后实测（03–07 区）

> 本文件是[场景落地与验证：应用已确认结构布局并交接实机检查](https://github.com/qinyuanj/se-fish/issues/65) P3 第 1 条的
> 派生产物。数字来自工具，不是手抄：
> 施工前后对比用 `tools/zone_space_contract.lua`（读基线 CSV），
> 施工本身由 `tests/probes/zone_layout_apply.lua`（数据块由 `tools/gen_zone_layout_probe.lua` 生成）执行。
>
> **范围**：本轮只动 **03 蟹湖 / 04 树林岛 / 05 沙滩岛 / 06 礁石岛 / 07 火山岛**。
> **01 鱼塘**保持现状（它的地面/水面本来就自洽，见 P2 §3.1）；**02 虾池**口径单独，见 §4。

## 0. 口径（谁定的）

2026-10-14 用户把 P3 施工口径**委托 agent 决断**（原话「你决定吧」），据此按前一轮交接评论里的建议执行：

| 编号 | 结论 |
|---|---|
| D1 主要活动地面基准 | 取合同 `Scene.SafePoint.y`（后五区 **6.00**）；运行时 `FlightPath.BoundsOf` 的 `GroundY`、摆渡目的地本来就取它，所以是让**场景**去对齐**合同** |
| D2 水陆关系 | **水塘式**：水面保持数学 `SurfaceY`（3.00）留在岸下 3 米，数学水域一个字不改；地块板抬到顶面 6.00 并把水面那块留成塘 |
| D3 边界口径 | **A**：数学范围作外沿、墙内面作有效边界，运行时不动（声明见 `zone-space-contract.md` §1） |
| D4 `Scene.State` | 施工核对后再提升；本轮**不动**配置字面量（见 §4 待办） |
| D5 主题轮廓资源 | 只用现场已有件：`official://preset/1204002`（现场名「海岛山体3」，基准盒 20×10×20）与 `official://preset/1101661`（10×1×10 板） |

## 1. 每区配方（由 `tools/plan_zone_layout.lua` 从合同 + 基线算出，不是手填）

地形 **5 块板**（`official://preset/1101661`，pivot：Y 底面 / XZ 中心）：

| 板 | 范围（以 03 蟹湖为例） | 顶面 |
|---|---|---|
| `Zx_Land`（原地改形） | x 420..540，z −32..48.5（水岸线 → 内侧墙内面），全宽 | **6.00** |
| `Zx_Bank`（新建） | x 420..540，z −68.5..−56（外侧墙内面 → 水的另一侧） | 6.00 |
| `Zx_PondFloor`（新建） | 水面矩形本身，z −56..−32 | **0.00**（水深 3） |
| `Zx_LandSideX430/X530`（新建） | 水面两侧各 20 米宽 | 6.00 |

- 五块板**铺满四面墙内面围出的可达范围且互不重叠**（fast 用例逐区核对面积与重叠）；
  水面那一块不铺地，四周是 6 米高的岸壁 → 池塘式水岸。
- 主题轮廓 **6 座山体**：外侧岸 4 座（x = 区中心 ±20 / ±48）、内侧抵达处 2 座（x = ±45），
  10×12×10，坐在岸顶，**不压水岸线**（外岸那排在水的另一侧，内侧那排在战斗空间之外）。
- 设施动线（#62：抵达 → 补给 → 水岸 → 摆渡；左商店、右抽奖/烧烤、钓鱼佬临水但不压净空间）：

| 对象 | 落位 | 说明 |
|---|---|---|
| `Zx_Fisherman`（交互范围 9³） | 左侧、水岸线内 15 米 | 临水，但含交互口径的岸边净宽仍有 10.5 米 |
| `Zx_Shop`（交互范围 6³） | 左侧偏内侧 | 抵达 → 补给，带 `FishFood` 子树（随父级移动，无需单独操作） |
| `Zx_Lottery` / `Zx_Grill` | 右侧，战斗空间外侧 6 米 | 避开战斗净空间 |
| `Zx_Bait1/2` | 水面两侧外沿（x = 水边 ∓12 之外） | 不落进水岸采样带，不压战斗空间 |
| `Zx_FerryOut` / `Zx_FerryReturn` | 内侧墙内面内 8 米，左右 ±25 | 与抵达点分开 |
| `Zx_Safe`（安全落点） | 区中线、内侧墙内面内 18 米，垫片压平到**顶面 6.00 齐平** | 抵达处 |
| 边界墙 / 水面实体 | **不动** | 水面顶 3.00 与数学 `SurfaceY` 相等 |

## 2. 施工方式与回执

- 写接口：`World:CreateAsset(contentId, pos, {scale})` + `SpaceUnit:SetPosition/SetScale` + `Unit:SetParent`，
  在 `editor-cli exec` 里直调公开 Unit API ——
  这与 [#100 的绕过合同](https://github.com/qinyuanj/se-fish/issues/100#issuecomment-6161565477)一致：
  `editor-cli editor-unit search/transform` 这类按 UnitID 的入口会走全树枚举，撞上
  `WorldService.lua:535` 的 SDK 故障（本轮实测 `transform --dry-run` 直接 `EDITOR_UNIT_SCAN_FAILED`），
  而 `create` 不枚举、可用；本探针**只按名字查找**（`World:FindFirstChild` 递归），不落 UnitID。
- 一次性 99 条操作：**新建 50**（5 区 × 10 件）、**改位姿 49**、**0 失败、0 未命中**。
  探针幂等：重跑只改位姿不重复创建（第二轮实测 `created=0|moved=99`）。
  证据：`zone-baseline-post-p3-log.json` 里的 `P3LAYOUT65` 行（逐条写前/写后回读）。
- 施工**前**的安全基线是 P2 提交的 `zone-baseline-rows.csv`（未改动），回滚路径见 §5。
- 保存：`editor-cli map save` → `save_result.status=success`（1.52 秒）。
  `map dirty` 仍报 `dirty=true`（sources: `cmd_stack_unsaved`/`cmd_stack_manual`）——这是本图**既有的**
  长期现象（P2 与会话评论里都记过），不是本批写入造成，也不能用保存回执代替重开核验。

## 3. 施工后实测（同一把尺子，读现场基线）

基线：`zone-baseline-rows-post-p3.csv`（364 行 = 原 264 + 新建 50 单位 + 50 个 PresetLink；
生成口径见 `tools/baseline_csv.lua`，它能把 P2 的老日志还原成**逐字节一致**的旧 CSV）。
审计：`zone-space-contract-post-p3.{json,txt}`。

| 区 | 地面差（地块顶 − 合同） | 岸边通道（实体 / 含交互） | 连续 ≥8 岸线 | 战斗净空间侵占（贴岸锚法） | 战斗空间支撑 |
|---|---|---|---|---|---|
| 03 蟹湖 | **0.00**（原 −4.00） | **13.25 / 10.50** | 80.0 / 80.0 米 | **0（原 1 碰撞体 + 1 交互）** | **100%**（原 2.3%） |
| 04 树林岛 | 0.00（原 −4.00） | 13.25 / 10.50 | 80.0 / 80.0 米 | **0（原 4 + 2）** | 100%（原 6.2%） |
| 05 沙滩岛 | 0.00（原 −4.00） | 13.25 / 10.50 | 80.0 / 80.0 米 | **0（原 4 + 2）** | 100%（原 6.2%） |
| 06 礁石岛 | 0.00（原 −4.00） | 13.25 / 10.50 | 80.0 / 80.0 米 | **0（原 4 + 2）** | 100%（原 6.2%） |
| 07 火山岛 | 0.00（原 −4.00） | 13.25 / 10.50 | 80.0 / 80.0 米 | **0（原 4 + 2）** | 100%（原 6.2%） |

- **#62 两条指标都达标**：岸边连续通道 8 米下限，实体碰撞体与含交互范围两套口径分别有 13.25 / 10.50 米，
  且连续段长等于整条水岸（80 米）；战斗净空间贴岸锚法下**零侵占**，支撑 100%。
- 岸边净宽从施工前的 26.25 米降到 13.25 米，是**故意的**：设施按 #62 动线往水岸靠（钓鱼佬临水、
  战斗场地紧邻水岸），仍然留下 5 米以上余量。
- 锚法无关的 `W×H` 无侵占窗口数：03 区 907 / 510（施工前 1276 / 1095）、04–05 区 621 / 300、
  06 区 488 / 249、07 区 528 / 269 —— 少了是因为新增了 6 座轮廓山体（正常，且仍远大于 0）。
- **可站立面 5 处**/区：`Zx_Land`、`Zx_Bank`、两条侧沿、`Zx_Safe`（全部顶面 6.00），地面不再只有一块 10×10 垫片。

**没有跑试玩**：本轮的验收是属性/几何口径；站得住、撞得实、体感归 P8 的逐区试玩（也归下一轮的施工后复核）。

## 4. 遗留与差异（下一批的输入）

1. **配置还没跟上场景**（P3 第 3 条）：审计里 `ANCHOR` 行显示 03–05 区 10/15、07 区 9/14 条锚点
   **坐标差非零**（最大 |Δx| 59、|Δy| 1、|Δz| 33），因为 `common/GameCfg.lua` 里仍写着旧计划坐标
   （安全点 `(中心, 6, 中心)`、鱼饵 `(中心±3, 6, 中心−3)`、设施锚点公式）。下一批要把
   `Scene.SafePoint`/`BaitSpots.Positions`/`Entities` 的每区坐标改成与现场一致，并重生成
   P2 的锚点数据块 + fast 守卫。**运行时依赖要单独核对**：摆渡目的地 = 目标区 `SafePoint`、
   `GroundY` = `SafePoint.y`（本次 y 不变 6.00，只动 x/z）。
2. **02 虾池未施工**：现场没有水面实体、可碰撞最高面 5.00、地块板顶 −2.80，安全点 `(240,6,0)` 下方无支撑。
   它的几何与后五区不同（边界 50×120、窄长池岸），配方要单独定；P0 已记「扩地块承接 SafePoint」。
3. **01 鱼塘维持原样**：出生点 5.01 站在山体顶面 5.00 上、水面在地面下 2.96，本来就自洽；
   它的战斗净空间四个候选里有 93.8% 支撑（+X/+Z 侧），但 `TGUnitFish` 的交互范围压在岸线上（设计如此）。
4. **主题轮廓只是粗轮廓**：6 座同一预设的山体按位置/尺度区分，正式美术不在本轮范围。
5. **水下封底仍归 P5**：本轮只给塘底（顶面 0、深 3 米），外墙以下到边界底部的完整封闭是 P5 的事。
6. **`Scene.State` 仍是 `planned`**：按 D4，等配置坐标同步 + 复核通过后再提升。

## 5. 回滚

`tests/probes/zone_layout_apply.lua` 里有第二块生成数据 `ZONE_REVERT`（把 `MODE` 改成 `'revert'` 使用）：
**恢复 94 个基线位姿 + 删除本批新建的 50 件**。判据是**基线存在性**，不是「有没有资产 id」——
`Zx_Land` 属于原地改形，回滚时被恢复而不是删除（fast 用例专门守这条）。

## 6. 复跑

```powershell
# 1) 规划与设计级核算（离线，改了配方后先跑这条：不达标会退出 1）
lua tools/plan_zone_layout.lua
lua tools/gen_zone_layout_probe.lua --check

# 2) 施工（编辑器，写场景；APPLY=false 时只读）
editor-cli exec --file tests\probes\zone_layout_apply.lua --expect-edit-mode --timeout 300 --json
editor-cli log grep P3LAYOUT65 --platform editor --context 0 --max-matches 400 --json

# 3) 施工后：重读基线 → 转 CSV → 审计
editor-cli exec --file tests\probes\zone_baseline_inventory.lua --expect-edit-mode --timeout 180 --json
editor-cli log grep P2BASE65V2 --platform editor --context 0 --max-matches 1500 --json   # 存成 json
lua tools/baseline_csv.lua --log <上一步的 json> --out evidence\issue65\zone-baseline-rows-post-p3.csv
lua tools/zone_space_contract.lua --csv evidence\issue65\zone-baseline-rows-post-p3.csv `
    --json evidence\issue65\zone-space-contract-post-p3.json `
    --text evidence\issue65\zone-space-contract-post-p3.txt

# 4) fast 车道守卫
busted --run=fast
```

本轮哈希（SHA256）：

- 施工前基线 `zone-baseline-rows.csv` = `266C676AB39CB7992E6A470BE112CE3439C45570E691E64C5DC93B7932A0B4FC`
- 规划器 `tools/plan_zone_layout.lua`、探针 `tests/probes/zone_layout_apply.lua`、审计工具
  `tools/zone_space_contract.lua` 的 sha256 见提交与 fast 用例（数据块逐字节守卫）。
