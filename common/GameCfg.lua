local GameCfg = {}
local ContentItems = require('common.cfg.Items')
local ContentFish = require('common.cfg.Fish')
local ContentShop = require('common.cfg.Shop')
local ContentLottery = require('common.cfg.Lottery')
local ContentBlindbox = require('common.cfg.Blindbox')
local FishCatch = require('common.FishCatch')

-- 钓鱼区 ID 用于内容与后续场景锚点；存档旧值在 LegacyZoneIdMap 中解析。
-- WaterId 是内容层稳定 ID，现场 Water.Zones[*].Id 保留已有编辑器单位名称。
GameCfg.Zones = {
    { Id = 'fishPond', Name = '鱼塘', WaterId = 'fishPond.water', BaitItemId = 'worm', source = '钓鱼表!R2' },
    { Id = 'shrimpPond', Name = '虾池', WaterId = 'shrimpPond.water', BaitItemId = 'sausage', source = '钓鱼表!R16' },
    { Id = 'crabLake', Name = '蟹湖', WaterId = 'crabLake.water', BaitItemId = 'item115', source = '钓鱼表!R30' },
    { Id = 'forestIsland', Name = '树林岛', WaterId = 'forestIsland.water', BaitItemId = 'item116', source = '钓鱼表!R44' },
    { Id = 'beachIsland', Name = '沙滩岛', WaterId = 'beachIsland.water', BaitItemId = 'item117', source = '钓鱼表!R58' },
    { Id = 'reefIsland', Name = '礁石岛', WaterId = 'reefIsland.water', BaitItemId = 'item118', source = '钓鱼表!R72' },
    { Id = 'volcanoIsland', Name = '火山岛', WaterId = 'volcanoIsland.water', BaitItemId = 'item119', source = '钓鱼表!R86' },
}
GameCfg.LegacyZoneIdMap = { fishPond1 = 'fishPond', shrimpPond = 'shrimpPond' }

function GameCfg.ResolveZoneId(id)
    return GameCfg.LegacyZoneIdMap[id] or id
end


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
    Id = { Tilapia = 'tilapia', Carp = 'carp', KnifeFish = 'knifeFish', Bass = 'bass', Catfish = 'catfish', Goldfish = 'goldfish', Worm = 'worm', Sausage = 'sausage', StarterRod = 'starterRod',
        Shrimp = 'shrimp', RiverShrimp = 'riverShrimp', Crayfish = 'crayfish', BostonLobster = 'bostonLobster', AussieLobster = 'aussieLobster', MilkLobster = 'milkLobster',
        RareShrimp = 'rareShrimp', RareRiverShrimp = 'rareRiverShrimp', RareCrayfish = 'rareCrayfish',
        RareBostonLobster = 'rareBostonLobster', RareAussieLobster = 'rareAussieLobster', RareMilkLobster = 'rareMilkLobster',
        EelMeat = 'eelMeat', EelHead = 'eelHead', GarMeat = 'garMeat', GarHead = 'garHead', Duck = 'duck', ShrimpTicket = 'shrimpTicket',
        ShrimpRod = 'shrimpRod', CrabRod = 'crabRod', NormalRod = 'normalRod', ProRod = 'proRod', AirforceRod = 'airforceRod', UnscientificRod = 'unscientificRod' },
    ActionCooldownSec = 0.12,
    -- 药水累计上限（物品表 item167/168 SourceDescription：加速最多 20 个、变大最多 10 个）
    PotionLimits = { item167 = 20, item168 = 10 },
    RodVisual = {
        -- Mesh 来自试玩世界单位「中式杆」（原 AssetId=map://preset/u46466002b9a47c588001c2e65ef4c3a）；
        -- 原场景 Scale=(0.2,1,0.2)，这里的缩放是左手持竿表现参数。
        Mesh = 'official://mesh/50450',
        Socket = 'l_weapon',
        Scale = { x = 0.2, y = 0.25, z = 0.2 },
    },
    Definitions = ContentItems.Definitions,
    SourceIdMap = ContentItems.SourceIdMap,
    LegacyIdMap = ContentItems.LegacyIdMap,
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

-- 生存恢复（#131，T10；策划案「濒死/复活」段原文数值，server/Mgr/MgrSurvival.lua）：
-- 血量扣到 1 点锁血倒地进入濒死，DownedSec 秒倒计时内可被抢救或自用肾上腺素解除（恢复
-- ReviveHealthPercent% 血量），否则死亡；死亡 DeadSec 秒倒计时结束原地虚弱复活（血量
-- ReviveHealthPercent%、饥饿至少 ReviveHungerPercent%、虚弱 WeakSec 秒、移速 ×WeakSpeedScale）。
-- 濒死/死亡暂停饥饿、无敌锁血、拒绝普通动作、断开钓鱼并释放举鱼；濒死或死亡退出重进按
-- 虚弱复活处理（原地 10% 血 + 虚弱）；虚弱中退出记录剩余秒数，重进继续倒数（离线不计时）。
-- 肾上腺素物品表 item171（R172 自救道具，购买获得）；无物时的平台购买入口与推广/金豆满血复活
-- 是平台能力接缝，适配归 T26。
GameCfg.Survival = {
    DownedSec = 15,
    DeadSec = 30,
    ReviveHealthPercent = 10,
    ReviveHungerPercent = 10,
    WeakSec = 60,
    WeakSpeedScale = 0.5,
    AdrenalineItemId = 'item171',
    -- 濒死呼救（策划案：两句随机冒，30 米内其他玩家可见）
    HelpCries = { '要死啦！', '救救我！' },
    HelpRadius = 30,
    HelpCooldownSec = 1,
    -- 蒙版文案（策划案原文）
    DownedTitle = '你还能再抢救一下！',
    DeadTitle = '你已经死了！倒计时结束后虚弱复活。',
    AdrenalineText = '给自己一针肾上腺素',
    CallHelpText = '向队友呼救',
    FreeReviveText = '免费满血复活',
    PaidReviveText = '5金豆满血复活',
    NoAdrenalineText = '没有肾上腺素，可前往地图商店购买',
    PlatformPendingText = '平台复活即将开放，请等待倒计时虚弱复活',
    WeakText = '虚弱中：移动速度减半',
    UnavailableText = '操作暂时不可用，请稍后再试',
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

-- 鱼种原表与物品引用在 common/cfg/Fish.lua；部分实体模型、招式尚待后续子单接入。
GameCfg.Fish = ContentFish.Definitions
GameCfg.FishSourceIdMap = ContentFish.SourceIdMap
GameCfg.LegacyFishIdMap = ContentFish.LegacyIdMap

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

-- 鱼获与共享地面实例（#43、#126 T05，#27 规格）：鱼死亡时在它的位置（举着时在持有者脚下）向下探地，
-- 贴地生成一份不参与物理、不消失的鱼获；PickupRadius 米内客户端显示「拾取」文字泡（策划案 line 151 的 2 米），
-- 服务端复验时多给 PickupSlack 米容差（网络延迟下角色位置两端不一致）[未查证：容差取值待 #55 实测]
GameCfg.Loot = {
    PickupRadius = 2,
    PickupSlack = 0.5,
    GroundRayUp = 1,
    GroundRayDown = 20,
    Height = 0.2,
    BubbleHeight = 1.2,
    DropSpacing = 1, -- 多份部位鱼获横向间距，避免模型与拾取泡完全重叠
    -- 分区上限回收（#91/#126，GameSpec §6.5）：场上掉落/丢弃物总量按**钓鱼区**（Water.Zones[*].ZoneId，
    -- 如 fishPond/shrimpPond）计数——同区的多块水域共用一份预算；超限最旧的先闪烁 FlashBeforeRecycleSec
    -- 秒再销毁；待回收期间仍可拾取，拾取即取消回收。上限进配置供压测校准。
    PerZoneCap = 200,
    FlashBeforeRecycleSec = 30,
    RecycleRetrySec = 5, -- 销毁失败（单位已被别的路径收走等）后的重试间隔
    FlashIntervalSec = 0.5, -- 待回收闪烁的可见性切换间隔（服务端驱动模型、客户端同节奏闪文字泡）
    -- 预警期（待回收）上限（#126）：待回收件不计入 PerZoneCap，若不封顶，「活跃 200 + 无限预警」仍会涨；
    -- 超过 PendingCap 时立刻回收最旧的预警件（跳过剩余预警），单区总量恒 ≤ PerZoneCap + PendingCap。
    -- 暂取 PerZoneCap 的 20% [未查证：取值待压测校准]
    PendingCap = 40,
    -- 主动丢弃落点（#126）：角色正前方 DropOffset 米，沿用 MgrFishUnit 放下鱼的口径
    DropOffset = 1.5,
    -- 非鱼物品（信物/首领饵/船票/普通饵/武器等）没有专用模型：借用 #45 点位鱼饵已在用的官方资产
    -- 「飘逸尾鳍」（official://mesh/7000571）作通用落物外观，缩放同点位鱼饵 [未查证：观感待 #55 截图]
    ItemMesh = 'official://mesh/7000571',
    ItemScale = 0.3,
}

-- 存档（#92）：DataStore 集合名与键前缀、限流重试策略。写失败只记日志不动内存态（内存比存档新），
-- 读写失败按 RetryDelaySec 退避重试 MaxRetries 次；AutosaveSec 周期自动存档，兑换/收船票即时记账，
-- 同一人写入合并排队只留最新快照（技术难点 §5）；体积与写频台账在 MgrSave.Ledger（验收③）。
GameCfg.Save = {
    Store = 'sefish_save_v1',
    KeyPrefix = 'u',
    -- #93 验收专用：在试玩前执行 lua tools/cli.lua acceptance-slot new，并部署。
    -- 同一账号同槽重进会恢复进度；切换或关闭槽用 acceptance-slot set/off，正式存档不受影响。
    -- 试玩过程中不要部署或更换槽名。
    AcceptanceSlot = '',
    MaxRetries = 3,
    RetryDelaySec = 1,
    AutosaveSec = 60,
}

-- 全服纪录（#149 T28）。CONTEXT「纪录」= 某种鱼在所有玩家中的最大重量及其保持者，
-- 与「个人最大重量」（图鉴收集口径，extra.collection.weights，归 #133）是两套数据。
-- 存储口径：重量按两位小数放大成整数（Scale）；保持者身份与重量写进**同一条记录**
-- （{ w = 放大整数, u = UserID, n = 显示名 }），一次 UpdateAsync CAS 同时落地——
-- 从结构上排除「重量更新了、名字还是旧的」这种错配，读出一律读整条三元组。
-- 权威数据放普通 DataStore 的单键三元组；OrderedDataStore 的整数范围、限流与跨服可见性
-- 在编辑器内不可实测，排行索引等 T27 实测通过再加（本轮没有排行消费者，不建派生索引）。
-- [未查证] OrderedDataStore 整数范围、DataStore 限流速率与错误码文本（技术难点 §5/§6 只有错误码，无阈值）。
-- 上限用 MaxScaled 挡：超出按 overflow 拒绝并留日志，不截断、不四舍五入（鱼种表里
-- fish56Boss 的 BaseWeight 是 50000000 的占位值，放大后会越界，正好被这条挡住）。
GameCfg.Records = {
    Store = 'sefish_records_v1',
    KeyPrefix = 'rec:',
    Scale = 100,                 -- 定标因子：两位小数放大为整数
    MaxScaled = 1e9,             -- 合法上限（= 1000 万 kg）
    MaxNameLength = 32,          -- 显示名长度上限，超长按缺失处理
    HolderFallback = '玩家%s',   -- 显示名缺失/改名未同步时的兜底（代入 UserID）
    HolderCacheTtlSec = 30,      -- 读到的纪录缓存有效期
    MissCacheTtlSec = 5,         -- 读失败与「暂无纪录」的负缓存，避免连续请求打爆读频
    FlushIntervalSec = 5,        -- 合并写入窗口：窗口内同鱼种的上岸只产生一次写
    MaxRetries = 3,              -- 写失败重试次数（重试走 CAS，过期候选不会盖掉更新的纪录）
    RetryDelaySec = 1,           -- 重试退避（秒）
    RequestCooldownSec = 0.2,    -- 单玩家纪录查询限频
    Texts = {
        Format = '全服纪录：%.2f kg（%s）',
        Missing = '全服纪录：暂无',
        Unavailable = '全服纪录：暂不可用',
    },
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

GameCfg.CastFeedback = {
    SplashDurationSec = 2.5,
    FloatSize = 56,
    FloatColor = { 255, 225, 70, 255 },
}

-- 交互点（#44，#27 规格）：场景既有触发器单位登记为可交互目标。当前只有钓鱼佬：
-- Radius 米内（只看 x/z：触发器中心在高处）显示「对话」「喂食」，服务端复验多给 Slack 米容差。
-- 喂食即出售（#127 改为按物品表回收）：未烤的本区信物优先走本区链 1:1 兑换（表见 Interact.Fishermen），
-- 其余选中物品按基础价 × 实例倍率结金币、烤过的按烤熟价；选中的鱼饵按 BaitPrice 每只结算。
-- 钓鱼佬的可见模型是官方「咸鱼」（official://preset/102179，场景单位名见 ModelName）；
-- 模型无 Eat 动画（EatAnimation 留空，服务端播动画自动跳过），喂食吃动作为客户端缩放脉冲
-- （LocalInteract 播，仅喂食者本机可见）。文字泡相对触发器中心（y=-1）抬高 9.5 米，露出高岸地面（y≈8.03）。
-- 本表只放七区共享的表现与鱼饵价；每区的锚点与兑换链见下方 GameCfg.Interact.Fishermen（#127）。
GameCfg.Interact = {
    Fisherman = {
        ModelName = 'FishermanModel',
        Radius = 5,
        Slack = 0.5,
        BubbleHeight = 9.5,
        DialogText = '我好饿啊，什么都吃！',
        BaitPrice = { worm = 1 },
    },
}

-- 钓场商店（#48/#90 起，#130 全量落地）：价格真源是 design 商店表（渔力全开--商店表.xlsx）的
-- 「商店售价」列。Goods 是 common/cfg/Shop.lua 全量 50 行有效商品（编号 27 作废除外）的规范化货架：
-- 购买键是原表编号 Number（升级行没有物品 id）；有物品的行保留 ItemId 兼容旧调用。
-- 分页 Pages 固定四页：钓具/武器/升级（金币定价）与金币（平台购买入口，汇率与真实商品 ID 是
-- 后台交付参数，不编造；平台不可用时金币页降级提示、可返回、不伪成功）。
-- 摊位 Stands（#90）：每个钓鱼区一个摊位，Level = 钓鱼区序号；商品按 MinShopLevel <= 摊位 Level 上架，
-- 所以虾池摊（2 级）比一区摊（1 级）多香肠与钓虾竿。玩家站在哪个摊位旁就按哪个摊位的等级结算，
-- 范围复验用共享的 Radius / Slack。入口复用场景触发器与旧入口用过的文字泡预设；
-- Radius 米内（只看 x/z）显示提示，出了 Radius 自动关商店，服务端复验多给 Slack 米
-- [未查证] Radius 与触发器实际尺寸是否一致、文字泡高度，待 #55 实测
GameCfg.Shop = {
    Stands = {
        { AnchorName = 'TGUnitShop', Level = 1 },
        { AnchorName = 'TGUnitShopShrimp', Level = 2 },
        -- #136 蟹湖摊位（3 级）：上架鲱鱼罐头 / 捕蟹竿 / 霰弹枪与 3 级升级行；锚点已盘点在场
        { AnchorName = 'Z3_Shop', Level = 3 },
    },
    BubblePreset = 'map://preset/uf5ad80a4c6a40d59b7f6e0eb99a58c0',
    BubbleHeight = 7,
    HintText = '看看有什么可买的',
    Radius = 5,
    Slack = 0.5,
    Pages = ContentShop.Pages,
    Goods = {},
}

-- 货架行规范化（#130）：原表小写列名映射为运行端字段；升级行（无 itemKey）以 Number 为购买键。
for _, row in ipairs(ContentShop.Goods) do
    GameCfg.Shop.Goods[#GameCfg.Shop.Goods + 1] = {
        Number = row.number,
        ItemId = row.itemKey,
        Name = row.itemName,
        Desc = row.description,
        Price = row.price,
        Page = row.page,
        MinShopLevel = row.minShopLevel,
        PurchaseLimit = row.purchaseLimit,
        Upgrade = row.upgrade,
        source = row.source,
    }
end

-- 强化参数由商店表升级行派生（#130，GameSpec §6.2）：逐级一次、按基础线性叠加。
-- melee 7 级 +10%/级（满级 +70%）、ranged 5 级 +10%/级（+50%）、explosive 3 级 +20%/级（+60%）、
-- magazine 3 级 +50%/级向上取整（+150%）；backpack 6 级沿用 Items.UpgradePrices 同源价格。
-- 火箭筒直击与溅射都只归 ranged（不双加成），消费点在 server/Mgr/MgrWeapon.lua。
GameCfg.Shop.UpgradeKinds = {}
for _, row in ipairs(ContentShop.Goods) do
    local upgrade = row.upgrade
    if upgrade then
        local kind = GameCfg.Shop.UpgradeKinds[upgrade.kind]
        if not kind then
            kind = { Increment = upgrade.increment, MaxLevel = 0,
                RoundUp = upgrade.roundUp == true, Prices = {} }
            GameCfg.Shop.UpgradeKinds[upgrade.kind] = kind
        end
        kind.MaxLevel = math.max(kind.MaxLevel, upgrade.level)
        kind.Prices[upgrade.level] = row.price
    end
end

-- 某摊位某页的上架行：MinShopLevel <= level 且 Page 匹配；当地新品（MinShopLevel == level）置顶，
-- 同组按原表编号 Number 升序（排序键唯一，不依赖 table.sort 稳定性；GameSpec §7 新品置顶口径）。
-- includeLocked 时等级不够的行也返回（客户端灰显「锁定」用），排序口径不变。
function GameCfg.Shop.ListForPage(level, page, includeLocked)
    local rows = {}
    if type(level) ~= 'number' or type(page) ~= 'string' then return rows end
    for _, row in ipairs(GameCfg.Shop.Goods) do
        if row.Page == page and (includeLocked or row.MinShopLevel <= level) then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b)
        local aNew = a.MinShopLevel == level and 0 or 1
        local bNew = b.MinShopLevel == level and 0 or 1
        if aNew ~= bNew then return aNew < bNew end
        return a.Number < b.Number
    end)
    return rows
end

-- 伤害加成：1 + Increment × level，按基础线性叠加（非复利）；等级钳到 [0, MaxLevel]。
-- 弹容不是伤害加成（RoundUp 种类返回 nil，用 MagazineSize）。
function GameCfg.Shop.DamageScale(kind, level)
    local spec = GameCfg.Shop.UpgradeKinds[kind]
    if not spec or not spec.Increment or spec.RoundUp or type(level) ~= 'number' then return nil end
    level = math.max(0, math.min(spec.MaxLevel, math.floor(level)))
    return 1 + spec.Increment * level
end

-- 弹容 = ceil(base × (1 + 50% × level))：向上取整（商店表弹容升级行 roundUp 标记）。
function GameCfg.Shop.MagazineSize(base, level)
    local spec = GameCfg.Shop.UpgradeKinds.magazine
    if type(base) ~= 'number' or base ~= base or not spec then return nil end
    level = math.max(0, math.min(spec.MaxLevel, math.floor(level or 0)))
    return math.ceil(base * (1 + spec.Increment * level))
end

-- 完整商品、抽奖、盲盒表是内容基线；Shop.Goods 货架（#130 起）即商店表全量 50 行的规范化，
-- 抽奖/盲盒行为尚待 #138/#147 接入，不能把内容行当作当前可用。
GameCfg.Content = { Shop = ContentShop, Lottery = ContentLottery, Blindbox = ContentBlindbox }
-- 七区信物链按已确认 GameSpec §8.1；行为尚待 #127 实装。
GameCfg.Content.Exchanges = {
    { ZoneId = 'fishPond', EliteFish = 'eel', EliteToken = 'eelHead', BossBait = 'duck', BossFish = 'alligatorGar', BossToken = 'garHead', Result = 'shrimpTicket', source = 'GameSpec.md#8.1-鱼塘' },
    { ZoneId = 'shrimpPond', EliteFish = 'fish15Elite', EliteToken = 'item31', BossBait = 'item121', BossFish = 'fish16Boss', BossToken = 'item32', Result = 'item147', source = 'GameSpec.md#8.1-虾池' },
    { ZoneId = 'crabLake', EliteFish = 'fish23Elite', EliteToken = 'item47', BossBait = 'item122', BossFish = 'fish24Boss', BossToken = 'item48', Result = 'item148', source = 'GameSpec.md#8.1-蟹湖' },
    { ZoneId = 'forestIsland', EliteFish = 'fish31Elite', EliteToken = 'item63', BossBait = 'item123', BossFish = 'fish32Boss', BossToken = 'item64', Result = 'item149', source = 'GameSpec.md#8.1-树林岛' },
    { ZoneId = 'beachIsland', EliteFish = 'fish39Elite', EliteToken = 'item79', BossBait = 'item124', BossFish = 'fish40Boss', BossToken = 'item80', Result = 'item150', source = 'GameSpec.md#8.1-沙滩岛' },
    { ZoneId = 'reefIsland', EliteFish = 'fish47Elite', EliteToken = 'item95', BossBait = 'item125', BossFish = 'fish48Boss', BossToken = 'item96', Result = 'item151', source = 'GameSpec.md#8.1-礁石岛' },
    { ZoneId = 'volcanoIsland', EliteFish = 'fish55Elite', EliteToken = 'item111', BossBait = 'item126', BossFish = 'fish56Boss', BossToken = 'item112', Result = 'achievement.final', source = 'GameSpec.md#8.1-火山岛' },
}
-- #127 T06 回收价与最终成就（行为在 server/Mgr/MgrInteract.lua）。喂钓鱼佬即回收：
-- 鱼获的基础价随鱼种表走 FishCatch（含个体倍率），其余物品取物品表的 BasePrice；
-- 烤过的按烤熟价 = 基础价 × 倍率 × 1.5（GameSpec §4.3）。烤制标记落在存档格位的
-- saved.cooked（PlayerData 序列化原样保留格位的未知字段，不额外占位）。
GameCfg.Items.CookedFlag = 'cooked'
GameCfg.Items.CookedPriceScale = 1.5
-- 烤制倍率统一读取（#137）：取出倍率是 (0, 1.5] 的数值——内存格位/快照在 entry.cooked，
-- 读档还原在 entry.saved.k；#127 之前的旧布尔标记 saved.cooked==true 等价烤熟价倍率。
-- 返回数值倍率，没烤过或数值非法（0/负数/NaN/Inf）返回 nil。
function GameCfg.Items.CookRate(entry)
    if type(entry) ~= 'table' then return nil end
    local rate = entry.cooked
    if type(rate) ~= 'number' and type(entry.saved) == 'table' then
        rate = entry.saved.k
        if type(rate) ~= 'number' and entry.saved[GameCfg.Items.CookedFlag] == true then
            rate = GameCfg.Items.CookedPriceScale
        end
    end
    if type(rate) ~= 'number' or rate <= 0 or rate ~= rate or rate >= math.huge then return nil end
    return rate
end
-- 物品表没有的物品返回 nil（不可回收，属配置事故；调用方按「没得喂」处理）。
-- cooked 可以是数值倍率（#137 烧烤取出）、布尔 true（旧标记，按烤熟价倍率）或 nil/false（未烤）。
function GameCfg.Items.SalePrice(itemId, mult, cooked)
    local rate = cooked == true and GameCfg.Items.CookedPriceScale
        or type(cooked) == 'number' and cooked or nil
    local species = type(itemId) == 'string' and GameCfg.Fish[itemId]
    if species then
        return rate and FishCatch.CookedPrice(species, mult, rate) or FishCatch.Price(species, mult)
    end
    local definition = type(itemId) == 'string' and GameCfg.Items.Definitions[itemId]
    local base = definition and definition.BasePrice
    if type(base) ~= 'number' then return nil end
    local factor = type(mult) == 'number' and mult or 1
    return math.floor(base * factor * (rate or 1) + 1e-9)
end

-- 最终成就（#127 第七区，GameSpec §8.1「哥斯拉头 → 通关成就」）：兑换产物是 'achievement.<id>'
-- 时写进 Extra.achievements[<id>]（不占道具格，重进照旧保留），这里只给客户端提示用的名字。
GameCfg.Achievements = {
    final = { Name = '通关成就' },
}
GameCfg.Shop.Catalog = ContentShop.Goods
GameCfg.Shop.Excluded = ContentShop.Excluded
GameCfg.Lottery = ContentLottery
-- 抽奖机运行参数（#138 T17，GameSpec §14 与策划案抽奖段）：内容表（七图案/权重/倍数/大奖）
-- 在 common/cfg/Lottery.lua；这里是行为参数。投注为投入物的实际回收价值
-- （GameCfg.Items.SalePrice 未烤口径）；结果服务端先定并持久化，动画只是表现：
-- 滚动 SpinSec 秒后按 AxisOrder 顺序每隔 AxisStopIntervalSec 停一轴。
GameCfg.Lottery.Radius = 5
GameCfg.Lottery.Slack = 0.5
GameCfg.Lottery.BubbleHeight = 7
GameCfg.Lottery.BubblePreset = GameCfg.Shop.BubblePreset -- 复用商店文字泡预设，换提示文案
GameCfg.Lottery.HintText = '极品食物换大奖'
GameCfg.Lottery.RuleHintText = '抽奖规则'
GameCfg.Lottery.ActionCooldownSec = 1
GameCfg.Lottery.SpinSec = 3
GameCfg.Lottery.AxisStopIntervalSec = 0.5
GameCfg.Lottery.AxisOrder = { 'left', 'right', 'middle' } -- 停轴顺序，客户端 UpdateAnim 消费
-- 回包超时兜底：服务端限频（CheckRECD）与存档 pending 窗口都静默丢弃请求不回包，
-- 客户端 Awaiting 闩锁超过该时长自动解锁并提示，避免界面永久卡死（#138 审查）
GameCfg.Lottery.ResultTimeoutSec = 5
-- 每区一台抽奖机：锚点名复用 #125 场景合同的 Lottery 实体（Z1_Lottery … Z7_Lottery）；
-- 现场未建的区取不到单位时交互自然拒绝（范围校验找不到锚点），不伪造可用性。
function GameCfg.Lottery.MachineAnchors()
    local names = {}
    for _, zone in ipairs(GameCfg.Zones) do
        if zone.Scene and zone.Scene.LotteryName then names[#names + 1] = zone.Scene.LotteryName end
    end
    return names
end
GameCfg.Blindbox = ContentBlindbox
-- 盲盒行为参数（#147 T26，GameSpec §15）：抽样与保底纯逻辑在 common/BlindboxDraw.lua；
-- 收费走平台适配层（GameCfg.Platform.Goods 的 blindboxSingle/blindboxTen 行），结果服务端先定并持久化；
-- 满格落地经 MgrLoot:SpawnItem 计入全区 200 件预算，购买前由客户端按库存快照明确告知。
GameCfg.Blindbox.ActionCooldownSec = 1
GameCfg.Blindbox.ResultTimeoutSec = 65 -- 含平台支付等待（FlowTimeoutSec 60）+ 落账余量
GameCfg.Blindbox.HintText = '盲盒'
GameCfg.Blindbox.FullNoticeText = '道具栏和背包已满：抽中的物品将落在面前地上，其他玩家可拾取'
GameCfg.Blindbox.UnavailableText = '盲盒暂未开放，请稍后再试'

-- #147 T26 平台功能本地接缝（GameSpec §7/§11/§15，docs/技术难点识别.md §4）：
-- 真实商品 ID（goodsId）、金币汇率与广告标签是商业化后台交付参数（#148），未交付即平台能力
-- 明确不可用，此时不发任何付费权益；官方无订单 ID、购买无取消/失败事件（教程明令禁止
-- 拼 UserId+goodsId 防重），本地接缝只做 pending flow 关联与超时兜底，跨会话防重、补发与
-- 对账接口归 #148 真实平台验收。
GameCfg.Platform = {
    BeanCurrency = '金豆',
    -- 广告/支付等待上限：真实平台无取消/失败事件，超时是唯一兜底（本地参数，真实超时未查证）
    FlowTimeoutSec = 60,
    ActionCooldownSec = 1,
    -- 金豆价目（GameSpec §11 肾上腺素 1/4 金豆与满血复活 5 金豆、§15 盲盒 10/90 金豆）；
    -- goodsId 缺省 nil = 后台未交付。count 是购买成功后的发货件数（仅肾上腺素类占格商品用）。
    Goods = {
        blindboxSingle = { beans = 10, name = '盲盒单抽' },
        blindboxTen = { beans = 90, name = '盲盒十连' },
        reviveFull = { beans = 5, name = '满血复活' },
        adrenaline1 = { beans = 1, count = 1, name = '肾上腺素', itemId = GameCfg.Survival.AdrenalineItemId },
        adrenaline5 = { beans = 4, count = 5, name = '肾上腺素×5', itemId = GameCfg.Survival.AdrenalineItemId },
    },
    -- 激励广告：广告看完发放商品奖励（ShowRewardedVideoAd 的 goodsId 语义），goodsId/adTag 未交付
    Ads = {
        revive = { name = '广告满血复活' },
    },
    UnavailableText = '平台功能暂不可用，请稍后再试',
}

-- 摆渡（#89 定细则，#127 T06 扩到七区六航线）：去程一人在船边交 1 张船票，倒计时 CountdownSec 秒后
-- 带走 BoatRange 米内（只看 x/z）所有玩家到本航线目的区落点，无票同行者搭便船合法；倒计时中再交票拒绝且不扣。
-- 返程按人付 Price 金币、立即传送回出发区。票、价、锚点、落点、区域名全部由航线（Ferry.Routes，见下）
-- 提供；区域名写入 PlayerData.Data.Zone（#92 存档用），HomeZone 是开局区域。
-- 具体的 Outbound / Return 两条腿在 PlannedRoutes 之后由航线派生（#127 前只有第一段是既有现场）。
GameCfg.Ferry = {
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
            -- #134 鱼塘极品六条（钓鱼表 R8–R13）：权重 2/2/2/8/6/4，罗非鱼行任意饵保底
            { Id = 'item7', Bait = 0, RodLevel = 1, DrawWeight = 2 },
            { Id = 'item8', Bait = 'worm', RodLevel = 1, DrawWeight = 2 },
            { Id = 'item9', Bait = 'worm', RodLevel = 1, DrawWeight = 2 },
            { Id = 'item10', Bait = 'worm', RodLevel = 1, DrawWeight = 8 },
            { Id = 'item11', Bait = 'worm', RodLevel = 1, DrawWeight = 6 },
            { Id = 'item12', Bait = 'worm', RodLevel = 1, DrawWeight = 4 },
        },
        -- 虾池（#90，钓鱼表第二区）：虾米任意饵保底；沼虾/小龙虾起用香肠；波龙及以上竿级 2。
        -- 极品权重另列（普通 8/8/8/32/24/16，极品 2/2/2/8/6/4）
        ShrimpPool = {
            { Id = 'shrimp', Bait = 0, RodLevel = 1, DrawWeight = 8 },
            { Id = 'riverShrimp', Bait = 'sausage', RodLevel = 1, DrawWeight = 8 },
            { Id = 'crayfish', Bait = 'sausage', RodLevel = 1, DrawWeight = 8 },
            { Id = 'bostonLobster', Bait = 'sausage', RodLevel = 2, DrawWeight = 32 },
            { Id = 'aussieLobster', Bait = 'sausage', RodLevel = 2, DrawWeight = 24 },
            { Id = 'milkLobster', Bait = 'sausage', RodLevel = 2, DrawWeight = 16 },
            { Id = 'rareShrimp', Bait = 0, RodLevel = 1, DrawWeight = 2 },
            { Id = 'rareRiverShrimp', Bait = 'sausage', RodLevel = 1, DrawWeight = 2 },
            { Id = 'rareCrayfish', Bait = 'sausage', RodLevel = 1, DrawWeight = 2 },
            { Id = 'rareBostonLobster', Bait = 'sausage', RodLevel = 2, DrawWeight = 8 },
            { Id = 'rareAussieLobster', Bait = 'sausage', RodLevel = 2, DrawWeight = 6 },
            { Id = 'rareMilkLobster', Bait = 'sausage', RodLevel = 2, DrawWeight = 4 },
            { Id = 'fish15Elite', Bait = 'sausage', RodLevel = 2, DrawWeight = 10 },
        },
        -- 蟹湖（#136，钓鱼表 R30–R42）：蟛蜞任意饵保底；寄居蟹起用鲱鱼罐头；梭子蟹起竿级 3（捕蟹竿）。
        -- 极品权重 2/2/2/8/6/4；帝王蟹入池权重 10。蟹老板由首领饵 item122 必出（BossBait），不入池。
        ['crabLake.water'] = {
            { Id = 'item33', Bait = 0, RodLevel = 1, DrawWeight = 8 },
            { Id = 'item34', Bait = 'item115', RodLevel = 1, DrawWeight = 8 },
            { Id = 'item35', Bait = 'item115', RodLevel = 1, DrawWeight = 8 },
            { Id = 'item36', Bait = 'item115', RodLevel = 3, DrawWeight = 32 },
            { Id = 'item37', Bait = 'item115', RodLevel = 3, DrawWeight = 24 },
            { Id = 'item38', Bait = 'item115', RodLevel = 3, DrawWeight = 16 },
            { Id = 'item39', Bait = 0, RodLevel = 1, DrawWeight = 2 },
            { Id = 'item40', Bait = 'item115', RodLevel = 1, DrawWeight = 2 },
            { Id = 'item41', Bait = 'item115', RodLevel = 1, DrawWeight = 2 },
            { Id = 'item42', Bait = 'item115', RodLevel = 3, DrawWeight = 8 },
            { Id = 'item43', Bait = 'item115', RodLevel = 3, DrawWeight = 6 },
            { Id = 'item44', Bait = 'item115', RodLevel = 3, DrawWeight = 4 },
            { Id = 'fish23Elite', Bait = 'item115', RodLevel = 3, DrawWeight = 10 },
        },
    },
    -- 首领饵（#88，GameSpec §12 已确认）：首领饵物品 id → 必出首领鱼种。挂首领饵在任意水区抛竿
    -- 必出对应首领，无视抽签权重、鱼饵-鱼种匹配与竿级；首领饵占道具栏/背包格、不进 Bait 计数，
    -- 抛竿一刻从道具栏（优先）或背包扣 1 只，钓出首领后消耗，脱钩 / 逃脱不返还。
    BossBait = { duck = 'alligatorGar', item121 = 'fish16Boss', item122 = 'fish24Boss' },
}

-- 源表抽鱼行按钓鱼区分组；水域/钓鱼区映射见下文 Water.ZoneIdByWater。
-- BossBait 启用鱼塘鸭子、虾池夜明珠与蟹湖绿色钞票；其余首领饵待后续区域内容可运行时再启用。
local sourceCastRows = {}
local bossBaitCatalog = {}
for _, species in pairs(GameCfg.Fish) do
    if species.Grade == 'boss' then
        bossBaitCatalog[species.Bait] = species.Id
    else
        local rows = sourceCastRows[species.ZoneId] or {}
        rows[#rows + 1] = { Id = species.Id, Bait = species.Bait,
            RodLevel = species.RodLevel, DrawWeight = species.DrawWeight, source = species.source }
        sourceCastRows[species.ZoneId] = rows
    end
end
for _, rows in pairs(sourceCastRows) do
    table.sort(rows, function(a, b)
        return tonumber(a.source:match('R(%d+)$')) < tonumber(b.source:match('R(%d+)$'))
    end)
end
GameCfg.Casting.Catalog = sourceCastRows
GameCfg.Casting.BossBaitCatalog = bossBaitCatalog

-- 首领近战（#88 占位，#134 头部攻击）：Combat='gar' 的鱼上岸放下后 Kinematic 追目标（仇恨 / 最近），
-- 移速取鱼种 Speed，伤害取鱼种 Attack，逃跑时限取鱼种 EscapeSec（耗尽走精英直线逃脱）。
-- 头部攻击：目标进入 BiteRange 即锁定朝向起咬（预警），BiteCooldownSec 后结算；只咬「头部区」——
-- 以鱼身中点为圆心 BiteRange 内、与锁定朝向夹角 < HeadHalfAngleDeg。正侧面与后半圆是后身，绕后即咬空。
-- 数值来源：追咬 30 / 间隔 1.5 秒来自钓鱼表与正文（GameSpec §12）；BiteRange 沿用 #88 占位；
-- HeadHalfAngleDeg=90 是把原表「头有伤害，后身是弱点」按鱼身中点切成前后两半的配置细化（GameSpec §12
-- 允许的预警 / 判定细化，非原表数值），待试玩调；「后身是弱点」原表没有受伤倍率，这里不加伤害加成。
-- ModelYawOffset：模型头部相对 yaw=0 的偏角（弧度）[未查证]，试玩看头朝向再校。
-- Warning：7190 为红色方向箭头与环形波纹预警（manual 特效目录），提示锁定朝向与范围；
-- 不表达精确半圆边界。EffectLength=10 与朝向偏角 [未查证]，须在试玩中核对并校准。
GameCfg.FishCombat = {
    -- #135 已确认：每2秒一击，双击后尾刺；活动15秒后眩晕5秒。
    shrimp = { BiteRange = 2.5, BiteCooldownSec = 2, HeadHalfAngleDeg = 90,
        ActiveSec = 15, StunSec = 5, ClawDamage = 20, TailDamage = 20, KnockHorizontal = 3, KnockUp = 1 },
    -- 每30秒都执行雨云6秒，再飞起俯冲；期间禁止啄击，落地眩晕5秒。
    dragon = { BiteRange = 2.5, BiteCooldownSec = 1.5, HeadHalfAngleDeg = 90,
        SpecialSec = 30, RainSec = 6, RainRadius = 10, RainDamage = 50, PeckDamage = 50,
        RainEffect = 'official://preset/1850', -- 官方暴雨 baoyu_v01，当前实例已核实
        DiveSec = 2, DiveHeight = 6, DiveRadius = 2.5, DiveDamage = 50, StunSec = 5 },
    gar = { BiteRange = 2.5, BiteCooldownSec = 1.5, HeadHalfAngleDeg = 90, ModelYawOffset = 0,
        Warning = { EffectPreset = 'official://preset/7190', EffectLength = 10, GroundOffset = 0.1,
            EffectYawOffset = 0, GraceSec = 0.5 } },
    -- #136 帝王蟹（GameSpec §12 正文与钓鱼表 R42）：每 5 秒对前方蟹钳乱刺，左右各 3 下、
    -- 每下间隔 0.2 秒、每下 15 伤害；每活动 30 秒眩晕 5 秒。乱刺一轮总时长
    -- JabStepSec × JabsPerSide × 2 = 1.2 秒；同一刺段只结算一次（不按帧重复）。
    kingCrab = { BiteRange = 2.5, HeadHalfAngleDeg = 90,
        JabIntervalSec = 5, JabsPerSide = 3, JabStepSec = 0.2, JabDamage = 15,
        ActiveSec = 30, StunSec = 5 },
    -- #136 蟹老板（GameSpec §12 正文与钓鱼表 R43）：正面蟹钳双击、每击 20、冷却 4 秒；
    -- 每 30 秒冲撞一次（冲向目标、命中 20、冲撞窗口 1.2 秒）；每 25 秒旋转 5 秒、
    -- 每秒 360 度、碰触伤害 30（同一秒槽同一玩家只结算一次）。三招互斥：旋转与冲撞
    -- 期间不双击；逃跑 / 移除打断进行中的招式。
    crabBoss = { BiteRange = 2.5, HeadHalfAngleDeg = 90,
        PinchDamage = 20, PinchCooldownSec = 4, PinchStrikes = 2, PinchStepSec = 0.2,
        ChargeSec = 30, ChargeDamage = 20, ChargeWindowSec = 1.2, ChargeRange = 2.5,
        SpinSec = 25, SpinDurationSec = 5, SpinDamage = 30, SpinRadius = 3 },
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
    -- #134 电鳗正式行为（GameSpec §12、策划案已确认结论）：5 米内每秒放电一次、每次 10，
    -- 连续 DischargeCount 次（持续 DischargeCount × DischargeIntervalSec = 5 秒），之后睡眠 10 秒可受击。
    -- 每次放电 = 一次技能施法（复用挥砍预设，CastSec 是单次施法窗口，须小于放电间隔，否则下一次会被 InCast 拒绝）；
    -- 乱甩角度、侧躺角度为可调表现参数。逃跑时限取鱼种 EscapeSec（180 秒）。
    FishAbilities = {
        eel = {
            AssetId = "map://preset/ucc31d1999a543a7ab329eff1fd3c00d",
            Index = 0,
            Anchor = "map://preset/u471a1004c1f43f1ae6ebe4ee2bcd080",
            AnchorBehavior = "eel_discharge",
            Radius = 5,
            Damage = 10,
            DischargeCount = 5,
            DischargeIntervalSec = 1,
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
            -- 技能实例覆盖：CD 归零（间隔由 MgrWeapon 的 IntervalSec 权威控制）；施法时长须 ≥ Duration 且 < 最小 IntervalSec 0.5
            CdSec = 0,
            CastSec = 0.3,
            AnchorAttributes = {
                -- 命中盒存活窗口；必须 ≤ 施法窗口（CastSec）
                Duration = 0.3,
                ABILITY_ANOSTATE_HITBOX_OFFSET = { x = 0, y = 1, z = 2 }, -- 面前 2 米
                ABILITY_ANOSTATE_HITBOX_SCALE = { x = 3, y = 2, z = 3 },
                ABILITY_ANOSTATE_BULLET_DAMAGE = 25.0,
                ABILITY_ANOSTATE_HITPOWER = 0.0, -- 验证期不击退，便于观察扣血
            },
        },
    },
    -- T08 武器系统（#129）：伤害/射速/弹匣/投掷数值集中在此，与商店表（common/cfg/Shop.lua
    -- 武器页 R16—R27）逐行对应；票面参数（射程、换弹、爆炸半径、保底鱼）来自 #129 任务说明。
    -- 暂取值（原表未给，待策划确认）：火箭筒 IntervalSec、GunShared.Range、Throw.FlightSec /
    -- FishTtlSec / LongPressSec / ArcHeight。
    Unarmed = { Damage = 5, IntervalSec = 0.5, Range = 2 }, -- 票面：空手 5 伤害 / 0.5 秒 / 2 米
    MeleeWeapons = {
        item134 = { Damage = 10, IntervalSec = 0.5, Range = 2 },  -- 指虎 商店表!R27
        item135 = { Damage = 15, IntervalSec = 0.5, Range = 3 },  -- 匕首 商店表!R26
        item136 = { Damage = 40, IntervalSec = 1.0, Range = 4 },  -- 斧头 商店表!R25
        -- #139 抽奖武器大奖（统一规格 §6.3）：匕首组 Range 暂取 3 对齐商店匕首，
        -- 斧组 Range 暂取 4 对齐商店斧头（原表未给近战射程，待策划确认）。
        item152 = { Damage = 15, IntervalSec = 0.5, Range = 3,    -- 淬毒匕首（毒 1/s/3s/5 层）
                    Effect = { Kind = 'poison' } },
        item153 = { Damage = 18, IntervalSec = 0.5, Range = 3 },  -- 秘银匕首
        item154 = { Damage = 18, IntervalSec = 0.5, Range = 3 },  -- 黄金匕首
        item155 = { Damage = 18, IntervalSec = 0.5, Range = 3 },  -- 黑曜石匕首
        item156 = { Damage = 18, IntervalSec = 0.5, Range = 3 },  -- 锯齿匕首
        item157 = { Damage = 52, IntervalSec = 1.0, Range = 4 },  -- 银斧
        item158 = { Damage = 52, IntervalSec = 1.0, Range = 4 },  -- 金斧
        item159 = { Damage = 40, IntervalSec = 1.0, Range = 4,    -- 炽焰战斧（灼烧 4/s/3s/5 层）
                    Effect = { Kind = 'burn' } },
        item160 = { Damage = 60, IntervalSec = 1.0, Range = 4 },  -- 血吼
        item161 = { Damage = 68, IntervalSec = 1.0, Range = 4 },  -- 无坚不摧之力
    },
    -- 枪械公共：手动/自动换弹均 2 秒（票面）；备弹无限、弹匣有限；射程暂取 30 米
    GunShared = { ReloadSec = 2, Range = 30, ActionCooldownSec = 0.1 },
    Guns = {
        item137 = { Damage = 10, IntervalSec = 1.0, Magazine = 10 },              -- 手枪 商店表!R24
        item138 = { Damage = 20, Pellets = 5, IntervalSec = 1.5, Magazine = 2 },  -- 霰弹枪 商店表!R23
        item139 = { Damage = 13, IntervalSec = 0.15, Magazine = 30, Auto = true }, -- 冲锋枪 商店表!R22
        item140 = { Damage = 20, IntervalSec = 0.2, Magazine = 30, Auto = true }, -- 自动步枪 商店表!R21
        item141 = { Damage = 200, IntervalSec = 1.5, Magazine = 5 },              -- 狙击枪 商店表!R20
        item142 = { Damage = 500, IntervalSec = 2.0, Magazine = 1,               -- 火箭筒 商店表!R19（射速暂取 2 秒）
                    Splash = { Damage = 100, Radius = 5 } },                      -- 周围 5 米 100（票面/原表一致）
        -- #139 抽奖武器大奖（统一规格 §6.3）
        item162 = { Damage = 15, IntervalSec = 1.0, Magazine = 15 },              -- 沙漠之鹰
        item163 = { Damage = 10, IntervalSec = 1.0, Magazine = 10,                -- 霜之新星（霜冻 -30%/3s 不叠加）
                    Effect = { Kind = 'frost' } },
        item164 = { Damage = 10, IntervalSec = 1.0, Magazine = 10,                -- 雷霆之力（麻痹 0.5s 不叠加）
                    Effect = { Kind = 'paralyze' } },
        item165 = { Damage = 30, IntervalSec = 0.2, Magazine = 30, Auto = true }, -- 黄金AK47
        item166 = { Damage = 500, IntervalSec = 1.0, Magazine = 10, Auto = true,               -- 连发火箭筒（溅射 5m/100）
                    Splash = { Damage = 100, Radius = 5 } },
    },
    -- #139 持续效果钉表（统一规格 §6.3）：毒/灼烧每秒一跳、最多 5 层、持续 3 秒，
    -- 重复命中叠层并刷新持续；霜冻/麻痹不叠加，重复命中只刷新持续。
    -- DOT 每跳都重新走 T07/#128 统一伤害入口（MgrVitals:NewHit('dot') + ApplyHit）。
    StatusEffects = {
        poison = { MaxStacks = 5, TickSec = 1, DamagePerStack = 1, DurationSec = 3 },
        burn = { MaxStacks = 5, TickSec = 1, DamagePerStack = 4, DurationSec = 3 },
        frost = { SlowPercent = 30, DurationSec = 3, Stackable = false },
        paralyze = { DurationSec = 0.5, Stackable = false },
    },
    -- #139 加速药水（item167，统一规格 §2）：每个 +10% 基础移速，最多 20 个，封顶基础 3 倍；
    -- 上限须与 GameCfg.Items.PotionLimits.item167 同值（钉表测试强制对账）。
    -- 移速唯一计算口见 common/AttrGrowth.lua 与 MgrAbility:RefreshMoveSpeed：
    -- 最终移速 = 基础 × (1 + 10%×药水数) × 虚弱 0.5 × 霜冻 0.7（麻痹为 0），不在不同管理器反复乘。
    SpeedPotion = { Item = 'item167', StepPercent = 10, MaxPotions = 20, MaxFactor = 3 },
    -- 角色基础移速：BaseController 默认 WalkSpeed 7.0（editor-cli manual BaseController.mdx 已核实）；
    -- 运行时以角色入图时捕获的控制器速度为准（MgrAbility:CaptureBaseSpeed），此值仅为兜底。
    MoveSpeed = { Base = 7 },
    Explosives = {
        item143 = { Damage = 50 },   -- 鞭炮 商店表!R18
        item144 = { Damage = 100 },  -- 手雷 商店表!R17
        item145 = { Damage = 150 },  -- 炸药 商店表!R16
    },
    Throw = {
        Range = 20,          -- 直接投掷 20 米（票面）
        ExplosionRadius = 5, -- 5 米爆炸（票面）
        FishMin = 3, FishMax = 5, -- 水中保底当地鱼（票面）
        FishRodLevel = 1,    -- 保底鱼只要当地 1 级（票面，按钓表 RodLevel + Grade='normal' 过滤）
        FishTtlSec = 60,     -- 保底鱼存活时间（暂取）
        FlightSec = 0.8,     -- 投掷飞行时间（暂取）
        ArcHeight = 3,       -- 飞行弧线高度（暂取，表现参数）
        LongPressSec = 0.35, -- 长按进入选点（暂取，UI 参数）
    },
    -- T11（#132）高风险能力原型：三倍体型 / 飞行 / 巡航叼人 / 分阶段首领的数值与契约集中在此，
    -- 纯逻辑见 common/BodyScale.lua、common/FlightPath.lua、common/CarryMount.lua、common/BossPhase.lua。
    -- 原型只证明逻辑一致性与接缝可调用；真机行为（碰撞、相机、挂点是否穿模）仍须编辑器窗口试玩。
    -- 标「暂取」的值在试玩前无实测依据，不是策划案数值。
    BodyScale = {
        -- GameSpec §2：体型 1 倍起，变大药水每个 +0.2 倍，上限 3 倍（最多 10 个）；
        -- 血量上限 300 起、每个 +20%（=60），上限 900。
        Base = 1, Step = 0.2, Max = 3, MaxPotions = 10,
        HealthBase = 300, HealthStepPercent = 20, HealthMax = 900,
        -- 1 倍体型下的基准量：胶囊高 2 米（与 MgrVitals.characterHeight 读到的角色 Height 同口径）、
        -- 相机距离 6 米、交互距离 2 米（同 GameCfg.Loot.PickupRadius，GameSpec §8.3「2 米内显示拾取」）。
        -- 本单只把派生量发布到角色属性（MgrAbility.ApplyBodyScale），**没有**改
        -- MgrLoot/LocalLoot 的 PickupRadius 判定与 MgrInteract 的 Fisherman.Radius（5 米）——
        -- 「三倍角色能拾取/钓鱼/摆渡」是否成立必须在编辑器窗口实测。
        CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2,
        -- 消费口：变大药水（common/cfg/Items.lua item168「吃掉增加体型和血量，最多吃 10 个」）
        PotionItem = 'item168',
    },
    Flight = {
        -- GameSpec §12：白头鹰 飞行移速 20 / 每 20 秒俯冲 / 基础攻击 30；风神翼龙 移速 20 /
        -- 每 4 秒投掷（5 米落地范围）/ 每 20 秒追踪俯冲（正文 100 / 260，表只给通用 35）；
        -- 沧龙 移速 13 / 每 15 秒跃起砸击 / 绕岛咬最近岛中心玩家并叼走入海。
        -- 高度上限取 #125 场景合同的 Boundary.MaxFlightHeight = 20（票面「20 米飞行」）。
        MaxHeight = 20, MaxStepSec = 0.25, DriftTolerance = 4,
        Speed = 20,          -- 巡航移速（GameSpec §12：白头鹰 / 风神翼龙 移速 20；也是漂移判定的基准）
        CruiseHeight = 12,   -- 巡航高度（暂取）
        DiveSpeed = 30,      -- 俯冲速度（暂取）
        ClimbSpeed = 8,      -- 爬升速度（暂取）
        DiveSec = 3,         -- 单次俯冲的最长持续时间（暂取）
        DiveIntervalSec = 20,-- 俯冲间隔兜底（GameSpec §12：每 20 秒俯冲一次）
        DiveDamage = 30,     -- 俯冲伤害兜底（表内白头鹰基础攻击 30）
        LeapHeight = 8,      -- 沧龙跃起高度（暂取）
        LeapSec = 1.5,       -- 沧龙跃起滞空时间（暂取）
        AggroRange = 60,     -- 飞行时的索敌半径（暂取）
        DiveRadius = 5,      -- 俯冲砸击的命中半径（暂取）
        -- 按鱼种 Id 的飞行档案；Bounds 由鱼所在钓鱼区的 Scene.Boundary 提供，缺省用下面的 FallbackBounds。
        Species = {
            fish47Elite = { CruiseHeight = 12, DiveIntervalSec = 20, DiveDamage = 30 },
            fish48Boss = { CruiseHeight = 15, DiveIntervalSec = 20, DiveDamage = 260,
                ThrowIntervalSec = 4, ThrowRadius = 5, ThrowDamage = 100 },
            fish55Elite = { Mode = 'leap', CruiseHeight = 0, DiveIntervalSec = 15, DiveDamage = 100 },
        },
        -- 场景合同缺失时的兜底边界（以鱼塘的中心为原点，见 GameCfg.Zones[1].Scene.Boundary）
        FallbackBounds = { MinX = -60, MaxX = 60, MinZ = -50, MaxZ = 70, BottomY = -30, TopY = 40,
            MaxFlightHeight = 20 },
    },
    Carry = {
        -- 巡航叼人（沧龙「咬最近岛中心玩家、叼走入海」，GameSpec §12）：咬中 300、过程接触 150。
        Socket = 'LiftSocket',                -- 与顶鱼挂点同名（MgrFishUnit.LiftSocket）
        -- 1 倍体型下的嘴部挂点位移：中心距 2.56 ≥ 宿主半高 1.2 + 玩家半高 1.0，整体在宿主体外
        -- （「挂点不穿出」的判定见 common/CarryMount.lua，取值为暂取，真机是否穿模待试玩）。
        Offset = { x = 0, y = 1.6, z = 2.0 },
        HostHalfHeight = 1.2,                 -- 宿主（沧龙）半高（暂取）
        CarriedHalfHeight = 1.0,              -- 携带物（玩家 2 米胶囊）半高，与 MgrVitals 的角色高同口径
        GrabRange = 2.5,                      -- 咬中判定距离（水平，暂取）
        GrabDamage = 300,                     -- 咬中伤害（正文）
        FollowTolerance = 3,                  -- 携带跟随容差（米）：超出即整段钳回挂点
        DropHeight = 1.5, DropForward = 2,    -- 释放落点（暂取）
        MaxCarrySec = 20,                     -- 单次叼走的最长携带时间（暂取）
        ContactIntervalSec = 1, ContactDamage = 150, -- 叼走过程的接触伤害节奏与数值（伤害取自正文 150）
        FallDamage = 0,                       -- 落地额外伤害（正文未给，先 0）
    },
    BossPhase = {
        -- 哥斯拉（fish56Boss，GameSpec §12）：低于 60% 入水、切沧龙式攻击（咬中 1000）；
        -- 低于 20% 重新上岸、伤害 +50%、原子吐息改为每 10 秒。阈值优先于普通招式循环。
        -- 阈值按百分比降序排列（= 阶段升级顺序）；一帧跨两个阈值只进最终合法阶段，
        -- 中间被跳过的阶段记进 Skipped（见 common/BossPhase.lua）。
        Thresholds = {
            { Percent = 60, Phase = 'water', BiteDamage = 1000 },
            { Percent = 20, Phase = 'enraged', DamageBonusPercent = 50, BreathIntervalSec = 10 },
        },
        -- 各阶段的招式集合；同一帧多个招式到期时按 Attacks 的书写顺序取唯一一个，保证确定性。
        AttackSets = {
            normal = { 'claw', 'tail', 'breath' },
            water = { 'bite' },
            enraged = { 'claw', 'tail', 'breath' },
        },
        Attacks = {
            claw = { IntervalSec = 2, Damage = 50 },   -- 表内 2 秒爪击（基础攻击 50）
            tail = { IntervalSec = 6, Damage = 50 },   -- 表内每 6 秒甩尾
            breath = { IntervalSec = 30, Range = 10, OneShot = true, WindupSec = 1.5 }, -- 正前 10 米秒杀
            bite = { IntervalSec = 2 },                -- 入水后的咬击：伤害取阶段条目的 BiteDamage
        },
        -- 走阶段机的鱼种（键为 GameCfg.Fish 的 Id）。本单只登记哥斯拉；
        -- 正式接入由 #144 决定是加 Combat 标签还是建「首领」注册表（本单不改 common/cfg/Fish.lua）。
        Species = { fish56Boss = true },
        -- 阶段首领的追击口径（与 #88 的 GameCfg.FishCombat 同字段；此处不依赖鱼的 Combat 标签）
        Chase = { BiteRange = 4, BiteCooldownSec = 2 },
    },
    -- T19（#140）特殊道具：风神之翼（item169，物品表!R170「使用时可以飞行」）与
    -- 哥斯拉变身（item170，物品表!R171「更换皮肤，可以使用原子吐息」）。
    -- 两者都是 GameSpec §3.2 两步规则的例外：选中即生效（翅膀背负 / 变身），再按道具键
    -- 触发主动行为（长按飞行 / 原子吐息）。纯逻辑见 common/SpecialItem.lua，
    -- 装配见 server/Mgr/MgrSpecialItem.lua。标「暂取」的值票面未给，真机表现待试玩。
    SpecialItem = {
        -- 选中槽物品 → 生效效果（Desired 的唯一数据源）
        Items = { item169 = 'wings', item170 = 'godzilla' },
        ReLimitSec = 0.1, -- SpecialItemAction 通道限频（暂取，与 WeaponAction 同口径）
        Wings = {
            -- 长按升空 / 松开缓降（票面）；高度上限与跨区围栏取场景合同
            -- （FlightPath.BoundsOf：CeilingY = GroundY + Boundary.MaxFlightHeight = 20）。
            ClimbSpeed = 8,      -- 上升速度（暂取：与 #132 鱼飞行 ClimbSpeed 同口径，票面未给）
            DescendSpeed = 3,    -- 松开缓降速度（暂取）
            MaxStepSec = 0.25,   -- 单帧步长上限（与 Ability.Flight 同口径，防一帧跨过围栏）
            -- 缓降落地判定：角色实际 y 高出上一帧写入值超过此量，视为被地形托住（暂取）
            LandEpsilon = 0.05,
            -- 背负翅膀的外观件：编辑器资源预设待补（官方资源库查询 / AIGC，[未查证]）；
            -- 空值时只开飞行能力、不改外观。
            AppearanceAssetId = nil,
            Socket = 'Spine',    -- Enums.SkeletalSocketType 的键，调用时解析为 socket_body（本地/在线 API 已核对）
            Offset = { x = 0, y = 0, z = 0 },
        },
        Godzilla = {
            -- 变身皮肤资源：官方模型库无哥斯拉（docs/技术难点识别.md §7），
            -- 待 AIGC / 编辑器预设（[未查证]）；空值时变身不改外观，其余行为照常。
            -- 变身体型：票面未要求变大，本单不改体型——三倍体型药水叠加由 BodyScale 独立管理。
            AppearanceAssetId = nil,
            Breath = {
                -- 原子吐息：3 秒直线 30 米、每个目标总计 1000、冷却 20 秒（issue #140 票面）。
                -- 与首领哥斯拉 BossPhase.Attacks.breath（正前 10 米 OneShot 秒杀）严格区分，
                -- 两处配置互不读取。
                DurationSec = 3, Range = 30, TotalDamage = 1000,
                TickSec = 0.25,        -- 结算节奏（暂取：3 秒 / 0.25 秒 = 12 段）
                Width = 3,             -- 光束走廊半宽（暂取）
                CooldownSec = 20,      -- 冷却（票面）
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
        -- 虾池水面（#90）：第二钓鱼区占位平台（星光地板，已扩到 x 90..110 / z 91..109，顶面 y=5.0）
        -- 东北角水区，抛竿落点命中后按 Casting.Zones.ShrimpPool 选鱼。SurfaceY 取水面单位
        -- （深水预设，pos.y=4.2，顶面约 5.2~5.35 批次漂移；取高点再加鱼获落地余量，与既有水区同口径）
        { Id = "ShrimpPool", Center = { x = 105, y = 4.2, z = 106 }, HalfXZ = 3.0, SurfaceY = 5.6 },
        -- 蟹湖水面（#136）：第三区北侧水区，场景合同 Z3_Water 实测中心 (260,2,144)、
        -- 80×24 米矩形（HalfX=40/HalfZ=12，MathWaterJudge 长方形口径）。SurfaceY 沿用场景合同
        -- 值 3（水面单位 pos.y=2、顶面约 3）；与其他水区相距数百米，无重叠。
        { Id = "crabLake.water", Center = { x = 260, y = 2, z = 144 }, HalfX = 40, HalfZ = 12, SurfaceY = 3 },
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

-- 仅列已在编辑器配置过并可实际抛竿的水域；新五区水域留给 #125 场景实施。
GameCfg.Water.ZoneIdByWater = {
    WaterCircle1 = 'fishPond', WaterCircle2 = 'fishPond', ShrimpPool = 'shrimpPond',
    ['crabLake.water'] = 'crabLake',
}
for _, zone in ipairs(GameCfg.Water.Zones) do
    if not GameCfg.Water.ZoneIdByWater[zone.Id] then
        GameCfg.Water.ZoneIdByWater[zone.Id] = zone.ZoneId or 'fishPond'
    end
    zone.ZoneId = GameCfg.Water.ZoneIdByWater[zone.Id]
end
GameCfg.Water.ContentWaterIds = {}
for _, zone in ipairs(GameCfg.Zones) do
    GameCfg.Water.ContentWaterIds[zone.WaterId] = zone.Id
end

-- #125 七区场景合同。所有新增坐标/名字是待建计划，绝非现场存在性证据。
-- 2026-09-29 只读盘点：已有鱼塘/虾池，后五区未建；编辑器有归属未明的未存改动，禁止自动启用。
-- Scene 与 PlannedRoutes 不接入 Water.Zones、Shop.Stands、BaitSpots.Spots 或当前摆渡消费者。
-- 创建、碰撞/落点实测、保存、sync 全通过后才可单独接入；State 不能由名称匹配自动提升。
local sceneCenters = {
    { x = 0, z = 40 }, { x = 100, z = 100 }, { x = 260, z = 100 },
    { x = 460, z = 100 }, { x = 660, z = 100 }, { x = 880, z = 100 },
    { x = 1160, z = 100 },
}
local existingScene = {
    { LandName = '大地板', FishermanName = 'TGUnitFish', ShopName = 'TGUnitShop',
      Land = { MinX = 0, MaxX = 18, MinZ = 25, MaxZ = 55 },
      SafePoint = { x = 6.26, y = 5.01, z = 39.29 },
      LandPosition = { x = -13.75, y = 0, z = 40.75 },
      FishermanPosition = { x = -6.25, y = -1, z = 30.75 },
      ShopPosition = { x = -8.75, y = 2.5, z = 55.25 } },
    { LandName = '星光地板', FishermanName = 'TGUnitFishShrimp', ShopName = 'TGUnitShopShrimp',
      Land = { MinX = 90, MaxX = 110, MinZ = 91, MaxZ = 109 },
      SafePoint = { x = 100, y = 6, z = 100 },
      LandPosition = { x = 100, y = -3, z = 100 },
      FishermanPosition = { x = 94, y = -4, z = 100 },
      ShopPosition = { x = 106, y = -0.5, z = 97 } },
}
for index, zone in ipairs(GameCfg.Zones) do
    local center, old = sceneCenters[index], existingScene[index]
    local prefix = 'Z' .. index .. '_'
    local scene = {
        State = 'planned', Entities = {}, Waters = {},
        SafePoint = old and old.SafePoint or { x = center.x, y = 6, z = center.z },
        Land = old and old.Land or { MinX = center.x - 40, MaxX = center.x + 40,
            MinZ = center.z - 30, MaxZ = center.z + 30 },
        Boundary = { MinX = center.x - (index == 2 and 25 or 60), MaxX = center.x + (index == 2 and 25 or 60),
            MinZ = center.z - 50, MaxZ = center.z + 70, BottomY = -30, TopY = 40,
            MaxFlightHeight = 20, CanClimb = false },
        BaitSpots = { ItemId = zone.BaitItemId, RespawnSec = 15, Count = 1, Positions = {} },
    }
    zone.Scene = scene
    local function entity(role, position, name, observed)
        name = name or prefix .. role
        scene.Entities[#scene.Entities + 1] = {
            Name = name, Role = role, Position = position,
            State = observed and 'observed' or 'planned',
        }
        return name
    end
    scene.LandName = entity('Land', old and old.LandPosition or { x = center.x, y = 0, z = center.z },
        old and old.LandName, old ~= nil)
    scene.SafePointName = entity('Safe', scene.SafePoint)
    scene.FishermanName = entity('Fisherman', old and old.FishermanPosition
        or { x = center.x - 20, y = 5, z = center.z }, old and old.FishermanName, old ~= nil)
    scene.ShopName = entity('Shop', old and old.ShopPosition
        or { x = center.x + 20, y = 5, z = center.z }, old and old.ShopName, old ~= nil)
    scene.LotteryName = entity('Lottery', { x = center.x + 5, y = 5, z = center.z + 5 })
    if index >= 3 then
        scene.GrillName = entity('Grill', { x = center.x - 10, y = 5, z = center.z - 10 })
    end
    if index <= 2 then
        for _, water in ipairs(GameCfg.Water.Zones) do
            if water.ZoneId == zone.Id then scene.Waters[#scene.Waters + 1] = water end
        end
        if index == 1 then
            entity('Water', { x = -11.75, y = 1.05, z = 27.75 }, 'WaterCircle2', true)
        else
            -- ShrimpPool 是既有数学水域 ID，尚未核实它的现场水面实体名。
            entity('Water', { x = 105, y = 4.2, z = 106 })
        end
    else
        local water = { Id = zone.WaterId, ZoneId = zone.Id,
            Center = { x = center.x, y = 2, z = center.z + 44 },
            HalfX = 40, HalfZ = 12, SurfaceY = 3 }
        scene.Waters[1] = water
        water.EntityName = entity('Water', water.Center)
    end
    local b = scene.Boundary
    b.EntityNames = {
        entity('BoundaryWest', { x = b.MinX, y = b.BottomY, z = center.z + 10 }),
        entity('BoundaryEast', { x = b.MaxX, y = b.BottomY, z = center.z + 10 }),
        entity('BoundarySouth', { x = center.x, y = b.BottomY, z = b.MinZ }),
        entity('BoundaryNorth', { x = center.x, y = b.BottomY, z = b.MaxZ }),
    }
    if index == 1 then
        for _, spot in ipairs(GameCfg.BaitSpots.Spots) do
            scene.BaitSpots.Positions[#scene.BaitSpots.Positions + 1] = spot.Position
        end
    else
        scene.BaitSpots.Positions = {
            { x = center.x - 3, y = 6, z = center.z - 3 },
            { x = center.x + 3, y = 6, z = center.z - 3 },
        }
    end
    for n, point in ipairs(scene.BaitSpots.Positions) do entity('Bait' .. n, point) end
    if index == 6 then
        scene.AirCombat = { MinY = 5, MaxY = 30, Radius = 35, Center = center }
    elseif index == 7 then
        scene.CruiseWater = scene.Waters[1]
        scene.BossArena = { Center = center, HalfX = 30, HalfZ = 25 }
    end
end
GameCfg.Ferry.PlannedRoutes = {}
local plannedReturnPrices = { 10, 30, 90, 270, 810, 2430 }
for index = 1, 6 do
    local from, to = GameCfg.Zones[index], GameCfg.Zones[index + 1]
    local outName = index == 1 and 'FerryBoat' or ('Z' .. index .. '_FerryOut')
    local returnName = index == 1 and 'FerryReturn' or ('Z' .. (index + 1) .. '_FerryReturn')
    local function ferryEntity(zone, name, position, observed)
        zone.Scene.Entities[#zone.Scene.Entities + 1] = {
            Name = name, Role = 'Ferry', Position = position,
            State = observed and 'observed' or 'planned',
        }
    end
    ferryEntity(from, outName, index == 1 and { x = -8, y = 1.5, z = 25 }
        or { x = sceneCenters[index].x + 15, y = 5, z = sceneCenters[index].z - 10 }, index == 1)
    ferryEntity(to, returnName, index == 1 and { x = 100, y = 5, z = 103 }
        or { x = sceneCenters[index + 1].x - 15, y = 5, z = sceneCenters[index + 1].z - 10 }, index == 1)
    GameCfg.Ferry.PlannedRoutes[index] = {
        State = 'planned', FromZoneId = from.Id, ToZoneId = to.Id,
        Outbound = { AnchorName = outName, Ticket = GameCfg.Content.Exchanges[index].Result,
            CountdownSec = 5, Destination = to.Scene.SafePoint },
        Return = { AnchorName = returnName, Price = plannedReturnPrices[index], Destination = from.Scene.SafePoint },
    }
end

-- #127 T06 六条航线（路线图 §8.2）：一条航线 = 一段去程（第 i 区 → 第 i+1 区）+ 一段返程（第 i+1 区 → 第 i 区），
-- 去程与返程各有**独立标识与独立状态**，不同航线互不占用倒计时。Id 是服务端唯一的航线凭证：
-- 请求里带 Id 才能拿到这条航线的 NPC 锚点、目的地、船票（去程）与票价（返程），查不到就拒收。
-- 票与价都随本区链推进：去程票 = 本区首领信物的产物（Content.Exchanges[i].Result，#126），
-- 返程价 = 10 × 3^(到达区序 − 2)，即 10 / 30 / 90 / 270 / 810 / 2430。
-- 腿的公共几何（BoatRange / Radius / Slack / BubbleHeight）与 #89 保持一致，逐条航线可单独覆盖。
GameCfg.Ferry.Routes = {}
local ferryLegGeometry = { BoatRange = 6, Radius = 5, Slack = 0.5, BubbleHeight = 6 }
for index = 1, 6 do
    local planned = GameCfg.Ferry.PlannedRoutes[index]
    local from, to = GameCfg.Zones[index], GameCfg.Zones[index + 1]
    local outbound, back = {}, {}
    for key, value in pairs(ferryLegGeometry) do outbound[key], back[key] = value, value end
    for key, value in pairs(planned.Outbound) do outbound[key] = value end
    for key, value in pairs(planned.Return) do back[key] = value end
    outbound.Zone = to.Id      -- 到达区（去程落点写进 Data.Zone）
    back.Zone = from.Id        -- 返程回出发区
    GameCfg.Ferry.Routes[index] = {
        Id = from.Id .. '>' .. to.Id,
        FromZoneId = from.Id,
        ToZoneId = to.Id,
        Outbound = outbound,
        Return = back,
    }
end

-- 第一段（鱼塘 ⇄ 虾池）是既有现场（#89 已实装）：这两个别名让老消费者与老用例不必认识 Routes。
GameCfg.Ferry.HomeZone = GameCfg.Zones[1].Id
GameCfg.Ferry.Outbound = GameCfg.Ferry.Routes[1].Outbound
GameCfg.Ferry.Return = GameCfg.Ferry.Routes[1].Return

-- 航线 id 校验（#127）：只有登记在 Routes 里的字符串 id 才算数，伪造成别的区号或数字一律查不到。
function GameCfg.Ferry.Route(routeId)
    if type(routeId) ~= 'string' then return nil end
    for _, route in ipairs(GameCfg.Ferry.Routes) do
        if route.Id == routeId then return route end
    end
end

-- #127 T06 七区兑换：每区一个钓鱼佬，锚点取本区场景合同（Zones[].Scene.FishermanName，#125 的真源），
-- 兑换链取本区信物链（Content.Exchanges）。共享表现参数与鱼饵价留在 Interact.Fisherman，
-- 消费端（server/Mgr/MgrInteract.lua）把两者合成一个完整交互点，避免把共享参数抄七份。
GameCfg.Interact.Fishermen = {}
for index, chain in ipairs(GameCfg.Content.Exchanges) do
    local zone = GameCfg.Zones[index]
    GameCfg.Interact.Fishermen[index] = {
        ZoneId = zone.Id,
        AnchorNames = { zone.Scene.FishermanName },
        -- 未烤信物 1:1：精英信物 → 本区首领饵，首领信物 → 本区产物（第七区是 achievement.final）
        Exchange = { [chain.EliteToken] = chain.BossBait, [chain.BossToken] = chain.Result },
        Chain = index,
    }
end

-- 烧烤（#137 T16，策划案烧烤段）：第三区起每区一个烧烤点（#125 场景合同 Zones[].Scene.GrillName），
-- 2 米内可操作；服务端从投入计时按 common/GrillCurve.lua 的曲线 1→1.5→0，4.5 秒烤糊损毁并
-- 对烤炉周围 3 米玩家造成 30 伤害（经 MgrVitals 统一伤害入口）。按玩家独立会话，取出时价格与
-- 食用恢复同乘当时倍率；烤过物品不可重烤/抽奖，烤过信物失去兑换资格（操作信物前先提示）。
GameCfg.Grill = {
    Radius = 2,                 -- docx：2 米内出现「烧烤」操作文字泡
    Slack = 0.5,                -- 距离复验宽限（对齐 Interact 惯例）
    BubbleHeight = 2.5,         -- 文字泡悬浮高度
    RiseSec = 2,                -- 0-2 秒：1 → 1.5
    HoldSec = 0.5,              -- 2-2.5 秒：保持 1.5
    FallSec = 2,                -- 2.5-4.5 秒：1.5 → 0
    MaxRate = 1.5,              -- 烤熟 1.5 倍价格加成、食用恢复 +50%
    BurnSec = 4.5,              -- = RiseSec + HoldSec + FallSec；到达即烤糊
    BurnDamage = 30,            -- docx：烤糊爆炸 30 伤害
    BurnRadius = 3,             -- docx：周围 3 米
    BubbleText = '烧烤',
    NoFishText = '你没有可烤的鱼',
    BurntText = '你的鱼烤糊了！',
    CookedPrefix = '烤',         -- 烤好的鱼名字加此前缀（CONTEXT.md 烤鱼条 Avoid「烤过的鱼」，用「烤」构成菜名式称呼）
    TokenWarnText = '信物烤制后将失去兑换和抽奖资格，再次点击确认烤制',
    FullText = '背包已满，烤好的鱼先留在烤炉上',
    TakeoutText = '取出',
    source = '策划案--渔力全开.docx#烧烤',
}
-- 烧烤点清单：锚点是 #125 场景合同真源（仅三区起有 GrillName），消费端按距离命中
GameCfg.Grill.Points = {}
for index, zone in ipairs(GameCfg.Zones) do
    if zone.Scene.GrillName then
        GameCfg.Grill.Points[#GameCfg.Grill.Points + 1] = {
            ZoneId = zone.Id, AnchorName = zone.Scene.GrillName,
        }
    end
end

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

GameCfg.DamageFloat = {
    DurationSec = 1,
    RisePixels = 90,
    SpreadPixels = 32,
    HeadHeight = 1.6,
    Width = 130,
    Height = 70,
    NormalFontSize = 36,
    CriticalFontSize = 48,
    NormalColor = { 255, 255, 255, 255 },
    CriticalColor = { 255, 185, 45, 255 },
    PoolSize = 24,
}

-- #134 精英鱼头顶状态字（client/FishCombatLabel.lua）：服务端 FishCombatState 广播的逃跑时限条
-- （电鳗 180 秒、鳄雀鳝 300 秒共用），电鳗另显放电次数与睡眠倒计时。
GameCfg.FishCombatLabel = {
    MovingRefreshSec = 0.5, -- 会移动的精英（鳄雀鳝）坐标补发间隔
    HeadHeight = 2.4,
    Width = 640,
    Height = 90,
    FontSize = 30,
    BarCells = 10,
    AttackColor = { 255, 230, 60, 255 },
    SleepColor = { 140, 200, 255, 255 },
    IdleColor = { 255, 255, 255, 255 },
}

return GameCfg
