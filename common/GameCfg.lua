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
        starterRod = { Name = '新手鱼竿', Icon = 'official://image/12024' },
    },
}
GameCfg.Items.InitialGrants = {
    { itemId = GameCfg.Items.Id.StarterRod, count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
    { itemId = GameCfg.Items.Id.Worm, count = GameCfg.Items.InitialWormCount, containerId = GameCfg.Items.ContainerId.Bait },
}

GameCfg.Casting = {
    Distance = 5,
    HookDelaySec = 3,
    ActionCooldownSec = 0.12,
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
            { Id = 'electricEel', Bait = 'worm', RodLevel = 1, Weight = 10 },
        },
    },
}

GameCfg.FishMap = {
    Fish001 = {Id = "Fish001",  Name = "草鱼",  Icon = 37132,    ReqStep = 3,    Coin = 40}, --Icon = "official://image/37132"
    Fish002 = {Id = "Fish002",  Name = "小丑鱼",    Icon = 37137,    ReqStep = 2,    Coin = 25},
    Fish003 = {Id = "Fish003",  Name = "鲫鱼",  Icon = 37134,    ReqStep = 3,    Coin = 30},
    Fish004 = {Id = "Fish004",  Name = "黑鱼",  Icon = 37125,    ReqStep = 3,    Coin = 35},
    Fish005 = {Id = "Fish005",  Name = "章鱼",  Icon = 15970,    ReqStep = 4,    Coin = 80},
    Fish006 = {Id = "Fish006",  Name = "旗鱼",  Icon = 37119,    ReqStep = 4,    Coin = 70},
    Fish007 = {Id = "Fish007",  Name = "蝴蝶鱼",    Icon = 37123,    ReqStep = 4,    Coin = 90},
    Fish008 = {Id = "Fish008",  Name = "鳐鱼",  Icon = 37121,    ReqStep = 5,    Coin = 150},    --150
    Fish009 = {Id = "Fish009",  Name = "三文鱼",  Icon = 37130,    ReqStep = 5,    Coin = 160},  --160
    Fish010 = {Id = "Fish010",  Name = "大马哈鱼",  Icon = 37118,    ReqStep = 5,    Coin = 120},   --120
    Fish011 = {Id = "Fish011",  Name = "鲨鱼",  Icon = 37120,    ReqStep = 6,    Coin = 200},
    Fish012 = {Id = "Fish012",  Name = "七彩鱼",  Icon = 37129,    ReqStep = 6,    Coin = 300},
    Fish013 = {Id = "Fish013",  Name = "大章鱼",  Icon = 33706,    ReqStep = 6,    Coin = 250},
}
--35971 鱼竿
GameCfg.MaxRodLv = 5
GameCfg.RodLevelMap = {}
GameCfg.RodLevelMap[1] = {
    Cost = 100, --升级需求
    FishTime = 4,
}

GameCfg.RodLevelMap[2] = {
    Cost = 500,
    FishTime = 4.5,
}

GameCfg.RodLevelMap[3] = {
    Cost = 1000,
    FishTime = 5,
}

GameCfg.RodLevelMap[4] = {
    Cost = 10000,
    FishTime = 5.5,
}

GameCfg.RodLevelMap[5] = {
    Cost = 0,
    FishTime = 6,
}

GameCfg.MaxFishLv = 5
GameCfg.FishLevelMap = {}
GameCfg.FishLevelMap[1] = {
    Cost = 100,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
    }
}

GameCfg.FishLevelMap[2] = {
    Cost = 500,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 1,
        Fish006 = 1,
        Fish007 = 1,
    }
}

GameCfg.FishLevelMap[3] = {
    Cost = 1000,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 2,
        Fish006 = 2,
        Fish007 = 2,
        Fish008 = 1,
        Fish009 = 1,
        Fish010 = 1,
    }
}

GameCfg.FishLevelMap[4] = {
    Cost = 10000,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 2,
        Fish006 = 2,
        Fish007 = 2,
        Fish008 = 2,
        Fish009 = 2,
        Fish010 = 2,
        Fish011 = 1,
        Fish012 = 1,
        Fish013 = 1,
    }
}

GameCfg.FishLevelMap[5] = {
    Cost = 0,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 2,
        Fish006 = 2,
        Fish007 = 2,
        Fish008 = 3,
        Fish009 = 3,
        Fish010 = 3,
        Fish011 = 4,
        Fish012 = 4,
        Fish013 = 4,
    }
}

function GameCfg:GetLootRst(loot)
    local total = 0
    for _, v in pairs(loot) do
        total = total + v
    end

    local randomValue = math.random(total)
    for k, v in pairs(loot) do
        if randomValue > v then
            randomValue = randomValue - v
        else
            return k
        end
    end
end

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
-- 与 GameCfg.FishMap 的鱼种对照（台账 §2.1）：13 个鱼种里 11 个在号段内一一对上——
--   Fish010 大马哈鱼 7000544 / Fish006 旗鱼 7000545 / Fish011 鲨鱼 7000546 / Fish008 鳐鱼 7000547 /
--   Fish007 蝴蝶鱼 7000549 / Fish004 黑鱼 7000551 / Fish012 七彩鱼 7000555 / Fish009 三文鱼 7000556 /
--   Fish001 草鱼 7000558 / Fish003 鲫鱼 7000560 / Fish002 小丑鱼 7000563
-- 未定案（要策划拍，本表不猜）：Fish005 章鱼不在号段内（台账记为模型号 6000019 /
--   official://preset/1510600）、Fish013 大章鱼没有对应模型号（台账建议退化为章鱼）。
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
