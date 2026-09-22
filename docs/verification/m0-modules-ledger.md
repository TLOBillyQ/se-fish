# M0 模块线台账：V1 水判定 / V5 高频输入契约 / V3 配置落点

- **归属**：mission M14，分支 `feat/m0-v1-v5`，worktree `wt-14`
- **日期**：2026-09-22
- **管什么**：issue #25 里 M0 的**模块线**——V1（水判定转正）、V5（高频输入契约骨架）的结论与证据，
  以及 V3 落在 `common/GameCfg.lua` 的那一半。
- **不管什么**：试玩验证线（V2/V3/V4/V6/V7 的实测）见 mission M15 的台账 `docs/verification/m0-playtest-ledger.md`（与本文件同批落地）。
- **格式**：按 #25 出口判据 3——每条写「验证项 → 结论 → 证据 → 归属」。
- **后续修订**（mission M17，分支 `feat/surfacey-fishcarrier-31`）：按 issue #31 把 §1.1 的 `SurfaceY`
  从 1.55 改成实测值 2.183（§1.3 由「待验」转为「已验」），并落掉 §3 的 `GameCfg.FishCarrier`。

证据里的宿主目录 = `%USERPROFILE%\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`；
日志行号指该目录下 `log.txt`（2026-09-22 那次 #12 原型试玩的记录）。

---

## 1. V1 水判定转正

**结论**：抛竿落点与鱼位置的水判定用**纯数学**——每区「中心 + 水平半宽 + 水面高度」，
逐字沿用原型 `MakeMathJudge` 的语义（`abs(dx) <= halfXZ and abs(dz) <= halfXZ and pos.y <= surfaceY`，
三处都含等号）。射线与 Trigger 两条路都不采用。判定收敛在 `common/MathWaterJudge.lua`，配置在 `GameCfg.Water.Zones`。

| 验证项 | 结论 | 证据 | 归属 |
|---|---|---|---|
| 判定语义进正式模块（W-1 / W-6） | `MathWaterJudge.InZone/HitZone/Build`，与原型 `MakeMathJudge` 逐字同义；`Build` 在装配期校验配置（缺字段 / 半宽非正 / 空表都当场报错，不静默退化成「永远不在水里」） | `common/MathWaterJudge.lua`；原型 `prototype/water-judgment:server/ProtoWater.lua`（commit `bcde0f4`，throwaway 分支，取证入口） | M1 落点判定、M0-V4 入水销毁 |
| 射线不可用（W-2） | 本图的水是水材质渲染 WorldUnit：`CanQuery=true` 但没有命中几何。水中心垂直射线先撞 `TGUnitFish`（命中 y≈6.77，是触发器拦射线），排除触发器后撞大地板（y=2.0），全程碰不到水圈 | 宿主 `log.txt:2213-2215`（`PROTO_WATER \| RAYCAST \| water_center/water_edge/land_control`） | 记录性备案（§8.3），防止后人重走射线方案 |
| Trigger 不可用（当前的鱼资产） | 咸鱼 `CanCollide=false CanTouch=false`，克隆后送进触发器中心也无 `OnTriggerEnter`、`GetPartsInPart` 也查不到；鱼逃脱不依赖 Trigger | #12 结案评论第 2 节；`log.txt:2311-2314` | M0-V4（在移动 tick 里做数学判定 + `Destroy`） |
| 配置不乘 Scale（W-4） | 运行时读到的 `Size` 已含 `Scale`：`WaterCircle2` 的 `Scale.x=2` 已经算进 `Size.x=6`，所以 `HalfXZ` 直接写半边尺寸 3.0 / 1.5，配置时再乘缩放会翻倍 | `log.txt:2207-2208`（INSPECT 的 Position/Size/Scale 三列）；单测 `TestWaterJudgeConfig:test_half_width_does_not_multiply_scale` | M1 落点判定 |
| 水面高于地板（W-7，#31 改正） | 实测推翻 #12 的取值口径：**`Position.y` 是底面、`Size.y` 是包围盒半长**，单位顶面 = `Position.y + Size.y`——大地板 `0 + 2 = 2.000`（与 `log.txt:2214` 的射线命中 y=2.0 对得上）、水圈 `1.18 + 1 ≈ 2.183`。所以水面**高于**大地板表面 y=2.0（原先记的「水面低于地板」是 1.55 那笔错账），水区矩形内的池塘底算在水里 | `docs/verification/m0-playtest-ledger.md`（M15 的实测与交接结论，§3 / §8）；单测 `TestWaterJudgeSemantics:test_point_at_floor_height_inside_pond_is_in_water` | M1 落点判定 |
| 六个边界用例（中心 / 水下 / 空中 / 贴边 ±0.1m / 远处陆地） | 全部通过 | `tests/water_judge_test.lua` → `TestWaterJudgeBoundary`：`test_center_below_surface_is_in_water`、`test_deep_underwater_is_in_water`、`test_air_above_surface_is_not_in_water`、`test_edge_outside_by_point_one_meter_is_not_in_water`、`test_edge_inside_by_point_one_meter_is_in_water`、`test_far_land_is_not_in_water` | M0-V1 |
| 边界含等号 / 多区顺序 | 正好贴在半宽线上、正好落在水面高度上都算在水里；同心水圈按配置顺序命中（外圈 `WaterCircle2` 在前）；Z 轴与 X 轴对称 | 同文件 `TestWaterJudgeSemantics`（5 条）、`TestWaterJudgeConfig`（5 条） | M0-V1 / M1 |

### 1.1 落进 `GameCfg` 的实测配置值

`common/GameCfg.lua` 的 `GameCfg.Water.Zones`：

| Id | Center | HalfXZ（米） | SurfaceY（米） | 出处 |
|---|---|---|---|---|
| `WaterCircle2` | (-11.75, 1.05, 27.75) | 3.0 | 2.183 | `HalfXZ`：`log.txt:2208` 的 `Size(6, 1, 6)` → `Size.x/2 = 3`；`SurfaceY`：#31 改正后取 M15 台账的实测顶面 `1.18 + 1 ≈ 2.183`（`m0-playtest-ledger.md` §3 / §8） |
| `WaterCircle1` | (-11.75, 1.05, 27.75) | 1.5 | 2.183 | `HalfXZ`：`log.txt:2207` 的 `Size(3, 1, 3)` → `1.5`；`SurfaceY` 同上（两圈同心、同一批次读数） |

- 两个水圈同心、同一 AssetId（`map://preset/u54263b69f25482dae18f9dbcfe6dc5b`），外圈包含内圈，
  所以判定结果只可能命中 `WaterCircle2`；`WaterCircle1` 保留在配置里是留 M1「按水区选鱼表」的口子。
- `Center.y` 只作场景溯源，判定只用到 x/z（`MathWaterJudge` 的注释与配置校验都按这个口径）。
- **`Center.y` 与 `SurfaceY` 的取值批次不同**：`Center.y = 1.05` 是 #12 那次 11:46 的 INSPECT 读数，
  `SurfaceY = 2.183` 是 M15 16:24 的读数——水单位运行时在漂移（`pos.y` 1.05 → 1.09 / 1.18），
  两个字段各自溯源、不要互相反推（`SurfaceY - Center.y` 并不等于 `Size.y`）。

### 1.2 判定开销实测（W-3，300 次调用）

| 方案 | 300 次总耗时 | 单次 | 30Hz 逻辑帧下 12 次调用（V4 的鱼上限） |
|---|---|---|---|
| 纯数学（采用） | **0.117 ms** | ≈0.4 µs | ≈0.0047 ms，占一帧（33.3ms）的 0.014% |
| `PhysicsService:Raycast` | 6.210 ms（每发都命中） | ≈20.7 µs | ≈0.25 ms，0.75% |
| `PhysicsService:GetPartBoundsInRadius` | 2.732 ms | ≈9.1 µs | ≈0.11 ms，0.33% |

- 证据：`log.txt:2310`（2026-09-22 11:48:54）`PROTO_WATER | BENCH | n=300 | math=0.117ms raycast=6.210ms(hit 300) overlap=2.732ms`，
  同批的 `BENCH | config | surfaceY=1.5499999523163 | halfXZ=3.0` 在 `log.txt:2308`。
- 三种方案在 30Hz 下都够用，选数学**不是**因为开销（约快 53 倍）而是因为**正确性**：
  射线在本图先撞触发器、再撞地板，拿不到「水」，见 §1 的 W-2 行。
- 记录提醒：同一份日志里 11:47:09 那次 BENCH 打的是 `halfXZ=6.0`（早期版本把 `Size.x` 当半宽），
  11:48:54 那次 `halfXZ=3.0 = Size.x/2` 才是终版口径；按 6.0 理解会得出「水区大一倍」的错误结论。
- 同一批 BENCH 里的 `surfaceY=1.5499999523163` 是 **#31 改正前的旧值**，本文件里凡出现 1.55 都属历史读数；
  终值 2.183 见 §1.1 / §1.3。三组开销数据与 `SurfaceY` 取多少无关（纯数学判定只读配置值）。

### 1.3 水面高度（原「待验」，#31 转已验）

**定案：`SurfaceY = Position.y + Size.y ≈ 2.183`**（配置已按此改正）。原「Position 是底面还是中心」的疑点由 M15 的试玩实测定案，证据来源 `docs/verification/m0-playtest-ledger.md`（§3 入水判定 / §8 交接结论）：

- **口径**：`Position.y` 是**底面**、`Size` 是包围盒**半长**，所以单位顶面 = `Position.y + Size.y`。
  两条自洽读数：大地板 `pos.y=0 + size.y=2 = 2.000`（与 `log.txt:2214` 射线命中的 y=2.0 对得上）、
  水圈 `pos.y=1.18 + size.y=1 ≈ 2.183`。
- **旧值 1.55 错在哪**：它按「`Position` 是几何中心」算成 `1.05 + Size.y/2`，少算了半个包围盒。
  这一笔在 M15 台账里有直接反证：实测的入水点 `y=2.15`（`m0-playtest-ledger.md` §3）在 1.55 下判不到，
  换成 2.183 才判得到。
- **为什么取 2.183 而不是低点 2.05**：水圈运行时会漂移（同一次试玩里 `pos.y` 从 1.05 变到 1.09 / 1.18），
  2.183 是 16:24 那次的高点。判低会把真在水面的点漏成陆地（抛竿不咬钩，玩家可见），
  判高的代价只是水面之上约 0.13m 的空气薄层被算作水里——且判定以 (x,z) 矩形为主、y 只当松过滤，
  这一层兜得住。
- **配置与单测**：`GameCfg.Water.Zones` 两个区的 `SurfaceY` 都改成 2.183；单测把
  `TestWaterJudgeSemantics:test_point_at_floor_height_is_not_in_water` 换成了
  `...:test_point_at_floor_height_inside_pond_is_in_water`（水面现在**高于**地板表面，
  水区矩形内的池塘底算在水里），`TestWaterJudgeBoundary` / `TestWaterJudgeConfig` 的常量同步。
- **语义没变**：`pos.y <= surfaceY` 仍含等号（正好落在 2.183 上算在水里），
  `Center.y = 1.05` 仍是 16:10 那次的读数、只作场景溯源（判定不用它）。

---

## 2. V5 高频输入契约骨架

**结论**：`common/RateLimit.lua` 落「客户端聚合 → `{s,n,q}` 载荷 → 服务端滑动窗限流（超限 clamp）→
服务端权威结果下发」四件套里的**前三件**（下发是 M1 收线会话的事）。全部是纯函数：时间由调用方注入
（`World:GetServerTime()`，秒），不 require 引擎、不碰 `game`，所以能在宿主机 lua 单测里跑。

| 契约点（来源） | 结论 | 证据 | 归属 |
|---|---|---|---|
| C-7 新增 `common/RateLimit.lua`（滑动窗），不动 `REUtil:CheckRECD` | 新文件只服务端高频输入这一条通道；`common/REUtil.lua` 一行未改 | `common/RateLimit.lua`；`git show --stat` 的改动列表里没有 `REUtil.lua` | M0-V5 |
| C-2 每玩家滑动窗 1s ≤10 次；超限 **clamp 不丢弃、不向玩家报错** | `Window:Admit(now, count)` 返回**采纳数**（0 ≤ accepted ≤ count），超限把采纳数压到窗口剩余额度；没有错误路径、也没有「丢弃」路径要业务处理 | `TestRateLimitWindow`：`test_window_allows_ten_per_second`（12 次只采纳 10）、`test_over_limit_clamps_to_zero_without_error`（第 11 次返回 0 而不是报错）、`test_batch_is_clamped_not_dropped`（n=25 → 10）、`test_batch_is_clamped_to_remaining_budget`（已用 6 → n=8 采纳 4） | M0-V5 / M1 |
| 窗口口径 | 看的是 `(now - WindowSec, now]`：`now - WindowSec` 上的批次算过期；额度随时间滑回，不是「每秒清零」 | `test_window_slides_at_the_boundary`（t=0.999 → 0、t=1.0 → 全额）、`test_window_frees_budget_over_time` | M0-V5 / M1 |
| C-1 客户端聚合窗口 100ms 固定可配 | `Aggregator:Click` 只记账，`Collect(now)` 到窗口才产出载荷；没点击或没到窗口返回 `nil`（= 这一帧不发包）；`Flush()` 立即产出 | `test_collect_waits_for_the_window`、`test_collect_emits_payload_with_count_and_monotonic_seq`（n=3、q=1→2）、`test_flush_emits_immediately` | M0-V5 / M1 |
| C-3 载荷 `{s=会话id, n=窗口内点击数, q=单调序号}`；丢弃非当前会话与旧序号 | 字段恰好三个（`RateLimit.PAYLOAD_FIELDS`）；接收侧 `bad-payload / session / order` 三类丢弃 | `test_payload_has_exactly_the_three_contract_fields`、`test_drops_other_session_payload`（含「当前没有会话」）、`test_drops_old_sequence`（重复与乱序都丢） | M0-V5 / M1 |
| R-2 官方五层校验（身份/类型/频率/业务条件/结果下发）的前四层 | `Receiver:Accept` 顺序：先类型 → 再会话 → 再序号 → 才动滑动窗与 `lastSeq`；身份由引擎注入的 `player` 提供（结果下发是 M1） | `common/RateLimit.lua` 的 `Receiver:Accept` | M0-V5 / M1 |
| 畸形包不能打崩服务端 | `nil` / 字符串 / 缺字段 / `s` 非字符串 / `n` 为字符串、0、`inf`、`nan`、`q` 缺失或 0 全部 drop；**`nan` 必须显式拦**，但理由不是「`math.floor` 会抛错」——本机 Lua 5.4.6 实测 `pcall(math.floor, 0/0)` → `true, -nan(ind)`，`math.floor` 本身不抛错。真实危害是两条：① nan 进了窗口账目（`UsedCount`）后 `Remaining` 也是 nan、所有比较恒为 false，`Admit` 每次都「采纳」，**限流被静默关掉**（不报错、不丢弃，比抛错更难发现）；② nan 流到整数化处（当表键、`x \| 0`、`string.format("%d")`）才抛 `table index is NaN` / `number has no integer representation` | `test_malformed_payload_is_dropped_not_raised`（10 个畸形输入）、`TestRateLimitWindow:test_bad_count_is_zero_not_an_error` | M0-V5 |
| 恶意大包 | `n=1e9` 一次请求只采纳窗口额度 10，`Status="ok"` + `Clamped=true`，不影响后续判定 | `test_huge_count_is_clamped` | M0-V5 |
| 会话切换与清理 | 换会话双端一起清（`SetSession` 清 `lastSeq` + 滑动窗；客户端丢未发出的批次、序号从 1 重来）；`EndSession` 后任何包都丢（对应「玩家离开时清理按玩家保存的限频表」） | `test_session_switch_then_old_payloads_drop`、`test_end_session_drops_everything`、`TestRateLimitAggregator:test_set_session_drops_pending_and_resets_seq` | M0-V5 / M1 |
| 端到端串一遍 | 客户端 12 次点击聚合成一个包 → 服务端采纳 10（clamp 2 次）→ 同一个包重放被序号挡掉 | `test_aggregator_payload_flows_through_receiver` | M0-V5 / M1 |
| 配置与逻辑对得上 | `GameCfg.HighFreqInput` = `WindowSec=1.0 / MaxCount=10 / AggregateSec=0.1`，且用这三个值真能建出窗口与聚合器 | `TestRateLimitConfig:test_gamecfg_constants_match_the_decision` | M0-V5 |

**不在本 mission 内**（同一张票的其他列）：ReelIn RE 通道建立（server/client 侧）= M15 的 V5 任务；
进度积分与衰减（C-4）、会话状态机与字段（C-6）、脱钩宽限（C-13）= M1；边沿型契约（C-16 的按住/松开）随武器期，
本骨架的窗口与载荷口径可直接复用。

### 2.1 R-7 三未决项处置

三条都给「书面判断 + 不压测的理由」，并附上**现在就能给的定量上界**（能算的不写「不知道」）。
共同前提：官方对 RemoteEvent 的频率、包大小、超限行为、通道数上限**全无数值**（#14：
`EggyAPI.lua:1995-2020` 只有 `RemoteEvent` 的收发方法、没有配额参数，`game:CreateRemoteEvent` 在存根里出现 **0 次**；
官方手册 RemoteEvent 页正文里「限制/上限/频率/大小/字节/KB」出现 0 次）。反证：官方对真有硬限制的接口会写数字
（`EggyAPI.lua:4341` 的 `MessageService:PublishAsync`：「序列化后大小不能超过 1k 字节，否则将引发错误」）。

| 未决项 | 处置 | 理由（为什么不压测） | 现在能给的定量上界 | 谁接受 |
|---|---|---|---|---|
| ① 上行阈值与超限行为（丢包 / 报错 / 断连） | **书面判断**，不压测 | 没有阈值可比：「压测」在编辑态只能测我们自己发多少，而那是我们自己定的（`AggregateSec=0.1` ⇒ 10 包/秒/人）；唯一官方测试手段是编辑态弱网模拟（R-6），它改的是延迟与丢包，**造不出一个不存在的阈值**。要拿到真阈值只能问官方或在线上环境观测，两者都在 M0 范围外 | 设计上界：**10 包/秒/人**（聚合窗口 100ms），3 人 = 30 包/秒 ≈ 1800 包/分钟。官方给的频率示例是「同一玩家 0.5 秒一次」（2/秒，R-2），我们比示例高 5 倍——但那是**校验示例值**不是配额，不能当判据 | 若 M1 的 3 人弱网验收（M1 出口）出现丢包或断连，M1 接手降级：通道合并 + 降频 |
| ② 载荷真实字节上限 | **书面判断 + schema 推导上界** | 没有公认的字节上限作比较基准，「测多少算过」无判据——压一个不存在的边界是白跑；且编辑器本地回环走的是同机通道，测不到线上网关。真正需要字节证据的时刻是「M1 收线在真实弱网下丢包」，届时按 R-6 + C-11 的比对采纳数定位 | 载荷字段**恰好 3 个**（`PAYLOAD_FIELDS`，单测钉住）：`s` 会话 id（契约要求非空字符串，按 UUID 最坏 36 字符算）、`n ≤ MaxCount = 10`（clamp 后，单测钉住）、`q` 会话内单调整数（单局内远小于 2^31，按最坏 19 位十进制算）⇒ 单包**几十字节**量级（最坏 ~60 字节），且与点击频率无关（聚合把频率折成 `n` 一个数）。对照官方唯一写明的同类上限 1KB（`MessageService:PublishAsync`）：1KB / 60B ≈ 17 倍，即**小一个数量级以上、约为其 1/17** | M1（弱网验收）；官方若给出字节上限，回到本表改上界 |
| ③ `game:CreateRemoteEvent` 无文档 + 通道数上限无口径 | **书面判断 + 通道数现状（可数，已数）** | 上限没有口径，也没有任一官方实现里的参考值；压测只能证明「还没到上限」，证明不了上限是多少。能做的降风险动作是**控制增长**，不是测量 | 本图通道现状（2026-09-22 仓库 grep）：REUtil 通道 **10 条**（`CancelFish` / `CloseScreenRE` / `DoneFish` / `FishLevelUp` / `GlobalMarquee` / `MsgNoticeRE` / `OpenScreenRE` / `ReqFish` / `ResetGM` / `RodLevelUp`）。**通道数不是常量**：`server/packages/ability_system/component_scripts/box_component_create.lua:52` 与 `client/packages/ability_system/component_scripts/box_component_fix.lua:24` 按单位开通道 `BoxComponentCreated_<UnitId>`，随包内建的单位数增长。降风险动作（#15 备案 C-8）：新通道只加 1 条（ReelIn，M15 建），此后通道数增长优先合并为带 `action` 字段的单通道；`box_component` 那条属 vendored 包，按 `docs/ability_system-vendor.md` 的纪律升包时不动 | 官方答复（R-4「问官方」）落地后回填本表 |

R-1（「无官方口径」这件事本身）也是记录性结论，已在上面的共同前提里写清，后人不必再调研一遍。

---

## 3. V3 配置落点（与试玩验证线的交接）

- **我负责**：`common/GameCfg.lua` 末尾的 V3 段落——拿到写法结论后填 `GameCfg.FishCarrier`
  （官方模型号 7000544 号段 + `RenderMeshId/PhysicsMeshId` 的写法）。
- **现状**：**已落盘**（#31，mission M17）。`GameCfg.FishCarrier.Models` 收了官方鱼模型库 20 条
  （模型号 `7000544–7000563` ↔ 官方预设 `official://preset/9000092–9000121`），每条给
  `Mesh`（可直接写进 `RenderMeshId` 的值）、`Name`、`Preset`；F-7 的 `[未查证]` 由此消除。
- **交接方**：mission M15（分支 `feat/m0-3-v2-v7`）在试玩里查实写法后经 `TowerSend` 交回，
  同时写进它的台账（`m0-playtest-ledger.md` §2.1）。
- **落进来的三条写法结论**（全部来自 M15 台账 §2.1）：
  1. `RenderMeshId = "official://mesh/<模型号>"`；
  2. `PhysicsMeshId` 创建时可省略，缺省就取 `RenderMeshId`（`EggyAPI.lua:6747`），
     也可以两个字段写同一个值（本图现有 `/World/罗飞鱼` 就这么写）；
  3. `official://preset/...` 也能建出来但只是**空壳**（`Size=(1,1,1)`、无几何）——配置里只放
     `official://mesh/<模型号>`。
- **写法守卫**：`tests/water_judge_test.lua` 的 `TestFishCarrierConfig` 钉住
  「`Mesh = official://mesh/<模型号>`」与 20 条号段连续；本 mission 的仓库侧改动只允许动三个文件，
  所以没另开 `tests/fish_carrier_test.lua`。
- **仍要策划定案**：`GameCfg.FishMap` 的 13 个鱼种里 **11 个**能在号段内一一对上；**章鱼**不在号段
  （台账记为模型号 `6000019` / `official://preset/1510600`）、**大章鱼**没有对应模型号（台账建议退化为章鱼）。
  台账 §2.1 同一句里又写「12 个能直接对上」，与「章鱼/大章鱼不在 7000544 段」口径不一，
  这里按「11 段内 + 1 外段 + 1 无」理解（差异已 `TowerFinding` 备案）。
- **下一步**：M2「打鱼变现」按 `World:CreateUnit("WorldUnit") + RenderMeshId` 建鱼；
  克隆场景里的鱼（台账 §2.2）只作对照，不走进生产链路。

---

## 4. 复现

```bash
cd <仓库检出>          # worktree 也行，测试不碰编辑器
lua tests/run.lua      # 全量单测；本文件引用的用例都在 tests/water_judge_test.lua 与 tests/rate_limit_test.lua
```

改过的 `.lua` 逐个过一遍语法检查（本机 `luac` 是 5.5，对 `for` 循环变量会报假错，用 `lua` 5.4）：

```bash
lua -e "assert(loadfile('common/MathWaterJudge.lua'))"
lua -e "assert(loadfile('common/RateLimit.lua'))"
lua -e "assert(loadfile('common/GameCfg.lua'))"
```

**证据重放（需要编辑器，属试玩线）**：原型分支 `prototype/water-judgment` 的 `server/ProtoWater.lua` +
宿主目录 `log.txt` 里的 `PROTO_WATER` 行（INSPECT / RAYCAST / BENCH / TRIGGER）。

---

## 5. 遗留与归属

| 项 | 说明 | 归属 |
|---|---|---|
| 章鱼 / 大章鱼的模型号 | `GameCfg.FishMap` 的鱼种对照缺 2 条：章鱼在外号段（`6000019` / `official://preset/1510600`）、大章鱼无对应模型号（台账建议退化为章鱼），要策划定案；见 §3 | 策划 / M2 |
| ReelIn 通道建立 | server/client 侧 RE 通道 + 端到端打通（本文件只管载荷与限流契约） | M15 |
| 边沿型契约 | 按下/松开两条消息（按住连发类武器） | M1 / 武器期 |
| R-4「问官方」 | `CreateRemoteEvent` 文档与通道数上限 | 人类 / 官方 |
| 水面高度与鱼表 | M1 按水区选鱼表（现在是同心两区，只可能命中外圈） | M1 |

已结项（不再是遗留）：**水面高度**——#31 定案为 2.183 并落进配置，见 §1.1 / §1.3；
**`GameCfg.FishCarrier`**——#31 落盘，见 §3。
