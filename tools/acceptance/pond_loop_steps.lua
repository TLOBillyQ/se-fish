-- #134 验收切片 D：鱼塘新档正常闭环的 Gherkin 步骤（只做断言；关键量由 tests/probes/pond_loop.lua 打印）。
-- 业务用真实模块：MgrSave / MgrPlayerData / MgrInteract / MgrShop / MgrQuest（经济、兑换），
-- MgrLoot:Give / OnCarrierDied（拾取发放、掉落结算），MgrFishUnit（电鳗 / 鳄雀鳝状态机）。
-- 引擎边界是假的（锚点、射线、技能施放只计数、玩家命中），逻辑通过不等于真机验收。
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态；每个场景结束的「那么」步骤恢复全局。
if not package.path:find('./tests/lib/?.lua', 1, true) then
    package.path = './tests/lib/?.lua;' .. package.path
end
local GameCfg = require('common.GameCfg')

local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar
local BACKPACK = GameCfg.Items.ContainerId.Backpack

local function signal()
    return { Connect = function() return { Disconnect = function() end } end }
end

-- ===== 经济世界（照 tests/gameplay/economy_persistence_test.lua 的引擎边界）=====
local function economyWorld(world)
    world.saved = { game = rawget(_G, 'game'), REUtil = rawget(_G, 'REUtil'),
        MgrPlayerData = rawget(_G, 'MgrPlayerData'), Debug = GameCfg.Debug }
    GameCfg.Debug = { Enabled = false }
    local env = { values = {}, queue = {}, events = {} }
    world.env = env
    local store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    local anchor = { Position = { x = 0, y = 0, z = 0 }, PlayAnimation = function() end }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end, Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
        if name == 'World' then return { GetServerTime = function() return 100 end,
            FindFirstChild = function() return anchor end } end
        if name == 'Players' then return { GetPlayers = function() return { world.player } end } end
    end }
    local function fire(name, value) env.events[#env.events + 1] = { name = name, value = value } end
    _G.REUtil = { GetRE = function(_, name) return {
        FireClient = function(_, _, value) fire(name, value) end,
        FireAllClients = function(_, value) fire(name, value) end,
    } end }
    world.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    world.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    world.interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    world.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
    world.quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
    world.players.Save, world.save.PlayerData = world.save, world.players
    world.interact.PlayerData, world.interact.Save, world.interact.Quest = world.players, world.save, world.quest
    world.shop.PlayerData, world.shop.Save, world.shop.Quest = world.players, world.save, world.quest
    world.shop.Interact = world.interact
    local savedCarrier = package.loaded['server.Mgr.MgrFishCarrier']
    package.loaded['server.Mgr.MgrFishCarrier'] = { SubscribeDied = function() end, Despawn = function() end }
    world.loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
    package.loaded['server.Mgr.MgrFishCarrier'] = savedCarrier
    world.player = { UserId = 13402, Character = { Position = { x = 0, y = 0, z = 0 } },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    world.players:OnPlayerAdded(world.player)
    world.quest:OnPlayerAdded(world.player)
    world.drain = function() while #env.queue > 0 do table.remove(env.queue, 1)() end end
    world.drain()
    world.data = world.players:GetDataInst(world.player)
    world.save:SaveExplicit(world.player.UserId, world.data, function() end)
    world.drain()
    world.seq = 0
end

local function restoreEconomy(world)
    if not world.saved then return end
    _G.game, _G.REUtil, _G.MgrPlayerData = world.saved.game, world.saved.REUtil, world.saved.MgrPlayerData
    GameCfg.Debug = world.saved.Debug
    world.saved = nil
end

local function lastResult(world, name)
    local events = world.env.events
    for i = #events, 1, -1 do if events[i].name == name then return events[i].value end end
end

local function nextSeq(world) world.seq = world.seq + 1 return world.seq end

local function feed(world)
    world.interact:Handle(world.player, { target = 'fisherman', action = 'Feed', seq = nextSeq(world) })
    world.drain()
    return lastResult(world, 'InteractResult') or {}
end

local function buy(world, itemId)
    world.shop:Handle(world.player, { action = 'Buy', itemId = itemId, seq = nextSeq(world) })
    world.drain()
end

local function slotOf(data, itemId)
    local items = data.Data.Containers[ITEM_BAR]
    for slot = 1, data:ItemBarCapacity() do
        local e = items[slot]
        if e and e.count > 0 and e.itemId == itemId then return slot end
    end
end

-- 背包里的信物按 ItemBarAction{action='MoveSlot'} 同一方法挪回道具栏
local function ensureBar(data, itemId)
    local slot = slotOf(data, itemId)
    if slot then return slot end
    local pack = data.Data.Containers[BACKPACK] or {}
    for i = 1, data:BackpackCapacity() do
        if pack[i] and pack[i].count > 0 and pack[i].itemId == itemId then
            local bar = data.Data.Containers[ITEM_BAR]
            for s = 1, data:ItemBarCapacity() do
                if not bar[s] and data:MoveSlot(BACKPACK, i, ITEM_BAR, s) then return slotOf(data, itemId) end
            end
        end
    end
end

-- ===== 战斗世界：真实 MgrFishUnit（复用 fish_lift / fish_escape 测试的假引擎）=====
local function combatWorld(world)
    require('tests.gameplay.fish_escape_test')
    local env = setmetatable({}, { __index = TestFishEscape })
    TestFishEscape.setUp(env)
    TestFishEscape.prepare(env)
    env.casts, env.hits, env.notices = {}, {}, {}
    for _, p in ipairs({ env.player, env.other }) do
        p.Character.Controller.Health = 300
        p.Character.Controller.TakeDamage = function(c, d) c.Health = c.Health - d end
    end
    env.other.Character.Position = Vector3.New(500, 2, 500)
    env.mgr.PublishBite = function(_, payload) env.notices[#env.notices + 1] = payload end
    env.mgr.CombatPublisher = function() end
    env.mgr.Ability = {
        EquipFish = function() return true end,
        CastFish = function() env.casts[#env.casts + 1] = env.now return true end,
        RemoveFish = function() end,
    }
    env.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, _, _, amount) env.hits[#env.hits + 1] = amount return true, amount end,
        CanTakeDamage = function() return true end,
    }
    world.combat = env
end

local function closeCombat(world)
    if world.combat then TestFishEscape.tearDown(world.combat) end
    world.combat = nil
end

local function dropFish(world, fishId)
    local env = world.combat
    local fish = env.mgr:SpawnLanded(env.player, { fishId = fishId, mult = 1.5 },
        env.player.Character.Position + Vector3.New(0, 0, 2))
    fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
    env.mgr:Drop(env.player)
    world.fish = fish
    return fish
end

local function at(env, now) env.now = now env.mgr:Update() end

return { patterns = {
    -- ===== 正常链：新档 → 免费拾饵 → 卖饵 → 买竿 =====
    { '^关闭 Debug 的新档玩家在鱼塘$', function(world)
        economyWorld(world)
        local d = world.data
        assert(GameCfg.Debug.Enabled == false, 'Debug 没关')
        assert((d.Data.FishCoin or 0) == 0, '新档金币不是 0: ' .. tostring(d.Data.FishCoin))
        assert(d:ItemCount('starterRod') == 0, '新档已有鱼竿')
        assert((d.Data.Bait.worm or 0) == 0, '新档已有鱼饵')
    end },

    { '^玩家在蚯蚓点免费拾到 (%d+) 只蚯蚓$', function(world, count)
        for _ = 1, tonumber(count) do
            assert(world.loot:Give(world.data, 'worm', nil, nil, 1), '拾饵发放失败')
        end
        assert(world.data.Data.Bait.worm == tonumber(count))
    end },

    { '^玩家把蚯蚓逐只喂给钓鱼佬$', function(world)
        world.data:SelectBait('worm')
        while (world.data.Data.Bait.worm or 0) > 0 do
            local result = feed(world)
            assert(result.ok, '喂饵失败: ' .. tostring(result.reason))
        end
    end },

    { '^玩家在商店买下新手鱼竿$', function(world)
        buy(world, 'starterRod')
    end },

    { '^玩家持有 1 根新手鱼竿且金币为 (%d+)$', function(world, coin)
        local d = world.data
        local ok = d:ItemCount('starterRod') == 1 and (d.Data.FishCoin or 0) == tonumber(coin)
        local detail = string.format('rod=%d coin=%s', d:ItemCount('starterRod'), tostring(d.Data.FishCoin))
        restoreEconomy(world)
        assert(ok, detail)
    end },

    -- ===== 信物兑换链：电鳗头 → 鸭子，鳄雀鳝头 → 船票 =====
    { '^玩家拾到 1 个未烤的(%S+)$', function(world, name)
        local ids = { ['电鳗头'] = 'eelHead', ['鳄雀鳝头'] = 'garHead' }
        local itemId = assert(ids[name], '未知信物: ' .. name)
        assert(world.loot:Give(world.data, itemId, 1.5, nil, 1), '信物拾取发放失败')
        world.token = itemId
    end },

    { '^玩家选中该信物喂给钓鱼佬$', function(world)
        local slot = assert(ensureBar(world.data, world.token), '信物不在库存')
        assert(world.data:SelectSlot(slot))
        world.coinBefore = world.data.Data.FishCoin or 0
        world.result = feed(world)
    end },

    { '^信物 1:1 换成(%S+)且不给金币$', function(world, name)
        local ids = { ['鸭子'] = 'duck', ['虾池船票'] = 'shrimpTicket' }
        local product = assert(ids[name], '未知产物: ' .. name)
        local d, r = world.data, world.result
        local ok = r.ok == true and r.exchange and r.exchange.to == product
            and d:ItemCount(product) == 1 and d:ItemCount(world.token) == 0
            and (d.Data.FishCoin or 0) == world.coinBefore
        local detail = string.format('ok=%s to=%s product=%d token=%d reason=%s', tostring(r.ok),
            tostring(r.exchange and r.exchange.to), d:ItemCount(product), d:ItemCount(world.token), tostring(r.reason))
        restoreEconomy(world)
        assert(ok, detail)
    end },

    -- ===== 电鳗：5 次放电后睡 10 秒 =====
    { '^电鳗上岸后被玩家放下$', function(world)
        combatWorld(world)
        local fish = dropFish(world, 'eel')
        assert(fish.State == 'combat', '放下后没进战斗: ' .. tostring(fish.State))
    end },

    { '^战斗推进到第 (%d+) 秒$', function(world, sec)
        local env = world.combat
        local target = tonumber(sec)
        local t = env.now
        while t < target do
            t = math.min(target, t + 0.5)
            at(env, t)
        end
    end },

    { '^电鳗已放电 (%d+) 次、间隔 (%d+) 秒，末次放电满一个间隔后入睡 (%d+) 秒$', function(world, count, gap, sleep)
        local env, fish = world.combat, world.fish
        local n, dt = tonumber(count), tonumber(gap)
        local spaced = #env.casts == n
        for i = 2, #env.casts do
            if math.abs(env.casts[i] - env.casts[i - 1] - dt) > 1e-6 then spaced = false end
        end
        local last = env.casts[#env.casts] or 0
        local ok = spaced and fish.State == 'sleeping'
            and fish.WakeAt and math.abs(fish.WakeAt - (last + dt) - tonumber(sleep)) < 1e-6
        local detail = string.format('casts=%s state=%s wakeAt=%s', table.concat(env.casts, ','),
            tostring(fish.State), tostring(fish.WakeAt))
        if not ok then closeCombat(world) end
        assert(ok, detail)
    end },

    { '^电鳗醒来后开始下一轮放电$', function(world)
        local env, fish = world.combat, world.fish
        local before = #env.casts
        at(env, fish.WakeAt - 0.01)
        local asleep = #env.casts == before
        at(env, fish.WakeAt)
        local ok = asleep and #env.casts == before + 1 and fish.State == 'attacking'
        local detail = string.format('asleep=%s casts=%d state=%s', tostring(asleep), #env.casts, tostring(fish.State))
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 鳄雀鳝：锁定朝向后绕到身后咬空 =====
    { '^鳄雀鳝上岸后被玩家放下且玩家站在它正前方$', function(world)
        combatWorld(world)
        local fish = dropFish(world, 'alligatorGar')
        local p = fish.Carrier.Body.Position
        world.combat.player.Character.Position = Vector3.New(p.x, 2, p.z + 1)
        at(world.combat, 0)
        assert(fish.BiteAim, '玩家在咬距内却没有起咬')
    end },

    { '^预警期间玩家绕到鳄雀鳝身后$', function(world)
        local env, fish = world.combat, world.fish
        local p = fish.Carrier.Body.Position
        env.player.Character.Position = Vector3.New(p.x - fish.Facing.x * 1.5, 2, p.z - fish.Facing.z * 1.5)
        at(env, GameCfg.FishCombat.gar.BiteCooldownSec)
    end },

    { '^这一口咬空且玩家不掉血$', function(world)
        local env = world.combat
        -- 结算后玩家仍在咬距内，同一帧可能立刻再次锁定；只看本口的结算原因
        local misses, bites = 0, 0
        for _, n in ipairs(env.notices) do
            if n.reason == 'miss' then misses = misses + 1 elseif n.reason == 'bite' then bites = bites + 1 end
        end
        local ok = #env.hits == 0 and misses == 1 and bites == 0
        local detail = string.format('hits=%d misses=%d bites=%d', #env.hits, misses, bites)
        closeCombat(world)
        assert(ok, detail)
    end },

    { '^玩家留在正前方直到结算$', function(world)
        at(world.combat, GameCfg.FishCombat.gar.BiteCooldownSec)
    end },

    { '^这一口咬中玩家 (%d+) 点$', function(world, amount)
        local env = world.combat
        local ok = #env.hits == 1 and env.hits[1] == tonumber(amount)
        local detail = 'hits=' .. table.concat(env.hits, ',')
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 重复死亡只结算一次 =====
    { '^放下的(%S+)被打死且死亡事件到达两次$', function(world, name)
        local ids = { ['电鳗'] = 'eel', ['鳄雀鳝'] = 'alligatorGar' }
        combatWorld(world)
        local fish = dropFish(world, assert(ids[name], '未知鱼种: ' .. name))
        local savedCarrier = package.loaded['server.Mgr.MgrFishCarrier']
        local loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
        package.loaded['server.Mgr.MgrFishCarrier'] = savedCarrier
        world.drops = {}
        loot.FishUnit = world.combat.mgr
        loot.Spawn = function(_, fishId, _, _, itemId) world.drops[#world.drops + 1] = itemId or fishId end
        loot:OnCarrierDied(fish.Carrier)
        loot:OnCarrierDied(fish.Carrier)
    end },

    { '^只掉一份：(%S+)×2 和 (%S+)×1$', function(world, meat, head)
        local ids = { ['电鳗肉'] = 'eelMeat', ['电鳗头'] = 'eelHead', ['鳄雀鳝肉'] = 'garMeat', ['鳄雀鳝头'] = 'garHead' }
        local counts = {}
        for _, id in ipairs(world.drops) do counts[id] = (counts[id] or 0) + 1 end
        local ok = #world.drops == 3 and counts[ids[meat]] == 2 and counts[ids[head]] == 1
        local detail = 'drops=' .. table.concat(world.drops, ',')
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 极品资格 =====
    { '^格位是未烤的 (%S+) 倍率 ([%d%.]+)$', function(world, itemId, mult)
        world.entry = { itemId = itemId, count = 1, mult = tonumber(mult) }
    end },

    { '^格位是烤过的 (%S+) 倍率 ([%d%.]+)$', function(world, itemId, mult)
        world.entry = { itemId = itemId, count = 1, mult = tonumber(mult),
            saved = { [GameCfg.Items.CookedFlag] = true } }
    end },

    { '^抽奖资格判定为 ([%w%-]+)$', function(world, expect)
        local okMod, Eligibility = pcall(require, 'common.LotteryEligibility')
        assert(okMod, '等待集成：common.LotteryEligibility 缺失')
        local ok, reason = Eligibility.Check(world.entry)
        if expect == 'eligible' then
            assert(ok == true, '应有资格，实际 ' .. tostring(reason))
        else
            assert(ok == false and reason == expect, '期望 ' .. expect .. '，实际 ' .. tostring(ok) .. '/' .. tostring(reason))
        end
    end },
} }
