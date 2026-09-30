-- #136 帝王蟹（fish23Elite，Combat='kingCrab'，GameSpec §12 正文与钓鱼表 R42）：
-- 上岸放下后进战斗，移速 10 追最近活着的玩家；进 2.5 米即起手乱刺（预警），
-- 每 5 秒一轮：左右钳各 3 下、每下间隔 0.2 秒、每下 15 伤害；每活动 30 秒眩晕 5 秒。
-- 失败方式（先列后写）：
--   1. 放下不进战斗、不追人，或追击速度不取鱼种 Speed=10；
--   2. 乱刺节奏错：不到 5 秒就连刺、一轮不是左右各 3 下、间隔不是 0.2 秒、伤害不取 15；
--   3. 同一刺段按帧重复结算（一轮超过 6 次伤害），或掉帧大 dt 补刺超额；
--   4. 逃跑时限到 / 入水不打断进行中的乱刺，仍结算剩余刺段；
--   5. 活动 30 秒后不眩晕 / 眩晕不足 5 秒，或眩晕期间仍起刺 / 仍结算伤害；
--   6. 眩晕醒来后计时错位：醒来立刻眩晕，或醒来后第一轮乱刺提前；
--   7. 预警残留：乱刺结束 / 逃跑 / 移除后客户端预警不收起（GarBiteNotice 缺 clear）；
--   8. 头顶标签缺新招式名：客户端拿到 move=jab 显示「攻击」之外的乱码（本单只钉协议字段）。
local lu = require('luaunit')
require('tests.gameplay.gar_combat_test')

TestKingCrabCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestKingCrabCombat[name] = TestGarCombat[name]
end

local function drop(self)
    self:prepare()
    self.player.Character.Controller.Health = 2000
    self.player.Character.Controller.TakeDamage = function() end
    local fish = self:heldFish(self.player, 'fish23Elite')
    self.mgr:Drop(self.player)
    lu.assertEquals(fish.State, 'combat')
    lu.assertEquals(fish.FleeAt, 180) -- EscapeSec=180
    local p = fish.Carrier.Body.Position
    -- 目标站进咬距：第一次 Update 即起手乱刺预警
    self.player.Character.Position = { x = p.x, y = p.y, z = p.z + 1 }
    self.other.Character.Controller.Health = 0
    return fish
end

-- 乱刺节奏：5 秒一轮、左右各 3 下、间隔 0.2、每下 15；起手帧是预警不结算，
-- 六刺在 0.2、0.4、0.6、0.8、1.0、1.2 秒各结算一次（1.2 秒第六刺与收招同帧，先结算再收招）。
-- 同一刺段重复帧不重复结算；掉帧只补当前刺段不追溯。
function TestKingCrabCombat:test_jab_combo_six_strikes_every_five_seconds_once_per_slot()
    local fish = drop(self)
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'jab')
    lu.assertEquals(#self.vitalsCalls, 0, '起手帧只是预警')
    for i, t in ipairs({ 0.2, 0.4, 0.6, 0.8, 1.0, 1.2 }) do
        self.now = t
        self.mgr:Update()
        self.mgr:Update() -- 同一刺段重复帧不重复结算
        lu.assertEquals(#self.vitalsCalls, i, '第 ' .. i .. ' 刺')
        lu.assertEquals(self.vitalsCalls[#self.vitalsCalls][3], 15)
    end
    lu.assertNil(fish.Move, '1.2 秒第六刺结算即收招')
    lu.assertEquals(self.notices[#self.notices].kind, 'clear')
    self.now = 4.99
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 6, '第二轮提前起刺')
    self.now = 5
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 6, '第二轮起手帧只是预警')
    self.now = 5.2
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 7)
    -- 掉帧大 dt：一轮只补当前刺段，不追溯历史
    self.now = 11.6
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 8, '大 dt 不得补刺')
end

-- 活动 30 秒眩晕 5 秒：眩晕中不起刺不结算；醒来后重新计活动与乱刺节拍
function TestKingCrabCombat:test_stun_after_thirty_seconds_no_jab_while_stunned()
    local fish = drop(self)
    self.mgr:Update()
    self.now = 30
    self.mgr:Update()
    lu.assertEquals(fish.State, 'stunned')
    lu.assertNil(fish.Move)
    lu.assertEquals(fish.WakeAt, 35)
    lu.assertEquals(#self.vitalsCalls, 0)
    self.now = 34.9
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 0, '眩晕期间不得起刺')
    self.now = 35
    self.mgr:Update()
    lu.assertEquals(fish.State, 'combat')
    lu.assertNotNil(fish.Move)
    lu.assertEquals(fish.Move.Name, 'jab')
    -- 醒来后重新计时：40 秒时不眩晕，65 秒才第二轮眩晕
    self.now = 64.9
    self.mgr:Update()
    lu.assertEquals(fish.State, 'combat')
    self.now = 65
    self.mgr:Update()
    lu.assertEquals(fish.State, 'stunned')
end

-- 逃跑打断：乱刺进行中逃跑时限到，清招式、收预警、直线逃脱不再结算
function TestKingCrabCombat:test_flee_interrupts_jab_and_clears_warning()
    local fish = drop(self)
    self.mgr:Update()
    self.now = 0.4
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 1) -- 0.4 结算第一刺（起手帧只是预警）
    lu.assertNotNil(fish.Move)
    self.now = 180
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertTrue(fish.StraightEscape)
    lu.assertNil(fish.Move)
    lu.assertEquals(self.notices[#self.notices].kind, 'clear')
    lu.assertEquals(self.notices[#self.notices].reason, 'gone')
    self.now = 181
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 1, '逃脱后不得结算剩余刺段')
end

-- 移除打断：乱刺进行中鱼被打死清场，预警收起不再结算
function TestKingCrabCombat:test_remove_during_jab_clears_warning_and_stops_strikes()
    local fish = drop(self)
    self.mgr:Update()
    self.now = 0.4
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 1) -- 起手帧只是预警，0.4 第一刺
    self.mgr:Remove(fish)
    lu.assertEquals(self.notices[#self.notices].kind, 'clear')
    lu.assertEquals(self.notices[#self.notices].reason, 'gone')
    self.now = 1
    self.mgr:Update()
    lu.assertEquals(#self.vitalsCalls, 1)
end

-- 战斗快照带招式名：客户端标签协议字段 move='jab'
function TestKingCrabCombat:test_combat_payload_carries_jab_move_name()
    local fish = drop(self)
    local payloads = {}
    self.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
    self.mgr:Update()
    lu.assertEquals(payloads[#payloads].move, 'jab')
end
