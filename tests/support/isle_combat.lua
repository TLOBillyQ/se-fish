-- #90 迁移期共享夹具：礁石岛 / 火山岛战斗用例的假引擎世界。
-- 原 tests/gameplay/reef_combat_test.lua 的 setUp/tearDown/drop/advance 被
-- tests/gameplay/volcano_combat_test.lua 直接继承（`TestVolcanoCombat.setUp = function(self) TestReefCombat.setUp(self) ...`）。
-- LuaUnit 靠全局类名互访实现复用；Busted 每个 spec 是独立 chunk，describe 之间不共享实例方法，
-- 所以把这份世界搬到 support 模块，两个 spec 各开各的（与旧套件「每案例新建世界」的口径一致）。
--
-- 只替换引擎对象、时间与 RemoteEvent，不替换业务管理器：真实 MgrFishCarrier / MgrFishUnit / MgrVitals
-- 全部走 require，SpawnLanded / Drop / Update 与对外预警都在真实实现上观察。
-- 因此这不是编辑器 E2E 证据。
local Cfg = require('common.GameCfg')

local M = {}

local MODULES = { 'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit', 'server.Mgr.MgrVitals',
    'common.REUtil', 'client.LocalGarBite', 'client.LocalCastSource' }
local GLOBALS = { 'game', 'Vector3', 'Quaternion', 'REUtil', 'Color' }

local function signal()
    local slots = {}
    return { Connect = function(_, fn)
        slots[fn] = true
        return { Disconnect = function() slots[fn] = nil end }
    end, Fire = function(_, ...) for fn in pairs(slots) do fn(...) end end }
end

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z) end })
end

--- 「岸边干地」起点：本区中线上、水岸线向内 32 米处（干地）。
--- #102 现场同步后合同安全点挪到了区内侧（离本区水岸线 62.5 米），而入水/逃脱类用例的时序是按
--- 「起点在水岸线外 32 米」调的 —— 这些用例要的只是「岸边」这个位置，所以按水岸线自己取，不借 SafePoint。
function M.shoreDryPoint(zoneIndex)
    local scene = Cfg.Zones[zoneIndex].Scene
    local water = scene.Waters[1]
    local boundary = scene.Boundary
    local halfZ = water.HalfZ or water.HalfXZ or 0
    local inland = water.Center.z >= (boundary.MinZ + boundary.MaxZ) / 2 and -1 or 1
    return vec(water.Center.x, scene.SafePoint.y, water.Center.z + inland * (halfZ + 32))
end

-- 建世界并接线三个真实管理器；返回的 env 供 spec 逐案例持有，env:tearDown() 负责拆除。
-- env 字段：now / notices / players / castStates / units / heartbeat / world / carrier / mgr / vitals / player。
function M.new(zoneIndex)
    local env = setmetatable({}, { __index = M })
    env.saved = {}
    for _, name in ipairs(GLOBALS) do env.saved[name] = rawget(_G, name) end
    env.modules = {}
    for _, name in ipairs(MODULES) do
        env.modules[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    env.now, env.notices, env.players, env.castStates = 0, {}, {}, {}
    env.units, env.heartbeat = {}, signal()
    env.vec = vec
    env.signal = signal
    env.world = { GetServerTime = function() return env.now end,
        CreateUnit = function(_, kind, values)
            local unit = { UnitType = kind, UnitId = tostring({}), OnLiftedBegin = signal(), OnLiftedEnd = signal() }
            for k, v in pairs(values) do unit[k] = v end
            env.units[#env.units + 1] = unit
            function unit:Destroy() self.Destroyed = true end
            function unit:AddNoCollisionPairWithUnit() end
            function unit:SetPosition(p) self.Position = p end
            if values.EnableController then
                unit.Controller = { Health = 100, MaxHealth = 100, HealthChanged = signal(), Died = signal() }
                function unit.Controller:TakeDamage(d)
                    self.Health = math.max(0, self.Health - d)
                    self.HealthChanged:Fire(self.Health)
                    if self.Health == 0 then self.Died:Fire() end
                end
            end
            return unit
        end }
    function env.world:CreateAsset(id) return { self:CreateUnit('WorldUnit', { Name = id }) } end
    _G.Vector3 = { New = vec }
    -- MgrFishCarrier 在有染色（species.VisualColor）时读 Color.New；旧 reef 用例从不自己设 Color，
    -- #90 迁移前一直是靠 damage_float 测试的全局泄漏跑通的。这里显式补替身并纳入恢复名单，
    -- 使这份夹具自洽（不改业务行为，只把缺的引擎替身补上）。
    _G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
    _G.Quaternion = { FromEulerAngles = function() return { GetForward = function() return vec(0, 0, 1) end } end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return env.world end
        if name == 'RunService' then return { IsServer = function() return true end, Heartbeat = env.heartbeat } end
        if name == 'Players' then return { GetPlayers = function() return env.players end, PlayerRemoving = signal() } end
    end, CreateRemoteEvent = function(_, name) return {
        FireAllClients = function(_, p) if name == 'GarBiteNotice' then env.notices[#env.notices + 1] = p end end,
        FireClient = function(_, player, p) if name == 'CastState' then env.castStates[#env.castStates + 1] = p end end,
        OnServerEvent = signal(), OnClientEvent = signal() } end }
    env.carrier = require('server.Mgr.MgrFishCarrier')
    env.mgr = require('server.Mgr.MgrFishUnit')
    env.vitals = require('server.Mgr.MgrVitals')
    env.vitals:Start()
    env.mgr.Vitals = env.vitals
    env.mgr:Start()
    local safe = M.shoreDryPoint(zoneIndex or 6)
    local c = { Health = 300, HealthChanged = signal(), Died = signal(), Lift = function() end }
    function c:TakeDamage(d) self.Health = math.max(0, self.Health - d); self.HealthChanged:Fire(self.Health) end
    env.player = { UserId = 3701, Character = { Controller = c, Position = vec(safe.x, safe.y, safe.z),
        Rotation = _G.Quaternion.FromEulerAngles() },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    env.players[1] = env.player
    env.vitals:OnPlayerAdded(env.player)
    env.mgr:OnPlayerAdded(env.player)
    return env
end

-- 拆除顺序与旧 tearDown 一致：先清鱼、停管理器，再回灌模块缓存与全局（含 nil 也写回 nil）。
function M:tearDown()
    local env = self
    for _, fish in pairs(env.mgr.Fish) do env.mgr:Remove(fish) end
    env.mgr:Stop()
    env.vitals:OnPlayerRemoving(env.player)
    for _, name in ipairs(MODULES) do package.loaded[name] = env.modules[name] end
    for _, name in ipairs(GLOBALS) do _G[name] = env.saved[name] end
end

-- 放下鱼并确认返回严格 true（旧用例这里是 lu.assertTrue；support 模块不依赖 luassert 的表形 assert）。
function M.drop(env, id)
    local fish = assert(env.mgr:SpawnLanded(env.player, { fishId = id, mult = 1 }, env.player.Character.Position))
    fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
    local dropped = env.mgr:Drop(env.player)
    if dropped ~= true then
        error('MgrFishUnit:Drop 未返回 true：' .. tostring(dropped))
    end
    return fish
end

function M.advance(env, to)
    while env.now < to - 1e-8 do
        env.now = math.min(to, env.now + 0.05)
        env.mgr:Update()
    end
end

return M
