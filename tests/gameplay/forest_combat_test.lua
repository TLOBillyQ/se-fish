-- #141 树林岛精英 / 首领战斗（剑鱼 fish31Elite Combat='swordfish'、三头鲨 fish32Boss Combat='shark'）：
-- 上岸放下后进战斗，追最近 / 最高仇恨的活着玩家，移速取鱼种 Speed=12；逃跑时限 剑鱼 180 / 三头鲨 300。
-- 剑鱼：左右挥头按表基础攻击 20；跳跃周期按表 50 秒、随机 10 米外落点、5 米范围 100 伤害。
-- 三头鲨：扫头按表 25、冷却 3 秒；翻滚移动有接触伤害（基础攻击 25 独立段，同一秒槽每玩家只结算一次）；
-- 跳跃取正文每 20 秒、随机 15 米外、10 米范围 200。
-- 失败方式（先列后写）：
--   1. 放下不进战斗（当普通鱼逃了）、不追人，或追击速度不取鱼种 Speed=12；
--   2. 挥头 / 扫头节奏错：起手帧就结算、超标伤害、或不取表基础攻击（20 / 25），同一击按帧重复；
--   3. 头部区失效：身后 / 正侧面仍被扫到，或正前头区反而不结算；
--   4. 跳跃周期错：提前 / 不到点就跳（剑鱼 50 秒、三头鲨 20 秒），或落点距离 / 范围 / 伤害与原表不符；
--   5. 翻滚接触：不结算、伤害不取 25、或同一秒槽同一玩家重复结算（超额伤害）；
--   6. 空中跳跃期间按落水误判直接逃脱，或落地前后位移 / 高度不连续；
--   7. 逃跑时限到 / 被移除不打断进行中的招式，仍结算剩余伤害。
local lu = require('luaunit')
require('tests.gameplay.gar_combat_test')

TestForestCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestForestCombat[name] = TestGarCombat[name]
end

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 放下鱼并把目标玩家摆到鱼身 (0, dz) 处；返回鱼与伤害记录表
local function drop(self, fishId, dz)
    self:prepare()
    local damages = {}
    self.player.Character.Controller.Health = 9000
    self.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    local fish = self:heldFish(self.player, fishId)
    self.mgr:Drop(self.player)
    lu.assertEquals(fish.State, 'combat')
    local p = fish.Carrier.Body.Position
    self.player.Character.Position = vec(p.x, 2, p.z + (dz or 2))
    self.other.Character.Controller.Health = 0
    return fish, damages
end

-- ===== 剑鱼 =====

function TestForestCombat:test_swordfish_drop_chases_and_flees_at_180()
    local fish = drop(self, 'fish31Elite', 20)
    lu.assertEquals(fish.FleeAt, 180)
    local body = fish.Carrier.Body
    local z0 = body.Position.z
    self.now = 0
    self.mgr:Update() -- 首帧 dt=0，不位移
    lu.assertAlmostEquals(body.Position.z, z0, 1e-9)
    self.now = 0.5
    self.mgr:Update()
    lu.assertAlmostEquals(body.Position.z - z0, 12 * 0.5, 1e-6, '追击步长 = Speed × dt')
    lu.assertNil(fish.Move, '追击帧不起手')
    self.now = 180
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertTrue(fish.StraightEscape)
end

function TestForestCombat:test_swordfish_head_swing_20_damage_on_cadence()
    local fish, damages = drop(self, 'fish31Elite', 2)
    self.now = 0
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'swing')
    lu.assertEquals(damages, {}, '起手帧只是预警')
    self.mgr:Update() -- 同击重复帧不重复结算
    lu.assertEquals(damages, {})
    self.now = 2 -- SwingCooldownSec
    self.mgr:Update()
    lu.assertEquals(damages, { 20 })
    lu.assertEquals(#self.vitalsCalls, 1)
    lu.assertEquals(self.vitalsCalls[1][1].source, fish)
    lu.assertEquals(self.vitalsCalls[1][1].category, 'fishAttack')
    -- 预警中绕到身后（仍在咬距内）：锁定朝向不跟着转头，结算落空
    local p = fish.Carrier.Body.Position
    self.now = 2.1
    self.mgr:Update() -- 冷却过后重新起手，朝向锁定 +z
    lu.assertEquals(fish.Move.Name, 'swing')
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9)
    self.player.Character.Position = vec(p.x, 2, p.z - 2)
    self.now = 2.5
    self.mgr:Update() -- 预警中不转头
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9)
    self.now = 2.1 + 2
    self.mgr:Update() -- 结算帧：身后算后身，不结算
    lu.assertEquals(damages, { 20 })
end

function TestForestCombat:test_swordfish_jumps_every_50s_ten_meters_five_radius_hundred()
    local fish, damages = drop(self, 'fish31Elite', 20)
    local body = fish.Carrier.Body
    local savedRandom = math.random
    math.random = function() return 0 end -- 落点方向固定为 +x
    self.now = 0
    self.mgr:Update()
    self.now = 49.9
    self.mgr:Update()
    lu.assertNil(fish.Move, '50 秒前不得起跳')
    self.now = 50
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'jump')
    local dest = fish.Move.Destination
    lu.assertAlmostEquals(dest.x - body.Position.x, 10, 1e-6, '随机 10 米外落点')
    lu.assertAlmostEquals(dest.z - body.Position.z, 0, 1e-6)
    math.random = savedRandom
    -- 落在落点 5 米内的玩家吃 100
    self.player.Character.Position = vec(dest.x, 2, dest.z)
    self.now = 50 + 1.5 * 0.5
    self.mgr:Update()
    lu.assertEquals(damages, {}, '飞行中不结算')
    self.now = 50 + 1.5
    self.mgr:Update()
    lu.assertEquals(damages, { 100 })
    lu.assertAlmostEquals(body.Position.x, dest.x, 1e-6, '落地停在落点')
end

-- ===== 三头鲨 =====

function TestForestCombat:test_shark_drop_chases_and_flees_at_300()
    local fish = drop(self, 'fish32Boss', 20)
    lu.assertEquals(fish.FleeAt, 300)
    local body = fish.Carrier.Body
    local z0 = body.Position.z
    self.now = 0
    self.mgr:Update()
    self.now = 0.5
    self.mgr:Update()
    lu.assertAlmostEquals(body.Position.z - z0, 12 * 0.5, 1e-6)
    self.now = 300
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
end

function TestForestCombat:test_shark_head_sweep_25_on_three_second_cadence()
    local fish, damages = drop(self, 'fish32Boss', 2)
    self.now = 0
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'sweep')
    lu.assertEquals(damages, {}, '起手帧只是预警')
    self.mgr:Update()
    lu.assertEquals(damages, {})
    self.now = 3
    self.mgr:Update()
    lu.assertEquals(damages, { 25 })
end

function TestForestCombat:test_shark_roll_contact_25_dedup_per_second_slot()
    local fish = drop(self, 'fish32Boss', 20) -- 目标玩家在 20 米外
    local body = fish.Carrier.Body
    self.other.Character.Controller.Health = 9000
    local rolled = {}
    self.other.Character.Controller.TakeDamage = function(_, d) rolled[#rolled + 1] = d end
    -- 仇恨落在远处玩家：追击目标仍是 player，贴身的 other 被“滚到”
    self.mgr:NoteDamage(fish, self.player, 30)
    self.other.Character.Position = vec(body.Position.x, 2, body.Position.z + 2)
    self.now = 0
    self.mgr:Update()
    lu.assertEquals(rolled, { 25 })
    self.mgr:Update() -- 同秒槽重复帧不重复结算
    lu.assertEquals(rolled, { 25 })
    -- 下一秒槽再结算一次
    self.other.Character.Position = vec(body.Position.x, 2, body.Position.z + 2)
    self.now = 1
    self.mgr:Update()
    lu.assertEquals(rolled, { 25, 25 })
end

function TestForestCombat:test_shark_jumps_every_20s_fifteen_meters_ten_radius_two_hundred()
    local fish, damages = drop(self, 'fish32Boss', 20)
    local body = fish.Carrier.Body
    local savedRandom = math.random
    math.random = function() return 0 end
    self.now = 0
    self.mgr:Update()
    self.now = 19.9
    self.mgr:Update()
    lu.assertNil(fish.Move, '20 秒前不得起跳')
    self.now = 20
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'jump')
    local dest = fish.Move.Destination
    lu.assertAlmostEquals(dest.x - body.Position.x, 15, 1e-6)
    math.random = savedRandom
    self.player.Character.Position = vec(dest.x, 2, dest.z)
    self.now = 20 + 1.5
    self.mgr:Update()
    lu.assertEquals(damages, { 200 })
end

function TestForestCombat:test_combat_payload_carries_move_names()
    local fish = drop(self, 'fish32Boss', 2)
    local payloads = {}
    self.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
    self.now = 0
    self.mgr:Update()
    lu.assertEquals(payloads[#payloads].move, 'sweep')
    lu.assertEquals(payloads[#payloads].fishId, 'fish32Boss')
end
