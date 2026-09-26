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
    lu.assertTrue(removed >= 1)
end
