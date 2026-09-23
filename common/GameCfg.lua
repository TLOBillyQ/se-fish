local GameCfg = {}

-- MVP 物品表；官方图片目录没有这八个物品的同名图，按 issue #33 确认使用代表图。
-- 鱼获共用 11164「鱼」，蚯蚓用 14066「勾爪-距离」的弯曲线条，鱼竿用 12024「捕虫网」。
-- 对照记录见 issue #33（评论 9859）。
GameCfg.Items = {
    ContainerId = { ItemBar = 'itemBar', Bait = 'bait' },
    ItemBarSlots = 8,
    Id = { Tilapia = 'tilapia', Carp = 'carp', KnifeFish = 'knifeFish', Bass = 'bass', Catfish = 'catfish', Goldfish = 'goldfish', Worm = 'worm', StarterRod = 'starterRod' },
    InitialWormCount = 10,
    ActionCooldownSec = 0.12,
    RodVisual = {
        -- Mesh 来自试玩世界单位「中式杆」（原 AssetId=map://preset/u46466002b9a47c588001c2e65ef4c3a）；
        -- 原场景 Scale=(0.2,1,0.2)，这里的缩放是左手持竿表现参数。
        Mesh = 'official://mesh/50450',
        Socket = 'l_weapon',
        Scale = { x = 0.2, y = 0.25, z = 0.2 },
    },
    Definitions = {
        tilapia = { Name = '罗非鱼', Icon = 'official://image/11164' },
        carp = { Name = '鲤鱼', Icon = 'official://image/11164' },
        knifeFish = { Name = '刀鱼', Icon = 'official://image/11164' },
        bass = { Name = '鲈鱼', Icon = 'official://image/11164' },
        catfish = { Name = '鲶鱼', Icon = 'official://image/11164' },
        goldfish = { Name = '金鱼', Icon = 'official://image/11164' },
        worm = { Name = '蚯蚓', Icon = 'official://image/14066' },
        starterRod = { Name = '新手鱼竿', Icon = 'official://image/12024', Level = 1 },
    },
}
GameCfg.Items.InitialGrants = {
    { itemId = GameCfg.Items.Id.StarterRod, count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
    { itemId = GameCfg.Items.Id.Worm, count = GameCfg.Items.InitialWormCount, containerId = GameCfg.Items.ContainerId.Bait },
}

-- 鱼种基础值（design 钓鱼表 / 物品表的鱼塘行）：Health=血量，BaseWeight=基础重量 kg，
-- BasePrice=基础出售价，Model=GameCfg.FishCarrier.Models 的模型号。
-- 个体重量 = BaseWeight × 倍率、售价 = BasePrice × 倍率，由 common/FishCatch.lua 派生，不存快照。
-- 极品鲶鱼 / 极品鲈鱼的血量、重量、售价照表抄（表里与普通版对调，疑问记在 #37）。
-- 电鳗是精英鱼，MVP 不做精英，暂不进渔获表（#37 评论）。
GameCfg.Fish = {
    tilapia = { Name = '罗非鱼', Grade = 'normal', Health = 5, BaseWeight = 1, BasePrice = 3, Model = '7000557', Speed = 3 },
    carp = { Name = '鲤鱼', Grade = 'normal', Health = 10, BaseWeight = 5, BasePrice = 4, Model = '7000552', Speed = 3 },
    knifeFish = { Name = '刀鱼', Grade = 'normal', Health = 15, BaseWeight = 0.5, BasePrice = 5, Model = '7000545', Speed = 3 },
    bass = { Name = '鲈鱼', Grade = 'normal', Health = 20, BaseWeight = 2, BasePrice = 6, Model = '7000551', Speed = 3 },
    catfish = { Name = '鲶鱼', Grade = 'normal', Health = 25, BaseWeight = 5, BasePrice = 7, Model = '7000553', Speed = 3 },
    goldfish = { Name = '金鱼', Grade = 'normal', Health = 3, BaseWeight = 0.1, BasePrice = 8, Model = '7000559', Speed = 3 },
    premiumTilapia = { Name = '极品罗非鱼', Grade = 'premium', Health = 5, BaseWeight = 1, BasePrice = 3, Model = '7000557' },
    premiumCarp = { Name = '极品鲤鱼', Grade = 'premium', Health = 10, BaseWeight = 5, BasePrice = 4, Model = '7000552' },
    premiumKnifeFish = { Name = '极品刀鱼', Grade = 'premium', Health = 15, BaseWeight = 0.5, BasePrice = 5, Model = '7000545' },
    premiumCatfish = { Name = '极品鲶鱼', Grade = 'premium', Health = 20, BaseWeight = 2, BasePrice = 6, Model = '7000553' },
    premiumBass = { Name = '极品鲈鱼', Grade = 'premium', Health = 25, BaseWeight = 5, BasePrice = 7, Model = '7000551' },
    premiumGoldfish = { Name = '极品金鱼', Grade = 'premium', Health = 3, BaseWeight = 0.1, BasePrice = 8, Model = '7000559' },
}

-- 活鱼（#41 起，server/Mgr/MgrFishUnit.lua）。来源：M0 试玩验证台账（issue #25 评论 9865）§1 V2 与 #27 规格。
GameCfg.FishUnit = {
    -- 顶鱼挂点：OnLiftedBegin 里立刻建在角色上，鱼 Parent 到挂点下（V2 实测 35s/69m 恒 (0,1.9,0)）
    LiftSocket = 'origin',
    LiftSocketOffset = { x = 0, y = 1.9, z = 0 },
    -- 服务端 Lift() 后等 OnLiftedBegin 的确认窗；没确认才重试，最多 LiftAttempts 次
    -- （Lift 是占用语义，确认前连调会把刚抓起的鱼放开）
    LiftConfirmSec = 1,
    LiftAttempts = 3,
    -- 待抓的鱼：关重力 + 阻尼，偏离生成点超过容差（米）或坐标 NaN 就拉回并清速度（M18-2）
    AwaitDriftTolerance = 0.05,
    LinearDamping = 5,
    AngularDamping = 5,
    -- 放下 / 逃脱（#42，#27 规格）：落在角色正前方 DropOffset 米、抬高 DropHeight 米，Kinematic 由脚本驱动；
    -- 鱼种没配 Speed 时用 EscapeSpeed（米/秒）。每 TurnSec 秒重新朝最近水区，RayHz 频率向前 RayDistance 米探墙，
    -- 撞墙转 90°（V4 实测）。上限：每人在逃 ≤ PerPlayerEscapeCap，全局 ≤ 在线人数 × GlobalEscapePerPlayer
    DropOffset = 1.5,
    DropHeight = 0.5,
    EscapeSpeed = 3,
    TurnSec = 3,
    RayHz = 8,
    RayDistance = 1.5,
    RayRetries = 3,
    PerPlayerEscapeCap = 1,
    GlobalEscapePerPlayer = 2,
}

GameCfg.Casting = {
    Distance = 5,
    HookDelaySec = 3,
    ActionCooldownSec = 0.12,
    -- 上岸停留：收线到 100% 后按钮灰化、播放上岸动作，停留结束归位到选中鱼竿（#37）
    LandedHoldSec = 1.2,
    LandedAnimation = 'official://animation/24450', -- 官方动画「钓鱼」
    -- 活鱼落在玩家正前方的水平距离与离地高度（米），要在原生抓举的命中范围内（#27 接口契约）；
    -- 取 M0 抓举夹具实测能抓中的角色局部 (0, 0.5, 2)（issue #25 台账 §6.5，tmp/qa25/lift-unforced.lua）
    LandingOffset = 2,
    LandingHeight = 0.5,
    Zones = {
        WaterCircle2 = {
            { Id = 'tilapia', Bait = 0, RodLevel = 1, Weight = 8 },
            { Id = 'carp', Bait = 'worm', RodLevel = 1, Weight = 8 },
            { Id = 'knifeFish', Bait = 'worm', RodLevel = 1, Weight = 8 },
            { Id = 'bass', Bait = 'worm', RodLevel = 1, Weight = 32 },
            { Id = 'catfish', Bait = 'worm', RodLevel = 1, Weight = 24 },
            { Id = 'goldfish', Bait = 'worm', RodLevel = 1, Weight = 16 },
            { Id = 'premiumTilapia', Bait = 0, RodLevel = 1, Weight = 2 },
            { Id = 'premiumCarp', Bait = 'worm', RodLevel = 1, Weight = 2 },
            { Id = 'premiumKnifeFish', Bait = 'worm', RodLevel = 1, Weight = 2 },
            { Id = 'premiumCatfish', Bait = 'worm', RodLevel = 1, Weight = 8 },
            { Id = 'premiumBass', Bait = 'worm', RodLevel = 1, Weight = 6 },
            { Id = 'premiumGoldfish', Bait = 'worm', RodLevel = 1, Weight = 4 },
        },
    },
}

-- 技能包（ability_system）在本图的接入配置。
-- 预设本体存在图里、不进 git，这里只记 key；预设的建法与完整命令记录见 issue #7 / #8——
-- 本编辑器不认包内的 ---@export_prefab_type 自定义预设类型（见 #7 结论），所以：
--   技能管理器（官方叫技能背包）= 复制官方「技能背包」模板（u014968…）
--   技能 = 复制官方「技能」模板（uc57b9…）；加速技能重写过壳源码（官方文档的「手工创建方式」），
--         挥砍技能沿用模板原壳
--   锚点 = 复制官方「锚点」模板（uccfb9d…），壳改成只声明属性（壳会在 Parent=World 时抢跑），
--         挂接由根 AbilityAPI.AttachAnchor 补做
-- 注意：change-asset-value 改不动「壳里已声明的属性」，实例拿到的是预设单位数据里的旧值，
-- 所以加速技能用的是模板默认 CastTime=0.5 秒（加速窗口只有 0.5 秒），详见 issue #7；
-- 锚点的关键实例值改由 AnchorAttributes 在挂接前 SetAttribute 覆盖（含 Duration，melee_hit 要求 > 0）。
-- melee_hit 的命中盒用包内硬编码的官方网格 57450——已实测它是平台级资源，本图直接可用（issue #8）。
GameCfg.Ability = {
    -- 角色进图时实例化到角色下的技能背包预设
    ManagerPreset = "map://preset/ubdb4a7e737d4eddb87729e9055ba375",
    -- 进图后装的初始技能：AssetId=技能预设，Index=槽位（0 基），
    -- Anchor=锚点预设，AnchorBehavior=锚点行为模块名（anchors/ 下的文件名），
    -- AnchorAttributes=挂接前覆盖到锚点实例的属性（{x,y,z} 表会转成 Vector3）
    InitialAbilities = {
        {
            AssetId = "map://preset/uf7fac66639546e2aa376151835cf3a6",
            Index = 0,
            Anchor = "map://preset/uaf2781161d6460990a4941b12ad30c2",
            AnchorBehavior = "speed_add",
        },
        -- 挥砍：玩家的攻击（手持武器发起，见 CONTEXT.md「战斗」），道具按钮触发
        {
            AssetId = "map://preset/ucc31d1999a543a7ab329eff1fd3c00d",
            Index = 1,
            Anchor = "map://preset/u471a1004c1f43f1ae6ebe4ee2bcd080",
            AnchorBehavior = "melee_hit",
            AnchorAttributes = {
                -- 命中盒存活窗口；必须 ≤ 施法窗口（技能模板默认 CastTime=0.5，已声明属性预设侧改不动，见 issue #7 坑 2）
                Duration = 0.3,
                ABILITY_ANOSTATE_HITBOX_OFFSET = { x = 0, y = 1, z = 2 }, -- 面前 2 米
                ABILITY_ANOSTATE_HITBOX_SCALE = { x = 3, y = 2, z = 3 },
                ABILITY_ANOSTATE_BULLET_DAMAGE = 25.0,
                ABILITY_ANOSTATE_HITPOWER = 0.0, -- 验证期不击退，便于观察扣血
            },
        },
    },
}

-- 水判定（M0-V1）：每个钓鱼区一条。Center 只用到 x/z（y 留作场景溯源），HalfXZ 是水平半宽（米），
-- SurfaceY 是水面高度（米）；判定语义与配置校验见 common/MathWaterJudge.lua，
-- 边界用例见 tests/water_judge_test.lua，取值溯源见 issue #25 的 M0 模块线台账（评论 9862）。
-- 数值来源：#12 在本图 SE 试玩里的实测（宿主目录 log.txt 2026-09-22 11:46:49 的 PROTO_WATER INSPECT 行）——
--   WaterCircle1  Position(-11.75, 1.05, 27.75) Size(3, 1, 3) Scale(1, 1, 1)
--   WaterCircle2  Position(-11.75, 1.05, 27.75) Size(6, 1, 6) Scale(2, 1, 2)
--   两个水圈同心；HalfXZ 与 SurfaceY 的取值见下面两条注意，SurfaceY 已按 #31 的实测改正。
-- 注意 1：运行时读到的 Size 已含 Scale（WaterCircle2 的 Scale.x=2 已经算进 Size.x=6），
--         HalfXZ 直接写半边尺寸（6/2=3），配置时再乘缩放会翻倍（#12 W-4）。
-- 注意 2（#31 改正）：**Position.y 是底面、Size 是包围盒半长**，单位顶面 y = Position.y + Size.y——
--         大地板 pos.y=0 + size.y=2 = 顶面 2.000，与射线实测命中的 y=2.0 自洽；水圈
--         pos.y=1.18 + size.y=1 = 顶面 ≈2.183。旧值 1.55（1.05 + Size.y/2，按 Position 是几何中心算）
--         偏低、已作废；实测来源见 issue #25 的 M0 试玩验证台账（评论 9865）。
-- 注意 3：水圈在运行时会漂移（同一次 M15 试玩里 pos.y 从 1.05 变到 1.09 / 1.18），y 阈值本身不稳——
--         判定以 (x,z) 矩形为主、y 只当松过滤（台账 §3）。这里取漂移高点的顶面 2.183 而不是低点
--         2.05：判低会把真在水面的点漏成陆地（V4 实测的入水点 y=2.15 在旧值 1.55 下也判不到），
--         判高的代价只是水面之上约 0.13m 的空气薄层被算作水里，且这一层由 (x,z) 矩形兜住。
--         Center.y 保留 1.05（#12 11:46 的 INSPECT 读数，M15 16:10 复读同为 1.05），只作场景溯源
--         （判定不用 Center.y）；它与 SurfaceY（M15 16:24 的读数）批次不同属已知事实。
-- 顺序：外圈 WaterCircle2 在前，同心时先命中它；M1 若要按水区选鱼表，改这里。
GameCfg.Water = {
    Zones = {
        { Id = "WaterCircle2", Center = { x = -11.75, y = 1.05, z = 27.75 }, HalfXZ = 3.0, SurfaceY = 2.183 },
        { Id = "WaterCircle1", Center = { x = -11.75, y = 1.05, z = 27.75 }, HalfXZ = 1.5, SurfaceY = 2.183 },
    },
}

-- 高频输入契约（M0-V5）：窗口与次数上限的常量，逻辑见 common/RateLimit.lua，
-- 载荷字段固定 {s=会话 id, n=窗口内点击数, q=单调序号}（C-3）。
-- 消费者：收线（计数型，M1）+ 按住连发类武器（边沿型，随武器期，共用同一套窗口，C-16）。
-- 取值依据：#14 调研（30Hz 逻辑帧 ⇒ 聚合窗口 ≥33ms，建议 100ms）+ #15 定案「100ms 固定可配、1s ≤10」。
GameCfg.HighFreqInput = {
    WindowSec = 1.0,    -- 滑动窗长度（秒）；每玩家窗口内最多采纳 MaxCount 次
    MaxCount = 10,      -- 1s ≤ 10 次（C-2）；超限 clamp 不丢弃、不向玩家报错
    AggregateSec = 0.1, -- 客户端聚合窗口 = 100ms（C-1）；上行上限 10 包/秒/人
}
GameCfg.ReelIn = {
    Initial = 50,
    DecayPerSec = 5,
    ClickGain = 5,
    GraceSec = 0.18,
    -- 本地显示（#38，common/ReelDisplay.lua）：与权威差距 ≤ Tolerance（%）不调整，超过则 ChaseSec 内平滑追平；
    -- 已发出的批次等服务端回包确认，超过 PendingTimeoutSec 没回就不再计入本地超前
    Tolerance = 5,
    ChaseSec = 0.18,
    PendingTimeoutSec = 1,
}

-- V3 鱼载体实例化（M0-V3）：官方鱼模型号与 mesh id 的写法已查实，F-7 的 [未查证] 由此消除。
-- 数据源：issue #25 的 M0 试玩验证台账 §2.1（评论 9865；mission M15 在本图 SE 试玩里实测，2026-09-22）。
-- 建法（F-7）：World:CreateUnit("WorldUnit") + RenderMeshId；克隆场景里的鱼只作对照（台账 §2.2）。
-- RenderMeshId 的写法：**official://mesh/<模型号>**；PhysicsMeshId 创建时可省略，缺省就取 RenderMeshId
--   （EggyAPI.lua:6747），也可以像本图现有鱼那样两个字段写同一个值。
--   反面样例：official://preset/9000092 也能建出来，但那是空壳（Size=(1,1,1)、无几何）——
--   别拿预设号当 mesh id。
-- Models = 官方鱼模型库 20 条（模型号 7000544–7000563 ↔ 官方预设 9000092–9000121），
--   Mesh 是建议直接写进 RenderMeshId 的值，Preset 只作溯源与编辑器侧对照。
-- 鱼种用哪个模型见 GameCfg.Fish 的 Model（#37 起旧 FishMap 已退役）。
-- 谁消费：M2「打鱼变现」按上面的写法建鱼；改本表时 tests/water_judge_test.lua 的
-- TestFishCarrierConfig 会先红（它钉住写法与 20 条的号段）。
GameCfg.FishCarrier = {
    Models = {
        ["7000544"] = { Name = "大马哈鱼", Mesh = "official://mesh/7000544", Preset = "official://preset/9000092" },
        ["7000545"] = { Name = "旗鱼",    Mesh = "official://mesh/7000545", Preset = "official://preset/9000093" },
        ["7000546"] = { Name = "鲨鱼",    Mesh = "official://mesh/7000546", Preset = "official://preset/9000094" },
        ["7000547"] = { Name = "鳐鱼",    Mesh = "official://mesh/7000547", Preset = "official://preset/9000095" },
        ["7000548"] = { Name = "彩圆儿",  Mesh = "official://mesh/7000548", Preset = "official://preset/9000096" },
        ["7000549"] = { Name = "蝴蝶鱼",  Mesh = "official://mesh/7000549", Preset = "official://preset/9000097" },
        ["7000550"] = { Name = "海龟",    Mesh = "official://mesh/7000550", Preset = "official://preset/9000098" },
        ["7000551"] = { Name = "黑鱼",    Mesh = "official://mesh/7000551", Preset = "official://preset/9000099" },
        ["7000552"] = { Name = "锦鲤",    Mesh = "official://mesh/7000552", Preset = "official://preset/9000110" },
        ["7000553"] = { Name = "鲶鱼",    Mesh = "official://mesh/7000553", Preset = "official://preset/9000111" },
        ["7000554"] = { Name = "螃蟹",    Mesh = "official://mesh/7000554", Preset = "official://preset/9000112" },
        ["7000555"] = { Name = "七彩鱼",  Mesh = "official://mesh/7000555", Preset = "official://preset/9000113" },
        ["7000556"] = { Name = "三文鱼",  Mesh = "official://mesh/7000556", Preset = "official://preset/9000114" },
        ["7000557"] = { Name = "鳊鱼",    Mesh = "official://mesh/7000557", Preset = "official://preset/9000115" },
        ["7000558"] = { Name = "草鱼",    Mesh = "official://mesh/7000558", Preset = "official://preset/9000116" },
        ["7000559"] = { Name = "金鱼",    Mesh = "official://mesh/7000559", Preset = "official://preset/9000117" },
        ["7000560"] = { Name = "鲫鱼",    Mesh = "official://mesh/7000560", Preset = "official://preset/9000118" },
        ["7000561"] = { Name = "兰寿",    Mesh = "official://mesh/7000561", Preset = "official://preset/9000119" },
        ["7000562"] = { Name = "食人鱼",  Mesh = "official://mesh/7000562", Preset = "official://preset/9000120" },
        ["7000563"] = { Name = "小丑鱼",  Mesh = "official://mesh/7000563", Preset = "official://preset/9000121" },
    },
}

return GameCfg
