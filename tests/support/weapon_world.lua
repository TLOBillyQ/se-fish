-- #90 迁移期共享夹具：MgrWeapon 的服务端权威世界（武器系统本体用例与强化用例共用）。
-- 原 tests/gameplay/weapon_system_test.lua 里 TestMgrWeaponUpgrade 用
-- `TestMgrWeaponUpgrade.setUp = function(self) TestMgrWeapon.setUp(self) end` 直接复用
-- TestMgrWeapon 的夹具（LuaUnit 靠全局类名互访实现）；Busted 每个 spec 是独立 chunk、
-- describe 之间不共享实例方法，所以把这份世界搬到 support 模块，两个 describe 各开各的。
--
-- 只替换引擎对象、时间与协作管理器（AbilityAPI 点调用桩 / REUtil / Vitals / PlayerData / FishUnit），
-- MgrWeapon 本体走 loadfile 逐案例新建，口径与旧夹具完全一致。
local PlayerData = require('server.Data.PlayerData')

local M = {}

local function weaponPlayer(id)
    return { UserId = id, Character = { Position = { x = 0, y = 2, z = 0 },
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end } } }
end

function M.open(ctx)
    ctx.saved = { game = rawget(_G, 'game'), re = rawget(_G, 'REUtil'),
        api = package.loaded['server.AbilityAPI'] }
    ctx.now = 1000
    ctx.player = weaponPlayer(42)
    ctx.other = weaponPlayer(43)
    ctx.casts, ctx.swingStaged, ctx.replies = {}, {}, {}
    ctx.applied, ctx.spawnedFish, ctx.order = {}, {}, 0
    -- 与真实 server.AbilityAPI 一致的点调用签名（模块函数，非方法）
    package.loaded['server.AbilityAPI'] = {
        StageSwing = function(userId, swing) ctx.swingStaged[userId] = swing end,
        PeekSwing = function(userId) return ctx.swingStaged[userId] end,
        TakeSwing = function(userId)
            local s = ctx.swingStaged[userId]; ctx.swingStaged[userId] = nil; return s end,
        CastAbility = function(unit, index)
            ctx.casts[#ctx.casts + 1] = { unit = unit, index = index }; return true end,
        AddCastGuard = function(fn) ctx.castGuard = fn end,
    }
    _G.REUtil = {
        GetRE = function(_, name)
            return { OnServerEvent = { Connect = function(_, fn) ctx.reHandler = fn end },
                FireClient = function(_, player, payload)
                    ctx.replies[#ctx.replies + 1] = { name = name, player = player, payload = payload } end }
        end,
        CheckRECD = function() return nil end,
    }
    ctx.rayHit = nil
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return ctx.now end } end
        if name == 'Players' then return { GetPlayers = function() return { ctx.player, ctx.other } end,
            GetPlayerFromCharacter = function(_, c)
                if c == ctx.player.Character then return ctx.player end
                if c == ctx.other.Character then return ctx.other end
            end }
        end
        if name == 'PhysicsService' then return { Raycast = function(_, o, d, p)
            ctx.lastRay = { o = o, d = d, p = p }
            return ctx.rayHit end }
        end
        return nil
    end }
    ctx.mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
    ctx.data = PlayerData.New({ UserId = 42, SetAttribute = function() end })
    ctx.data:Init()
    ctx.mgr.PlayerData = { GetDataInst = function() return ctx.data end,
        SendItemBar = function() end }
    ctx.mgr.Attr = require('tests.lib.attr_runtime').New(ctx.mgr.PlayerData)
    ctx.mgr.Vitals = {
        CanAct = function() return true end,
        NewHit = function(_, source, category)
            ctx.order = ctx.order + 1
            return { id = ctx.order, source = source, category = category }
        end,
        ApplyHit = function(_, hit, target, amount)
            ctx.order = ctx.order + 1
            ctx.applied[#ctx.applied + 1] = { order = ctx.order, hit = hit,
                target = target, amount = amount }
            return true, amount
        end,
    }
    ctx.mgr.FishUnit = { Fish = {}, SpawnBlastFish = function(_, fishId, mult, pos, owner)
        ctx.order = ctx.order + 1
        ctx.spawnedFish[#ctx.spawnedFish + 1] = { order = ctx.order,
            fishId = fishId, mult = mult, pos = pos, owner = owner }
        return { Id = #ctx.spawnedFish }
    end }
    ctx.mgr.FishCarrier = { ResolveCarrier = function(_, unit) return nil end }
end

function M.close(ctx)
    _G.game = ctx.saved.game
    _G.REUtil = ctx.saved.re
    package.loaded['server.AbilityAPI'] = ctx.saved.api
end

function M.lastReply(ctx)
    local r = ctx.replies[#ctx.replies]
    return r and r.payload or nil
end

return M
