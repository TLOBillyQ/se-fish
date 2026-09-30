-- #140 验收：风神之翼飞行 / 哥斯拉原子吐息的 Gherkin 步骤（只做断言）。
-- 业务用真实模块：MgrSpecialItem / MgrVitals（统一伤害入口、命中身份去重）/ SpecialItem / FlightPath；
-- 引擎边界（角色、外观、RE、服务器时刻）是假的，逻辑通过不等于真机验收。
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态；每个场景最后一步恢复全局。
local GameCfg = require('common.GameCfg')

local FRAME = 0.05
local TARGET_HEALTH = 5000 -- 目标血量抬高到能吃满 1000，才能量出吐息总额

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

local function scene()
    return GameCfg.Zones[1].Scene -- 鱼塘（#125 场景合同：SafePoint / Boundary）
end

local function newCharacter(x, y, z)
    local controller = { Health = 300, MaxHealth = 300, GravityEnabled = true,
        HealthChanged = signal(), Died = signal(), taken = 0 }
    function controller:TakeDamage(n)
        self.taken = self.taken + n
        self.Health = math.max(0, self.Health - n)
        self.HealthChanged:Fire()
        if self.Health == 0 then self.Died:Fire() end
    end
    local ch = { Position = { x = x, y = y, z = z }, Controller = controller, binds = {}, skin = nil,
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end } }
    ch.EggyAppearance = {
        BindAppearance = function() ch.binds[#ch.binds + 1] = 'wing' return #ch.binds end,
        UnbindAppearance = function(_, id) ch.binds[id] = nil end,
        SetAppearanceByAssetId = function(_, assetId) ch.skin = assetId end,
        ResetAppearance = function() ch.skin = nil end,
    }
    return ch
end

local function newData(itemId)
    local bar = {}
    if itemId then bar[1] = { itemId = itemId, count = 1 } end
    return { Data = { SelectedSlot = itemId and 1 or nil, Zone = 'fishPond',
        Containers = { [GameCfg.Items.ContainerId.ItemBar] = bar } }, Extra = { cooldowns = {} } }
end

local function step(world, seconds)
    local frames = math.floor(seconds / FRAME + 0.5)
    for _ = 1, frames do
        world.env.now = world.env.now + FRAME
        world.mgr:Update(FRAME)
    end
end

local function addPlayer(world, id, x, y, z, itemId)
    local env = world.env
    local player = { UserId = id, attrs = {}, Character = newCharacter(x, y, z) }
    function player:SetAttribute(k, v) self.attrs[k] = v end
    env.players[#env.players + 1] = player
    env.datas[id] = env.datas[id] or newData(itemId)
    world.vitals:OnPlayerAdded(player)
    player.Character.Controller.Health = TARGET_HEALTH
    world.mgr:OnPlayerAdded(player)
    world.players[id] = player
    return player
end

local function openWorld(world)
    world.saved = { game = rawget(_G, 'game'), REUtil = rawget(_G, 'REUtil'), Vector3 = rawget(_G, 'Vector3'),
        Enums = rawget(_G, 'Enums'), Quaternion = rawget(_G, 'Quaternion'),
        wingAsset = GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId,
        skinAsset = GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId }
    -- 外观资源待编辑器预设（[未查证]）；验收用占位 id 驱动绑定 / 换肤接缝
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = 'wing-asset'
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = 'godzilla-asset'
    local env = { now = 1000, players = {}, datas = {}, events = {} }
    world.env, world.players = env, {}
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Enums = { SkeletalSocketType = { Spine = 'socket_body' } }
    _G.Quaternion = { Identity = function() return { x = 0, y = 0, z = 0, w = 1 } end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end }
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { OnServerEvent = signal(), FireClient = function(_, player, payload)
                if name == 'SpecialItemResult' then player.lastResult = payload else player.lastState = payload end
            end }
        end
        return env.events[name]
    end }
    world.vitals = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    world.vitals.Now = function() return env.now end
    world.vitals.DamagePublisher = function() end
    world.mgr = assert(loadfile('server/Mgr/MgrSpecialItem.lua'))()
    world.mgr.Vitals = world.vitals
    world.mgr.PlayerData = { GetDataInst = function(_, p) return env.datas[p.UserId] end }
    world.mgr.FishUnit = { Fish = {} }
    world.mgr:Start()
end

local function closeWorld(world)
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = world.saved.wingAsset
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = world.saved.skinAsset
    _G.game, _G.REUtil, _G.Vector3 = world.saved.game, world.saved.REUtil, world.saved.Vector3
    _G.Enums, _G.Quaternion = world.saved.Enums, world.saved.Quaternion
end

local function fire(world, id, payload)
    world.env.events.SpecialItemAction.OnServerEvent:Fire(world.players[id], payload)
end

local function selectItem(world, id, itemId)
    local data = world.env.datas[id]
    data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1] = itemId and { itemId = itemId, count = 1 } or nil
    data.Data.SelectedSlot = itemId and 1 or nil
end

local function groundY()
    return scene().SafePoint.y
end

return { patterns = {
    { '^鱼塘里玩家 (%d+) 选中 (%S+) 面朝正前，玩家 (%d+) 在其正前 (%d+) 米$', function(world, a, itemId, b, dist)
        openWorld(world)
        local safe = scene().SafePoint
        addPlayer(world, tonumber(a), safe.x, safe.y, safe.z, itemId)
        addPlayer(world, tonumber(b), safe.x, safe.y, safe.z + tonumber(dist), nil)
        step(world, FRAME)
        assert(world.mgr.States[tonumber(a)].effect == 'godzilla', '选中 ' .. itemId .. ' 应即变身')
    end },

    { '^鱼塘里玩家 (%d+) 选中 (%S+)$', function(world, a, itemId)
        openWorld(world)
        local safe = scene().SafePoint
        addPlayer(world, tonumber(a), safe.x, safe.y, safe.z, itemId)
        step(world, FRAME)
        assert(world.mgr.States[tonumber(a)].effect == 'wings', '选中 ' .. itemId .. ' 应即背负')
    end },

    { '^玩家 (%d+) 原子吐息并过 (%d+) 秒$', function(world, a, seconds)
        fire(world, tonumber(a), { action = 'breath' })
        local result = world.players[tonumber(a)].lastResult
        assert(result and result.ok, '吐息应成功: ' .. tostring(result and result.reason))
        step(world, tonumber(seconds))
    end },

    { '^玩家 (%d+) 总共受到 (%d+) 伤害且仍存活$', function(world, b, total)
        local controller = world.players[tonumber(b)].Character.Controller
        assert(controller.taken == tonumber(total), '吐息总伤害 ' .. tostring(controller.taken))
        assert(controller.Health == TARGET_HEALTH - tonumber(total), '血量 ' .. tostring(controller.Health))
        assert(world.vitals:CanAct(world.players[tonumber(b)]), '不应被首领式秒杀')
        local bc = GameCfg.Ability.SpecialItem.Godzilla.Breath
        assert(bc.OneShot == nil and bc.Range == 30 and bc.CooldownSec == 20, '玩家吐息配置不得含首领秒杀')
        closeWorld(world)
    end },

    { '^玩家 (%d+) 切到 (%S+) 再切回 (%S+)$', function(world, a, other, back)
        selectItem(world, tonumber(a), other)
        step(world, FRAME)
        assert(world.mgr.States[tonumber(a)].effect == nil, '切走应解除变身')
        selectItem(world, tonumber(a), back)
        step(world, FRAME)
    end },

    { '^玩家 (%d+) 再次吐息被拒为 (%S+)$', function(world, a, reason)
        fire(world, tonumber(a), { action = 'breath' })
        local result = world.players[tonumber(a)].lastResult
        assert(result and result.ok == false and result.reason == reason,
            '应拒为 ' .. reason .. '，实际 ' .. tostring(result and result.reason))
    end },

    { '^又过了 (%d+) 秒$', function(world, seconds)
        step(world, tonumber(seconds))
    end },

    { '^玩家 (%d+) 再次吐息成功$', function(world, a)
        fire(world, tonumber(a), { action = 'breath' })
        local result = world.players[tonumber(a)].lastResult
        assert(result and result.ok, '冷却到点应可再吐: ' .. tostring(result and result.reason))
        closeWorld(world)
    end },

    { '^玩家 (%d+) 离线后重进$', function(world, a)
        local id = tonumber(a)
        local old = world.players[id]
        world.mgr:OnPlayerRemoving(old)
        world.vitals:OnPlayerRemoving(old)
        for i, p in ipairs(world.env.players) do
            if p == old then table.remove(world.env.players, i) break end
        end
        assert(old.Character.skin == nil, '离线前应复位皮肤')
        local safe = scene().SafePoint
        addPlayer(world, id, safe.x, safe.y, safe.z) -- 存档（选中槽 + 冷却镜像）沿用
        step(world, FRAME)
    end },

    { '^重进的玩家 (%d+) 再次吐息被拒为 (%S+)$', function(world, a, reason)
        fire(world, tonumber(a), { action = 'breath' })
        local result = world.players[tonumber(a)].lastResult
        assert(result and result.ok == false and result.reason == reason,
            '应拒为 ' .. reason .. '，实际 ' .. tostring(result and result.reason))
        assert(world.players[tonumber(a)].Character.Controller.GravityEnabled == true, '重进不得残留关重力')
        closeWorld(world)
    end },

    { '^玩家 (%d+) 死亡$', function(world, a)
        world.vitals:ApplyDamage(world.players[tonumber(a)], TARGET_HEALTH * 2)
        step(world, FRAME)
    end },

    { '^玩家 (%d+) 变身已解除且再次吐息被拒为 (%S+)$', function(world, a, reason)
        local player = world.players[tonumber(a)]
        assert(world.mgr.States[tonumber(a)].effect == nil, '死亡应解除变身')
        assert(player.Character.skin == nil, '死亡应复位皮肤')
        fire(world, tonumber(a), { action = 'breath' })
        local result = player.lastResult
        assert(result and result.ok == false and result.reason == reason,
            '应拒为 ' .. reason .. '，实际 ' .. tostring(result and result.reason))
        closeWorld(world)
    end },

    { '^玩家 (%d+) 在地面时重力开启$', function(world, a)
        assert(world.players[tonumber(a)].Character.Controller.GravityEnabled == true, '地面待机不应关重力')
    end },

    { '^玩家 (%d+) 长按飞行 (%d+) 秒$', function(world, a, seconds)
        fire(world, tonumber(a), { action = 'fly', holding = true })
        step(world, tonumber(seconds))
    end },

    { '^玩家 (%d+) 离区地面高度是 (%d+) 米且重力关闭$', function(world, a, height)
        local ch = world.players[tonumber(a)].Character
        local rise = ch.Position.y - groundY()
        assert(math.abs(rise - tonumber(height)) < 1e-6, '离地高度 ' .. tostring(rise))
        assert(ch.Controller.GravityEnabled == false, '空中应接管重力')
    end },

    { '^玩家 (%d+) 松开飞行 (%d+) 秒$', function(world, a, seconds)
        fire(world, tonumber(a), { action = 'fly', holding = false })
        step(world, tonumber(seconds))
    end },

    { '^玩家 (%d+) 落回区地面且重力开启$', function(world, a)
        local ch = world.players[tonumber(a)].Character
        assert(math.abs(ch.Position.y - groundY()) < 1e-6, '落点 ' .. tostring(ch.Position.y))
        assert(ch.Controller.GravityEnabled == true, '落地应交还重力')
        assert(world.mgr.States[tonumber(a)].airborne == false, '落地后不应判空中')
        closeWorld(world)
    end },

    { '^玩家 (%d+) 在空中被推到本区围栏外$', function(world, a)
        local ch = world.players[tonumber(a)].Character
        local b = scene().Boundary
        ch.Position = { x = b.MaxX + 50, y = ch.Position.y, z = b.MinZ - 50 }
        step(world, FRAME)
    end },

    { '^玩家 (%d+) 被钳回本区围栏内$', function(world, a)
        local pos = world.players[tonumber(a)].Character.Position
        local b = scene().Boundary
        assert(pos.x >= b.MinX and pos.x <= b.MaxX and pos.z >= b.MinZ and pos.z <= b.MaxZ,
            string.format('越界 (%.2f, %.2f)', pos.x, pos.z))
        closeWorld(world)
    end },

    { '^玩家 (%d+) 切到 (%S+)$', function(world, a, itemId)
        selectItem(world, tonumber(a), itemId)
        step(world, FRAME)
    end },

    { '^玩家 (%d+) 重力开启、不在空中、翅膀已解绑$', function(world, a)
        local ch = world.players[tonumber(a)].Character
        local state = world.mgr.States[tonumber(a)]
        assert(ch.Controller.GravityEnabled == true, '切走应恢复重力')
        assert(state.airborne == false and state.holding == false, '切走不应滞空')
        assert(next(ch.binds) == nil, '翅膀外观应解绑')
        closeWorld(world)
    end },

    { '^玩家 (%d+) 没有变身也没有吐息冷却$', function(world, b)
        local state = world.mgr.States[tonumber(b)]
        assert(state.effect == nil and state.lastBreathAt == nil, '玩家状态串扰')
        assert(world.players[tonumber(b)].Character.skin == nil, '他人不应被换肤')
        closeWorld(world)
    end },
} }
