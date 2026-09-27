local GameCfg = {}

-- 场景交互气泡：参考 GM 的独立白字层，显式设置字号，避免按钮默认文字过小。
GameCfg.InteractionBubble = {
    Width = 220,
    Height = 84,
    FontSize = 40,
    Gap = 20,
    Image = 'official://image/11017',
    BackgroundColor = { 35, 57, 78, 245 },
}

-- MVP 物品表；官方图片目录没有这些物品的同名图，按 issue #33 确认使用代表图。
-- 鱼获共用 11164「鱼」，蚯蚓用 14066「勾爪-距离」的弯曲线条，鱼竿用 12024「捕虫网」；
-- M1（#84）新增：肉用 13008「肉」，鸭子用 11154「鸡腿」（目录无鸭，禽类代表），船票用 14105「门票」；
-- 选型核对的是官方目录 ID 与名称，试玩显示单独验收。对照记录见 issue #33（评论 9859）。
-- EatPercent = 物品表「食用恢复百分比」（#53）：吃一件恢复 EatPercent% × 上限的血量与饥饿度，没配的物品不能吃。
-- BasePrice = 物品表「基础出售价格（喂钓鱼佬）」：鱼获的 BasePrice 在 GameCfg.Fish 里（随个体倍率派生），
-- 这里只给不挂在鱼种表上的物品（掉落部位、鱼饵、鱼竿、船票）；信物喂食走兑换不走金币（#87 落地）。
GameCfg.Items = {
    ContainerId = { ItemBar = 'itemBar', Backpack = 'backpack', Bait = 'bait' },
    ItemBarSlots = 8,
    InitialItemBarSlots = 2,
    InitialBackpackSlots = 5,
    BackpackSlotsPerUpgrade = 5,
    -- 六次各 +5 从 5 只能到 35；#85 同时要求终值 40，最后一级补至 40。
    MaxBackpackSlots = 40,
    UpgradePrices = { 100, 200, 400, 800, 1600, 3200 },
    Id = { Tilapia = 'tilapia', Carp = 'carp', KnifeFish = 'knifeFish', Bass = 'bass', Catfish = 'catfish', Goldfish = 'goldfish', Worm = 'worm', StarterRod = 'starterRod',
        Shrimp = 'shrimp', RiverShrimp = 'riverShrimp', Crayfish = 'crayfish', BostonLobster = 'bostonLobster', AussieLobster = 'aussieLobster', MilkLobster = 'milkLobster',
        RareShrimp = 'rareShrimp', RareRiverShrimp = 'rareRiverShrimp', RareCrayfish = 'rareCrayfish',
        RareBostonLobster = 'rareBostonLobster', RareAussieLobster = 'rareAussieLobster', RareMilkLobster = 'rareMilkLobster',
        EelMeat = 'eelMeat', EelHead = 'eelHead', GarMeat = 'garMeat', GarHead = 'garHead', Duck = 'duck', ShrimpTicket = 'shrimpTicket',
        ShrimpRod = 'shrimpRod', CrabRod = 'crabRod', NormalRod = 'normalRod', ProRod = 'proRod', AirforceRod = 'airforceRod', UnscientificRod = 'unscientificRod' },
    ActionCooldownSec = 0.12,
    RodVisual = {
        -- Mesh 来自试玩世界单位「中式杆」（原 AssetId=map://preset/u46466002b9a47c588001c2e65ef4c3a）；
        -- 原场景 Scale=(0.2,1,0.2)，这里的缩放是左手持竿表现参数。
        Mesh = 'official://mesh/50450',
        Socket = 'l_weapon',
        Scale = { x = 0.2, y = 0.25, z = 0.2 },
    },
    Definitions = {
        tilapia = { Name = '罗非鱼', EatPercent = 15, Icon = 'official://image/11164' },
        carp = { Name = '鲤鱼', EatPercent = 20, Icon = 'official://image/11164' },
        knifeFish = { Name = '刀鱼', EatPercent = 20, Icon = 'official://image/11164' },
        bass = { Name = '鲈鱼', EatPercent = 25, Icon = 'official://image/11164' },
        catfish = { Name = '鲶鱼', EatPercent = 25, Icon = 'official://image/11164' },
        goldfish = { Name = '金鱼', EatPercent = 30, Icon = 'official://image/11164' },
        worm = { Name = '蚯蚓', EatPercent = 5, Icon = 'official://image/14066', Container = 'bait', BasePrice = 1 },
        starterRod = { Name = '新手鱼竿', Icon = 'official://image/12024', Level = 1, BasePrice = 3 },
        -- 虾池鱼获（#84，GameSpec §5.2 / 物品表 17-28；售价在 GameCfg.Fish 对应鱼种行）
        shrimp = { Name = '虾米', EatPercent = 15, Icon = 'official://image/11164' },
        riverShrimp = { Name = '沼虾', EatPercent = 20, Icon = 'official://image/11164' },
        crayfish = { Name = '小龙虾', EatPercent = 20, Icon = 'official://image/11164' },
        bostonLobster = { Name = '波龙', EatPercent = 25, Icon = 'official://image/11164' },
        aussieLobster = { Name = '澳龙', EatPercent = 25, Icon = 'official://image/11164' },
        milkLobster = { Name = '奶龙', EatPercent = 30, Icon = 'official://image/11164' },
        -- 极品鱼获同属极品食物，可投抽奖机（CONTEXT.md「信物」「抽奖机」）
        rareShrimp = { Name = '极品虾米', EatPercent = 15, Icon = 'official://image/11164' },
        rareRiverShrimp = { Name = '极品沼虾', EatPercent = 20, Icon = 'official://image/11164' },
        rareCrayfish = { Name = '极品小龙虾', EatPercent = 20, Icon = 'official://image/11164' },
        rareBostonLobster = { Name = '极品波龙', EatPercent = 25, Icon = 'official://image/11164' },
        rareAussieLobster = { Name = '极品澳龙', EatPercent = 25, Icon = 'official://image/11164' },
        rareMilkLobster = { Name = '极品奶龙', EatPercent = 30, Icon = 'official://image/11164' },
        -- 精英/首领掉落部位（#84，物品表 13-16）：电鳗头 = 精英信物，鳄雀鳝鱼头 = 首领信物（GameSpec §5.1 注）
        eelMeat = { Name = '电鳗肉', EatPercent = 50, Icon = 'official://image/13008', BasePrice = 10 },
        eelHead = { Name = '电鳗头', EatPercent = 50, Icon = 'official://image/11164', BasePrice = 10 },
        garMeat = { Name = '鳄雀鳝鱼肉', EatPercent = 100, Icon = 'official://image/13008', BasePrice = 15 },
        garHead = { Name = '鳄雀鳝鱼头', EatPercent = 100, Icon = 'official://image/11164', BasePrice = 20 },
        -- 首领饵「鸭子」（物品表 120）：按 #85 占道具栏/背包格；挂饵与首领抽签随 #88 落地
        duck = { Name = '鸭子', EatPercent = 10, Icon = 'official://image/11154', BasePrice = 10 },
        -- 船票（过关道具，不能吃）：交给摆渡 NPC 去虾池（#89 落地）；物品表原名「虾池车票」，
        -- 按 CONTEXT.md 术语定名「虾池船票」，后续钓鱼区各有一张
        shrimpTicket = { Name = '虾池船票', Icon = 'official://image/14105', BasePrice = 1 },
        -- 七级鱼竿（#84，GameSpec §4.5/§7.2；商店售价在 GameCfg.Shop.Goods）
        shrimpRod = { Name = '钓虾竿', Icon = 'official://image/12024', Level = 2, BasePrice = 6 },
        crabRod = { Name = '捕蟹竿', Icon = 'official://image/12024', Level = 3, BasePrice = 13 },
        normalRod = { Name = '普通鱼竿', Icon = 'official://image/12024', Level = 4, BasePrice = 25 },
        proRod = { Name = '专业鱼竿', Icon = 'official://image/12024', Level = 5, BasePrice = 50 },
        airforceRod = { Name = '空军之竿', Icon = 'official://image/12024', Level = 6, BasePrice = 100 },
        unscientificRod = { Name = '不科学鱼竿', Icon = 'official://image/12024', Level = 7, BasePrice = 250 },
    },
}
-- 血量与饥饿（#53，#40 规格；设计案「玩家属性」）：上限各 300，饥饿每秒 −HungerPerSec，归零后的下一秒起
-- 每秒经 MgrVitals:ApplyDamage 掉 StarveDamagePerSec 血；按 World:GetServerTime() 的整秒推进，
-- 服务端卡顿后一次最多补算 MaxCatchUpSec 秒。死亡后引擎 ReviveDelaySec 秒复活（编辑器面板复活延时，M0 已核），
-- 超过 ReviveDelaySec + ReviveGraceSec 仍没复活，服务端兜底调一次 Controller:Reborn()。复活后两项回满。
-- HUD（client/ScreenHandlers/ScreenMain.lua）：左上角两个环形进度 + 数值；饥饿归零期间屏幕四边红框
-- 每 FlashPeriodSec 秒亮灭一次，WarnText 每 WarnIntervalSec 秒提示一次（设计案只写「闪红」和这句提示，
-- 频率与间隔是替换点）。图片资源用途：
--   HealthRing / HungerRing  环形进度填充 30013（标准环形 128×128），RingBg 环形背景 30014
--   FlashImage               四边红框的底图 11081（圆角矩形），按 FlashColor 染红
-- [未查证：环形图、红框观感与 HUD 位置是否与 LabelCoin / 任务条重叠，待 #55 截图迭代]
GameCfg.Vitals = {
    MaxHealth = 300,
    MaxHunger = 300,
    HungerPerSec = 1,
    StarveDamagePerSec = 5,
    MaxCatchUpSec = 5,
    ReviveDelaySec = 5,
    ReviveGraceSec = 2,
    FlashPeriodSec = 0.5,
    WarnIntervalSec = 5,
    WarnText = '我要饿死了！',
    HealthRing = 'official://image/30013',
    HungerRing = 'official://image/30013',
    RingBg = 'official://image/30014',
    HealthColor = { 230, 60, 60, 255 },
    HungerColor = { 240, 170, 40, 255 },
    FlashImage = 'official://image/11081',
    FlashColor = { 255, 0, 0, 150 },
    FlashThickness = 40,
}

-- 调试开关（#47 / #49，#28 规格）：开发阶段默认开启，发布或开放地图前关闭。开启后服务端接受 GM 发放
-- （server/Mgr/MgrGM.lua，客户端控制台 _G.GM.Coin / _G.GM.Item / _G.GM.SetHealth / _G.GM.SetHunger），进图时按 InitialGrants 白送（M1 的进图白送降级至此）。
-- 关闭时正式获取路径只有拾饵、喂食换金币与商店购买。
GameCfg.Debug = {
    Enabled = true,
    InitialGrants = {
        { itemId = GameCfg.Items.Id.StarterRod, count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
        { itemId = GameCfg.Items.Id.Worm, count = 10, containerId = GameCfg.Items.ContainerId.Bait },
    },
}

-- 鱼种基础值（design 钓鱼表 / 物品表）：Health=血量，BaseWeight=基础重量 kg，
-- BasePrice=基础出售价，Model=GameCfg.FishCarrier.Models 的模型号，Speed=逃脱移动速度（米/秒）。
-- 个体重量 = BaseWeight × 倍率、售价 = BasePrice × 倍率，由 common/FishCatch.lua 派生，不存快照。
-- Grade 品级（CONTEXT.md）：normal=普通鱼 / rare=极品鱼 / elite=精英鱼 / boss=首领。
-- 精英/首领另配 Attack=攻击力、EscapeSec=逃跑时限（秒）、Drops=击杀掉落——它们不掉自身鱼获，
-- 所以没有同名物品定义，BasePrice 记 0（电鳗在 #86 入表，首领随 #88 接入）；
-- 普通/极品没有 Drops，鱼获即自身（物品定义同名）。
-- M1（#84）：鱼塘加精英电鳗、首领鳄雀鳝；虾池 6 普通 + 6 极品（GameSpec §5.2），
-- 极品数值与普通版相同（规格「同上」），虾池模型先用鱼塘鱼占位（已知差异不算 bug，正式模型随 #90）。
GameCfg.Fish = {
    -- 鱼塘（第一钓鱼区）普通鱼
    tilapia = { Name = '罗非鱼', Grade = 'normal', Health = 5, BaseWeight = 1, BasePrice = 3, Model = '7000557', Speed = 3 },
    carp = { Name = '鲤鱼', Grade = 'normal', Health = 10, BaseWeight = 5, BasePrice = 4, Model = '7000552', Speed = 3 },
    knifeFish = { Name = '刀鱼', Grade = 'normal', Health = 15, BaseWeight = 0.5, BasePrice = 5, Model = '7000545', Speed = 3 },
    bass = { Name = '鲈鱼', Grade = 'normal', Health = 20, BaseWeight = 2, BasePrice = 6, Model = '7000551', Speed = 3 },
    catfish = { Name = '鲶鱼', Grade = 'normal', Health = 25, BaseWeight = 5, BasePrice = 7, Model = '7000553', Speed = 3 },
    goldfish = { Name = '金鱼', Grade = 'normal', Health = 3, BaseWeight = 0.1, BasePrice = 8, Model = '7000559', Speed = 3 },
    -- 鱼塘精英/首领（GameSpec §5.1 第 7/8 行；模型占位：电鳗用 7000545「旗鱼」（与刀鱼同模型）、
    -- 鳄雀鳝用 7000546「鲨鱼」，正式模型随 #86/#88；鱼饵/权重是抽签表行字段，随 #86/#88 一并入表）
    eel = { Name = '电鳗', Grade = 'elite', Health = 300, Attack = 10, BaseWeight = 5, BasePrice = 0, Model = '7000545', Speed = 6, EscapeSec = 180,
        Combat = 'eel',
        Drops = { { ItemId = 'eelMeat', Count = 2 }, { ItemId = 'eelHead', Count = 1 } } },
    alligatorGar = { Name = '鳄雀鳝', Grade = 'boss', Health = 600, Attack = 30, BaseWeight = 5, BasePrice = 0, Model = '7000546', Speed = 6, EscapeSec = 300,
        Drops = { { ItemId = 'garMeat', Count = 2 }, { ItemId = 'garHead', Count = 1 } } },
    -- 虾池（第二钓鱼区）普通鱼（#84，GameSpec §5.2；模型按鱼塘六鱼顺次占位）
    shrimp = { Name = '虾米', Grade = 'normal', Health = 20, BaseWeight = 0.02, BasePrice = 4, Model = '7000557', Speed = 3 },
    riverShrimp = { Name = '沼虾', Grade = 'normal', Health = 30, BaseWeight = 0.05, BasePrice = 10, Model = '7000552', Speed = 3 },
    crayfish = { Name = '小龙虾', Grade = 'normal', Health = 40, BaseWeight = 0.1, BasePrice = 12, Model = '7000545', Speed = 3 },
    bostonLobster = { Name = '波龙', Grade = 'normal', Health = 50, BaseWeight = 1, BasePrice = 15, Model = '7000551', Speed = 4 },
    aussieLobster = { Name = '澳龙', Grade = 'normal', Health = 60, BaseWeight = 2, BasePrice = 18, Model = '7000553', Speed = 4 },
    milkLobster = { Name = '奶龙', Grade = 'normal', Health = 70, BaseWeight = 10, BasePrice = 21, Model = '7000559', Speed = 4 },
    -- 虾池极品鱼：数值与普通版相同，模型跟随各自的普通版
    rareShrimp = { Name = '极品虾米', Grade = 'rare', Health = 20, BaseWeight = 0.02, BasePrice = 4, Model = '7000557', Speed = 3 },
    rareRiverShrimp = { Name = '极品沼虾', Grade = 'rare', Health = 30, BaseWeight = 0.05, BasePrice = 10, Model = '7000552', Speed = 3 },
    rareCrayfish = { Name = '极品小龙虾', Grade = 'rare', Health = 40, BaseWeight = 0.1, BasePrice = 12, Model = '7000545', Speed = 3 },
    rareBostonLobster = { Name = '极品波龙', Grade = 'rare', Health = 50, BaseWeight = 1, BasePrice = 15, Model = '7000551', Speed = 4 },
    rareAussieLobster = { Name = '极品澳龙', Grade = 'rare', Health = 60, BaseWeight = 2, BasePrice = 18, Model = '7000553', Speed = 4 },
    rareMilkLobster = { Name = '极品奶龙', Grade = 'rare', Health = 70, BaseWeight = 10, BasePrice = 21, Model = '7000559', Speed = 4 },
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
    -- WorldUnit API 的阻尼范围为 0～1；越界值会在抓举时使坐标变为 NaN。
    LinearDamping = 0.5,
    AngularDamping = 0.5,
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

-- 鱼获（#43，#27 规格）：鱼死亡时在它的位置（举着时在持有者脚下）向下探地，贴地生成一份
-- 不参与物理、不消失的鱼获；PickupRadius 米内客户端显示「拾取」文字泡（策划案 line 151 的 2 米），
-- 服务端复验时多给 PickupSlack 米容差（网络延迟下角色位置两端不一致）[未查证：容差取值待 #55 实测]
GameCfg.Loot = {
    PickupRadius = 2,
    PickupSlack = 0.5,
    GroundRayUp = 1,
    GroundRayDown = 20,
    Height = 0.2,
    BubbleHeight = 1.2,
    DropSpacing = 1, -- 多份部位鱼获横向间距，避免模型与拾取泡完全重叠
}

-- 固定点位鱼饵（#45，#27 规格）：每个点位同时最多一份，复用鱼获的 2 米拾取与服务端复验，
-- 拾取成功后 RespawnSec 秒在原位刷新；鱼饵进 Bait 计数库存，不占道具栏格。鱼获不刷新、不消失。
-- Spots 的 Position 只用 x/z，y 由向下探地决定（Position.y 是探地起点参考）。
-- 正式新手点位（#51）：分布在空气墙围住的玩家可行走陆地上；
-- 2026-09-26 试玩寻路抵达五处候选点，向下射线均命中 y=5、法线向上。
-- 新手任务第 1 步「拾取 5 只蚯蚓」不必等刷新，改坐标只改这里。
-- Mesh 取官方资产「飘逸尾鳍」（软体蠕虫状，official://mesh/7000571），没有官方蚯蚓模型 [未查证：观感待 #55 截图]
GameCfg.BaitSpots = {
    RespawnSec = 15,
    Mesh = 'official://mesh/7000571',
    Scale = 0.3,
    Spots = {
        { Id = 'worm-1', ItemId = 'worm', Count = 1, Position = { x = 5, y = 6, z = 31 } },
        { Id = 'worm-2', ItemId = 'worm', Count = 1, Position = { x = 5, y = 6, z = 40 } },
        { Id = 'worm-3', ItemId = 'worm', Count = 1, Position = { x = 10, y = 6, z = 28 } },
        { Id = 'worm-4', ItemId = 'worm', Count = 1, Position = { x = 15, y = 6, z = 34 } },
        { Id = 'worm-5', ItemId = 'worm', Count = 1, Position = { x = 10, y = 6, z = 45 } },
    },
}

-- 新手任务（#51 前三步，#52 续写第 4–9 步；#40 规格）：文案对应策划案「新手任务」的 9 句（钓场老板按 CONTEXT.md 用词），
-- Kind 是玩法事实种类（MgrQuest:Notify 的 kind），ItemId 是要求的物品，Category 是要求的物品类别（fish = 鱼获），
-- Need 是次数。任务不发奖励，进度单局内存态。
-- 事实来源：PickBait 拾饵（MgrLoot）、Feed 喂食（MgrInteract）、Buy 购买（MgrShop）、EquipBait 鱼饵栏挂饵成功
-- （MgrPlayerData）、CastWater 抛竿落点在水区（MgrCast）、Land 收线上岸（MgrCast）、DropShore 主动放下且落点
-- 不在水区（MgrFishUnit）、Kill 鱼被打死，归属鱼的主人即上岸者（MgrFishUnit）。
-- 任务条文案「<Title> 步号/总步数：<Text>（计数）」；推进时消息条提示 NextNotice，全部完成提示 DoneText
GameCfg.Quest = {
    Title = '新手任务',
    NextNotice = '任务完成，下一步：%s',
    DoneText = '新手任务完成！',
    Steps = {
        { Kind = 'PickBait', ItemId = 'worm', Need = 5, Text = '拾取 5 只蚯蚓' },
        { Kind = 'Feed', ItemId = 'worm', Need = 5, Text = '喂钓鱼佬吃 5 只蚯蚓' },
        { Kind = 'Buy', ItemId = 'starterRod', Need = 1, Text = '向钓场老板购买 1 只新手鱼竿' },
        { Kind = 'EquipBait', ItemId = 'worm', Need = 1, Text = '捡只蚯蚓，挂饵' },
        { Kind = 'CastWater', Need = 1, Text = '水边第一次抛竿' },
        { Kind = 'Land', Need = 1, Text = '咬钩后狂点收线，将它拉上岸' },
        { Kind = 'DropShore', Need = 1, Text = '将鱼丢在岸上' },
        { Kind = 'Kill', Need = 1, Text = '揍它！把鱼打死！' },
        { Kind = 'Feed', Category = 'fish', Need = 1, Text = '捡起鱼，再喂给钓鱼佬' },
    },
}

-- 开场对话（#54，#40 规格；设计案「游戏开场：对话介绍游戏背景」）：进图后（客户端主界面首次打开时）
-- 对每名玩家调一次 StoryService:StartStory(player, StoryId)，可跳过由剧情系统自带的跳过按钮负责；
-- 任务推进与剧情无关，剧情信号只打日志取证（server/Mgr/MgrStory.lua）。
-- 降级：StoryId 未配置、StoryService 不可用、StartStory 报错，或 StartTimeoutSec 秒内没收到 OnStoryStart，
-- 就改发一条单行公告 FallbackText，并打带「[MgrStory] 降级」前缀的日志（原因 / 影响 / 接受者）。
-- [未查证] 本图剧情配表里还没有开场剧情（CLI 没有剧情编辑子命令，要在编辑器里配），StoryId 暂为 nil 走降级；
-- 配好后只填这里。FallbackText 是占位文案，非策划定案。
GameCfg.Story = {
    StoryId = nil,
    StartTimeoutSec = 3,
    FallbackText = '欢迎来到钓场！钓鱼佬什么都吃，钓场老板卖鱼竿——跟着左上角的新手任务开始吧。',
}

-- 上钩提示（#54，#40 规格的占位方案，非策划定案，替换点在此一处）：抛竿会话进入 hooked 相位的那一次，
-- 同时给出文字 Text、2 号位收线按钮高亮（HighlightColor 与常规底色按 BreathPeriodSec 呼吸式明暗）、提示音 Sound 一次，
-- 持续 DurationSec 秒后高亮停止、文字回到收线百分比。同一收线会话只提示一次（界面重开不重复）。
-- [未查证] Sound 取官方音频库示例号 10001（docs SoundUnit 示例），实际音色待 #55 试听；播放失败只保留文字与高亮并打日志
GameCfg.HookAlert = {
    DurationSec = 3,
    Text = '鱼上钩了！狂点收线',
    HighlightColor = { 255, 190, 40, 255 },
    BreathPeriodSec = 0.6,
    Sound = 'official://audio/10001',
    Volume = 100,
}

-- 交互点（#44，#27 规格）：场景既有触发器单位登记为可交互目标，当前只有钓鱼佬（TGUnitFish，
-- 退役入口 LocalFishEnter 用它做靠近判定）。Radius 米内（只看 x/z：触发器中心在高处）显示「对话」「喂食」，
-- 服务端复验多给 Slack 米容差。喂食即出售：鱼获 floor(BasePrice × mult)，鱼饵每只 BaitPrice 金币。
-- 钓鱼佬的可见模型是官方「咸鱼」（official://preset/102179，场景单位名见 ModelName）；
-- 模型无 Eat 动画（EatAnimation 留空，服务端播动画自动跳过），喂食吃动作为客户端缩放脉冲
-- （LocalInteract 播，仅喂食者本机可见）。文字泡相对触发器中心（y=-1）抬高 9.5 米，露出高岸地面（y≈8.03）。
GameCfg.Interact = {
    Fisherman = {
        AnchorName = 'TGUnitFish',
        ModelName = 'FishermanModel',
        Radius = 5,
        Slack = 0.5,
        BubbleHeight = 9.5,
        DialogText = '我好饿啊，什么都吃！',
        BaitPrice = { worm = 1 },
    },
}

-- 钓场商店（#48，#28 规格）：价格真源是 design 商店表（渔力全开--商店表.xlsx）的「商店售价」列，
-- Goods 每行照抄表列：物品、商店售价 Price、所属分页 Page、最低商店等级 MinShopLevel、每人购买次数上限 PurchaseLimit。
-- MVP 白名单上架「钓具」分页的新手鱼竿（表编号 14）与蚯蚓（表编号 13）；
-- M1（#84）鱼竿表按七级统一：竿级 = 商店表七支竿的顺序，第 N 钓鱼区起售竿级 N 的竿（MinShopLevel = 竿级）。
-- 商店等级 Level 取当前钓鱼区序号（第一区 = 1，规格推断，替换点在此一处），
-- 所以 Level=1 时只有新手鱼竿可购，其余六级是落盘配置——钓虾竿上架随 #90 虾池商店生效。
-- 表里其余钓具（假饵等）、「武器」「升级」分页均未实现，不进白名单；
-- PurchaseLimit 都是 0（不限），MVP 只读不实现。入口复用场景触发器 TGUnitShop 与旧入口用过的文字泡预设；
-- Radius 米内（只看 x/z）显示提示，出了 Radius 自动关商店，服务端复验多给 Slack 米
-- [未查证] Radius 与触发器实际尺寸是否一致、文字泡高度，待 #55 实测
GameCfg.Shop = {
    AnchorName = 'TGUnitShop',
    BubblePreset = 'map://preset/uf5ad80a4c6a40d59b7f6e0eb99a58c0',
    BubbleHeight = 7,
    HintText = '看看有什么可买的',
    Radius = 5,
    Slack = 0.5,
    Level = 1,
    Goods = {
        { ItemId = 'starterRod', Price = 5, Page = '钓具', MinShopLevel = 1, PurchaseLimit = 0 },
        { ItemId = 'worm', Price = 1, Page = '钓具', MinShopLevel = 1, PurchaseLimit = 0 },
        { ItemId = 'shrimpRod', Price = 12, Page = '钓具', MinShopLevel = 2, PurchaseLimit = 0 },
        { ItemId = 'crabRod', Price = 24, Page = '钓具', MinShopLevel = 3, PurchaseLimit = 0 },
        { ItemId = 'normalRod', Price = 50, Page = '钓具', MinShopLevel = 4, PurchaseLimit = 0 },
        { ItemId = 'proRod', Price = 100, Page = '钓具', MinShopLevel = 5, PurchaseLimit = 0 },
        { ItemId = 'airforceRod', Price = 200, Page = '钓具', MinShopLevel = 6, PurchaseLimit = 0 },
        { ItemId = 'unscientificRod', Price = 500, Page = '钓具', MinShopLevel = 7, PurchaseLimit = 0 },
    },
}

-- 抛竿选鱼（钓鱼表）。Zones 每行：Id=鱼种，Bait=需要的鱼饵（0 = 不挂饵也可），RodLevel=鱼竿等级下限
-- （鱼竿 Definitions.Level ≥ RodLevel 才可钓，第一区全为 1），DrawWeight=钓鱼表的「抽签权重」。
-- DrawWeight 与基础重量 BaseWeight（kg）、个体重量 FishCatch.Weight 无关，别拿它乘倍率（#49 从 Weight 改名）
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
            { Id = 'tilapia', Bait = 0, RodLevel = 1, DrawWeight = 8 },
            { Id = 'carp', Bait = 'worm', RodLevel = 1, DrawWeight = 8 },
            { Id = 'knifeFish', Bait = 'worm', RodLevel = 1, DrawWeight = 8 },
            { Id = 'bass', Bait = 'worm', RodLevel = 1, DrawWeight = 32 },
            { Id = 'catfish', Bait = 'worm', RodLevel = 1, DrawWeight = 24 },
            { Id = 'goldfish', Bait = 'worm', RodLevel = 1, DrawWeight = 16 },
            { Id = 'eel', Bait = 'worm', RodLevel = 1, DrawWeight = 10 },
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
    -- #86 原型：复用挥砍预设的 0.5 秒施法窗口，半径取现有近战命中盒宽度 3 米；
    -- 范围、乱甩角度为可调表现参数，睡眠 10 秒来自钓鱼表原案。
    FishAbilities = {
        eel = {
            AssetId = "map://preset/ucc31d1999a543a7ab329eff1fd3c00d",
            Index = 0,
            Anchor = "map://preset/u471a1004c1f43f1ae6ebe4ee2bcd080",
            AnchorBehavior = "eel_discharge",
            Radius = 3,
            CastSec = 0.5,
            SleepSec = 10,
            SleepRollRadians = math.pi / 2, -- 睡眠侧躺，醒来或逃脱时恢复初始朝向
            FlailRadians = 0.45,
            FlailHz = 8,
        },
    },
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

-- 水判定：同一钓鱼区可用多条正方形拼接。Center 只用到 x/z（y 留作场景溯源），HalfXZ 是水平半宽（米），
-- SurfaceY 是水面高度（米）；判定语义与配置校验见 common/MathWaterJudge.lua，
-- 边界用例见 tests/gameplay/water_judge_test.lua，取值溯源见 issue #25 的 M0 模块线台账（评论 9862）。
-- 2026-09-24 在 #12 的场景基础上水平扩建两倍，中心与高度不变；编辑器回读：
--   WaterCircle1  Position(-11.75, 1.05, 27.75) Size(6, 1, 6) Scale(2, 1, 2)
--   WaterCircle2  Position(-11.75, 1.05, 27.75) Size(12, 1, 12) Scale(4, 1, 4)
--   两个水圈同心；HalfXZ 与 SurfaceY 的取值见下面两条注意，SurfaceY 已按 #31 的实测改正。
-- 注意 1：运行时读到的 Size 已含 Scale（WaterCircle2 的 Scale.x=4 已经算进 Size.x=12），
--         HalfXZ 直接写半边尺寸（12/2=6），配置时再乘缩放会重复计算（#12 W-4）。
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
        { Id = "WaterCircle2", Center = { x = -11.75, y = 1.05, z = 27.75 }, HalfXZ = 6.0, SurfaceY = 2.183 },
        { Id = "WaterCircle1", Center = { x = -11.75, y = 1.05, z = 27.75 }, HalfXZ = 3.0, SurfaceY = 2.183 },
    },
}

-- 2026-09-27 编辑器实测：六面空气墙围成带西南凹角的地块。
-- 按墙体水平厚度 3 米的外沿留出陆地：外框 x[-24.25,21.75]、z[16.25,61.25]，
-- 西南凹角 x<-4.982 且 z<35.268。墙体本身不作为水域，闭区间交界线沿用水判定约定。
-- 本轮只覆盖大地板水平尺寸 90×60 的范围 x[-58.75,31.25]、z[10.75,70.75]。
-- 各矩形用短边作正方形边长，最后一块向回贴齐；允许重叠，避免末端留缝或越界。
local function addWaterStrip(name, minX, maxX, minZ, maxZ)
    local side = math.min(maxX - minX, maxZ - minZ)
    local countX = math.ceil((maxX - minX) / side)
    local countZ = math.ceil((maxZ - minZ) / side)
    for ix = 1, countX do
        for iz = 1, countZ do
            local id = name .. '_' .. ix .. '_' .. iz
            GameCfg.Water.Zones[#GameCfg.Water.Zones + 1] = {
                Id = id,
                Center = {
                    x = math.min(minX + (ix - 1) * side, maxX - side) + side / 2,
                    y = 1.05,
                    z = math.min(minZ + (iz - 1) * side, maxZ - side) + side / 2,
                },
                HalfXZ = side / 2,
                SurfaceY = 2.183,
            }
            GameCfg.Casting.Zones[id] = GameCfg.Casting.Zones.WaterCircle2
        end
    end
end

addWaterStrip('PondWest', -58.75, -24.25, 10.75, 70.75)
addWaterStrip('PondEast', 21.75, 31.25, 10.75, 70.75)
addWaterStrip('PondSouth', -24.25, 21.75, 10.75, 16.25)
addWaterStrip('PondNorth', -24.25, 21.75, 61.25, 70.75)
addWaterStrip('PondNotch', -24.25, -4.982, 16.25, 35.268)

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
-- 谁消费：M2「打鱼变现」按上面的写法建鱼；改本表时 tests/gameplay/water_judge_test.lua 的
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
