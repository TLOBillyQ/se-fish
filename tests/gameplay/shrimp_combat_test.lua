-- #135 失败模式：放下即逃；连击顺序/20点伤害错误；重复帧重复伤害；尾刺位移错误；
-- 15秒后未眩晕5秒；雨云与俯冲重叠/漏招；雨云少于6次；移除后残留预警；绕后仍啄中。
local lu = require('luaunit')
require('tests.gameplay.gar_combat_test')
TestShrimpCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestShrimpCombat[name] = TestGarCombat[name]
end
local function drop(self, id)
    self:prepare()
    self.player.Character.Controller.Health = 2000
    self.player.Character.Controller.TakeDamage = function() end
    local fish = self:heldFish(self.player, id)
    self.mgr:Drop(self.player)
    local p = fish.Carrier.Body.Position
    self.player.Character.Position = { x = p.x, y = p.y, z = p.z + 1 }
    self.other.Character.Controller.Health = 0
    return fish
end
function TestShrimpCombat:test_rain_jitter_keeps_six_slots_without_extending_duration()
    local fish = drop(self, 'fish16Boss')
    self.now = 30; self.mgr:Update()
    for _, t in ipairs({ 31.01, 32.02, 33.03, 34.04, 35.05, 36.01 }) do
        self.now = t; self.mgr:Update(); self.mgr:Update()
    end
    lu.assertEquals(#self.vitalsCalls, 6)
    lu.assertEquals(fish.Move.Name, 'dive')
end

function TestShrimpCombat:test_rain_large_dt_does_not_retroactively_hit_new_arrival()
    local fish = drop(self, 'fish16Boss')
    self.now = 30; self.mgr:Update()
    self.now = 36; self.mgr:Update(); self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 1)
    lu.assertEquals(fish.Move.Name, 'dive')
    local notice = self.notices[#self.notices]
    lu.assertEquals(notice.position.x, fish.Move.Destination.x)
    lu.assertEquals(notice.position.z, fish.Move.Destination.z)
end
function TestShrimpCombat:test_stun_wake_and_warning_cancel_do_not_accumulate_chase_time()
    local fish = drop(self, 'fish15Elite')
    self.mgr:Update()
    self.now = 15; self.mgr:Update()
    local p = fish.Carrier.Body.Position
    self.player.Character.Position = { x = p.x + 50, y = p.y, z = p.z }
    self.now = 20; self.mgr:Update()
    lu.assertEquals(fish.Carrier.Body.Position, p)
    self.now = 21; self.mgr:Update()
    lu.assertAlmostEquals(fish.Carrier.Body.Position.x, p.x + 8, 1e-6)
    self.player.Character.Position = { x = p.x + 9, y = p.y, z = p.z }
    self.now = 22; self.mgr:Update()
    lu.assertNotNil(fish.Move)
    local before = fish.Carrier.Body.Position
    self.player.Character.Position = { x = p.x + 50, y = p.y, z = p.z }
    self.now = 24; self.mgr:Update()
    lu.assertEquals(fish.Carrier.Body.Position, before)
    self.now = 25; self.mgr:Update()
    lu.assertAlmostEquals(fish.Carrier.Body.Position.x, before.x + 8, 1e-6)
end
function TestShrimpCombat:test_airborne_dive_over_water_survives_and_timeout_lands()
    local fish = drop(self, 'fish16Boss')
    self.now = 30; self.mgr:Update()
    self.now = 36; self.mgr:Update()
    local ground = fish.Move.Center.y
    fish.Carrier.Body.Position = { x = 105, y = ground + 3, z = 106 }
    self.now = 37; self.mgr:Update()
    lu.assertNotEquals(fish.State, 'escaping')
    self.now = fish.FleeAt; self.mgr:Update()
    lu.assertEquals(fish.Carrier.Body.Position.y, ground)
    lu.assertNil(fish.Move)
end

function TestShrimpCombat:test_script_chase_moves_kinematic_body_without_overshooting()
    local fish = drop(self, 'fish15Elite')
    local p = fish.Carrier.Body.Position
    self.player.Character.Position = { x = p.x + 10, y = p.y, z = p.z }
    self.mgr:Update()
    self.now = 1; self.mgr:Update()
    lu.assertAlmostEquals(fish.Carrier.Body.Position.x, p.x + 7.5, 1e-6)
    self.now = 2; self.mgr:Update()
    lu.assertNotNil(fish.Move)
    self.downed[self.player] = true
    local payloads = {}
    self.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
    self.mgr:Update()
    lu.assertNil(fish.MoveName)
    lu.assertNil(payloads[#payloads].move)
end

function TestShrimpCombat:test_shrimp_stun_cancels_warning_and_restarts_after_five_seconds()
    local fish = drop(self, 'fish15Elite')
    self.mgr:Update()
    self.now = 15; self.mgr:Update()
    lu.assertEquals(fish.State, 'stunned')
    lu.assertNil(fish.Move)
    lu.assertEquals(fish.WakeAt, 20)
    self.now = 19.9; self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 0)
    self.now = 20; self.mgr:Update()
    lu.assertEquals(fish.State, 'combat')
    lu.assertNotNil(fish.Move)
end
function TestShrimpCombat:test_dragon_rain_six_ticks_then_dive_and_stun_are_mutually_exclusive()
    local fish = drop(self, 'fish16Boss')
    self.mgr:Update()
    self.now = 1.5; self.mgr:Update()
    lu.assertEquals(self.vitalsCalls[1][3], 50)
    self.now = 30; self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'rain')
    local start = #self.vitalsCalls
    for t = 31, 36 do
        self.now = t; self.mgr:Update(); self.mgr:Update()
    end
    lu.assertEquals(#self.vitalsCalls - start, 6)
    lu.assertEquals(fish.Move.Name, 'dive')
    self.now = 37; self.mgr:Update()
    lu.assertTrue(fish.Carrier.Body.Position.y > fish.Move.Center.y)
    self.now = 38; self.mgr:Update(); self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls - start, 7)
    lu.assertEquals(fish.State, 'stunned')
    lu.assertEquals(fish.WakeAt, 43)
    self.now = 42.9; self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls - start, 7)
    self.now = 60; self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'rain')
end
function TestShrimpCombat:test_remove_and_timeout_cancel_moves_and_stun()
    local fish = drop(self, 'fish16Boss')
    self.now = 30; self.mgr:Update()
    self.mgr:Remove(fish)
    self.now = 40; self.mgr:Update()
    lu.assertNil(fish.Move)
    lu.assertEquals(#self.vitalsCalls, 0)
    fish = drop(self, 'fish15Elite')
    self.mgr:Update()
    self.now = fish.FleeAt; self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertNil(fish.Move)
    lu.assertNil(fish.WakeAt)
end
function TestShrimpCombat:test_tail_rejected_hit_does_not_displace_and_downed_cancels()
    local fish = drop(self, 'fish15Elite')
    self.mgr:Update()
    self.now = 2; self.mgr:Update()
    self.now = 4; self.mgr:Update()
    local cp = self.player.Character.Position
    self.mgr.Vitals.ApplyHit = function() return false end
    self.now = 6; self.mgr:Update()
    lu.assertEquals(self.player.Character.Position, cp)
    self.downed[self.player] = true
    self.mgr:Update()
    lu.assertNil(fish.Move)
end

function TestShrimpCombat:test_shrimp_combo_is_two_hits_then_tail_with_no_duplicate_frame()
    local fish = drop(self, 'fish15Elite')
    self.mgr:Update()
    lu.assertNotNil(fish.Move)
    for _, t in ipairs({ 2, 4, 6 }) do self.now = t; self.mgr:Update(); self.mgr:Update() end
    lu.assertEquals(#self.vitalsCalls, 3)
    for _, call in ipairs(self.vitalsCalls) do lu.assertEquals(call[3], 20) end
    local p = fish.Carrier.Body.Position
    lu.assertAlmostEquals(self.player.Character.Position.z, p.z + 4, 1e-6)
    lu.assertAlmostEquals(self.player.Character.Position.y, p.y + 1, 1e-6)
end
