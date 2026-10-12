-- 举鱼共享夹具：仅提供环境方法，不注册测试案例。
local M = {}

local function signal()
    local slots = {}
    return {
        Connect = function(_, fn)
            slots[#slots + 1] = fn
            return { Disconnect = function()
                for i, f in ipairs(slots) do if f == fn then table.remove(slots, i) break end end
            end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(slots) do fn(...) end end,
        Count = function() return #slots end,
    }
end

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

function M:setUp()
    local env = self
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        RaycastParams = rawget(_G, 'RaycastParams') }
    self.modules = {}
    for _, name in ipairs({ 'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }) do
        self.modules[name] = package.loaded[name]
    end
    self.now = 0
    self.created = {}
    self.spawned = {}
    self.despawned = {}
    self.lifts = {}
    _G.Vector3 = { New = vec }
    self.world = {
        GetServerTime = function() return env.now end,
        CreateUnit = function(_, unitType, values)
            local unit = { UnitType = unitType, Destroyed = false }
            for k, v in pairs(values) do unit[k] = v end
            function unit:Destroy() self.Destroyed = true end
            env.created[#env.created + 1] = unit
            return unit
        end,
    }
    self.players = {}
    _G.game = { GetService = function(_, name)
        if name == 'World' then return env.world end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end }
    local nextUnit = 0
    local function body(position)
        nextUnit = nextUnit + 1
        local unit = { UnitId = nextUnit, Position = position, BodyType = 4, Parent = nil, Pairs = {},
            LinearVelocity = vec(0, 0, 0), AngularVelocity = vec(0, 0, 0),
            OnLiftedBegin = signal(), OnLiftedEnd = signal() }
        function unit:AddNoCollisionPairWithUnit(other) self.Pairs[other] = true end
        return unit
    end
    package.loaded['server.Mgr.MgrFishCarrier'] = {
        Spawn = function(_, opts)
            local carrier = { Opts = opts, Body = body(opts.Position),
                Receiver = { UnitId = 'r' .. tostring(#env.spawned + 1), Controller = { LiftedEnabled = true } } }
            env.spawned[#env.spawned + 1] = carrier
            return carrier
        end,
        Despawn = function(_, carrier) env.despawned[#env.despawned + 1] = carrier end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = nil
    self.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    self.pushed = {}
    self.mgr.Cast = { PushState = function(_, player) env.pushed[#env.pushed + 1] = player end }
    self.mgr:Start()
    self.player = self:newPlayer(7, vec(10, 2, -20))
    self.other = self:newPlayer(8, vec(30, 2, -20))
end

function M:newPlayer(id, position)
    local env = self
    local character
    character = { Position = position, Rotation = { GetForward = function() return vec(0, 0, 1) end },
        Controller = { Died = signal(), Lift = function()
            env.lifts[#env.lifts + 1] = character
        end } }
    local player = { UserId = id, Character = character, CharacterAdded = signal(), CharacterRemoving = signal() }
    self.players[#self.players + 1] = player
    self.mgr:OnPlayerAdded(player)
    return player
end

function M:tearDown()
    if not self.saved then return end
    -- 即使 setUp 只走到一半也恢复已保存的进程状态；Stop 失败最后传播。
    local ok, err = pcall(function() if self.mgr then self.mgr:Stop() end end)
    if self.modules then
        for _, name in ipairs({ 'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }) do
            package.loaded[name] = self.modules[name]
        end
    end
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.RaycastParams = self.saved.RaycastParams
    self.saved = nil
    if not ok then error(err, 0) end
end

function M:land(player, fishId, mult)
    local c = player.Character.Position
    return self.mgr:SpawnLanded(player, { fishId = fishId or 'bass', mult = mult or 1.37 }, vec(c.x, c.y, c.z + 2))
end

function M:mounts()
    local list = {}
    for _, unit in ipairs(self.created) do
        if unit.UnitType == 'SkeletalSocketMount' then list[#list + 1] = unit end
    end
    return list
end

return M
