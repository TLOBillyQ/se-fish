-- #128：先列失败方式见 .scratch/128/progress.md；通过服务端公开伤害入口验证命中身份与隔离。
local lu = require('luaunit')
local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire() for _, fn in ipairs(self.handlers) do fn() end end
    return s
end
local function player(id)
    local c = { Health = 300, HealthChanged = signal(), Died = signal(), calls = 0 }
    function c:TakeDamage(n)
        self.calls = self.calls + 1
        self.Health = math.max(0, self.Health - n)
        self.HealthChanged:Fire()
        if self.Health == 0 then self.Died:Fire() end
    end
    local p = { UserId = id, CharacterAdded = signal(), attrs = {},
        Character = { Controller = c, Position = { x = id, y = 0, z = 0 }, Size = { y = 2 } } }
    function p:SetAttribute(k, v) self.attrs[k] = v end
    return p
end
TestCombatBase = {}
function TestCombatBase:setUp()
    self.v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    self.v.Now = function() return 100 end
    self.notices = {}
    self.v.DamagePublisher = function(payload) self.notices[#self.notices + 1] = payload end
    self.a, self.b = player(1), player(2)
    self.v:OnPlayerAdded(self.a)
    self.v:OnPlayerAdded(self.b)
end
function TestCombatBase:test_same_hit_is_once_per_target_and_actual_damage_matches_notice()
    local hit = self.v:NewHit(nil, 'grill')
    local ok, amount = self.v:ApplyHit(hit, self.a, 25)
    lu.assertTrue(ok)
    lu.assertEquals(amount, 25)
    lu.assertFalse(self.v:ApplyHit(hit, self.a.Character, 25))
    lu.assertTrue(self.v:ApplyHit(hit, self.b, 25))
    lu.assertEquals({ self.a.Character.Controller.Health, self.b.Character.Controller.Health }, { 275, 275 })
    lu.assertEquals({ #self.notices, self.notices[1].amount, self.notices[2].amount }, { 2, 25, 25 })
    lu.assertFalse(self.v:ApplyHit(hit, self.a, 0 / 0))
end
function TestCombatBase:test_source_alias_life_hook_and_zone_filter_stay_in_entry()
    local hit = self.v:NewHit(self.b.Character, 'weapon')
    lu.assertEquals(self.v:ResolveHitSource(hit), self.b)
    local filtered = 0
    self.v.DamageFilter = function(incoming, target)
        filtered = filtered + 1
        lu.assertEquals(incoming.sourcePlayer, self.b)
        lu.assertEquals(target, self.a)
        return incoming.category ~= 'weapon'
    end
    lu.assertFalse(self.v:ApplyHit(hit, self.a, 10))
    lu.assertEquals(self.a.Character.Controller.Health, 300)
    self.v.DamageFilter = nil
    lu.assertTrue(self.v:ApplyHit(hit, self.a.Character, 10))

    local rescued = {}
    self.v:SetLifeHooks({
        LifeStatus = function(state) return state.player.attrs.Health <= 1 and 'downed' or 'alive' end,
        CanTakeDamage = function(state) return state.player.attrs.Health > 1 end,
        OnBeforeDamage = function(state)
            if state.player.attrs.Health - 10 <= 0 then state.player.Character.Controller.Health = 1 return true end
        end,
        Rescue = function(state, rescuer)
            rescued[#rescued + 1] = { state.player, rescuer }
            state.player.Character.Controller.Health = 30
            return true
        end,
    })
    self.a.Character.Controller.Health = 5
    self.a.attrs.Health = 5
    local lethal = self.v:NewHit(self.b, 'fishAttack')
    local ok, actual = self.v:ApplyHit(lethal, self.a, 10)
    lu.assertTrue(ok)
    lu.assertEquals(actual, 4)
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertFalse(self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 1))
    lu.assertTrue(self.v:Rescue(self.a, self.b))
    lu.assertEquals(rescued, { { self.a, self.b } })
end

TestAbilityCastGuard = {}
function TestAbilityCastGuard:test_root_api_applies_server_guard_before_package_cast()
    local impl = {}
    for _, name in ipairs(require('common.AbilityAPIBase').SERVER_API) do impl[name] = function() return false end end
    local calls = {}
    impl.CastAbility = function(unit, index) calls[#calls + 1] = { unit, index } return true end
    package.preload['server.packages.ability_system.api'] = function() return impl end
    local api = assert(loadfile('server/AbilityAPI.lua'))()
    local allowed, unit = false, {}
    api.SetCastGuard(function(candidate, index)
        lu.assertEquals({ candidate, index }, { unit, 2 })
        return allowed
    end)
    lu.assertFalse(api.CastAbility(unit, 2))
    lu.assertEquals(calls, {})
    allowed = true
    lu.assertTrue(api.CastAbility(unit, 2))
    lu.assertEquals(#calls, 1)
end

TestMgrAbilityActionGuard = {}
function TestMgrAbilityActionGuard:test_player_cast_is_blocked_by_vitals_state()
    local oldGame, oldApi = rawget(_G, 'game'), package.loaded['server.AbilityAPI']
    local guard
    package.loaded['server.AbilityAPI'] = { SetCastGuard = function(fn) guard = fn end }
    _G.game = { GetService = function() return {} end }
    local mgr = assert(loadfile('server/Mgr/MgrAbility.lua'))()
    local blocked, free = player(1), player(2)
    local vitals = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    vitals.Now = function() return 100 end
    vitals:OnPlayerAdded(blocked)
    vitals:OnPlayerAdded(free)
    vitals:SetLifeHooks({ LifeStatus = function(state)
        return state.player == blocked and 'downed' or 'alive'
    end })
    mgr.Vitals = vitals
    mgr:Start()
    _G.game = oldGame
    package.loaded['server.AbilityAPI'] = oldApi
    lu.assertNotNil(guard)
    lu.assertFalse(mgr:CanCast(blocked))
    lu.assertFalse(guard(blocked, 0))
    lu.assertTrue(mgr:CanCast(free))
    lu.assertTrue(guard(free, 0))
end

function TestCombatBase:test_fish_damage_uses_same_hit_identity_and_reports_actual_amount()
    local carrier = { Body = { UnitId = 91 }, Receiver = {}, Controller = {} }
    local damageCalls = {}
    self.v.FishCarrier = {
        ResolveCarrier = function(_, target)
            if target == carrier or target == carrier.Receiver then return carrier, 'fish:91' end
        end,
        Damage = function(_, target, amount, hit)
            damageCalls[#damageCalls + 1] = { target, amount, hit }
            return true, math.min(amount, 7)
        end,
    }
    local hit = self.v:NewHit(self.a.Character, 'weapon')
    local ok, actual = self.v:ApplyHit(hit, carrier, 10)
    lu.assertTrue(ok)
    lu.assertEquals(actual, 7)
    lu.assertFalse(self.v:ApplyHit(hit, carrier.Receiver, 10))
    lu.assertEquals(#damageCalls, 1)
    lu.assertEquals(damageCalls[1][2], 10)
    lu.assertEquals(damageCalls[1][3].sourcePlayer, self.a)
    lu.assertEquals(self.a.Character.Controller.Health, 300)
end
