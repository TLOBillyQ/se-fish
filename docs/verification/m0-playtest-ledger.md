# M0 试玩验证台账（V2–V7）

**来源**：issue #25「M0 技术验证」的 V2–V7（路线图 §2.2，`docs/plan/mvp-roadmap.md`）。V1/V8 与工具链前置由并行线承担（M14 = V1/V5 的 `common/RateLimit.lua` 与高频输入骨架；V8 的三票见路线图 §9），本台账只记本线跑出来的东西。

**验收形态**：`editor-cli` 试玩日志 + 探针 + 语法/单测，**不要求可玩闭环**（路线图 §2.1 判据 5）。

**硬约束遵守情况**

- 全程**没有执行 `map save`**。
- `play start` / `play stop` 之间不与其它 worker 抢试玩 session（动手前查 `editor-cli status --json` 的 `in_game_runtime`）。
- 探针与临时产物放 `tmp/m15/`（`.gitignore:32` 的 `tmp/`，不进 git）。

**环境**

| 项 | 值 |
|---|---|
| 地图 | 钓鱼怎么这么危险啊喂！（`map_id=6aab8e60ee615830184f4963`，SE，`isSEMap=true`） |
| 编辑器 | pid 36768，`editor-cli` 0.18.0 |
| 试玩 session | `b823e7f`（V2/V3/V4/V6/V7，16:10–16:24）、`af0fb25`（V5 通道，deploy 后重启，16:24） |
| 日志文件 | `C:\FeverApps\party_pc\logs\editor_36768.log` |
| 宿主目录 | `C:\Users\Lzx_8\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！` |

**怎么复跑**（证据都在日志里，标记统一 `[M15]`）

```bash
E="$USERPROFILE/.eggitor/cli/editor-cli.exe"
"$E" play start --json                       # session 记下来
"$E" exec -p server --file tmp/m15/p_v2c.lua      # 探针源码在 tmp/m15/，不进 git
"$E" log grep "M15" --play-session <id> --json    # 读回探针输出
"$E" play stop
```

`exec -p <runtime> --file` 是异步提交，**不返回值**：探针一律 `print` 唯一标记，再用 `log grep` 读回。

**探针清单**（`tmp/m15/`，一次性、不进 git；每条命令见台账对应小节）

| 文件 | 覆盖 |
|---|---|
| `p0_scene.lua` | 场景盘点（单位/水/玩家/血量字段） |
| `p_char.lua` | 角色属性与信号可用性 + 行走速度基线 |
| `p_v2a.lua` / `p_v2b.lua` / `p_v2c.lua` / `p_v2d_server.lua` + `p_v2d_client.lua` | V2 |
| `p_v3.lua` / `p_v3b.lua` / `p_v3c.lua` / `p_v3d.lua` | V3 |
| `p_v4.lua` / `p_v4b.lua` | V4 |
| `p_v5_server.lua` / `p_v5_client.lua` | V5（通道） |
| `p_v6.lua` / `p_v6b.lua` | V6 |
| `p_v7.lua` | V7 |

---

## 1. V2 举鱼接缝：抓举 → 骨骼挂点组合

### 结论

**接缝成立（绿）**：原生抓举（服务端 `character.Controller:Lift()`）与骨骼挂点可以同时用，做法是在 `fish.OnLiftedBegin` 回调里**立刻**建 `SkeletalSocketMount`（`SocketName="origin"`、`SocketOffset=(0,1.9,0)`、`Parent=角色`）并把鱼 `Parent` 到挂点下。之后鱼恒处于角色局部 `(0,1.9,0)`，走路不掉、不互拉、`OnLiftedEnd` 不误触发。

顺带确定了几件会写进 M2 的细节：

1. **抓举自己就会把鱼切成 Kinematic**。探针建鱼时 `BodyType=4`（Dynamic），举起后回读是 `2`（Kinematic）。所以路线图里「切 Kinematic 后抓举会不会被打断」这条，答案是**不会**——抓举本身就是 Kinematic 状态下成立的；再显式切一次 Kinematic 也毫无影响。
2. **举着的时候切回 Dynamic 会让鱼掉下去**：显式 `fish.BodyType = 4` 后 3 秒内漂移 4.322m、下沉 2.718m。举着期间这条不改。
3. **挂点解析有延迟**：吸收进挂点后约 0.9–1.5 秒内鱼的位置还没稳定（实测 t≈0.9s 读到 `rel=(0.08,1.40,0.09)`），稳定后恒 `(0,1.90,0)`。**按位置验收要等挂点解析完**，别用第一帧判定。
4. **`Lift()` 是占用语义**：手上已经有东西时再调 `Lift()` 会**放开旧的**，不会举起新的（相位 A 的 `begin=0`，同时上一条鱼触发 `OnLiftedEnd`）。业务侧抓举前要判「手上有没有东西」，别把 `Lift()` 当幂等。
5. **客户端发起无效（L-13 的加强版）**：`exec -p client` 里 `LocalPlayer.Character.Controller:Lift()` 返回成功，但服务端 `onLiftedBegin=0`、`ctrlBegin=0`、鱼仍在 `World` 下。真人按「举起」按钮走的就是客户端这一端 → 生产链路的抓举要服务端发起；真人按键档本轮**无法用探针复现**（`input touch` 到不了界面按钮，是 `eggy-lua` 试玩参考里已证的既有结论）。

### 证据（`--play-session b823e7f`）

```
[M15] | V2A | spawn | M15FishV2A | pos=(-16.64,5.00,33.73) | BodyType=4 Liftable=true ...
[M15] | V2A | Lift() | true | nil
[M15] | V2A | EV fish.OnLiftedBegin | liftunit=伯乐好马！ | t=1790064683.80
[M15] | V2A | mount | created=ok | parentFish=true nil | fishParent=M15MountV2A
[M15] | V2A | after-lift | begin=1 | ctrlBegin=1 | fishParent=M15MountV2A | fishBody=BodyType=2 ...
[M15] | V2A | summary | samples=142 | walk_seconds=32 | relY_avg=1.900 | relY_min=1.900 | relY_max=1.900
                      | relXZ_max=0.762 | onLiftedBegin=1 | onLiftedEnd=0 | ctrlOnLiftBegin=1 | ctrlOnLiftEnd=0
[M15] | V2C | R1 | result | seconds=6 | walk=false | relY[min/avg/max]=1.900/1.900/1.900 | relXZ_max=0.000 | onLiftedEnd=0
[M15] | V2C | R3 | result | seconds=6 | walk=false | relY[min/avg/max]=1.900/1.900/1.900 | relXZ_max=0.000 | onLiftedEnd=0
[M15] | V2C | R99 | result | seconds=35 | walk=true | samples=176 | char_path=69.32m
                       | relY[min/avg/max]=1.900/1.900/1.900 | relXZ_max=0.989 | onLiftedBegin=1 | onLiftedEnd=0
[M15] | V2B | B | explicit-kinematic | end=1 | rel=(0.00,1.90,0.00) | drift_max=0.000 | BodyType=2
[M15] | V2B | B | explicit-dynamic   | end=1 | rel=(-0.10,-0.82,-3.36) | drift_max=4.322 | dropY_max=2.718 | BodyType=4
[M15] | V2B | A | holding(no mount) | begin=0 | end=0 | ... | parent=World（Lift() 放开了上一条鱼）
[M15] | V2D | summary | onLiftedBegin=0 | onLiftedEnd=0 | ctrlBegin=0 | ctrlEnd=0 | fishParent=World   （客户端发起）
[M15] | CLIENT | Lift() | true | nil
```

- 「举着走 30m/30s 不掉」：走动窗口 35 秒、累计路程 69.32m（远超 30m），`relY` 全程恒 1.900、`relXZ_max=0.989m`（走动中的瞬时水平误差，与 #13 的 ≤0.82m 同量级）、`onLiftedEnd=0`。
- 「举着走自己结束」（L-9）本轮**没有复现**：69.32m / 35s 内 0 次 `OnLiftedEnd`。规避手段记在案：`V2B` 相位 A 那次 `OnLiftedEnd` 是「手上已有东西时再 `Lift()`」造成的，不是自己掉的——业务侧判「手上有没有东西」即可避开。

### 归属

M2「原生抓举」「顶鱼（骨骼挂点）」两条任务；`Lift()` 占用语义与客户端无效两条进 M2 的实现纪律。

---

## 2. V3 鱼载体实例化与伤害入口

### 2.1 `RenderMeshId` / `PhysicsMeshId` 的写法（已查实）

| 问题 | 结论 | 依据 |
|---|---|---|
| 写什么 | **`RenderMeshId = "official://mesh/<模型号>"`**；`PhysicsMeshId` 创建时可省略，缺省就取 `RenderMeshId` | `EggyAPI.lua:6747`「缺省时，若初始创建时传入了 RenderMeshId，则默认使用该 RenderMeshId 作为物理资源」；实测 `render-only` 变体回读 `PhysicsMeshId=official://mesh/7000544` |
| 两个字段能不能同值 | 能，本图现有鱼就是这么写的 | `/World/罗飞鱼` 运行时回读 `RenderMeshId=custom://0gwLbwtupD1fS2iRa`、`PhysicsMeshId=` 同值 |
| 能不能写 `official://preset/...` | **不报错但建出空壳**（`Size=(1.000,1.000,1.000)`，无几何） | 探针 `preset-uri` 变体：`created=ok`、`RenderMeshId=official://preset/9000092`、`Size=(1,1,1)`；同位置的 `official://mesh/7000544` 变体是 `Size=(2.710,3.420,5.310)` |
| 官方鱼模型号在哪 | 官方模型库 `7000544–7000563`（20 条），对应官方预设 `official://preset/9000092–9000121` | `<站点>/assets/model.html` 的 id 列 + 缩略图文件名 `img_editor_<预设号>_*`；`preset is-official-asset-id official://preset/9000092` 返回 `true` |

**官方鱼模型号 → 建议配置值**（`GameCfg.FishCarrier` 的输入；表由 `tmp/m15/fish_models.txt` 生成，`<站点>/assets/model.html` 2026-09-22 取）

| 模型号 | 官方预设 | 名称 | | 模型号 | 官方预设 | 名称 |
|---|---|---|---|---|---|---|
| 7000544 | official://preset/9000092 | 大马哈鱼 | | 7000554 | official://preset/9000112 | 螃蟹 |
| 7000545 | official://preset/9000093 | 旗鱼 | | 7000555 | official://preset/9000113 | 七彩鱼 |
| 7000546 | official://preset/9000094 | 鲨鱼 | | 7000556 | official://preset/9000114 | 三文鱼 |
| 7000547 | official://preset/9000095 | 鳐鱼 | | 7000557 | official://preset/9000115 | 鳊鱼 |
| 7000548 | official://preset/9000096 | 彩圆儿 | | 7000558 | official://preset/9000116 | 草鱼 |
| 7000549 | official://preset/9000097 | 蝴蝶鱼 | | 7000559 | official://preset/9000117 | 金鱼 |
| 7000550 | official://preset/9000098 | 海龟 | | 7000560 | official://preset/9000118 | 鲫鱼 |
| 7000551 | official://preset/9000099 | 黑鱼 | | 7000561 | official://preset/9000119 | 兰寿 |
| 7000552 | official://preset/9000110 | 锦鲤 | | 7000562 | official://preset/9000120 | 食人鱼 |
| 7000553 | official://preset/9000111 | 鲶鱼 | | 7000563 | official://preset/9000121 | 小丑鱼 |

`GameCfg.FishMap` 现有的 13 个鱼种名（草鱼 / 小丑鱼 / 鲫鱼 / 黑鱼 / 章鱼 / 旗鱼 / 蝴蝶鱼 / 鳐鱼 / 三文鱼 / 大马哈鱼 / 鲨鱼 / 七彩鱼 / 大章鱼）里，**12 个在上表里能直接对上**（章鱼/大章鱼不在 7000544 段：章鱼是 `6000019`、对应预设 `official://preset/1510600`，大章鱼无对应模型号——需策划确认或退化为章鱼）。以上结论已 `TowerSend` 给模块线 worker 落 `GameCfg.FishCarrier`。

### 2.2 「克隆场景里的鱼不可用」

**本轮没有复现**：克隆 `/World/罗飞鱼`（源 `BodyType=1`）与 `/World/咸鱼`（源 `BodyType=2`）都成功，写入 `BodyType=4 / Liftable=true / PhysicsActive=true / GravityEnabled=true` 后回读一致、并且**真的受重力**（1 秒内下落 23.25m / 23.38m，落到 y≈-21 的世界外）。

```
[M15] | V3 | clone-luofeiyu | after-set-dynamic | BodyType=4 Liftable=true PhysicsActive=true GravityEnabled=true Mass=10 ... | dropped= 23.25
[M15] | V3 | clone-xianyu   | after-set-dynamic | BodyType=4 Liftable=true PhysicsActive=true GravityEnabled=true Mass=10 ... | dropped= 23.38
```

未测的是**克隆鱼能不能被抓举**（L-14 坑 4 说的「不可靠」可能指那条路径）。M2 仍按 F-7 走 `World:CreateUnit("WorldUnit") + official://mesh/<模型号>`；克隆只作对照。

### 2.3 挥砍能不能打自建鱼（M2 硬前提）—— **不成立**

分三层，前两层通、第三层断：

1. **命中盒能"看见"自建鱼** ✓。挥砍（`AbilityAPI.CastAbility(character, 1)`，命中盒 `MeleeHitBox_TU`，偏移 `(0,1,2)`、缩放 `(3,2,3)`）确实触发了自建 WorldUnit 鱼：
   ```
   [M15] | V3D | EV hitbox.OnTriggerEnter | M15V3HitFish | WorldUnit
   [M15] | V3D | GetPartsInPart | n=4 | 无形方块/WorldUnit,M15V3HitFish/WorldUnit,无形方块/WorldUnit,伯乐好马！/EggyUnit
   ```
   （注意：命中盒同时报 `无形方块`、玩家自己这类场景件，业务侧要用标签/属性过滤。）
2. **伤害入口的两条路都不存在**。包内 `server/packages/ability_system/anchors/melee_hit.lua:107`（`_applyDamage`）的实现是 `target:TakeDamage(damage, owner)`，退化到 `target.Controller:TakeDamage(...)`：
   - 自建 `WorldUnit`：`hasHealth=false hasMaxHealth=false hasTakeDamage=false hasController=false hasDied=false hasHealthChanged=false`；`wu:TakeDamage(25, ch)` 直接报 `attempt to call a nil value (method 'TakeDamage')`。
   - 自建 `EggyUnit` / `HumanUnit` / `PhysicsUnit`：能创建，但**永远拿不到 Controller**（探针等了 5.5 秒仍是 `controller=false`，子节点只有 `Animator`）；`PetUnit` 创建直接被拒（`CreateUnit('PetUnit') failed`）。
   - 给 WorldUnit 挂自造方法的想法也被挡：`fish.TakeDamage = function(...) end` 报 `cannot access an internal table/userdata! (key='TakeDamage')`。
3. **血量宿主在 `Controller` 上，而自建单位没有 Controller**。`EggyAPI.lua` 的 `BaseController`（`:5235`）才有 `Health / MaxHealth / Died / HealthChanged / TakeDamage`；玩家角色的 `character.Health` 读出来是 `nil`，`character.Controller.Health` 才是 100。

**影响面**：M2「打鱼」的伤害入口**必须自建**——推荐形态是业务侧自行判定命中（监听命中盒 `MeleeHitBox_TU.OnTriggerEnter` 或干脆自建命中盒）并维护自己的鱼 HP 表；只靠技能包 `melee_hit` 的 `_applyDamage` 永远扣不到血。这条直接改写 M2 的实现形态，属于路线图 §2.2 里「V2/V3 不绿，M2 开工即返工」。

### 归属

- `GameCfg.FishCarrier` 的模型号/写法 → 模块线（已交接）。
- M2 的伤害入口形态 → M2；
- 「打不动自建鱼」这条同时 `TowerFinding` 备案（库内锚点对自建单位只做击退、不做伤害这一事实，属包内行为，不在本 mission 改动范围）。

---

## 3. V4 逃脱运动与消散

| 验收项 | 结论 | 实测 |
|---|---|---|
| Kinematic + `LinearVelocity` 3m/s 可驱动 | ✓ | `moved_1s_along=3.10m`（采样点落在 1.00–1.05s，等效 ≈3 m/s）、`first_move_after=0.07s`（≤0.15s）、`BodyType=2` |
| 前向射线撞墙转 90°（5–10Hz 可配） | ✓ | 8Hz 前向 1.5m 射线，6 秒 3 次转向，命中距离 1.19–1.33m；四向 30m 射线都命中 `无形方块` |
| 入水即 `Destroy` | ⚠ 要用 (x,z) 判，不能用 y 阈值 | 见下 |
| 上限「每玩家 ≤1 + 全局 6」超限踢最旧 | ✓（逻辑） | 见下 |
| 12 条 30Hz 总开销 < 1ms | ✓ | 12 条 × 300 帧（含 8Hz 射线）总 22.187ms → **0.0740 ms/帧** |

**入水判定的坑（会直接让鱼永远不消失）**：逃脱鱼沿水平方向穿过池塘矩形时，y 一直停在岸上高度（实测 y=2.15），而水面配置高 1.55（+0.5 容差 = 2.05）→ **y 阈值版永远判不到「入水」**；改成水平矩形 (x,z) 判定后，t=2.74s 在 `(-8.75,2.15,27.75)` 判定入水并 `Destroy`。

```
[M15] | V4  | C | summary | destroyed=false | at_t=never          （y 阈值版）
[M15] | V4B | water-XZ | t=2.74 | pos=(-8.75,2.15,27.75) | y_above_surface=0.60
[M15] | V4B | water-summary | entered_XZ_at=2.74 | entered_y_threshold_at=never | destroyed_on_XZ_enter=true
```

另外发现**水单位在运行时会漂移**：同一次试玩里 `WaterCircle1/2` 的 y 从 `1.05`（16:10）变到 `1.09 / 1.18`（16:24）。所以「按 y 判水」本身就不稳，M1 的落点判定与 M2 的入水判定都该以 (x,z) 矩形为主、y 只做上下界过滤（这条也回答了模块线问的水面高度问题，见 §6）。

**上限**：「每玩家 ≤1 + 全局 6，超限踢最旧」的剔除逻辑实测正确（3 人各 3 条时每人只剩 1 条、全局始终 3 条、被踢的都是本玩家最旧的那条）。**一处口径提醒**：每玩家 ≤1 时 3 人最多 3 条，全局 6 要到 ≥7 人才会真正起作用（F-5 的「玩家数 × 2 + 常数」比「每玩家 1」宽），M2 实现时按两个上限分别写、别只留一个。

**射线过滤要加**：转向用的前向射线除了墙，还会命中 `TGUnitShop` 这类 TriggerUnit（第 3 次转向就是被它触发的）——生产实现要按碰撞组或标签过滤，否则鱼会在 NPC 前原地打转。

---

## 4. V6 死亡与复活链路

### 结论

| 验收项 | 结论 | 证据 |
|---|---|---|
| 服务端权威死亡时刻 | **选 `character.Controller.Died`**（服务端收得到；`HealthChanged` 也收得到） | `EV Died(server) | t=... | health=0.0`；`healthEvents=4` |
| D-11 的「`Died` 只在客户端」担心 | **本图不成立**：服务端确实收到 `Died` | 同上 |
| `MaxHealth=300` | ✓ 可写、回读 300 | `set-maxhealth | ok=true | readback=300` |
| 每秒 `TakeDamage(5)` | ✓ 每次扣 5，归零触发 `Died` | `hp 20.0->15.0 ->10.0 ->5.0 ->0.0`，`died=1` |
| 复活满血 | ✓ 复活后 `health=300`（= `MaxHealth`） | `revive | delay_after_death=5.08 | health=300 | maxHealth=300` |
| 复活落点 | ✓ 原生出生点 | `revive_pos=(-2.73,4.98,33.52)`（出生点 `(-2.745,5.01,33.52)`） |
| 复活驱动 | ✓ 引擎 `RespawnTime=5`，实测 **5.08s** | 同上 |
| `Respawn.OnDied` 单点 | ✗ **没有这个服务**（`game:GetService("Respawn")` = `nil`），需自建单点（建议 `Controller.Died`） | `service | Respawn | ok=true | value=nil` |

**三个会改实现的发现**：

1. **血量宿主是 `character.Controller`，不是 `character`**：`character.Health / MaxHealth / Died / HealthChanged / TakeDamage` 全是 `nil`；`character.Controller`（`<EggyController>`）才有全套（`Health=100, MaxHealth=100` 默认，与 D-1 的「默认 100、上限 999999」一致）。所有掉血/死亡监听都要写 `Controller` 一侧。
2. **复活不换角色对象、`CharacterAdded` 不触发**：`charId` 前后都是 `1`、`charAdds=0`。所以 `MgrAbility` / `MgrPlayer` 里挂在 `player.CharacterAdded` 上的装配逻辑**不会**在复活后重跑（本轮同一对象复活，技能与锚点自然还在；但若将来改成重建角色，这里会静默失效——写进 M2/M4 的注意项）。
3. **单点伤害与单点死亡都要自建**：D-3 的 `game:GetService("Combat")` 同样是 `nil`（`service | Combat | ok=true | value=nil`），`Combat.ApplyDamage(player, amount)` 不存在。

### 饥饿度（挂账）

「复活后饥饿度回满 300」**无法验证**：本仓库当前没有饥饿字段（`grep` 不到饥饿/饥饿度相关实现，属 M1/M4 落地范围）。降级记录见 §7。

### D-12（面板字段人工核对）—— 留给人类的 HITL 清单

编辑器【规则 → 死亡规则 / 复位规则】面板字段要人对着 UI 核一遍（CLI 侧只读得到 `api get` 的类型默认值，读不到本图的落地值）。请按这张清单核：

- [ ] 死亡规则：`RespawnTime` = ?（引擎实测复活血条在 5.08s 后满，期望面板是 5）
- [ ] 死亡规则：`LivesCount` = ?（M0 只验「死了能复活」，不限命数）
- [ ] 死亡规则：`CorpseLifetime` = ?
- [ ] 复位规则：`ResetCamera` = ?
- [ ] 复位规则：`ResetCD` = ?（期望 5）
- [ ] 出生点 `/World/出生点` 的「容纳上限（Capacity）」实际值 = ?（`api get SpawnLocationUnit` 的默认是 1，但 `editor-unit get-property <出生点> Capacity` 返回 `null`，读不到实例值）

---

## 5. V5 通道：ReelIn RemoteEvent 打通

### 交付物

- `server/Mgr/MgrReelIn.lua`（新）：建通道 `ReelInRE`（走 `common/REUtil.lua:GetRE`）、做「身份 + 类型」两层校验、把通过的批次转给 `Subscribe` 进来的订阅者；频率层留给模块线的 `common/RateLimit.lua`。
- `client/LocalReelIn.lua`（新）：同一通道的客户端半，`RequestReel(count)` 发送 `{s,n,q}`、`OnClientEvent` 接服务端下发的结果；聚合器接缝 `SetAggregator`（M1 落地时注入 `common/RateLimit.lua` 的聚合器；未注入时退化成「一点击一包」，仅供 M0 取证）。
- `server/main.lua` 的 `MgrMap` 加 `MgrReelIn`；`client/main.lua` 起 `LocalReelIn:Start()`。

### 端到端证据（`--play-session af0fb25`，deploy 后重启）

```
[M15] | V5S | ready | channel=ReelInRE | accepted=0 | rejected=0
[M15] | V5C | sent | i=1 | ok=true | s=M15S1 | n=2 | q=1
[M15] | V5S | recv | session=M15S1 | n=2 | q=1 | player=伯乐好马！
[LocalReelIn] 收到结果 action=ack session=M15S1 progress=10          （服务端 FireClient → 客户端收到）
[M15] | V5C | sent | i=3 | ok=true | s=M15S1 | n=2 | q=3
[M15] | V5C | negative-start                                        （7 个坏包）
[M15] | V5S | recv | session=M15S1 | n=3 | q=99 | player=伯乐好马！   （坏包之后唯一合法的那个）
[M15] | V5S | summary | accepted=4 | rejected=7
```

上行 4 个合法包全部通过并回包；7 个坏包（`s` 是数字、`n=0`、`n=1.5`、`n=nan`、`q=0`、非 table、空参）全部被挡在「类型」层，计数 `rejected=7`、没有任何回包。

### 记录性结论（R-4）

- **`game:CreateRemoteEvent` 无文档但可用**：官方手册与存根都没有这个函数（存根只有 `RemoteEvent.New`），但本图一直在用（`common/REUtil.lua:14`），本轮又建了一条 `ReelInRE`，两端都成功。
- **通道数上限仍无口径**。本图当前在用的通道（同一次试玩启动日志）：
  - 服务端 8 条：`GlobalMarquee`、`ReelInRE`、`ResetGM`、`CancelFish`、`DoneFish`、`ReqFish`、`RodLevelUp`、`FishLevelUp`
  - 客户端 4 条：`MsgNoticeRE`、`OpenScreenRE`、`CloseScreenRE`、`ReelInRE`
  - 到这个数量级没有任何报错，但**不能**据此推断上限；问题的正确去处是问官方（路线图 §8.2）。
- **R-7（上行阈值与超限行为、载荷真实字节上限）仍无数据**，且**本轮不压测**，理由：① 官方对频率/包大小/超限行为都没有数值（R-1，`docs/research/remoteevent-limits.md` §2）；② 编辑器试玩是本地单客户端，压不出真实网络边界（要压必须已发布地图 + 多客户端，属 §8.2 的上游项）。这条按路线图 §8.2 的口径记为「书面判断」而不是「压测数据」。

---

## 6. V7 3 人同图并发

### 结论

**编辑器 CLI 不支持真实多客户端同图并发** → 按路线图 §1.1 / §0.1 的口径落 **1 真人 + 2 模拟** 的降级。

证据：

| 证据 | 内容 |
|---|---|
| `editor-cli start --help` | 「Multiple editors may run side by side (different maps); **the same map is never launched twice** -- an existing healthy instance is reused.」→ 同一张地图开不出第二个编辑器实例 |
| `editor-cli editor-instances list --json` | 只有一个实例（pid 36768 / port 19861，map = 本图） |
| `editor-cli play start --help` | 只有 `--wait-ready` / `--wait-timeout` / `--log-path`，**没有客户端数或多人选项** |
| `editor-cli status --json` | `available_runtimes: ["editor"]` |
| 试玩内探针 | `[M15] | V7 | players | count=1 | names=伯乐好马！` |

### 出生点 capacity=1 是否卡人

- 地图只有 **1 个** `SpawnLocationUnit`（`/World/出生点`，`unit_id=1840496167`）。
- `api get SpawnLocationUnit` 确认有 `Capacity`（标题「容纳上限」，类型 `Int`，默认 `1`）；但 `editor-unit get-property 1840496167 Capacity` 返回 `null`，**CLI 读不到实例上的实际值**。
- 单人侧：死亡 → 5.08s → 满血复活，落点每次都回到出生点 `(-2.73,4.98,33.52)`，没有被挡。
- **3 人同时出生会不会被 capacity=1 卡住：未实测**（没有多客户端手段）。这条留验收期真人多客户端，见 §7 降级记录。

### 单人可验证的替代证据

- 3 秒复活链在单人下成立（§4）。
- 服务端逐玩家的结构是齐的（`MgrPlayer.PlayerSignal`、`MgrAbility.CharacterSignals`、`MgrReelIn.Sessions` 都按 `UserId` 建表、`PlayerRemoving` 清），但**「3 个真人同时进图」这件事本身没有在本线验证过**。

---

## 7. 降级记录（三件套：明确降级 + 影响面 + 谁接受）

路线图 §2.3 判据 2 要求未绿项必须以三件套书面记录。「谁接受」一栏本线只能填**人类（验收期确认）**——本 mission 没有人类在场。

| # | 降级项 | 影响面 | 谁接受 |
|---|---|---|---|
| D-1 | **V7 真实 3 客户端并发**：编辑器 CLI 不支持 | 用 1 真人 + 2 模拟代替。真实并发下才暴露的问题（出生点争抢、同步压力、弱网）在 M0 内**无验收途径**；M4 的「3 人同图」出口判据同样受影响，需要在验收期补真人 | 人类（验收期） |
| D-2 | **出生点 capacity=1 是否卡人**：无多客户端手段实测 | 3 人同时出生可能有人被挡在出生点外→ M4 的总 DoD（3 人各自走完闭环）有卡死风险。缓解：先在验收期用真人 3 客户端验一次，若真卡人则改多出生点或提高 Capacity | 人类（验收期） |
| D-3 | **「复活后饥饿度回满 300」**：本仓库还没有饥饿字段 | 只能验「复活满血 300」这一半；饥饿度那半要等 M1/M4 落地后才能复验 | 人类（验收期）+ M1/M4 落地后回补 |
| D-4 | **真人按键档**（V2 要求的「真人按键档限制记录」）：`input touch` 到不了界面按钮，客户端脚本 `Lift()` 也无效 | M0 内抓举一律由服务端探针发起；「真人按举起按钮」这条路径没有在本线验证过。生产链路必须服务端触发，客户端按钮只发请求 | 人类（验收期）；实现纪律进 M2 |
| D-5 | **V5 的 R-7 压测**：只给书面判断，不给压测数据 | 上行真实阈值/载荷字节上限/超限行为仍未知；生产必须按「平台随时可能限流且不告知」设计（R-5：结果一律服务端权威下发） | 人类（验收期）+ 问官方（§8.2） |
| D-6 | **D-12 面板字段人工核对**：CLI 读不到，需人对着编辑器 UI 核 | §4 的 HITL 清单 6 项未勾；死亡/复位规则的实际面板值未经人眼确认 | 人类（HITL 清单已给） |
| D-7 | **「克隆场景里的鱼不可用」**：本轮未复现「不可用」，但也没测克隆鱼的抓举 | 结论从「不可用」降级为「克隆能创建、能受物理，抓举路径未测」；M2 仍按 F-7 走 CreateUnit | M2（实现期再验） |
| D-8 | **12 条 30Hz 开销**：0.0740 ms/帧是在单客户端本地试玩里量的纯逻辑开销 | 不含网络同步、渲染与真实多玩家负载；不能直接外推到线上 3 人 | 人类（验收期） |

---

## 8. 交给别人的结论

| 收件人 | 内容 |
|---|---|
| 模块线 worker（M14，`GameCfg` 归它） | §2.1 的模型号↔预设对照表与 `RenderMeshId="official://mesh/<号>"` 写法；`PhysicsMeshId` 可缺省。§3 / §6 的水面高度：**`Position.y` 是底面、`Size` 是包围盒半长，表面 y = `Position.y + Size.y`** —— 实测大地板顶面 y=2.000（pos.y=0 + size.y=2）、水圈顶面 y≈2.183（pos.y=1.18 + size.y=1）；水单位运行时在漂移（1.05 → 1.09/1.18），所以 `SurfaceY=1.55` 偏低、y 阈值判定不可靠，建议以 (x,z) 矩形为主 |
| M2（打鱼变现） | §2.3 的伤害入口结论（必须自建）；§1 的抓举接缝配方与「举着期间别切回 Dynamic」「`Lift()` 是占用语义」「客户端发起无效」；§3 的入水判定要用 (x,z)、射线要过滤 TriggerUnit、两个上限分别写 |
| M4（鲁棒性抽查） | §4 的死亡/复活链路与「复活不换角色对象、`CharacterAdded` 不触发」；`Respawn`/`Combat` 两个服务都不存在，单点要自建 |
| 路线图（§8.2 上游项） | `game:CreateRemoteEvent` 无文档但可用（本轮又验证一条）；通道数上限仍无口径；R-7 三项仍要问官方 |

---

## 9. 完成判据自查

| 命令 | 结果 |
|---|---|
| `lua tests/run.lua` | `Ran 77 tests ... 77 successes, 0 failures` / `OK` |
| `bash tools/acceptance/run_acceptance.sh` | `3 passed, 0 failed` / `acceptance run OK` |
| `lua -e "assert(loadfile('<file>'))"`（每个改过的 `.lua`） | 见 §10 |
| `editor-cli code validate --strict --json --workspace <宿主目录>`（deploy 之后） | `deploy ok` + `validate: OK`（16:24 那次 deploy） |

## 10. 本线改动的文件

| 文件 | 说明 |
|---|---|
| `server/Mgr/MgrReelIn.lua` | 新增：ReelIn 通道服务端半（建通道 + 身份/类型校验 + Subscribe 接缝） |
| `client/LocalReelIn.lua` | 新增：ReelIn 通道客户端半（发 `{s,n,q}` + 接服务端结果 + 聚合器接缝） |
| `server/main.lua` | `MgrMap` 加 `MgrReelIn` |
| `client/main.lua` | 起 `LocalReelIn:Start()` |
| `docs/verification/m0-playtest-ledger.md` | 本文件 |

探针（`tmp/m15/*.lua`）**不进 git**——`tmp/` 在 `.gitignore:32`，按 mission 口径当临时文件处理。
