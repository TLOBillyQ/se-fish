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
