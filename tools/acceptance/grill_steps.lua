-- #137 验收：烧烤曲线边界、烤糊伤害、会话隔离与恢复的 Gherkin 步骤（只做断言）。
-- 业务用真实模块：GrillCurve / MgrGrill / MgrSave / PlayerData / LotteryEligibility；
-- 引擎边界（锚点、RE、DataStore、Vitals、Loot）是假的，逻辑通过不等于真机验收。
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态；每个场景最后一步恢复全局。
local GameCfg = require('common.GameCfg')
local GrillCurve = require('common.GrillCurve')

local function signal()
    local handlers = {}
    return {
        Connect = function(_, fn)
            handlers[#handlers + 1] = fn
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...) for _, cb in ipairs(handlers) do cb(...) end end,
    }
end

-- 三区烧烤锚点（#125 场景合同）：验收用它做唯一合法烤位
local function grillAnchor()
    for _, entity in ipairs(GameCfg.Zones[3].Scene.Entities) do
        if entity.Role == 'Grill' then return entity end
    end
end

-- 烧烤世界：照 tests/gameplay/grill_test.lua 的引擎边界
local function grillWorld(world)
    world.saved = { game = rawget(_G, 'game'), REUtil = rawget(_G, 'REUtil'), Debug = GameCfg.Debug }
    GameCfg.Debug = { Enabled = false }
    local env = { now = 1000, values = {}, queue = {}, events = {}, datas = {}, hits = {}, hitSeq = 0,
        playerList = {}, alive = {}, seq = 0 }
    world.env = env
    env.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return env.playerList end } end
    end }
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = {
                OnServerEvent = signal(),
                FireClient = function(_, player, payload)
                    if name == 'GrillResult' then
                        player.grillResults = player.grillResults or {}
                        player.grillResults[#player.grillResults + 1] = payload
                    elseif name == 'GrillState' then
                        player.grillState = payload
                    end
                end,
            }
        end
        return env.events[name]
    end }
    world.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    world.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    world.mgr = assert(loadfile('server/Mgr/MgrGrill.lua'))()
    env.anchorPos = grillAnchor().Position
    world.mgr.FindAnchor = function(_, name)
        if name == GameCfg.Zones[3].Scene.GrillName then return { Name = name, Position = env.anchorPos } end
    end
    world.mgr.PlayerData = {
        GetDataInst = function(_, p) return env.datas[p.UserId] end,
        SendItemBar = function() end,
    }
    world.mgr.Vitals = {
        CanAct = function(_, p) return env.alive[p.UserId] ~= false end,
        NewHit = function(_, source, category)
            env.hitSeq = env.hitSeq + 1
            return { id = env.hitSeq, source = source, category = category, targets = {} }
        end,
        ApplyHit = function(_, hit, target, amount)
            if hit.targets[target.UserId] then return false end
            hit.targets[target.UserId] = true
            env.hits[#env.hits + 1] = { id = hit.id, category = hit.category,
                userId = target.UserId, amount = amount }
            return true, amount
        end,
    }
    world.mgr.Save = world.save
    world.mgr:Start()
    world.drain = function() while #env.queue > 0 do table.remove(env.queue, 1)() end end
end

local function closeWorld(world)
    if not world.saved then return end
    _G.game, _G.REUtil = world.saved.game, world.saved.REUtil
    GameCfg.Debug = world.saved.Debug
    world.saved = nil
end

local function join(world, id)
    local env = world.env
    local player = { UserId = id, Name = 'p' .. id, attrs = {}, CharacterAdded = signal(),
        Character = { Position = { x = env.anchorPos.x + 1, y = env.anchorPos.y, z = env.anchorPos.z } } }
    function player:SetAttribute(k, v) self.attrs[k] = v end
    local data = world.PlayerData.New(player)
    data:Init(true)
    world.save:LoadInto(player, data)
    world.drain()
    assert(data.LoadState == 'ready', '存档未就绪')
    env.datas[id] = data
    env.playerList[#env.playerList + 1] = player
    world.mgr:OnPlayerAdded(player)
    return player, data
end

local function act(world, player, payload)
    local env = world.env
    env.seq = env.seq + 1
    payload.seq = env.seq
    env.events.GrillAction.OnServerEvent:Fire(player, payload)
    world.drain()
    return player.grillResults and player.grillResults[#player.grillResults]
end

local function advance(world, seconds)
    world.env.now = world.env.now + seconds
    world.mgr:Update()
    world.drain()
end

local function countItem(data, itemId)
    local total = 0
    for _, container in pairs(data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId and entry.count > 0 then total = total + entry.count end
        end
    end
    return total
end

local function findEntry(data, itemId)
    for _, container in pairs(data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId and entry.count > 0 then return entry end
        end
    end
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

return { patterns = {

    { '^关闭 Debug 的新档玩家在烧烤点旁$', function(world)
        grillWorld(world)
        world.player, world.data = join(world, 9101)
    end },

    { '^玩家选中一条未烤的 (%S+) 倍率 ([%d%.]+)$', function(world, itemId, mult)
        assert(world.data:AddItem(itemId, tonumber(mult)), '发放失败: ' .. itemId)
        assert(world.data:SelectSlot(1), '选中失败')
    end },

    { '^玩家选中未烤的信物 (%S+)$', function(world, itemId)
        assert(world.data:AddItem(itemId), '发放失败: ' .. itemId)
        assert(world.data:SelectSlot(1), '选中失败')
    end },

    { '^玩家点击烧烤开烤$', function(world)
        local reply = act(world, world.player, { action = 'Start' })
        assert(reply and reply.ok, '开烤被拒: ' .. tostring(reply and reply.reason))
    end },

    { '^烤了 ([%d%.]+) 秒后取出$', function(world, seconds)
        advance(world, tonumber(seconds))
        world.reply = act(world, world.player, { action = 'Takeout' })
    end },

    { '^取出倍率是 ([%d%.]+) 且存档槽位同倍率$', function(world, expect)
        local rate = tonumber(expect)
        local reply = world.reply
        assert(reply and reply.ok, '取出被拒: ' .. tostring(reply and reply.reason))
        assert(near(reply.rate, rate), '倍率 ' .. tostring(reply.rate) .. ' ≠ ' .. expect)
        local entry = findEntry(world.data, reply.itemId)
        assert(entry, '烤鱼没回到库存')
        assert(near(entry.cooked, rate), '格位倍率 ' .. tostring(entry.cooked))
        assert(entry.saved and near(entry.saved.k, rate), '存档槽位倍率未持久化')
        assert(world.data.Extra.recovery.grill == nil, '取出后不应留待恢复标记')
        assert(world.mgr:GetSession(world.player) == nil, '取出后会话应清掉')
        closeWorld(world)
    end },

    -- ===== 快慢帧 =====
    { '^烧烤曲线配置生效$', function(world)
        world.cfg = GameCfg.Grill
        assert(world.cfg.BurnSec == 4.5, '曲线配置缺失')
    end },

    { '^把 ([%d%.]+) 秒切成 (%d+) 帧逐帧算倍率$', function(world, total, frames)
        total, frames = tonumber(total), tonumber(frames)
        world.wholeRate = GrillCurve.Rate(total, world.cfg)
        local step = total / frames
        for i = 1, frames do world.frameRate = GrillCurve.Rate(i * step, world.cfg) end
    end },

    { '^末帧倍率与整烤同秒数的倍率相同$', function(world)
        assert(near(world.frameRate, world.wholeRate),
            '帧末 ' .. tostring(world.frameRate) .. ' ≠ 整烤 ' .. tostring(world.wholeRate))
    end },

    -- ===== 烤糊 =====
    { '^烤了 ([%d%.]+) 秒不取出$', function(world, seconds)
        advance(world, tonumber(seconds))
    end },

    { '^烤鱼只损毁一次且周围玩家受一次 (%d+) 点烤糊伤害$', function(world, amount)
        local env = world.env
        assert(countItem(world.data, 'carp') == 0, '烤糊后库存里不应再有这条鱼')
        assert(world.mgr:GetSession(world.player) == nil, '烤糊后会话应清掉')
        assert(world.data.Extra.recovery.grill == nil, '烤糊后不应留待恢复标记')
        assert(#env.hits == 1, '应只有一次烤糊伤害，实际 ' .. #env.hits)
        assert(env.hits[1].amount == tonumber(amount), '伤害 ' .. tostring(env.hits[1].amount))
        assert(env.hits[1].category == 'grillBurn', '伤害类别应经统一入口登记为 grillBurn')
        assert(world.player.grillState and world.player.grillState.state == 'burnt', '应推送 burnt')
        advance(world, 1) -- 再推进也不应第二次损毁/爆炸
        assert(#env.hits == 1, '烤糊只结算一次')
        closeWorld(world)
    end },

    -- ===== 信物守卫 =====
    { '^玩家点击烧烤被提示失去资格$', function(world)
        local reply = act(world, world.player, { action = 'Start' })
        assert(reply and not reply.ok and reply.reason == 'token-warn',
            '应先提示: ' .. tostring(reply and reply.reason))
        assert(countItem(world.data, 'eelHead') == 1, '提示阶段不扣信物')
    end },

    { '^玩家再次点击确认烤制$', function(world)
        local reply = act(world, world.player, { action = 'Start', confirm = true })
        assert(reply and reply.ok, '确认后开烤被拒: ' .. tostring(reply and reply.reason))
        assert(countItem(world.data, 'eelHead') == 0, '开烤后信物应锁进会话')
    end },

    { '^烤过的信物不可兑换也不可抽奖$', function(world)
        local entry = findEntry(world.data, 'eelHead')
        assert(entry, '烤好的信物没回到库存')
        assert(GameCfg.Items.CookRate(entry) ~= nil, '烤过标记缺失，兑换守卫会放行')
        local Eligibility = require('common.LotteryEligibility')
        -- 直接喂真实库存格位（顶层 cooked 是快照/库存字段；saved.k 是压缩存档协议，资格判定不读）
        local ok, reason = Eligibility.Check(entry)
        assert(ok == false and reason == 'cooked',
            '烤过极品应判 cooked，实际 ' .. tostring(ok) .. '/' .. tostring(reason))
        closeWorld(world)
    end },

    -- ===== 双玩家隔离 =====
    { '^另一名玩家选中未烤的 (%S+) 倍率 ([%d%.]+) 并开烤$', function(world, itemId, mult)
        world.player2, world.data2 = join(world, 9102)
        assert(world.data2:AddItem(itemId, tonumber(mult)), '发放失败: ' .. itemId)
        assert(world.data2:SelectSlot(1), '选中失败')
        local reply = act(world, world.player2, { action = 'Start' })
        assert(reply and reply.ok, '第二名玩家开烤被拒: ' .. tostring(reply and reply.reason))
    end },

    { '^烤了 ([%d%.]+) 秒后双方各自取出$', function(world, seconds)
        advance(world, tonumber(seconds))
        world.reply1 = act(world, world.player, { action = 'Takeout' })
        world.reply2 = act(world, world.player2, { action = 'Takeout' })
    end },

    { '^各自拿到自己的鱼且倍率都是 ([%d%.]+)$', function(world, expect)
        local rate = tonumber(expect)
        assert(world.reply1 and world.reply1.ok and world.reply1.itemId == 'carp',
            '玩家一应取回自己的 carp')
        assert(world.reply2 and world.reply2.ok and world.reply2.itemId == 'tilapia',
            '玩家二应取回自己的 tilapia，取不到对方会话物')
        assert(near(world.reply1.rate, rate) and near(world.reply2.rate, rate), '倍率不符')
        assert(findEntry(world.data, 'carp'), '玩家一库存没有 carp')
        assert(findEntry(world.data2, 'tilapia'), '玩家二库存没有 tilapia')
        assert(countItem(world.data, 'tilapia') == 0 and countItem(world.data2, 'carp') == 0,
            '串号：拿到了对方的鱼')
        closeWorld(world)
    end },

    -- ===== 断线与重进 =====
    { '^烤了 ([%d%.]+) 秒后玩家断线$', function(world, seconds)
        advance(world, tonumber(seconds))
        world.mgr:BeforeLeave(world.player)
    end },

    { '^玩家重进$', function(world)
        world.snapshot = world.data:Serialize()
        local restored = world.PlayerData.New(world.player)
        restored:Init()
        assert(restored:ApplySave(world.snapshot), '重进载入失败')
        world.data2 = restored
    end },

    { '^烤鱼按 ([%d%.]+) 倍率回到库存且重进后倍率保持$', function(world, expect)
        local rate = tonumber(expect)
        assert(world.mgr:GetSession(world.player) == nil, '断线后不应残留会话')
        assert(world.data.Extra.recovery.grill == nil, '能放回库存时不应留待恢复标记')
        local entry = findEntry(world.data, 'carp')
        assert(entry and near(entry.cooked, rate), '断线结算倍率 ' .. tostring(entry and entry.cooked))
        local back = findEntry(world.data2, 'carp')
        assert(back and near(back.cooked, rate), '重进后倍率未保持: ' .. tostring(back and back.cooked))
        closeWorld(world)
    end },

    -- ===== 满格冻结 =====
    { '^烤了 ([%d%.]+) 秒且背包道具栏全满$', function(world, seconds)
        advance(world, tonumber(seconds))
        while world.data:AddItem('tilapia') do end
    end },

    { '^玩家取出被拒为 (%S+)$', function(world, reason)
        local reply = act(world, world.player, { action = 'Takeout' })
        assert(reply and not reply.ok and reply.reason == reason,
            '应拒为 ' .. reason .. '，实际 ' .. tostring(reply and reply.reason))
        assert(countItem(world.data, 'carp') == 0, '满格也不能把烤鱼吞掉')
        local session = world.mgr:GetSession(world.player)
        assert(session and session.state == 'ready', '满格后会话应冻结为 ready')
    end },

    { '^又过了 ([%d%.]+) 秒玩家腾出一格再取出$', function(world, seconds)
        advance(world, tonumber(seconds)) -- 曲线已回落，但倍率在首次取出时冻结
        world.data.Data.Containers[GameCfg.Items.ContainerId.Backpack][1] = nil
        world.reply = act(world, world.player, { action = 'Takeout' })
    end },
} }
