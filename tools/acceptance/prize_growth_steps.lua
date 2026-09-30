-- #139 T18 验收步骤：武器持续效果与永久药水的逻辑契约。
-- 用 loadfile 取全新 MgrAbility（真实状态机与唯一移速计算口），World 时钟、AbilityAPI、
-- Vitals / PlayerData / Survival 以与 server/main.lua 接线同形状的替身注入；world 在步骤间传状态。
local GameCfg = require('common.GameCfg')

local function ensure(world)
    if world.ability then return world end
    world.now, world.hits, world.scales, world.potions, world.weak = 100, {}, {}, {}, false
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return world.now end,
            CreateAsset = function() return nil end } end
        if name == 'Players' then return { GetPlayerFromCharacter = function() return nil end } end
        if name == 'Task' then return { Spawn = function() end, Wait = function() end } end
        return {}
    end }
    package.loaded['server.AbilityAPI'] = {
        SetCastGuard = function() end,
        SetBodyScale = function(_, scale)
            world.scales[#world.scales + 1] = scale
            return { Ok = true, Scale = scale, Derived = {} }
        end,
    }
    local mgr = assert(loadfile('server/Mgr/MgrAbility.lua'))()
    mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, hit, target, amount)
            world.hits[#world.hits + 1] = { category = hit.category, target = target, amount = amount }
            return true
        end,
        RefreshMaxHealth = function() return true end,
    }
    mgr.PlayerData = { GetDataInst = function() return {
        PotionCount = function(_, itemId) return world.potions[itemId] or 0 end } end }
    mgr.Survival = { GetState = function()
        return world.weak and { weakUntil = world.now + 60 } or nil end }
    world.ability = mgr
    world.controller = { WalkSpeed = 7 }
    world.player = { UserId = 13999,
        Character = { Controller = world.controller, SetAttribute = function() end } }
    return world
end

local function advance(world, sec)
    world.now = world.now + sec
    world.ability:Update(sec)
end

local function hit(world)
    assert(world.ability:ApplyWeaponEffect(world.player, world.target, world.effect), '武器特效未挂上')
end

return { patterns = {
    { '^玩家手持 (item%d+) 攻击一名目标$', function(world, itemId)
        ensure(world)
        local cfg = GameCfg.Ability.MeleeWeapons[itemId] or GameCfg.Ability.Guns[itemId]
        assert(cfg and cfg.Effect, itemId .. ' 没有持续效果配置')
        world.effect = cfg.Effect
        world.target = { UserId = 13998 }
    end },

    { '^连续命中 (%d+) 次后过 (%d+) 秒$', function(world, times, sec)
        for _ = 1, tonumber(times) do hit(world) end
        advance(world, tonumber(sec))
    end },

    { '^目标中毒 (%d+) 层$', function(world, stacks)
        local entry = world.ability.Effects['p:13998']
        assert(entry and entry.poison, '目标没有中毒')
        assert(entry.poison.stacks == tonumber(stacks), '实际层数=' .. tostring(entry.poison.stacks))
    end },

    { '^最近一跳经统一伤害入口造成 (%d+) 点 dot 伤害$', function(world, amount)
        local last = world.hits[#world.hits]
        assert(last, '没有 DOT 结算')
        assert(last.category == 'dot', '伤害类别=' .. tostring(last.category))
        assert(last.amount == tonumber(amount), '实际伤害=' .. tostring(last.amount))
    end },

    { '^命中 1 次后过 (%d+) 秒再命中 1 次$', function(world, sec)
        hit(world)
        advance(world, tonumber(sec))
        hit(world)
    end },

    { '^目标霜冻在 (%d+) 秒后失效$', function(world, sec)
        advance(world, tonumber(sec) - 0.1)
        local entry = world.ability.Effects['p:13998']
        assert(entry and entry.frost, '刷新后霜冻应仍在（不叠加但刷新持续）')
        advance(world, 0.1)
        entry = world.ability.Effects['p:13998']
        assert(not (entry and entry.frost), '霜冻应在刷新后 ' .. sec .. ' 秒失效，不应叠加延长')
    end },

    { '^玩家基础移速为 (%d+)$', function(world, speed)
        ensure(world)
        world.controller.WalkSpeed = tonumber(speed)
        world.ability:CaptureBaseSpeed(world.player)
    end },

    { '^玩家累计喝了 (%d+) 个加速药水$', function(world, count)
        ensure(world)
        world.potions[GameCfg.Ability.SpeedPotion.Item] = tonumber(count)
        world.ability:ApplyGrowth(world.player)
    end },

    { '^玩家累计喝了 (%d+) 个变大药水$', function(world, count)
        ensure(world)
        world.potions[GameCfg.Ability.BodyScale.PotionItem] = tonumber(count)
        world.ability:ApplyGrowth(world.player)
    end },

    { '^玩家移速为 ([%d%.]+)$', function(world, speed)
        local actual = world.controller.WalkSpeed
        assert(math.abs(actual - tonumber(speed)) < 1e-9, '实际移速=' .. tostring(actual))
    end },

    { '^玩家体型为 (%d+) 倍且血量上限为 (%d+)$', function(world, scale, maxHealth)
        local last = world.scales[#world.scales]
        assert(last and math.abs(last - tonumber(scale)) < 1e-9, '实际体型=' .. tostring(last))
        local actual = world.ability:MaxHealth(world.player)
        assert(actual == tonumber(maxHealth), '实际血量上限=' .. tostring(actual))
    end },

    { '^玩家进入虚弱$', function(world)
        world.weak = true
        world.ability:RefreshMoveSpeed(world.player)
    end },

    { '^玩家虚弱消退$', function(world)
        world.weak = false
        world.ability:RefreshMoveSpeed(world.player)
    end },
} }
