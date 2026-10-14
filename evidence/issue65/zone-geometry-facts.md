# #65 P2 基线与几何事实（编辑器属性口径）

> 本文件是[场景落地与验证：应用已确认结构布局并交接实机检查](https://github.com/qinyuanj/se-fish/issues/65) P2 的派生产物。
> 原始回读（未加工）：`zone-baseline-exec.json` / `zone-baseline-log.json`（场景基线）、
> `config-anchor-exec.json` / `config-anchor-log.json`（配置锚点）。
> 机器可读基线：`zone-baseline-rows.csv`（264 行，逐单位）。

## 0. 先读口径

1. **属性回读 ≠ 运行时角色碰撞**。本项验收的是「按属性解析出来的名称、类型、层级、变换、
   尺寸与碰撞开关」；角色胶囊、三倍体型、游泳/飞行状态下的实际碰撞归 P8。
2. **pivot 约定只有部分被实测**。七区空气墙（preset `1101635`）已由 P1 的运行时射线实测为
   「Position 是**底面**起点、X/Z 以 Position 为中心」。其它 preset 未实测，所以下文凡涉及
   上/下表面，一律同时给出**底部假设**与**中心假设**两套数值，并单独声明哪一套与现场自洽。
3. **`Size` 已含 `Scale`**：例 `size=138,3,138` = `scale=46,1,46` × 预设基准 `3,3,3`。
   编辑器 API 没有包围盒成员（`SpaceUnit` 只有 `Get/SetPosition`、`Get/SetRotation`、
   `Get/SetScale`、`GetProperty`），所以「模型包围盒」只能用 `Size` 表达。
4. **`EffectUnit` 不是 `SpaceUnit`** → `GetPosition()` 回读为 nil，基线里记 `-`，
   不能把 `-` 当坐标 0。全图 4 个特效单位（鱼塘 1、虾池 2、根级 1）都如此。
5. **同名查找的层级语义**：`Unit:FindFirstChild(name)` **只匹配直接子级**（第二个参数被静默
   忽略）；只有 `World` 服务的 `FindFirstChild(name)` 才递归。需要递归时手工栈遍历。
6. **编辑器 exec 沙盒不能 `require`**（`sdk.common.lua:830: attempt to call a nil value
   (field 'require')`），也没有 `io`/`os`。所以配置锚点清单必须离线生成后嵌字面量（见 §2）。

## 1. 基线快照（每批修改前的可恢复基线）

探针：`tests/probes/zone_baseline_inventory.lua`（只读，MARK `P2BASE65V2`）。
七区子树共 **264 个节点**；根级（`World` 直接子级）另有 **11 个对象**。

| 区 | 子树节点 | Folder | 空间单位 | TriggerUnit | EffectUnit | PresetLink |
|---|---|---|---|---|---|---|
| 01 鱼塘 | 40 | 4 | 23 | 2 | 1 | 13 |
| 02 虾池 | 36 | 4 | 19 | 2 | 2 | 13 |
| 03 蟹湖 | 38 | 5 | 19 | 2 | 0 | 14 |
| 04 树林岛 | 38 | 5 | 19 | 2 | 0 | 14 |
| 05 沙滩岛 | 38 | 5 | 19 | 2 | 0 | 14 |
| 06 礁石岛 | 38 | 5 | 19 | 2 | 0 | 14 |
| 07 火山岛 | 36 | 5 | 18 | 2 | 0 | 13 |

- 层级：鱼塘与虾池是 `地块 / 摆渡 / 空气墙 / 设施` 四个 Folder（**没有「水域」Folder**，
  水圈单位直接挂在地块下）；三区起每区多一个 `水域` Folder。
- 全图类型计数（`GetUnitsByUnitType`，`exact=true`）：`WorldUnit` 118、`Folder` 43、
  `TriggerUnit` 14、`EffectUnit` 4、`SpawnLocationUnit` **1**（只在鱼塘）、`PresetLink` 95 在区内。
- 根级 11 个对象：7 个区根 Folder + `FX` Folder + 两条空 `名称1` Folder +
  `渐变光-箭头`（EffectUnit）。按名探测 `预设链接` / `加速锚点` 均返回 **nil**
  （与 2026-10-14 的现场一致）；`Script` / `PresetLink` 类型不可枚举，根级这两类残留
  **本清单不覆盖**，属非穷尽项。用户对根级残留的裁定仍是「暂不清理，保持现状」。
- 基线身份用「区 / 路径 / 类型 / 名称」表达，**不含 `UnitId`**：本轮加载的临时 ID 不是
  跨加载稳定标识。复跑方式：同探针 + `log grep P2BASE65V2`，重新生成 `zone-baseline-rows.csv`
  后与提交版本 diff（子级按名称排序，输出稳定）。

## 2. 配置依赖复解析

探针：`tests/probes/config_anchor_resolution.lua`（只读，MARK `P2CFG65`）。
清单由 `lua tools/gen_config_anchor_probe.lua` 从 `common/GameCfg.lua` 离线生成并嵌入；
fast 车道的 `tests/native/config_anchor_baseline_sync_test.lua` 逐字节守卫它不漂移。

**结果：142 条锚点，128 条现场命中，0 条歧义（无同名多命中），0 条落在预期区之外，
14 条未命中且全部是配置自己标 `state=planned` 的项**（未命中 `observed` 的为 **0**）。

- 运行时真正按名查找的消费者全部命中：`Interact.Fishermen` 7、`Shop.Stands` 7、
  `Grill.Points` 5、`Lottery` 7、`Ferry.Outbound/Return` 12、`Scene` 命中的 90 条。
- 14 条未命中，逐条原因（都不是「现场少了东西」那么简单，属命名口径）：

| 未命中 | 条数 | 现场实际 |
|---|---|---|
| `Z1_Safe` / `Z2_Safe` | 2 | 鱼塘/虾池的安全点单位现场叫 `出生点`（挂在 `摆渡` 下）；配置里 `SafePointName` 是 `planned` |
| `Z1_Bait1..5` / `Z2_Bait1..2` | 7 | 鱼饵刷新位只有数学坐标，未建同名单位 |
| `Z1_BoundaryWest/East/South/North` | 4 | 鱼塘六面墙现场名全是 `无形方块`（无名方向） |
| `Z2_Water` | 1 | 虾池**现场没有水面实体**（配置注释已声明未核实） |

## 3. 几何事实

### 3.1 落地支撑与地面高度

| 区 | 现场落地物（位置 / 尺寸） | 上表面（底部假设 / 中心假设） | 合同 `GroundY` | 差（底部假设） |
|---|---|---|---|---|
| 01 鱼塘 | `大地板` (−13.75, 0, 0.75) 90×2×60；`海岛山体3` (−1.75, −5, −1.25) 40×10×40 | 2.00 / 1.00 ；山体 **5.00** / 0.00 | 5.01 | 山体 **+0.01**，地板 −3.01 |
| 02 虾池 | `星光地板` (240, −3, 0) 4×0.2×6；`海岛山体3`×3 (230,−5,−6)/(235,−6,−6)/(242,−5,1) 各 20×10×20 | −2.80 / −2.90 ；山体 5.00 / 4.00 / 5.00（中心 0 / −1 / 0） | 6.00 | 最高山体 **−1.00** |
| 03–07 | `Zx_Land` (区中心, 0, 区中心) 120×2×140；另有 `Zx_Safe` 垫片 (区中心, 6, 区中心) 10×0.2×10 | 2.00 / 1.00 | 6.00 | **−4.00**（中心假设 −5.00） |

- **鱼塘自洽性检查**：出生点单位实测 `(6.26, 5.01, −0.71)`，与合同 `SafePoint` 完全一致；
  它脚下的 `海岛山体3` 在**底部假设**下上表面 = −5 + 10 = 5.00，与出生点差 0.01（离地间隙量级）；
  在中心假设下是 0.00，差 5.01。**只有底部假设能解释这一处现场**——这是属性口径的推断，
  不是射线实测（该 preset 与 P1 实测的 `1101635` 不同）。
- **虾池**：全图唯一的 `SpawnLocationUnit` 在鱼塘，虾池没有出生点单位，其 `SafePoint`
  `(240, 6, 0)` 是配置声明值（`state=planned`）；区内可碰撞地面的最高上表面是 5.00（底部假设），
  比合同地面高 1.00。
- **三区起**：`Zx_Land` 上表面 2.00（底部假设）比合同 `GroundY` 6.00 低 4.00，
  **中心假设下低 5.00——两种假设都解释不了，所以这个差值与 pivot 无关**。
  区内除地块板以外没有任何与地面同高的可碰撞水平面：`Zx_Safe`（10×0.2×10）是唯一落在 y=6
  的落地物，设施锚点（`Lottery`/`Grill`/`FerryOut`/`FerryReturn` 底面 y=5.00，
  `Bait1/2` 底面 y=6.00）到地块板上表面之间没有别的 `CanCollide` 单位。
- 同批的一条反向佐证：三区起的 `Zx_Water` 板 `Position.y=2` + 厚 1 = **3.00**，正好等于数学水域
  的 `SurfaceY=3`——说明这一批按「Position 是底面」放置。

### 3.2 水岸与水域

| 区 | 现场水面实体 | 所在侧 | 数学水域 |
|---|---|---|---|
| 01 鱼塘 | `WaterCircle1` 6×1×6、`WaterCircle2` 12×1×12（同心，(−11.75, 1.05, −12.25)） | 圆形水圈 | 33 个（2 圆 + 31 条水带），`Center.y=1.05`、`SurfaceY=2.183`；实体上表面 2.05（底部假设），差 0.13 |
| 02 虾池 | **无** | — | `ShrimpPool` `Center=(235, 4.2, −6)`、`SurfaceY=5.6` |
| 03 / 04 | `Zx_Water` 80×1×24 @(区中心, 2, 区中心−44) | **−Z 侧** | `Center=(区中心, 2, 区中心−44)`、`SurfaceY=3`（= 实体上表面，底部假设） |
| 05 / 06 / 07 | `Zx_Water` 80×1×24 @(区中心, 2, 区中心+44) | **+Z 侧** | `Center=(区中心, 2, 区中心+44)`、`SurfaceY=3` |

- 水域板在 120×140 地块板的范围之内（80×24），所以「岸」是同一块板上水面与非水面的交界，
  不是两块板拼缝；两侧各留 20 单位露出陆地（x 向）。
- 三/四区水在 −Z、五/六/七区在 +Z，来源是布局变换对第 2–4 区取 `sign=-1`（180° 镜像），
  不是摆放错误。
- 鱼塘是唯一有「现场水面实体 + 数学水带」双份的区；虾池是唯一**完全没有现场水面实体**的区。

### 3.3 模型盒与碰撞范围

`Size` 口径下的碰撞开关分布（264 节点全查）：

- `CanCollide=true`：七区地块板、山体/岛屿、`空气墙`（30 面）、`Zx_Safe` 垫片、设施实体
  （`Lottery`/`Grill`/`Zx_FerryOut`/`Zx_FerryReturn`/`Bait*`/`Shop/FishFood`/`FishermanModel`/`FerryBoat`）；
- `CanCollide=false` 但 `CanQuery=true`：七区 `Zx_Water` 水面板、鱼塘 `WaterCircle1/2`、
  鱼塘 `出生点`（SpawnLocationUnit）；
- `TriggerUnit`（`TGUnitFish*`/`TGUnitShop*`/`Zx_Fisherman`/`Zx_Shop`）没有
  `CanCollide`/`CanQuery` 属性（回读 nil），只有 `PhysicsActive=true`；
- 装饰件（`中式杆`/`直线绳索`/`铁艺弯钩`/`咸鱼`）`CanCollide=false`。

三区起的灰盒是**同一套模板**（相对区中心的偏移），五/六/七区是它的 180° 副本：

| 对象 | 三/四区偏移 (dx, dz) | 底面 y | 尺寸 |
|---|---|---|---|
| `Zx_Land` | (0, 0) | 0 | 120×2×140 |
| `Zx_Water` | (0, −44) | 2 | 80×1×24 |
| `Zx_Safe` | (0, 0) | 6 | 10×0.2×10 |
| `Zx_FerryOut` | (−15, +10) | 5 | 1.5³ |
| `Zx_FerryReturn` | (+15, +10) | 5 | 1.5³ |
| `Zx_Fisherman` | (+20, 0) | 5 | 9³（TriggerUnit） |
| `Zx_Shop` | (−20, 0) | 5 | 6³（TriggerUnit，另带 `FishFood` 2×1.5×2） |
| `Zx_Grill` | (+10, +10) | 5 | 1.5³ |
| `Zx_Lottery` | (−5, −5) | 5 | 1.5³ |
| `Zx_Bait1/2` | (±3, +3) | 6 | 1.5³ |
| `Zx_Boundary*` | 四面墙 | −30 | 120(或3)×70×3 |

### 3.4 方位命名（按名推方向不可靠）

实测 `Xx_BoundaryEast` 的坐标：鱼塘墙无名（六面皆 `无形方块`，其中 x=−67.5 的面在 P1 里按
坐标称「东墙」）；虾池 East x=215、蟹湖 East x=420、树林岛 East x=660（**都是 −x 侧**）；
沙滩岛 East x=780、礁石岛 East x=540、火山岛 East x=300（**+x 侧**）。North/South 同样成对相反。
即 2/3/4 区（180° 镜像那批）的名字方向与 5/6/7 区相反——与 #61 §4.2 记录的「Z3/Z4 旋转 180°」
同源，本轮把它扩到**全部七区**并落到坐标上。改任何边界/门/接缝前必须按坐标判向，不能按名判向。

## 4. 未定项与交接

- **pivot 只在 preset `1101635` 上被射线实测**；本节其它 preset（`1101661`、`1204002`、
  `map://preset/u54263b…`、`map://preset/u46466002…`）的顶/底是把两种假设都列出来的，
  鱼塘出生点那一处支持「底部」。要在属性口径外定论，复用
  `tests/probes/air_wall_bounds_runtime.lua` 的同一手法（试玩内射线）即可。
- **`common/GameCfg.lua:1232` 的「后五区未建」与 `Scene.State='planned'` 已经过期**：
  三区起的 `Zx_Land`/`Zx_Water`/`Zx_Safe`/摆渡锚点/设施锚点都在现场。是否把 `State` 提升为
  `observed`（配置注释要求「不能由名称匹配自动提升」）与 §3.1 的 4 单位落差如何对齐，都是 P3 的输入。
- 本项只覆盖属性口径；地面实际站得住、水面判定、角色碰撞、体感全部归 P8。

## 5. 复跑

```powershell
# 场景基线（只读）
editor-cli exec --file tests\probes\zone_baseline_inventory.lua --expect-edit-mode --timeout 120 --json
editor-cli log grep P2BASE65V2 --platform editor --context 0 --max-matches 1500 --json

# 配置锚点（只读；先按当前 GameCfg 重新生成数据块）
lua tools/gen_config_anchor_probe.lua
editor-cli exec --file tests\probes\config_anchor_resolution.lua --expect-edit-mode --timeout 120 --json
editor-cli log grep P2CFG65 --platform editor --context 0 --max-matches 800 --json
```
