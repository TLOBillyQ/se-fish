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
--   7. 逃跑时限到 / 被移除不打断进行中的招式，仍结算剩余伤害；
--   8. 高跃位移失败（引擎拒绝写 Position）仍按预定落点结算落地伤害、不收招式 / 预警；
--   9. 追击位移失败后仍按「没滚到的」目标位置结算，而不是按真实位置；
--  10. 单一玩家被翻滚追击贴到时不结算接触伤害（只有多人贴身才算），或接触与扫头同帧并发多扣。
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

-- 把载体 Body 换成「写 Position 会报错、其余透传」的代理，模拟引擎位移失败（真实边界）。
local function breakPosition(fish)
    local real = fish.Carrier.Body
    fish.Carrier.Body = setmetatable({}, {
        __index = function(_, key)
            if key == 'Position' then return real.Position end
            return real[key]
        end,
        __newindex = function(_, key, value)
            if key == 'Position' then error('position-write-failed') end
            real[key] = value
        end,
    })
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
    self.now = 0.1
    self.mgr:Update() -- 首个真实滚动帧才结算接触
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
    damages = {} -- 只记录本次高跃，此前真实翻滚接触另有用例覆盖
    self.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
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

-- ===== 位移失败（引擎拒绝写 Position）：招式作废、不按预定落点结算 =====

function TestForestCombat:test_jump_midflight_displacement_failure_cancels_without_landing_damage()
    local fish, damages = drop(self, 'fish31Elite', 20)
    local savedRandom = math.random
    math.random = function() return 0 end
    self.now = 0
    self.mgr:Update()
    self.now = 50
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'jump')
    local dest = fish.Move.Destination
    math.random = savedRandom
    self.player.Character.Position = vec(dest.x, 2, dest.z) -- 落点范围内有玩家
    breakPosition(fish)
    self.now = 50 + 1.5 * 0.5
    self.mgr:Update() -- 飞行中段位移失败
    lu.assertNil(fish.Move, '中段位移失败必须取消招式 / 收起预警')
    lu.assertEquals(damages, {}, '位移失败不得按预定落点结算落地伤害')
    self.now = 50 + 1.5
    self.mgr:Update() -- 到点也不得补结算
    lu.assertEquals(damages, {}, '取消后不得补结算落地伤害')
end

function TestForestCombat:test_jump_final_frame_displacement_failure_cancels_without_landing_damage()
    local fish, damages = drop(self, 'fish31Elite', 20)
    local savedRandom = math.random
    math.random = function() return 0 end
    self.now = 0
    self.mgr:Update()
    self.now = 50
    self.mgr:Update()
    local dest = fish.Move.Destination
    math.random = savedRandom
    self.player.Character.Position = vec(dest.x, 2, dest.z)
    breakPosition(fish)
    self.now = 50 + 1.5
    self.mgr:Update() -- 结算帧位移失败
    lu.assertNil(fish.Move, '最终帧位移失败必须取消招式 / 收起预警')
    lu.assertEquals(damages, {}, '最终帧位移失败不得结算落地伤害')
end

-- ===== 翻滚接触：单人追击贴到也结算，且按真实位置 =====

function TestForestCombat:test_shark_roll_contact_hits_the_single_chased_target()
    local fish, damages = drop(self, 'fish32Boss', 20) -- other 已倒下，唯一玩家就是目标
    self.now = 0
    self.mgr:Update() -- 首帧 dt=0 不位移
    lu.assertEquals(damages, {})
    self.now = 2
    self.mgr:Update() -- 翻滚 17.5 米贴到咬距边缘：滚到唯一玩家
    lu.assertEquals(damages, { 25 }, '单人追击也要结算翻滚接触伤害')
    lu.assertNil(fish.Move, '接触伤害是独立段，不与扫头同帧并发')
end

function TestForestCombat:test_roll_contact_uses_actual_position_when_chase_fails()
    local fish = drop(self, 'fish32Boss', 20)
    self.other.Character.Controller.Health = 9000
    local rolled = {}
    self.other.Character.Controller.TakeDamage = function(_, d) rolled[#rolled + 1] = d end
    self.now = 0
    self.mgr:Update()
    local start = fish.Carrier.Body.Position
    -- 第二名玩家摆在「本该滚到」的位置（追击路径中段）
    self.other.Character.Position = vec(start.x, 2, start.z + 10)
    breakPosition(fish) -- 位移失败：鱼实际没有滚过去
    self.now = 1
    self.mgr:Update()
    lu.assertEquals(rolled, {}, '位移失败不得按未到达的滚动路径结算接触')
end

-- ===== 追击失败必须可诊断，且不能造成计划路径伤害 =====
function TestForestCombat:test_chase_failure_logs_module_operation_fish_and_error()
    for _, id in ipairs({ 'fish31Elite', 'fish32Boss' }) do
        local fish, damages = drop(self, id, 20)
        self.now = 0
        self.mgr:Update()
        breakPosition(fish)
        local savedPrint, lines = print, {}
        print = function(...)
            local words = {}
            for _, value in ipairs({ ... }) do words[#words + 1] = tostring(value) end
            lines[#lines + 1] = table.concat(words, ' ')
        end
        self.now = 1
        local ok, err = pcall(function() self.mgr:Update() end)
        print = savedPrint
        lu.assertTrue(ok, tostring(err))
        local text = table.concat(lines, '\n')
        lu.assertStrContains(text, '[MgrFishUnit]')
        lu.assertStrContains(text, '追击位移失败')
        lu.assertStrContains(text, 'fish=' .. tostring(fish.Id))
        lu.assertStrContains(text, 'position-write-failed')
        lu.assertEquals(damages, {})
        self.mgr:Remove(fish)
    end
end

-- ===== 高跃预警：整圆范围（含后方），不是 90° 扇形 =====

function TestForestCombat:test_jump_warning_is_full_circle_landing_range()
    local fish = drop(self, 'fish31Elite', 20)
    local savedRandom = math.random
    math.random = function() return 0 end
    self.now = 0
    self.mgr:Update()
    self.notices = {}
    self.now = 50
    self.mgr:Update()
    math.random = savedRandom
    local lock
    for _, notice in ipairs(self.notices) do
        if notice.kind == 'lock' and notice.move == 'jump' then lock = notice end
    end
    lu.assertNotNil(lock, '到点没有起跳预警')
    lu.assertEquals(lock.shape, 'circle', '高跃落地是整圆范围，不是 90° 扇形')
    lu.assertEquals(lock.halfAngleDeg, 180)
    lu.assertAlmostEquals(lock.range, 5, 1e-9, '预警半径取 JumpRadius')
end
