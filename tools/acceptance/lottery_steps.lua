-- #138 验收切片：抽奖机服务端结算契约的 Gherkin 步骤（只做断言；真实随机分布见
-- tests/probes/lottery_runtime.lua 的专项探针，期望验算在 tests/gameplay/lottery_draw_test.lua）。
-- 业务用真实模块：MgrSave / MgrPlayerData / MgrInteract / MgrLottery；
-- 引擎边界是假的（DataStore、RE、锚点），三轴结果用脚本化 RNG 锁定（经 MgrLottery.Random 注入）。
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态；每个场景结束的「那么」步骤恢复全局。
if not package.path:find('./tests/lib/?.lua', 1, true) then
    package.path = './tests/lib/?.lua;' .. package.path
end
local GameCfg = require('common.GameCfg')

local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar

local PREMIUM = { ['极品罗非鱼'] = 'item7', ['信物虾尾'] = 'item31' }

local function signal()
    return { Connect = function() return { Disconnect = function() end } end }
end

-- ===== 抽奖世界（照 tests/gameplay/lottery_settle_test.lua 的引擎边界）=====
local function lotteryWorld(world)
    world.saved = { game = rawget(_G, 'game'), REUtil = rawget(_G, 'REUtil'), Debug = GameCfg.Debug }
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
    local anchor = { Position = { x = 0, y = 0, z = 0 } }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
        if name == 'World' then return { GetServerTime = function() return 100 end,
            FindFirstChild = function() return anchor end } end
        if name == 'Players' then return { GetPlayers = function() return { world.player } end } end
    end }
    _G.REUtil = { GetRE = function(_, name) return { FireClient = function(_, _, value)
        env.events[#env.events + 1] = { name = name, value = value }
    end } end }
    world.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    world.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    world.interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    world.lottery = assert(loadfile('server/Mgr/MgrLottery.lua'))()
    world.players.Save, world.save.PlayerData = world.save, world.players
    world.interact.PlayerData, world.interact.Save = world.players, world.save
    world.lottery.PlayerData, world.lottery.Save, world.lottery.Interact =
        world.players, world.save, world.interact
    world.rolls = {}
    world.lottery.Random = function()
        return assert(table.remove(world.rolls, 1), '脚本化 RNG 序列耗尽')
    end
    world.player = { UserId = 13801, Character = { Position = { x = 0, y = 0, z = 0 } },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    world.players:OnPlayerAdded(world.player)
    world.drain = function() while #env.queue > 0 do table.remove(env.queue, 1)() end end
    world.drain()
    world.data = world.players:GetDataInst(world.player)
    world.seq = 0
end

-- 发一件物品进道具栏后存档定基线（与 settle 测试 persistReady 同口径）
local function giveAndPersist(world, itemId, mult, cooked)
    assert(world.data:AddItem(itemId, mult, cooked), '发放失败: ' .. itemId)
    assert(world.save:SaveExplicit(world.player.UserId, world.data, function() end))
    world.drain()
    world.env.events = {}
end

local function restore(world)
    if not world.saved then return end
    _G.game, _G.REUtil = world.saved.game, world.saved.REUtil
    GameCfg.Debug = world.saved.Debug
    world.saved = nil
end

local function results(world)
    local out = {}
    for _, event in ipairs(world.env.events) do
        if event.name == 'LotteryResult' then out[#out + 1] = event.value end
    end
    return out
end

local function draw(world, slot, seq)
    world.lottery:Handle(world.player, { action = 'Draw', slot = slot, seq = seq })
    world.drain()
end

return { patterns = {
    { '^抽奖档玩家在抽奖机旁$', function(world)
        lotteryWorld(world)
        assert(GameCfg.Debug.Enabled == false, 'Debug 没关')
        assert((world.data.Data.FishCoin or 0) == 0, '新档金币不是 0')
    end },

    { '^玩家道具栏第一件是未烤的(%S+)倍率 ([%d%.]+)$', function(world, name, mult)
        local itemId = assert(PREMIUM[name], '未知极品: ' .. name)
        giveAndPersist(world, itemId, tonumber(mult))
        local entry = world.data.Data.Containers[ITEM_BAR][1]
        assert(entry and entry.itemId == itemId, '投入物不在道具栏第 1 格')
    end },

    { '^玩家道具栏第一件是烤过的(%S+)倍率 ([%d%.]+)$', function(world, name, mult)
        local itemId = assert(PREMIUM[name], '未知极品: ' .. name)
        -- 烤制倍率字段口径（#137 最小约定）：顶层 cooked 数值标记
        giveAndPersist(world, itemId, tonumber(mult), 1.5)
        local entry = world.data.Data.Containers[ITEM_BAR][1]
        assert(entry and entry.itemId == itemId, '投入物不在道具栏第 1 格')
    end },

    { '^三轴摇出 (%d+) (%d+) (%d+)$', function(world, a, b, c)
        world.rolls = { tonumber(a), tonumber(b), tonumber(c) }
    end },

    { '^三轴摇出 (%d+) (%d+) (%d+) 武器选第 (%d+) 件$', function(world, a, b, c, pick)
        world.rolls = { tonumber(a), tonumber(b), tonumber(c), tonumber(pick) }
    end },

    { '^玩家抽第 (%d+) 格的奖$', function(world, slot)
        world.seq = world.seq + 1
        draw(world, tonumber(slot), world.seq)
    end },

    { '^玩家用同一序号再抽第 (%d+) 格$', function(world, slot)
        world.beforeReplay = { coin = world.data.Data.FishCoin,
            results = #results(world) }
        draw(world, tonumber(slot), world.seq) -- 同 seq 重发
        world.afterReplay = { coin = world.data.Data.FishCoin,
            results = #results(world) }
    end },

    { '^玩家断线重进$', function(world)
        world.player = { UserId = 13801, Character = { Position = { x = 0, y = 0, z = 0 } },
            CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
        world.players:OnPlayerAdded(world.player)
        world.drain()
        world.data = world.players:GetDataInst(world.player)
        world.env.events = {}
        world.lottery:OnPlayerAdded(world.player)
    end },

    { '^抽奖两同赔金币 (%d+) 且投入已消耗$', function(world, coins)
        local result = results(world)[1]
        local ok = result and result.ok and result.outcome == 'pair'
            and result.coins == tonumber(coins)
            and world.data.Data.FishCoin == tonumber(coins)
            and world.data.Data.Containers[ITEM_BAR][1] == nil
        local detail = result and string.format('outcome=%s coins=%s coin=%d',
            tostring(result.outcome), tostring(result.coins), world.data.Data.FishCoin) or '无回包'
        restore(world)
        assert(ok, detail)
    end },

    { '^抽奖三同大奖是(%S+)且不另发金币$', function(world, prizeName)
        local result = results(world)[1]
        local ok = result and result.ok and result.outcome == 'triple'
            and result.prize and result.prize.name == prizeName
            and result.coins == nil and world.data.Data.FishCoin == 0
        local detail = result and string.format('outcome=%s prize=%s coin=%d', tostring(result.outcome),
            result.prize and tostring(result.prize.name) or 'nil', world.data.Data.FishCoin) or '无回包'
        restore(world)
        assert(ok, detail)
    end },

    { '^抽奖三同大奖是(%S+)且回到第 (%d+) 格$', function(world, prizeName, slot)
        local result = results(world)[1]
        local entry = world.data.Data.Containers[ITEM_BAR][tonumber(slot)]
        local ok = result and result.ok and result.outcome == 'triple'
            and result.prize and result.prize.name == prizeName
            and entry and entry.itemId == result.prize.itemId and entry.count == 1
            and world.data.Data.FishCoin == 0
        local detail = result and string.format('outcome=%s slot=%s', tostring(result.outcome),
            entry and entry.itemId or '空') or '无回包'
        restore(world)
        assert(ok, detail)
    end },

    { '^抽奖未中奖且投入已消耗$', function(world)
        local result = results(world)[1]
        local ok = result and result.ok and result.outcome == 'none'
            and result.coins == nil and result.prize == nil
            and world.data.Data.FishCoin == 0
            and world.data.Data.Containers[ITEM_BAR][1] == nil
        restore(world)
        assert(ok, result and tostring(result.outcome) or '无回包')
    end },

    { '^抽奖被拒绝 ([%w%-]+) 且物品还在$', function(world, reason)
        local result = results(world)[1]
        local ok = result and result.ok == false and result.reason == reason
            and world.data.Data.Containers[ITEM_BAR][1] ~= nil
            and world.data.Data.FishCoin == 0
        local detail = result and string.format('ok=%s reason=%s',
            tostring(result.ok), tostring(result.reason)) or '无回包'
        restore(world)
        assert(ok, detail)
    end },

    { '^两次结果相同且只扣一件只发一次$', function(world)
        local all = results(world)
        local ok = world.afterReplay.results == world.beforeReplay.results + 1
            and all[1] and all[2] and all[1].coins == all[2].coins
            and world.afterReplay.coin == world.beforeReplay.coin -- 不重复发奖
            and world.data:ItemCount('item7') == 0 -- 只扣过一件
        local detail = string.format('results=%d->%d coin=%s->%s', world.beforeReplay.results,
            world.afterReplay.results, tostring(world.beforeReplay.coin), tostring(world.afterReplay.coin))
        restore(world)
        assert(ok, detail)
    end },

    { '^补推的结果与落账一致且加速药水只有一件$', function(world)
        local all = results(world)
        local recovered = all[1]
        local ok = recovered and recovered.recovered == true
            and recovered.outcome == 'triple'
            and recovered.prize and recovered.prize.itemId == 'item167'
            and world.data:ItemCount('item167') == 1 -- 奖品只发过一次
            and world.data:ItemCount('item31') == 0 -- 投入只扣过一次
            and world.data.Data.FishCoin == 0
        local detail = recovered and string.format('recovered=%s prize=%s item167=%d',
            tostring(recovered.recovered), recovered.prize and recovered.prize.itemId or 'nil',
            world.data:ItemCount('item167')) or '无补推'
        restore(world)
        assert(ok, detail)
    end },
} }
