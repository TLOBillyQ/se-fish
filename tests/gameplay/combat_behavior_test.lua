-- #128：武器命中与电鳗范围命中必须经统一伤害入口；同一判定段重放不双扣。
local lu = require('luaunit')

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire(...)
        for _, fn in ipairs(self.handlers) do fn(...) end
    end
    return s
end
local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

TestMeleeHitEntry = {}
function TestMeleeHitEntry:setUp()
    self.saved = {
        game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion'),
        vitals = package.loaded['server.Mgr.MgrVitals'],
        carrier = package.loaded['server.Mgr.MgrFishCarrier'],
        gm = package.loaded['server.Mgr.MgrGM'],
    }
    _G.Vector3 = { New = vec }
    _G.Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
    self.ownerPlayer = { UserId = 7 }
    self.owner = { UnitId = 70, Position = vec(0, 0, 0) }
    self.ownerPlayer.Character = self.owner
    self.controllerCalls = 0
    self.target = { UnitId = 80, UnitType = 'EggyUnit', Position = vec(1, 0, 0), Controller = {
        TakeDamage = function() self.controllerCalls = self.controllerCalls + 1 end,
    } }
    self.carrier = { Receiver = self.target }
    self.hits = {}
    package.loaded['server.Mgr.MgrVitals'] = {
        NewHit = function(_, source, category)
            local hit = { source = source, category = category, id = 1 }
            self.createdHit = hit
            return hit
        end,
        ApplyHit = function(_, hit, target, amount)
            self.hits[#self.hits + 1] = { hit, target, amount }
            return true, amount
        end,
    }
    package.loaded['server.Mgr.MgrFishCarrier'] = {
        ResolveCarrier = function(_, target) return target == self.target and self.carrier or nil end,
    }
    package.loaded['server.Mgr.MgrGM'] = { GetMeleeDamage = function(_, _, damage) return damage end }
    self.created = {}
    local env = self
    _G.game = { GetService = function(_, name)
        if name == 'RunService' then return { IsServer = function() return true end } end
        if name == 'World' then return { CreateUnit = function(_, unitType, values)
            local unit = { UnitId = 500 + #env.created, UnitType = unitType, OnTriggerEnter = signal() }
            for k, v in pairs(values or {}) do unit[k] = v end
            env.created[#env.created + 1] = unit
            return unit
        end, CreateAsset = function() return {} end } end
        if name == 'Players' then return { GetPlayerFromCharacter = function(_, unit)
            return unit == env.owner and env.ownerPlayer or nil
        end } end
        if name == 'PhysicsService' then return { GetPartsInPart = function() return {} end } end
        if name == 'TimerService' then return { CreateTimer = function() end } end
    end }
end
function TestMeleeHitEntry:tearDown()
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.Quaternion = self.saved.Quaternion
    package.loaded['server.Mgr.MgrVitals'] = self.saved.vitals
    package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
    package.loaded['server.Mgr.MgrGM'] = self.saved.gm
end
function TestMeleeHitEntry:test_fish_hit_uses_one_hit_identity_and_never_direct_controller()
    local attrs = {
        Duration = 0.2,
        ABILITY_ANOSTATE_HITBOX_OFFSET = vec(0, 0, 1),
        ABILITY_ANOSTATE_HITBOX_SCALE = vec(2, 2, 2),
        ABILITY_ANOSTATE_BULLET_DAMAGE = 25,
        ABILITY_ANOSTATE_HITPOWER = 0,
        ABILITY_ANOSTATE_USE_PERFAB = '',
        ABILITY_ANOSTATE_ANIMKEY = '',
    }
    local manager = { Parent = self.owner }
    local ability = { Parent = manager }
    local anchor = { Parent = ability, AnchorStart = signal(), Destroying = signal() }
    function anchor:FindFirstChild(name) return self[name] end
    function anchor:GetAttribute(name) return attrs[name] end
    local behavior = assert(loadfile('server/AbilityBehaviors/melee_hit.lua'))()
    behavior.Attach(anchor)
    anchor.AnchorStart:Fire()
    local hitBox = self.created[#self.created]
    hitBox.OnTriggerEnter:Fire(self.target)
    hitBox.OnTriggerEnter:Fire(self.target)
    lu.assertEquals(self.controllerCalls, 0)
    lu.assertEquals(#self.hits, 1)
    lu.assertEquals(self.hits[1][1], self.createdHit)
    lu.assertEquals(self.hits[1][1].source, self.ownerPlayer)
    lu.assertEquals(self.hits[1][1].category, 'weapon')
    lu.assertEquals(self.hits[1][2], self.target)
    lu.assertEquals(self.hits[1][3], 25)
end

-- #128：server/main.lua 必须完成战斗接线，否则运行时各管理器拿不到统一入口。
TestMainCombatWiring = {}
local function readSource(path)
    local parts = {}
    for line in io.lines(path) do
        parts[#parts + 1] = line
    end
    return table.concat(parts, "\n")
end
function TestMainCombatWiring:test_combat_managers_are_wired_to_unified_entry()
    local src = readSource('server/main.lua')
    lu.assertStrContains(src, 'MgrMap.MgrAbility.Vitals = MgrMap.MgrVitals')
    lu.assertStrContains(src, 'MgrMap.MgrFishUnit.Vitals = MgrMap.MgrVitals')
    lu.assertStrContains(src, 'MgrMap.MgrVitals.FishCarrier = MgrMap.MgrFishCarrier')
    lu.assertStrContains(src, 'MgrMap.MgrCast.Vitals = MgrMap.MgrVitals')
    lu.assertStrContains(src, 'MgrMap.MgrFishCarrier.DamageListener')
    -- 有效鱼受击伤害要回报仇恨：监听里必须经 FindByCarrier 找回鱼并 NoteDamage
    lu.assertStrContains(src, 'FindByCarrier')
    lu.assertStrContains(src, 'NoteDamage')
end

TestEelDischargeEntry = {}
function TestEelDischargeEntry:setUp()
    self.saved = { game = rawget(_G, 'game'),
        vitals = package.loaded['server.Mgr.MgrVitals'],
        carrier = package.loaded['server.Mgr.MgrFishCarrier'] }
    self.hits = {}
    self.seenHits = {}
    self.hitSerial = 0
    package.loaded['server.Mgr.MgrVitals'] = {
        NewHit = function(_, source, category)
            self.hitSerial = self.hitSerial + 1
            return { id = self.hitSerial, source = source, category = category }
        end,
        ApplyHit = function(_, hit, player, amount)
            local key = tostring(hit.id) .. ':' .. tostring(player.UserId)
            if self.seenHits[key] then return false end
            self.seenHits[key] = true
            self.hits[#self.hits + 1] = { hit, player, amount }
            return true, amount
        end,
    }
    self.owner = { Position = vec(0, 0, 0) }
    self.carrier = { Receiver = self.owner }
    package.loaded['server.Mgr.MgrFishCarrier'] = {
        ResolveCarrier = function(_, unit) return unit == self.owner and self.carrier or nil end,
    }
    self.inside = { UserId = 1, Character = { Position = vec(1, 0, 0), Controller = { Health = 300 } } }
    self.outside = { UserId = 2, Character = { Position = vec(9, 0, 0), Controller = { Health = 300 } } }
    local env = self
    _G.game = { GetService = function(_, name)
        if name == 'Players' then return { GetPlayers = function() return { env.inside, env.outside } end } end
    end }
end
function TestEelDischargeEntry:tearDown()
    _G.game = self.saved.game
    package.loaded['server.Mgr.MgrVitals'] = self.saved.vitals
    package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
end
function TestEelDischargeEntry:test_discharge_uses_fish_hit_and_replay_does_not_double_apply()
    local behavior = assert(loadfile('server/AbilityBehaviors/eel_discharge.lua'))()
    lu.assertEquals(behavior.Discharge(self.owner, 5, 15), 1)
    lu.assertEquals(#self.hits, 1)
    lu.assertEquals(self.hits[1][1].source, self.carrier)
    lu.assertEquals(self.hits[1][1].category, 'fishAttack')
    lu.assertEquals(self.hits[1][2], self.inside)
    local replay = { id = 99, source = self.carrier, category = 'fishAttack' }
    lu.assertEquals(behavior.Discharge(self.owner, 5, 15, replay), 1)
    lu.assertEquals(behavior.Discharge(self.owner, 5, 15, replay), 0)
    lu.assertEquals(#self.hits, 2)
end
