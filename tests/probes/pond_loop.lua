-- #134 验收切片 D：鱼塘新档正常闭环探针（离线模拟，只证明逻辑，不当真机验收）。
-- 运行：在仓库根执行 `lua tests/probes/pond_loop.lua`；退出码 0 = 全部通过。
-- 链路：关闭 Debug 的新档 → 免费拾饵 → 喂钓鱼佬卖饵 → 买新手鱼竿 → 钓鱼 / 打死 / 拾取 / 卖鱼（普通与极品都卖）
--       → 攒够 50 金买匕首（未够钱先钓出电鳗：放下走开的安全失败，电鳗到时限回水、无损失，继续钓）
--       → 持匕首打电鳗（5 次放电后睡 10 秒）→ 电鳗头换鸭子 → 挂鸭子钓鳄雀鳝 → 绕后咬空 → 打死（重复死亡只结算一次）
--       → 鳄雀鳝头换虾池船票。不用 GM、不跳关、不付费、不指定中大奖；最后用 1000 个种子估算买匕首前是否存在经济阻塞。
--
-- 失败模式（先列后写）：
--   1. 新档不是 Debug=false 的正常档（开局就有竿 / 金币 / 武器），或闭环借 GM、直接加金币才走通；
--   2. 拾饵、卖饵、卖鱼的金币与配置价不符（鱼按 floor(基础价 × 倍率)），攒不够 5 金买竿或买竿不扣钱；
--   3. 抛竿不扣饵、挂鸭子不必出鳄雀鳝、没挂饵也能钓到要饵的鱼；
--   4. 电鳗一轮放电不是 5 次、间隔不是 1 秒、放完不睡或睡眠不足 10 秒、睡眠中仍放电；
--   5. 鳄雀鳝不锁定朝向：玩家绕到身后仍被咬（绕后无效），或正前方头部区反而不咬；
--   6. 载体死亡事件重复到达时重复掉落 / 重复发信物（TakeKilled 不幂等）；
--   7. 电鳗头不换鸭子、鳄雀鳝头不换船票，兑换多给金币或丢失信物以外的库存；
--   8. 个人最大重量不随更重的一条刷新；极品（item7～item12、信物头）资格判断错，烤过的仍可投抽奖机；
--   9. 模拟时间线失控（金币为负、耗时为负或远超逃跑时限），经济 K 值无法复算；
--  10. 没匕首时钓出电鳗无法安全放弃：放下后仍占住抛竿、走开仍挨电、不按时限逃脱、逃脱扣金币 / 库存；
--  11. 攒匕首钱存在经济阻塞（某些自然抽样下永远攒不够），或跳过匕首直接空手挑战电鳗（没验证武器成长）。
--
-- 模拟边界（逐条标注在输出里）：
--   * 业务模块用真实代码：MgrSave / MgrPlayerData / MgrInteract / MgrShop / MgrQuest（经济与兑换）、
--     MgrLoot:Give / OnCarrierDied（拾取发放与掉落）、MgrFishUnit（电鳗 / 鳄雀鳝战斗状态机）、
--     FishCatch（抽鱼与倍率）、LotteryEligibility（极品资格）。
--   * 引擎边界是假的：场景锚点、物理射线、技能施放（CastFish 只计数）、玩家命中（按武器间隔扣载体血量）。
--   * 抽鱼与倍率用「确定性 RNG」（固定种子 LCG，替换 FishCatch 的 random 参数），不直接指定鱼种或倍率。
--   * 走位 / 收线 / 上岸动作的耗时是估算常数（见 SIM），不是实测；卖鱼往返不单独计时。
--   * 安全失败时电鳗的逃脱位移由探针按 LinearVelocity × dt 积分（假引擎无物理），回水判定走真实 MgrFishUnit。
--   * 第 10 节多种子经济估算只用配置 + FishCatch（不走管理器），与主链同一套规则，结果标 [估算]。
package.path = table.concat({ './?.lua', './?/init.lua', './tests/lib/?.lua', package.path }, ';')

local Pass, Fail = 0, 0
local function check(name, ok, detail)
    if ok then
        Pass = Pass + 1
        print('[PASS] ' .. name)
    else
        Fail = Fail + 1
        print('[FAIL] ' .. name .. (detail and ('  -- ' .. tostring(detail)) or ''))
    end
end
local function quantity(label, value) print(string.format('K %s = %s', label, tostring(value))) end
local Timeline = {}
local Clock = 0
local function event(text)
    Timeline[#Timeline + 1] = string.format('t=%7.1fs %s', Clock, text)
end

local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')

-- 估算常数（模拟耗时，不是实测）
local SIM = {
    BaitTripSec = 30,        -- 绕 5 个蚯蚓点一圈
    FishermanWalkSec = 8,    -- 钓位 ↔ 钓鱼佬
    ShopWalkSec = 15,        -- 钓位 ↔ 商店
    ReelSec = 3,             -- 连点收线到 100%
    RetreatSec = 5,          -- 没匕首时放下电鳗后走开
    Seed = 134,
}

-- 确定性 RNG：固定种子 LCG；与 math.random(m) / math.random(m, n) 同签名
local function makeRng(seed)
    local state = seed
    return function(m, n)
        state = (state * 1103515245 + 12345) % 2147483648
        local r = state / 2147483648
        if n then return m + math.floor(r * (n - m + 1)) end
        return 1 + math.floor(r * m)
    end
end
local rng = makeRng(SIM.Seed)

-- ===== 经济环境（照 economy_persistence_test 的引擎边界）=====
local ENV = { values = {}, queue = {}, events = {} }
local oldDebug = GameCfg.Debug
GameCfg.Debug = { Enabled = false }
local store = {
    GetAsync = function(_, key) return ENV.values[key] end,
    UpdateAsync = function(_, key, transform)
        local value = transform(ENV.values[key])
        if value then ENV.values[key] = value end
        return value
    end,
    SetAsync = function(_, key, value) ENV.values[key] = value end,
}
local anchor = { Position = { x = 0, y = 0, z = 0 }, PlayAnimation = function() end }
local function signal()
    return { Connect = function() return { Disconnect = function() end } end }
end
local economyGame = { GetService = function(_, name)
    if name == 'Task' then return { Spawn = function(_, fn) ENV.queue[#ENV.queue + 1] = fn end, Wait = function() end } end
    if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
    if name == 'World' then return { GetServerTime = function() return 100 + Clock end,
        FindFirstChild = function() return anchor end } end
    if name == 'Players' then return { GetPlayers = function() return { ENV.player } end } end
end }
_G.game = economyGame
local function fire(name, player, value) ENV.events[#ENV.events + 1] = { name = name, player = player, value = value } end
_G.REUtil = { GetRE = function(_, name) return {
    FireClient = function(_, player, value) fire(name, player, value) end,
    FireAllClients = function(_, value) fire(name, nil, value) end,
} end }
local function drain() while #ENV.queue > 0 do table.remove(ENV.queue, 1)() end end
local function lastResult(name)
    for i = #ENV.events, 1, -1 do
        if ENV.events[i].name == name then return ENV.events[i].value end
    end
end

local save = assert(loadfile('server/Mgr/MgrSave.lua'))()
local players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
local interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
local shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
local quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
players.Save, save.PlayerData = save, players
interact.PlayerData, interact.Save, interact.Quest = players, save, quest
shop.PlayerData, shop.Save, shop.Quest, shop.Interact = players, save, quest, interact

-- 掉落与拾取发放：真实 MgrLoot（载体模块换成空桩，Spawn 由 OnCarrierDied 调用时记录掉落）
local savedCarrier = package.loaded['server.Mgr.MgrFishCarrier']
package.loaded['server.Mgr.MgrFishCarrier'] = { SubscribeDied = function() end, Despawn = function() end }
local loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
package.loaded['server.Mgr.MgrFishCarrier'] = savedCarrier

local player = { UserId = 13401, Character = { Position = { x = 0, y = 0, z = 0 } },
    CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
ENV.player = player
players:OnPlayerAdded(player)
quest:OnPlayerAdded(player)
drain()
local data = players:GetDataInst(player)

-- ===== 1. 新档检查 =====
local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar
check('新档：Debug 关闭', GameCfg.Debug.Enabled == false)
check('新档：金币 0、无鱼竿、无武器、无鱼饵',
    (data.Data.FishCoin or 0) == 0 and data:ItemCount('starterRod') == 0
    and data:WeaponCount('item135') == 0 and (data.Data.Bait.worm or 0) == 0,
    string.format('coin=%s rod=%d dagger=%d worm=%s', tostring(data.Data.FishCoin), data:ItemCount('starterRod'),
        data:WeaponCount('item135'), tostring(data.Data.Bait.worm)))
save:SaveExplicit(player.UserId, data, function() end)
drain()

local Seq = 0
local function nextSeq() Seq = Seq + 1 return Seq end
local function slotOf(itemId)
    local items = data.Data.Containers[ITEM_BAR]
    for slot = 1, data:ItemBarCapacity() do
        local entry = items[slot]
        if entry and entry.count > 0 and entry.itemId == itemId then return slot, entry end
    end
end
-- 道具栏满时信物落进背包：走与 ItemBarAction{action='MoveSlot'} 相同的 data:MoveSlot 挪回道具栏
local BACKPACK = GameCfg.Items.ContainerId.Backpack
local function ensureBar(itemId)
    local slot = slotOf(itemId)
    if slot then return slot end
    local pack = data.Data.Containers[BACKPACK] or {}
    local index
    for i = 1, data:BackpackCapacity() do
        if pack[i] and pack[i].count > 0 and pack[i].itemId == itemId then index = i break end
    end
    if not index then return nil end
    local bar = data.Data.Containers[ITEM_BAR]
    local target
    for s = 1, data:ItemBarCapacity() do if not bar[s] then target = s break end end
    if not target then
        for s = 1, data:ItemBarCapacity() do
            if bar[s].itemId ~= 'starterRod' then target = s break end
        end
    end
    if target and data:MoveSlot(BACKPACK, index, ITEM_BAR, target) then return slotOf(itemId) end
end
local Stats = { coinsEarned = 0, coinsSpent = 0, baitPicked = 0, casts = 0, catches = {}, kills = 0,
    maxWeight = 0, maxWeightFish = nil, premium = 0, premiumKept = nil, baitTrips = 0,
    fishSold = 0, fishCoins = 0, safeFails = 0, daggerAt = nil, castsToDagger = nil }

local function feedSelected(what)
    local before = data.Data.FishCoin or 0
    interact:Handle(player, { target = 'fisherman', action = 'Feed', seq = nextSeq() })
    drain()
    local result = lastResult('InteractResult') or {}
    local gained = (data.Data.FishCoin or 0) - before
    if gained > 0 then Stats.coinsEarned = Stats.coinsEarned + gained end
    return result, gained
end
local function buy(itemId)
    local before = data.Data.FishCoin or 0
    shop:Handle(player, { action = 'Buy', itemId = itemId, seq = nextSeq() })
    drain()
    local spent = before - (data.Data.FishCoin or 0)
    if spent > 0 then Stats.coinsSpent = Stats.coinsSpent + spent end
    return spent
end

-- 免费拾饵：一趟 5 个点位各 1 只；点位刷新 RespawnSec 秒（拾取发放走 MgrLoot:Give，距离复验由 fish_loot_test 覆盖）
local SpotReadyAt = 0
local function baitTrip()
    if Clock < SpotReadyAt then Clock = SpotReadyAt end
    Clock = Clock + SIM.BaitTripSec
    local picked = 0
    for _ = 1, #GameCfg.BaitSpots.Spots do
        if loot:Give(data, 'worm', nil, nil, 1) then picked = picked + 1 end
    end
    Stats.baitPicked = Stats.baitPicked + picked
    Stats.baitTrips = Stats.baitTrips + 1
    SpotReadyAt = Clock + GameCfg.BaitSpots.RespawnSec
    return picked
end

-- ===== 2. 拾饵 → 卖饵 → 买竿 =====
local picked = baitTrip()
event(string.format('拾饵 %d 只（免费点位）', picked))
check('免费拾饵：一趟拾到点位数量的蚯蚓', picked == #GameCfg.BaitSpots.Spots and data.Data.Bait.worm == picked,
    'picked=' .. picked)
data:SelectBait('worm')
Clock = Clock + SIM.FishermanWalkSec
local wormPrice = GameCfg.Interact.Fisherman.BaitPrice.worm
local rodPrice
for _, row in ipairs(GameCfg.Shop.Catalog) do if row.itemKey == 'starterRod' then rodPrice = row.price end end
local sold = 0
while (data.Data.FishCoin or 0) < rodPrice and (data.Data.Bait.worm or 0) > 0 do
    local _, gained = feedSelected('worm')
    if gained ~= wormPrice then break end
    sold = sold + 1
end
event(string.format('喂钓鱼佬卖饵 %d 只，金币 %d', sold, data.Data.FishCoin or 0))
check('卖饵按 BaitPrice 结算并攒够鱼竿钱', (data.Data.FishCoin or 0) >= rodPrice,
    string.format('coin=%s rodPrice=%s', tostring(data.Data.FishCoin), tostring(rodPrice)))
Clock = Clock + SIM.ShopWalkSec
local spent = buy('starterRod')
event(string.format('买新手鱼竿 -%d 金', spent))
check('买竿扣 ' .. tostring(rodPrice) .. ' 金并入库', spent == rodPrice and data:ItemCount('starterRod') == 1,
    string.format('spent=%d rod=%d', spent, data:ItemCount('starterRod')))

-- ===== 战斗环境：真实 MgrFishUnit（复用 fish_lift / fish_escape 测试的假引擎）=====
require('tests.gameplay.fish_escape_test')
local function combatEnv()
    local env = setmetatable({}, { __index = TestFishEscape })
    TestFishEscape.setUp(env)
    TestFishEscape.prepare(env)
    env.notices, env.casts, env.hits, env.published = {}, {}, {}, {}
    local maxHealth = GameCfg.Vitals.MaxHealth or 300
    for _, p in ipairs({ env.player, env.other }) do
        p.Character.Controller.Health = maxHealth
        p.Character.Controller.TakeDamage = function(c, d) c.Health = c.Health - d end
    end
    env.other.Character.Position = Vector3.New(500, 2, 500) -- 另一名玩家远离，不参与本局
    env.mgr.PublishBite = function(_, payload) env.notices[#env.notices + 1] = payload end
    env.mgr.CombatPublisher = function(payload) env.published[#env.published + 1] = payload end
    env.mgr.Ability = {
        EquipFish = function() return true end,
        -- 技能施放只计数；5 米内的玩家记一次模拟命中（伤害取配置）
        CastFish = function(_, fish)
            env.casts[#env.casts + 1] = env.now
            local eel = GameCfg.Ability.FishAbilities.eel
            local p, q = fish.Carrier.Body.Position, env.player.Character.Position
            local dx, dz = p.x - q.x, p.z - q.z
            if dx * dx + dz * dz <= eel.Radius * eel.Radius then
                env.hits[#env.hits + 1] = { source = 'eel', amount = eel.Damage or GameCfg.Fish.eel.Attack }
            end
            return true
        end,
        RemoveFish = function() end,
    }
    env.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, _, _, amount)
            env.hits[#env.hits + 1] = { source = 'gar', amount = amount }
            return true, amount
        end,
        CanTakeDamage = function() return true end,
    }
    return env
end
local function closeEnv(env)
    TestFishEscape.tearDown(env)
    _G.game = economyGame
end
local function weapon()
    if data:WeaponCount('item135') > 0 then return 'item135', GameCfg.Ability.MeleeWeapons.item135 end
    return 'unarmed', GameCfg.Ability.Unarmed
end

-- 打死并结算：命中由模拟判定（每 IntervalSec 一击）；载体死亡事件投递两次验证防重；掉落经 MgrLoot 结算
local function killAndLoot(env, fish, onTick)
    local species = GameCfg.Fish[fish.FishId]
    local _, w = weapon()
    local health = species.Health
    local start = env.now
    while health > 0 do
        env.now = env.now + w.IntervalSec
        if onTick then onTick(env, fish) end
        env.mgr:Update()
        if env.mgr.Fish[fish.Id] ~= fish then return nil, env.now - start end
        health = health - w.Damage
    end
    local drops = {}
    loot.FishUnit = env.mgr
    loot.Spawn = function(_, fishId, mult, _, itemId)
        drops[#drops + 1] = { fishId = fishId, itemId = itemId or fishId, mult = mult }
    end
    loot:OnCarrierDied(fish.Carrier)
    local first = #drops
    loot:OnCarrierDied(fish.Carrier) -- 重复死亡事件
    loot.Spawn = nil
    loot.FishUnit = nil
    Stats.kills = Stats.kills + 1
    return drops, env.now - start, first
end

local function pickupAll(drops)
    local ok = true
    for _, d in ipairs(drops) do ok = loot:Give(data, d.itemId, d.mult, nil, 1) and ok end
    return ok
end

local function noteCatch(fishId, mult)
    local species = GameCfg.Fish[fishId]
    Stats.catches[fishId] = (Stats.catches[fishId] or 0) + 1
    if species.BaseWeight then
        local weight = FishCatch.Weight(species, mult)
        if weight > Stats.maxWeight then Stats.maxWeight, Stats.maxWeightFish = weight, fishId end
    end
end

-- 一次合法抛竿：扣饵 → 等咬钩 → 收线 → 上岸；选鱼走 FishCatch + 确定性 RNG（首领饵走 BossBait）
local function castOnce()
    local slot = ensureBar('duck')
    local fishId
    if slot then
        -- 首领饵：抛竿一刻从道具栏扣 1 只（等价于 MgrCast 扣首领饵；背包里的先按 MoveSlot 挪回道具栏）
        data:UpdateData(function(d) d.Containers[ITEM_BAR][slot] = nil end, true)
        fishId = GameCfg.Casting.BossBait.duck
    else
        local baitId = (data.Data.Bait.worm or 0) > 0 and 'worm' or nil
        data:SelectBait(baitId)
        local ok = data:ConsumeSelectedBait()
        if not ok then return nil end
        fishId = FishCatch.Select(GameCfg.Casting.Zones.WaterCircle2, 1, baitId or 0, rng)
    end
    Stats.casts = Stats.casts + 1
    Clock = Clock + GameCfg.Casting.HookDelaySec + SIM.ReelSec + GameCfg.Casting.LandedHoldSec
    return fishId, FishCatch.Multiplier(rng)
end

-- 普通鱼 / 极品：上岸 → 放下 → 打死 → 拾取 → 喂钓鱼佬卖掉（攒匕首钱）；
-- 第一条极品卖前先对真实库存格验抽奖资格（复制一份格位留给第 8 节的烤过对照）
local function handleNormal(fishId, mult)
    local species = GameCfg.Fish[fishId]
    local _, w = weapon()
    Clock = Clock + math.ceil(species.Health / w.Damage) * w.IntervalSec
    Stats.kills = Stats.kills + 1
    loot:Give(data, fishId, mult, nil, 1)
    local slot, entry = ensureBar(fishId)
    if slot then entry = select(2, slotOf(fishId)) end
    local premium = GameCfg.Items.Definitions[fishId] and GameCfg.Items.Definitions[fishId].Type == '极品食物'
    if premium then
        Stats.premium = Stats.premium + 1
        if not Stats.premiumKept and entry then
            local copy = {}
            for k, v in pairs(entry) do copy[k] = v end
            local okElig, Eligibility = pcall(require, 'common.LotteryEligibility')
            Stats.premiumKept = { itemId = fishId, entry = copy,
                eligibleInBar = okElig and (Eligibility.Check(entry) == true) or nil }
            event(string.format('钓到极品 %s x%.2f（先验抽奖资格，再卖掉攒钱）', fishId, mult))
        end
    end
    if slot and data:SelectSlot(slot) then
        local _, gained = feedSelected(fishId)
        Stats.fishSold = Stats.fishSold + 1
        Stats.fishCoins = Stats.fishCoins + gained
        if gained ~= FishCatch.Price(species, mult) then Stats.priceMismatch = (Stats.priceMismatch or 0) + 1 end
    end
end

local function fishUntil(stop, limit)
    local guard = 0
    while not stop() and guard < limit do
        guard = guard + 1
        if (data.Data.Bait.worm or 0) == 0 and not slotOf('duck') then
            local got = baitTrip()
            event(string.format('补饵 %d 只', got))
        end
        local fishId, mult = castOnce()
        if fishId then
            noteCatch(fishId, mult)
            if GameCfg.Fish[fishId].Combat then return fishId, mult end
            handleNormal(fishId, mult)
        end
    end
end

-- 安全失败：没匕首时钓出电鳗 → 放下后退出放电半径，不打；逃跑时限到后电鳗自行回水消失。
-- 验证：放下后立即可再抛竿、退到半径外不挨电、到时限转逃脱、回水后移除、无掉落、金币与库存不变（免费失败恢复）。
-- 引擎边界：载体位移由探针按 LinearVelocity × dt 积分（假引擎没有物理）。
local function safeFailEel(mult)
    local env = combatEnv()
    local fish = env.mgr:SpawnLanded(env.player, { fishId = 'eel', mult = mult or 1.5 },
        env.player.Character.Position + Vector3.New(0, 0, 2))
    fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
    env.mgr:Drop(env.player)
    local canCast = env.mgr:CanCast(env.player)
    local cfgEel = GameCfg.Ability.FishAbilities.eel
    local fp = fish.Carrier.Body.Position
    env.player.Character.Position = Vector3.New(fp.x + cfgEel.Radius + 3, fp.y, fp.z) -- 退出放电半径
    local coin, heads, meats, worms = data.Data.FishCoin, data:ItemCount('eelHead'), data:ItemCount('eelMeat'),
        data.Data.Bait.worm or 0
    local start, dt = env.now, 0.5
    local fleeAt = fish.FleeAt
    local escapedAt, goneAt
    while env.now - start < GameCfg.Fish.eel.EscapeSec + 300 do
        env.now = env.now + dt
        local body = fish.Carrier.Body
        local v = body.LinearVelocity
        if fish.State == 'escaping' and v then
            body.Position = Vector3.New(body.Position.x + v.x * dt, body.Position.y, body.Position.z + v.z * dt)
        end
        env.mgr:Update()
        if not escapedAt and fish.State == 'escaping' then escapedAt = env.now end
        if env.mgr.Fish[fish.Id] ~= fish then goneAt = env.now break end
    end
    closeEnv(env)
    Stats.safeFails = Stats.safeFails + 1
    local tag = '安全失败 #' .. Stats.safeFails
    check(tag .. '：放下电鳗后立即可再抛竿（不被占住）', canCast == true)
    check(tag .. '：退到放电半径外不挨电', #env.hits == 0, 'hits=' .. #env.hits)
    check(tag .. '：到逃跑时限（' .. GameCfg.Fish.eel.EscapeSec .. ' 秒）才转逃脱',
        escapedAt ~= nil and escapedAt >= fleeAt and escapedAt - fleeAt <= dt + 1e-6,
        string.format('fleeAt=%s escapedAt=%s', tostring(fleeAt), tostring(escapedAt)))
    check(tag .. '：回水后移除，无掉落、金币与库存不变', goneAt ~= nil and data.Data.FishCoin == coin
        and data:ItemCount('eelHead') == heads and data:ItemCount('eelMeat') == meats
        and (data.Data.Bait.worm or 0) == worms,
        string.format('goneAt=%s coin=%s->%s head=%d', tostring(goneAt), tostring(coin),
            tostring(data.Data.FishCoin), data:ItemCount('eelHead')))
    -- 玩家不等电鳗逃完：走开后继续钓（逃脱在后台进行），只计走开的时间
    Clock = Clock + SIM.RetreatSec
    event(string.format('%s：没匕首，放下电鳗走开（%.0f 秒后回水消失，无损失）', tag,
        (goneAt or env.now) - start))
end

-- ===== 3. 钓鱼卖鱼攒钱买匕首；未够钱时钓出电鳗走安全失败，恢复后继续 =====
local daggerPrice
for _, row in ipairs(GameCfg.Shop.Catalog) do if row.itemKey == 'item135' then daggerPrice = row.price end end
local guard = 0
while data:WeaponCount('item135') == 0 and guard < 50 do
    guard = guard + 1
    local fishId, mult = fishUntil(function() return (data.Data.FishCoin or 0) >= daggerPrice end, 400)
    if (data.Data.FishCoin or 0) >= daggerPrice then
        Clock = Clock + SIM.ShopWalkSec
        local cost = buy('item135')
        Stats.daggerAt, Stats.castsToDagger = Clock, Stats.casts
        event(string.format('买匕首 -%d 金', cost))
        check('钓鱼卖鱼攒够 ' .. daggerPrice .. ' 金并买下匕首', cost == daggerPrice and data:WeaponCount('item135') == 1,
            string.format('cost=%d dagger=%d', cost, data:WeaponCount('item135')))
    elseif fishId == 'eel' then
        safeFailEel(mult)
    elseif not fishId then
        break
    end
end
check('买匕首前卖鱼按 floor(基础价 × 倍率) 结算', (Stats.priceMismatch or 0) == 0 and Stats.fishSold > 0,
    string.format('sold=%d mismatch=%d', Stats.fishSold, Stats.priceMismatch or 0))
check('挑战电鳗前已持有匕首（正常金币武器成长）', data:WeaponCount('item135') == 1)

-- ===== 4. 电鳗（持匕首挑战）=====
local eelFish, eelM = fishUntil(function() return false end, 600)
check('正常钓鱼（确定性 RNG）能钓出电鳗', eelFish == 'eel', 'got=' .. tostring(eelFish))
local eelDrops, eelKillSec, eelFirst
if eelFish == 'eel' then
    event('钓出电鳗')
    local env = combatEnv()
    local fish = env.mgr:SpawnLanded(env.player, { fishId = 'eel', mult = eelM or 1.5 },
        env.player.Character.Position + Vector3.New(0, 0, 2))
    fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
    env.mgr:Drop(env.player)
    local fp = fish.Carrier.Body.Position
    env.player.Character.Position = Vector3.New(fp.x + 1.5, fp.y, fp.z) -- 贴身近战
    local cfgEel = GameCfg.Ability.FishAbilities.eel
    local sleepSeen, wakeAt, castsBeforeSleep
    eelDrops, eelKillSec, eelFirst = killAndLoot(env, fish, function(e, f)
        if f.State == 'sleeping' and not sleepSeen then
            sleepSeen, wakeAt, castsBeforeSleep = e.now, f.WakeAt, #e.casts
        end
    end)
    local startAt = env.casts[1]
    quantity('电鳗放电次数（打死前）', #env.casts)
    quantity('电鳗放电时刻', table.concat(env.casts, ','))
    quantity('电鳗击杀耗时（秒，命中由模拟判定）', eelKillSec)
    check('电鳗一轮放电 ' .. tostring(cfgEel.DischargeCount) .. ' 次、间隔 '
        .. tostring(cfgEel.DischargeIntervalSec) .. ' 秒后入睡',
        castsBeforeSleep == cfgEel.DischargeCount
        and startAt and math.abs(env.casts[cfgEel.DischargeCount] - startAt
            - (cfgEel.DischargeCount - 1) * cfgEel.DischargeIntervalSec) < 1e-6,
        string.format('castsBeforeSleep=%s casts=%s', tostring(castsBeforeSleep), table.concat(env.casts, ',')))
    check('电鳗睡眠 ' .. tostring(cfgEel.SleepSec) .. ' 秒且睡眠中不放电',
        wakeAt ~= nil and castsBeforeSleep ~= nil and (#env.casts == castsBeforeSleep
            or env.casts[castsBeforeSleep + 1] >= wakeAt)
        and math.abs(wakeAt - (env.casts[cfgEel.DischargeCount] + cfgEel.DischargeIntervalSec) - cfgEel.SleepSec) < 1e-6,
        string.format('sleepSeen=%s wakeAt=%s', tostring(sleepSeen), tostring(wakeAt)))
    check('电鳗放电伤害 = ' .. tostring(cfgEel.Damage) .. '（5 米内）',
        #env.hits > 0 and env.hits[1].amount == cfgEel.Damage, env.hits[1] and env.hits[1].amount)
    check('电鳗重复死亡只掉一份（肉×2 + 头×1）', eelDrops and eelFirst == 3 and #eelDrops == 3,
        string.format('first=%s total=%s', tostring(eelFirst), tostring(eelDrops and #eelDrops)))
    Clock = Clock + (eelKillSec or 0)
    closeEnv(env)
    if eelDrops then
        local okPick = pickupAll(eelDrops)
        check('电鳗掉落全部拾进库存', okPick and data:ItemCount('eelHead') == 1 and data:ItemCount('eelMeat') == 2,
            string.format('ok=%s head=%d meat=%d', tostring(okPick), data:ItemCount('eelHead'), data:ItemCount('eelMeat')))
    end
end

-- ===== 5. 电鳗头 → 鸭子 =====
local headSlot = ensureBar('eelHead')
check('拾到电鳗头', headSlot ~= nil)
local exchangedDuck = false
if headSlot then
    local headEntry = select(2, slotOf('eelHead'))
    local okHead = require('common.LotteryEligibility').Check(headEntry)
    check('电鳗头（未烤信物）有抽奖资格', okHead == true)
    data:SelectSlot(headSlot)
    Clock = Clock + SIM.FishermanWalkSec
    local coin = data.Data.FishCoin
    local result = feedSelected('eelHead')
    exchangedDuck = result.ok == true and result.exchange and result.exchange.to == 'duck'
    event('电鳗头喂钓鱼佬 → ' .. tostring(result.exchange and result.exchange.to))
    check('电鳗头兑换鸭子（1:1、不给金币）', exchangedDuck and slotOf('duck') ~= nil
        and data:ItemCount('eelHead') == 0 and data.Data.FishCoin == coin, result.reason)
end
-- 电鳗肉卖掉
for _ = 1, 2 do
    local slot = ensureBar('eelMeat')
    if slot and data:SelectSlot(slot) then feedSelected('eelMeat') end
end

-- ===== 6. 挂鸭子钓鳄雀鳝 → 绕后 → 打死 =====
local garDrops
if exchangedDuck then
    Clock = Clock + SIM.FishermanWalkSec
    local fishId, mult = castOnce()
    noteCatch(fishId, mult)
    check('挂鸭子抛竿必出鳄雀鳝且鸭子被扣', fishId == 'alligatorGar' and data:ItemCount('duck') == 0,
        'got=' .. tostring(fishId))
    if fishId == 'alligatorGar' then
        event('钓出鳄雀鳝')
        local env = combatEnv()
        local fish = env.mgr:SpawnLanded(env.player, { fishId = 'alligatorGar', mult = mult },
            env.player.Character.Position + Vector3.New(0, 0, 2))
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        env.mgr:Drop(env.player)
        local params = GameCfg.FishCombat.gar
        local fp = fish.Carrier.Body.Position
        -- 第一口站在正前方头部区挨咬；之后每次锁定后立刻绕到身后（咬距内）
        env.player.Character.Position = Vector3.New(fp.x, fp.y, fp.z + 1)
        local circled = 0
        local firstLockSeen = false
        local function tick(e, f)
            local aim = f.BiteAim
            if aim and f.Facing then
                if firstLockSeen and aim ~= e.lastAim then
                    local p = f.Carrier.Body.Position
                    e.player.Character.Position = Vector3.New(p.x - f.Facing.x * 1.5, p.y, p.z - f.Facing.z * 1.5)
                    circled = circled + 1
                end
                e.lastAim = aim
            end
        end
        env.now = env.now
        env.mgr:Update() -- 第一口起咬
        env.lastAim = fish.BiteAim
        env.now = env.now + params.BiteCooldownSec
        env.mgr:Update() -- 第一口结算（正前方）
        firstLockSeen = true
        local ticks = env.now
        garDrops = select(1, killAndLoot(env, fish, tick))
        local garKillSec = env.now - ticks
        local bites, misses, locks = 0, 0, 0
        for _, n in ipairs(env.notices) do
            if n.kind == 'lock' then locks = locks + 1
            elseif n.reason == 'bite' then bites = bites + 1
            elseif n.reason == 'miss' then misses = misses + 1 end
        end
        local garDamage = 0
        for _, h in ipairs(env.hits) do if h.source == 'gar' then garDamage = garDamage + h.amount end end
        quantity('鳄雀鳝起咬次数', locks)
        quantity('鳄雀鳝咬中 / 咬空（绕后）', bites .. ' / ' .. misses)
        quantity('鳄雀鳝对玩家总伤害', garDamage)
        quantity('鳄雀鳝击杀耗时（秒，命中由模拟判定）', garKillSec)
        check('鳄雀鳝正前方头部区咬中一口（' .. tostring(GameCfg.Fish.alligatorGar.Attack) .. ' 伤害）',
            bites == 1 and garDamage == GameCfg.Fish.alligatorGar.Attack,
            string.format('bites=%d damage=%d', bites, garDamage))
        -- 绕后的每一口都咬空；打死时可能还有一口在预警中未结算
        check('锁定后绕到身后全部咬空', misses >= 1 and bites == 1
            and (misses == circled or misses == circled - 1),
            string.format('misses=%d circled=%d', misses, circled))
        check('鳄雀鳝重复死亡只掉一份（肉×2 + 头×1）', garDrops and #garDrops == 3,
            'drops=' .. tostring(garDrops and #garDrops))
        Clock = Clock + params.BiteCooldownSec + garKillSec
        closeEnv(env)
        if garDrops then pickupAll(garDrops) end
    end
end

-- ===== 7. 鳄雀鳝头 → 船票 =====
local garSlot = ensureBar('garHead')
check('拾到鳄雀鳝头', garSlot ~= nil)
if garSlot then
    data:SelectSlot(garSlot)
    Clock = Clock + SIM.FishermanWalkSec
    local result = feedSelected('garHead')
    event('鳄雀鳝头喂钓鱼佬 → ' .. tostring(result.exchange and result.exchange.to))
    check('鳄雀鳝头兑换虾池船票', result.ok == true and result.exchange and result.exchange.to == 'shrimpTicket'
        and data:ItemCount('shrimpTicket') == 1 and data:ItemCount('garHead') == 0, result.reason)
end

-- ===== 8. 极品资格与个人最大重量 =====
local okElig, Eligibility = pcall(require, 'common.LotteryEligibility')
if okElig then
    if Stats.premiumKept then
        check('钓到的未烤极品在道具栏里有抽奖资格（' .. Stats.premiumKept.itemId .. '，卖前判定）',
            Stats.premiumKept.eligibleInBar == true)
        local cookedEntry = { itemId = Stats.premiumKept.itemId, count = 1, mult = Stats.premiumKept.entry.mult,
            saved = { [GameCfg.Items.CookedFlag] = true } }
        local okCooked, reason = Eligibility.Check(cookedEntry)
        check('烤过的极品失去资格（cooked）', okCooked == false and reason == 'cooked', reason)
    else
        check('闭环内钓到至少 1 条极品（确定性 RNG）', false, '未钓到极品，换种子或加长闭环')
    end
    local okNormal, reason = Eligibility.Check({ itemId = 'bass', count = 1, mult = 1.2 })
    check('普通鱼无抽奖资格（not-premium）', okNormal == false and reason == 'not-premium', reason)
else
    check('LotteryEligibility 模块可用', false, '等待集成：common/LotteryEligibility 缺失')
end
local premiumRows, premiumWeights = 0, {}
for _, row in ipairs(GameCfg.Casting.Zones.WaterCircle2) do
    local def = GameCfg.Items.Definitions[row.Id]
    if def and def.Type == '极品食物' then
        premiumRows = premiumRows + 1
        premiumWeights[#premiumWeights + 1] = row.DrawWeight
    end
end
check('WaterCircle2 共 13 行，其中极品 6 行权重 2/2/2/8/6/4',
    #GameCfg.Casting.Zones.WaterCircle2 == 13 and table.concat(premiumWeights, '/') == '2/2/2/8/6/4',
    string.format('rows=%d premium=%s', #GameCfg.Casting.Zones.WaterCircle2, table.concat(premiumWeights, '/')))
check('个人最大重量随钓获刷新（> 0）', Stats.maxWeight > 0, Stats.maxWeight)

-- ===== 9. 经济与耗时自洽 =====
check('金币非负且收支可复算', (data.Data.FishCoin or 0) >= 0
    and data.Data.FishCoin == Stats.coinsEarned - Stats.coinsSpent,
    string.format('coin=%s earned=%d spent=%d', tostring(data.Data.FishCoin), Stats.coinsEarned, Stats.coinsSpent))
check('闭环耗时为正', Clock > 0, Clock)

-- ===== 10. 经济阻塞估算：新档 → 买竿 → 买匕首，多种子自然抽样（纯配置 + FishCatch，不走管理器）=====
-- 与主链同一套规则：蚯蚓用完就去免费点位补；没匕首钓出电鳗走安全失败（只花走开时间）；其余鱼空手打死后卖掉。
local zone = GameCfg.Casting.Zones.WaterCircle2
local function econRun(seed)
    local r = makeRng(seed)
    local coin, worm, t, casts, eels, trips, spotReady = 0, 0, 0, 0, 0, 0, 0
    local function trip()
        if t < spotReady then t = spotReady end
        t = t + SIM.BaitTripSec
        worm = worm + #GameCfg.BaitSpots.Spots
        spotReady = t + GameCfg.BaitSpots.RespawnSec
        trips = trips + 1
    end
    trip()
    t = t + SIM.FishermanWalkSec
    while coin < rodPrice and worm > 0 do worm, coin = worm - 1, coin + wormPrice end
    if coin < rodPrice then return false, 0, t, 0, trips end
    t, coin = t + SIM.ShopWalkSec, coin - rodPrice
    while coin < daggerPrice and casts < 400 do
        if worm == 0 then trip() end
        local bait = worm > 0 and 'worm' or 0
        if worm > 0 then worm = worm - 1 end
        local id = FishCatch.Select(zone, 1, bait, r)
        local m = FishCatch.Multiplier(r)
        casts = casts + 1
        t = t + GameCfg.Casting.HookDelaySec + SIM.ReelSec + GameCfg.Casting.LandedHoldSec
        if GameCfg.Fish[id].Combat then
            eels, t = eels + 1, t + SIM.RetreatSec
        else
            local s = GameCfg.Fish[id]
            t = t + math.ceil(s.Health / GameCfg.Ability.Unarmed.Damage) * GameCfg.Ability.Unarmed.IntervalSec
            coin = coin + FishCatch.Price(s, m)
        end
    end
    return coin >= daggerPrice, casts, t, eels, trips
end
local Runs = 1000
local blocked, castsList, timeList, eelFirst = 0, {}, {}, 0
for seed = 1, Runs do
    local ok, casts, t, eels = econRun(seed)
    if not ok then blocked = blocked + 1 end
    castsList[#castsList + 1], timeList[#timeList + 1] = casts, t
    if eels > 0 then eelFirst = eelFirst + 1 end
end
table.sort(castsList)
table.sort(timeList)
local function pct(list, p) return list[math.max(1, math.ceil(#list * p))] end
local wormTotal, wormValue = 0, 0
for _, row in ipairs(zone) do
    if row.Bait == 0 or row.Bait == 'worm' then
        wormTotal = wormTotal + row.DrawWeight
        wormValue = wormValue + row.DrawWeight * GameCfg.Fish[row.Id].BasePrice * 1.5
    end
end
check('经济无硬阻塞：' .. Runs .. ' 个种子全部在 400 杆内攒够匕首钱', blocked == 0, 'blocked=' .. blocked)
quantity('[估算] 新档→匕首 抛竿数 p50 / p90 / 最大', pct(castsList, 0.5) .. ' / ' .. pct(castsList, 0.9)
    .. ' / ' .. castsList[#castsList])
quantity('[估算] 新档→匕首 耗时秒 p50 / p90 / 最大', string.format('%.0f / %.0f / %.0f',
    pct(timeList, 0.5), pct(timeList, 0.9), timeList[#timeList]))
quantity('[估算] 买匕首前至少钓出一次电鳗（需安全失败）的种子占比', string.format('%.1f%%', eelFirst * 100 / Runs))
quantity('[估算] 挂蚯蚓每杆期望售价（金，未取整）vs 卖 1 只蚯蚓', string.format('%.2f vs %d',
    wormValue / wormTotal, wormPrice))

-- ===== 输出 =====
print('--- 时间线（模拟耗时估算） ---')
for _, line in ipairs(Timeline) do print(line) end
local catchList = {}
for id, n in pairs(Stats.catches) do catchList[#catchList + 1] = id .. '×' .. n end
table.sort(catchList)
quantity('RNG', '确定性 LCG seed=' .. SIM.Seed .. '（模拟，非真机自然 RNG）')
quantity('抛竿次数', Stats.casts)
quantity('拾饵次数 / 只数', Stats.baitTrips .. ' / ' .. Stats.baitPicked)
quantity('钓获', table.concat(catchList, ' '))
quantity('击杀数', Stats.kills)
quantity('金币收入 / 支出 / 结余', Stats.coinsEarned .. ' / ' .. Stats.coinsSpent .. ' / ' .. tostring(data.Data.FishCoin))
quantity('卖鱼条数 / 卖鱼收入', Stats.fishSold .. ' / ' .. Stats.fishCoins)
quantity('买匕首时刻（秒）/ 当时抛竿数', tostring(Stats.daggerAt) .. ' / ' .. tostring(Stats.castsToDagger))
quantity('没匕首时电鳗安全失败次数', Stats.safeFails)
quantity('模拟总耗时（秒）', Clock)
quantity('个人最大重量（kg）', Stats.maxWeight .. ' ' .. tostring(Stats.maxWeightFish))
quantity('极品命中次数', Stats.premium)
quantity('持有船票', data:ItemCount('shrimpTicket'))

GameCfg.Debug = oldDebug
print(string.format('== 探针结果：%d 通过 / %d 失败', Pass, Fail))
print('说明：离线模拟只证明逻辑自洽；命中、走位、收线耗时为模拟判定，不能当真机验收。')
os.exit(Fail == 0 and 0 or 1)
