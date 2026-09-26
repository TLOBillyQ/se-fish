-- #86 失败方式：举鱼提前攻击、施法失败也睡眠、睡眠反复攻击、180秒仍睡眠、直线逃脱被普通鱼转向覆盖、移除残留技能。
local lu = require('luaunit')
require('tests.gameplay.fish_escape_test')
TestEelCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestEelCombat[name] = TestFishEscape[name]
end
function TestEelCombat:test_drop_attacks_sleeps_ten_seconds_then_escapes_at_deadline()
    self:prepare()
    local casts, removed = 0, 0
    self.mgr.Ability = {
        EquipFish = function() return true end,
        CastFish = function() casts = casts + 1 return true end,
        RemoveFish = function() removed = removed + 1 end,
    }
    local fish = self:heldFish(self.player, 'eel')
    self.mgr:Update()
    lu.assertEquals(casts, 0)
    self.mgr:Drop(self.player)
    lu.assertEquals(fish.State, 'combat')
    self.mgr:Update()
    lu.assertEquals(casts, 1)
    lu.assertEquals(fish.State, 'attacking')
    self.now = 0.5
    self.mgr:Update()
    lu.assertEquals(fish.State, 'sleeping')
    self.now = 10.49
    self.mgr:Update()
    lu.assertEquals(casts, 1)
    self.now = 10.5
    self.mgr:Update()
    lu.assertEquals(casts, 2)
    self.now = 180
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    local heading = fish.Heading
    self.now = 184
    self.hits = { { Instance = { Name = 'Wall' }, Distance = 1 } }
    self.mgr:Update()
    lu.assertEquals(fish.Heading, heading)
    fish.Carrier.Body.Position = Vector3.New(-11.75, 5, 27.75)
    self.mgr:Update()
    lu.assertNil(self.mgr.Fish[fish.Id])
end

-- 再放普通鱼不能提前清掉尚未到逃跑时限的精英鱼。
function TestEelCombat:test_combat_fish_is_not_counted_as_escaping()
    self:prepare()
    local eel = self:heldFish(self.player, 'eel')
    self.mgr:Drop(self.player)
    self.now = 1
    local normal = self:heldFish(self.player, 'bass')
    self.mgr:Drop(self.player)
    lu.assertEquals(self.mgr.Fish[eel.Id], eel)
    lu.assertEquals(self.mgr:Escaping(), { normal })
end
function TestEelCombat:test_sleep_lies_sideways_and_waking_restores_rotation()
    self:prepare()
    local oldQuaternion = Quaternion
    local rotation = setmetatable({}, { __mul = function(_, value) return value end })
    Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
    self.mgr.Ability = { EquipFish = function() end, CastFish = function() return true end }
    local fish = self:heldFish(self.player, 'eel')
    fish.Carrier.Body.Rotation = rotation
    self.mgr:Drop(self.player)
    self.mgr:Update()
    self.now = 0.5
    self.mgr:Update()
    local sleepRotation = fish.Carrier.Body.Rotation
    self.now = 10.5
    self.mgr:Update()
    local wakeRotation = fish.Carrier.Body.Rotation
    Quaternion = oldQuaternion
    lu.assertNotEquals(sleepRotation, rotation)
    lu.assertEquals(wakeRotation, rotation)
end
