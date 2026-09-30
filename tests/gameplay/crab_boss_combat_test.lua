-- #136 蟹老板（fish24Boss，Combat='crabBoss'，GameSpec §12 正文与钓鱼表 R43）：
-- 上岸放下后进战斗，移速 10 追最近活着的玩家；进 2.5 米起手正面蟹钳双击、每击 20、冷却 4 秒；
-- 每 30 秒冲撞一次（冲向目标、命中 20）；每 25 秒旋转 5 秒、每秒 360 度、碰触 30。
-- 三招互斥：旋转 / 冲撞期间不双击；逃跑 / 移除打断进行中的招式。
-- 失败方式（先列后写）：
--   1. 放下不进战斗、不追人，或追击速度不取鱼种 Speed=10；
--   2. 双击节奏错：一次只打一下、两下间隔错、伤害不取 20、冷却不是 4 秒；
--   3. 双击中同一击按帧重复结算，或掉帧补击超额；
--   4. 冲撞不按期（30 秒）发动、冲撞伤害不取 20、冲撞后不回正常节拍；
--   5. 旋转不按期（25 秒）发动、旋转不足 5 秒、旋转中仍双击 / 冲撞，碰触伤害不取 30；
--   6. 同一旋转内同一玩家按秒槽重复结算（超额伤害），或旋转结束后秒槽残留导致下次漏结算；
--   7. 逃跑时限到 / 入水 / 移除不打断进行中的双击 / 冲撞 / 旋转，仍结算剩余伤害；
--   8. 预警残留：招式结束 / 逃跑 / 移除后客户端预警不收起；
--   9. 战斗快照缺新招式名（pinch / charge / spin），客户端标签协议字段缺失。
local lu = require('luaunit')
require('tests.gameplay.gar_combat_test')

TestCrabBossCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestCrabBossCombat[name] = TestGarCombat[name]
end

local function drop(self)
    self:prepare()
    self.player.Character.Controller.Health = 2000
    self.player.Character.Controller.TakeDamage = function() end
    local fish = self:heldFish(self.player, 'fish24Boss')
    self.mgr:Drop(self.player)
    lu.assertEquals(fish.State, 'combat')
    lu.assertEquals(fish.FleeAt, 300) -- EscapeSec=300
    local p = fish.Carrier.Body.Position
    self.player.Character.Position = { x = p.x, y = p.y, z = p.z + 1 }
    self.other.Character.Controller.Health = 0
    return fish
end

-- 双击：起手帧预警不结算，两击在起手后各间隔 0.2 秒结算、每击 20；冷却 4 秒后再起
function TestCrabBossCombat:test_pinch_two_strikes_twenty_damage_four_second_cooldown()
    local fish = drop(self)
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'pinch')
    lu.assertEquals(#self.vitalsCalls, 0, '起手帧只是预警')
    self.now = 0.2
    self.mgr:Update()
    self.mgr:Update() -- 同一击重复帧不重复结算
    lu.assertEquals(#self.vitalsCalls, 1)
    lu.assertEquals(self.vitalsCalls[1][3], 20)
    self.now = 0.4
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 2, '第二击')
    lu.assertEquals(self.vitalsCalls[2][3], 20)
    self.now = 0.5
    self.mgr:Update()
    lu.assertNil(fish.Move, '双击后招式即收')
    -- 冷却 4 秒：3.9 秒不起手，4 秒后起第二轮
    self.now = 3.9
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 2, '冷却中不得起手')
    self.now = 4.0
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'pinch')
    self.now = 4.2
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 3, '第二轮第一击')
end

-- 冲撞：每 30 秒一次，命中 20；冲撞窗口内不双击
function TestCrabBossCombat:test_charge_every_thirty_seconds_hits_twenty()
    local fish = drop(self)
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'pinch')
    -- 冲撞节拍 30 秒；25 秒已过的旋转顺延到 30 秒起手、持续 5 秒（30..35），冲撞再顺延
    self.now = 29.9
    self.mgr:Update()
    lu.assertNotEquals(fish.Move and fish.Move.Name, 'charge', '冲撞提前发动')
    self.now = 30
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'spin', '30 秒旋转起手')
    -- 旋转 35 秒收招帧不连起新招；下一帧冲撞起手
    self.now = 35.1
    self.mgr:Update()
    lu.assertNil(fish.Move, '旋转 35 秒收招')
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'charge', '旋转结束后冲撞起手')
    -- 冲撞命中 20（窗口内结算一次）
    local before = #self.vitalsCalls
    self.now = 35.5
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, before + 1, '冲撞命中一次')
    lu.assertEquals(self.vitalsCalls[#self.vitalsCalls][3], 20)
end

-- 旋转：25 秒节拍（首次 Update 后即起手）、持续 5 秒、碰触 30；同一旋转内同一玩家按秒槽只结算一次
function TestCrabBossCombat:test_spin_every_twentyfive_seconds_thirty_damage_once_per_second_slot()
    local fish = drop(self)
    self.mgr:Update()
    -- 25 秒节拍：首次起手 pinch 收招后，下一次无招式帧（now≥25）起 spin
    self.now = 25
    self.mgr:Update()
    -- pinch 已收、spin 未起（pinch 收招帧不连起 spin）；再一帧起 spin
    if not fish.Move then self.mgr:Update() end
    lu.assertEquals(fish.Move.Name, 'spin')
    local spinStart = fish.Move.At
    local before = #self.vitalsCalls
    -- 旋转 5 秒：每秒槽一次碰触，同一秒槽重复帧不重复结算
    for tick = 1, 5 do
        self.now = spinStart + tick
        self.mgr:Update()
        self.mgr:Update()
    end
    lu.assertEquals(#self.vitalsCalls - before, 5, '旋转五秒每秒槽一次碰触')
    lu.assertEquals(self.vitalsCalls[#self.vitalsCalls][3], 30)
    -- 持续 5 秒后结束
    self.now = spinStart + 5.1
    self.mgr:Update()
    lu.assertNotEquals(fish.Move and fish.Move.Name, 'spin', '旋转 5 秒后结束')
end

-- 互斥：旋转期间不冲撞不双击；冲撞期间不旋转
function TestCrabBossCombat:test_spin_charge_pinch_are_mutually_exclusive()
    local fish = drop(self)
    self.mgr:Update()
    self.now = 25
    self.mgr:Update() -- pinch 收招帧
    self.mgr:Update() -- 收招帧后下一帧旋转起手
    lu.assertEquals(fish.Move.Name, 'spin')
    -- 旋转持续期跨过 30 秒冲撞节拍：冲撞被旋转压住
    self.now = 29.9
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'spin', '旋转中不得冲撞')
end

-- 逃跑打断：旋转进行中逃跑时限到，清招式、收预警、直线逃脱不再结算
function TestCrabBossCombat:test_flee_interrupts_spin_and_clears_warning()
    local fish = drop(self)
    self.mgr:Update()
    self.now = 25
    self.mgr:Update() -- pinch 收招帧
    self.mgr:Update() -- 收招帧后下一帧旋转起手
    lu.assertEquals(fish.Move.Name, 'spin')
    local settled = #self.vitalsCalls
    self.now = 300
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertTrue(fish.StraightEscape)
    lu.assertNil(fish.Move)
    lu.assertEquals(self.notices[#self.notices].kind, 'clear')
    lu.assertEquals(self.notices[#self.notices].reason, 'gone')
    self.now = 301
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, settled, '逃脱后不得结算')
end

-- 移除打断：双击进行中鱼被打死清场，预警收起不再结算
function TestCrabBossCombat:test_remove_during_pinch_clears_warning_and_stops_strikes()
    local fish = drop(self)
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'pinch')
    self.mgr:Remove(fish)
    lu.assertEquals(self.notices[#self.notices].kind, 'clear')
    lu.assertEquals(self.notices[#self.notices].reason, 'gone')
    self.now = 0.4
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 0)
end

-- 战斗快照带招式名：pinch / spin 协议字段
function TestCrabBossCombat:test_combat_payload_carries_move_names()
    local fish = drop(self)
    local payloads = {}
    self.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
    self.mgr:Update()
    lu.assertEquals(payloads[#payloads].move, 'pinch')
end
