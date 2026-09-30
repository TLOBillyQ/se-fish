-- #142 沙滩岛精英 / 首领战斗（海象 fish39Elite Combat='walrus'、虎鲸 fish40Boss Combat='orca'）：
-- 上岸放下后进战斗，追最近 / 最高仇恨的活着玩家，移速取鱼种 Speed（海象 11 / 虎鲸 13）；
-- 逃跑时限 海象 180 / 虎鲸 300。
-- 海象（#121 裁定 / 钓鱼表 R70 / 正文第五关）：甩头按表基础攻击 25（起手即锁定朝向的预警）；
-- 突击周期按表 40 秒（覆盖正文旧 20 秒），直线冲锋 20 米、对撞到的玩家一次 120（取正文）。
-- 虎鲸（#121 裁定 / 钓鱼表 R71 / 正文第五关）四招并集、互斥不丢：爪击按表 30、间隔 2 秒（进身触发）；
-- 表内每 10 秒虎啸远程攻击（未给伤，按独立基础 30 披露细化）；正文每 10 秒甩尾、对后方 160；
-- 跳跃周期按表 25 秒（覆盖正文旧 20 秒）、随机 15 米外落点、10 米范围 240。
-- 失败方式（先列后写）：
--   1. 放下不进战斗（当普通鱼逃了）、不追人，或追击速度不取鱼种 Speed；
--   2. 甩头节奏错：起手帧就结算、超标伤害、不取表 25，或同一击按帧重复；
--   3. 头部区失效：身后 / 正侧面仍被甩到，或正前头区反而不结算；
--   4. 突击周期错：提前 / 不到点就冲（40 秒），或冲程 / 伤害与原表不符（20 米 / 120）；
--   5. 突击接触错：路径外的玩家被「隔空」撞到，或路径上的玩家不被结算 / 按帧重复结算；
--   6. 突击位移失败（引擎拒绝写 Position）仍按预定冲锋路径结算伤害、不收招式 / 预警；
--   7. 突击预警期间跟着目标转头（直线冲锋变跟踪导弹），或预警中目标倒下仍落地结算；
--   8. 追击 / 突击位移失败后无日志传播，无法诊断；
--   9. 单人贴身时甩头互斥分支覆盖接触 / 追击结算（海象贴身只走甩头，冷却帧不得并发突击）；
--  10. 虎鲸四招丢招 / 并发的：爪击不取 30 / 2 秒、虎啸不到 10 秒或不按远程 30 结算、
--      甩尾不打身后 / 打到身前、鲸跃周期 / 落点 / 范围 / 伤害错（25 秒 / 15 米 / 10 米 / 240）；
--  11. 虎鲸位移失败（追击 / 鲸跃）仍按预定位置结算或无日志。
local lu = require('luaunit')
require('tests.gameplay.forest_combat_test')

TestBeachCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestBeachCombat[name] = TestForestCombat[name]
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

local function walrusParams() return require('common.GameCfg').FishCombat.walrus end

-- 推进到 40 秒突击节拍并等预警起手（40 秒帧可能压着上一记甩头的预警，做有界等待）；
-- 返回起手的 charge move 与鱼身位置（预警 / 冲锋期间位置不变）。
local function startCharge(self, fish)
    for t = 0.5, 39.5, 0.5 do self.now = t self.mgr:Update() end
    self.now = 40
    self.mgr:Update()
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'charge') and guard < 50 do
        self.now = self.now + 0.1
        self.mgr:Update()
        guard = guard + 1
    end
    lu.assertNotNil(fish.Move, '40 秒起到突击预警')
    lu.assertEquals(fish.Move.Name, 'charge')
    return fish.Move, fish.Carrier.Body.Position
end

-- ===== 海象：追击与逃跑时限 =====

function TestBeachCombat:test_walrus_drop_chases_and_flees_at_180()
    local fish = drop(self, 'fish39Elite', 20)
    lu.assertEquals(fish.FleeAt, 180)
    local body = fish.Carrier.Body
    local z0 = body.Position.z
    self.now = 0
    self.mgr:Update() -- 首帧 dt=0，不位移
    lu.assertAlmostEquals(body.Position.z, z0, 1e-9)
    self.now = 0.5
    self.mgr:Update()
    lu.assertAlmostEquals(body.Position.z - z0, 11 * 0.5, 1e-6, '追击步长 = Speed(11) × dt')
    lu.assertNil(fish.Move, '追击帧不起手')
    self.now = 180
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertTrue(fish.StraightEscape)
end

-- ===== 海象：甩头 25，起手即锁定朝向 =====

function TestBeachCombat:test_walrus_head_swing_25_on_cadence()
    local fish, damages = drop(self, 'fish39Elite', 2)
    self.now = 0
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'swing')
    lu.assertEquals(damages, {}, '起手帧只是预警')
    self.mgr:Update() -- 同击重复帧不重复结算
    lu.assertEquals(damages, {})
    self.now = 2 -- SwingCooldownSec（配置细化）
    self.mgr:Update()
    lu.assertEquals(damages, { 25 })
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
    lu.assertEquals(damages, { 25 })
end

-- ===== 海象：40 秒突击，直线冲锋 20 米、撞到 120 =====

function TestBeachCombat:test_walrus_charge_every_40s_hits_player_on_path_once()
    local fish, damages = drop(self, 'fish39Elite', 20)
    local params = walrusParams()
    local move, bp = startCharge(self, fish)
    -- 预警起手后重新记录伤害，把玩家摆到锁定冲锋方向（+z）的路径上
    damages = {}
    self.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    self.player.Character.Position = vec(bp.x, 2, bp.z + 10)
    lu.assertEquals(damages, {}, '突击预警帧不结算')
    self.now = move.At + params.ChargeWindupSec + 0.3
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'charge')
    lu.assertEquals(damages, {}, '冲锋途中不逐帧结算')
    self.now = fish.Move.StrikeAt + 0.1
    self.mgr:Update()
    lu.assertNil(fish.Move, '冲完 20 米收招')
    lu.assertEquals(damages, { 120 }, '路径上的玩家只被撞到一次 120')
    lu.assertAlmostEquals(fish.Carrier.Body.Position.z - bp.z, params.ChargeDistance, 1e-6,
        '直线冲锋 20 米')
end

function TestBeachCombat:test_walrus_charge_misses_player_off_path()
    local fish, damages = drop(self, 'fish39Elite', 20)
    local move, bp = startCharge(self, fish)
    damages = {}
    -- 路径外侧 5 米（> 接触距离 2.5）：不得被冲锋撞到
    self.player.Character.Position = vec(bp.x + 5, 2, bp.z + 10)
    self.now = move.At + require('common.GameCfg').FishCombat.walrus.ChargeWindupSec + 0.3
    self.mgr:Update()
    self.now = fish.Move.StrikeAt + 0.1
    self.mgr:Update()
    lu.assertEquals(damages, {}, '路径外的玩家不得被冲锋撞到')
end

-- 突击预警必须覆盖真实危险区：20 米冲锋走廊（双轴审查 P2，与 #141 同类合并前修复；
-- 预警 range 只给接触距离 2.5 米属严重欠警）。朝向目标的前向扇形 + 冲程半径可覆盖走廊，
-- 走廊两侧之外属横向超警（安全方向）。
function TestBeachCombat:test_walrus_charge_telegraph_covers_corridor()
    local fish = drop(self, 'fish39Elite', 20)
    local params = walrusParams()
    startCharge(self, fish)
    local lock
    for _, notice in ipairs(self.notices) do
        if notice.kind == 'lock' and notice.move == 'charge' then lock = notice end
    end
    lu.assertNotNil(lock, '突击没有发预警')
    lu.assertAlmostEquals(lock.range, params.ChargeDistance, 1e-9,
        '突击预警半径必须取冲程 20 米（走廊），不能只给接触距离')
end

function TestBeachCombat:test_walrus_charge_displacement_failure_cancels_without_damage()
    local fish, damages = drop(self, 'fish39Elite', 20)
    local params = walrusParams()
    local move, bp = startCharge(self, fish)
    damages = {}
    self.player.Character.Position = vec(bp.x, 2, bp.z + 10) -- 冲锋路径上
    breakPosition(fish) -- 引擎拒绝位移
    self.now = move.At + params.ChargeWindupSec + 0.2
    self.mgr:Update()
    lu.assertNil(fish.Move, '突击位移失败必须取消招式 / 收起预警')
    lu.assertEquals(damages, {}, '位移失败不得按预定冲锋路径结算伤害')
    self.now = 43
    self.mgr:Update()
    lu.assertEquals(damages, {}, '取消后不得补结算')
end

-- 突击预警期间锁定朝向：目标挪开也不转头（直线冲锋不是跟踪导弹）
function TestBeachCombat:test_walrus_charge_windup_locks_facing()
    local fish, damages = drop(self, 'fish39Elite', 20)
    local params = walrusParams()
    local move, bp = startCharge(self, fish)
    damages = {}
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9, '起手朝向锁定 +z')
    self.player.Character.Position = vec(bp.x, 2, bp.z - 10) -- 预警中挪到身后（仍活着）
    self.now = move.At + params.ChargeWindupSec + 0.2
    self.mgr:Update()
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9, '预警 / 冲锋期间不跟着目标转头')
    self.now = fish.Move.StrikeAt + 0.1
    self.mgr:Update()
    lu.assertEquals(damages, {}, '挪到身后的目标不得被冲锋撞到')
    lu.assertAlmostEquals(fish.Carrier.Body.Position.z - bp.z, params.ChargeDistance, 1e-6)
end

function TestBeachCombat:test_walrus_displacement_failures_log_module_fish_and_error()
    -- 追击失败日志（与 #141 同口径）
    local fish, damages = drop(self, 'fish39Elite', 20)
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
    -- 突击位移失败日志
    fish, damages = drop(self, 'fish39Elite', 20)
    local move = startCharge(self, fish)
    damages = {}
    breakPosition(fish)
    lines = {}
    print = function(...)
        local words = {}
        for _, value in ipairs({ ... }) do words[#words + 1] = tostring(value) end
        lines[#lines + 1] = table.concat(words, ' ')
    end
    self.now = move.At + require('common.GameCfg').FishCombat.walrus.ChargeWindupSec + 0.2
    local ok2, err2 = pcall(function() self.mgr:Update() end)
    print = savedPrint
    lu.assertTrue(ok2, tostring(err2))
    local text2 = table.concat(lines, '\n')
    lu.assertStrContains(text2, '[MgrFishUnit]')
    lu.assertStrContains(text2, '突击位移失败')
    lu.assertStrContains(text2, 'fish=' .. tostring(fish.Id))
    lu.assertStrContains(text2, 'position-write-failed')
    lu.assertEquals(damages, {})
end

-- ===== 虎鲸：追击与逃跑时限 =====

function TestBeachCombat:test_orca_drop_chases_and_flees_at_300()
    local fish = drop(self, 'fish40Boss', 20)
    lu.assertEquals(fish.FleeAt, 300)
    local body = fish.Carrier.Body
    local z0 = body.Position.z
    self.now = 0
    self.mgr:Update() -- 首帧 dt=0，不位移
    lu.assertAlmostEquals(body.Position.z, z0, 1e-9)
    self.now = 0.5
    self.mgr:Update()
    lu.assertAlmostEquals(body.Position.z - z0, 13 * 0.5, 1e-6, '追击步长 = Speed(13) × dt')
    lu.assertNil(fish.Move, '追击帧不起手')
    self.now = 300
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertTrue(fish.StraightEscape)
end

-- ===== 虎鲸：爪击 30、间隔 2 秒（进身触发） =====

function TestBeachCombat:test_orca_claw_30_every_2s_in_bite_range()
    local fish, damages = drop(self, 'fish40Boss', 2)
    self.now = 0
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'claw')
    lu.assertEquals(damages, {}, '起手帧只是预警')
    self.mgr:Update() -- 同击重复帧不重复结算
    lu.assertEquals(damages, {})
    for t = 0.5, 5.5, 0.5 do -- 0.5 秒帧连续推进：1 / 3 / 5 秒各结算一爪
        self.now = t
        self.mgr:Update()
    end
    lu.assertEquals(damages, { 30, 30, 30 })
    for _, d in ipairs(damages) do lu.assertEquals(d, 30) end
end

-- ===== 虎鲸：虎啸 10 秒远程 30（未给伤的独立基础披露细化），咬距外也结算 =====

function TestBeachCombat:test_orca_roar_10s_ranged_30_outside_bite_range()
    local fish, damages = drop(self, 'fish40Boss', 2)
    local params = require('common.GameCfg').FishCombat.orca
    for t = 0.5, 9.5, 0.5 do self.now = t self.mgr:Update() end
    damages = {}
    self.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    local bp = fish.Carrier.Body.Position
    self.player.Character.Position = vec(bp.x, 2, bp.z + 12) -- 咬距外、虎啸射程内
    self.now = 10
    self.mgr:Update()
    lu.assertEquals(fish.Move.Name, 'roar', '10 秒起到虎啸预警')
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9)
    lu.assertEquals(damages, {}, '虎啸预警帧不结算')
    self.now = 10.5
    self.mgr:Update()
    lu.assertEquals(damages, {}, '前摇途中不结算')
    self.now = 10 + params.RoarWindupSec
    self.mgr:Update()
    lu.assertEquals(damages, { 30 }, '咬距外的目标也被虎啸远程结算 30')
    lu.assertNil(fish.Move, '虎啸收招')
end

-- ===== 虎鲸：甩尾 10 秒 160，只打身后 =====

function TestBeachCombat:test_orca_tail_160_hits_rear_player_only()
    local fish, damages = drop(self, 'fish40Boss', 2) -- 目标玩家在身前咬距内
    self.other.Character.Controller.Health = 9000
    local rolled = {}
    self.other.Character.Controller.TakeDamage = function(_, d) rolled[#rolled + 1] = d end
    local p = fish.Carrier.Body.Position
    self.other.Character.Position = vec(p.x, 2, p.z - 4) -- 身后 4 米（甩尾半径内）
    for t = 0.5, 9.5, 0.5 do self.now = t self.mgr:Update() end
    damages = {}
    self.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    self.now = 10
    self.mgr:Update() -- 虎啸（RoarAt=10 先到，尾 At 也是 10：鲸跃 > 虎啸 > 甩尾 > 爪）
    lu.assertEquals(fish.Move.Name, 'roar')
    self.now = 11
    self.mgr:Update() -- 虎啸结算（身前目标 30），随后让位甩尾
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'tail') and guard < 50 do
        self.now = self.now + 0.1
        self.mgr:Update()
        guard = guard + 1
    end
    lu.assertEquals(fish.Move.Name, 'tail')
    self.now = fish.Move.StrikeAt + 0.1
    self.mgr:Update()
    lu.assertEquals(rolled, { 160 }, '身后的玩家被甩尾结算一次 160')
    lu.assertFalse((function()
        for _, d in ipairs(damages) do if d == 160 then return true end end
        return false
    end)(), '身前的目标不得被甩尾打到')
end

-- 甩尾预警必须是整圆：真实伤害打身后 TailRadius 半圆，前向 90° 扇形盖不住 180° 半圆、
-- 且方向性误导（双轴审查 P2，与 #141 合并前修复同类）。整圆覆盖身后，前向超警属安全方向。
function TestBeachCombat:test_orca_tail_telegraph_is_full_circle()
    local fish = drop(self, 'fish40Boss', 2)
    for t = 0.5, 9.5, 0.5 do self.now = t self.mgr:Update() end
    self.now = 10
    self.mgr:Update() -- 虎啸先起手（同 10 秒节拍，优先级压住甩尾）
    lu.assertEquals(fish.Move.Name, 'roar')
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'tail') and guard < 50 do
        self.now = self.now + 0.1
        self.mgr:Update()
        guard = guard + 1
    end
    lu.assertEquals(fish.Move.Name, 'tail')
    local params = require('common.GameCfg').FishCombat.orca
    local lock
    for _, notice in ipairs(self.notices) do
        if notice.kind == 'lock' and notice.move == 'tail' then lock = notice end
    end
    lu.assertNotNil(lock, '甩尾没有发预警')
    lu.assertEquals(lock.shape, 'circle', '甩尾预警必须是整圆（真实伤害区是身后半圆）')
    lu.assertEquals(lock.halfAngleDeg, 180)
    lu.assertAlmostEquals(lock.range, params.TailRadius, 1e-9, '预警半径取 TailRadius')
end

-- 虎啸预警对齐径向结算：实际只按锁定目标的径向距离结算，前向 90° 扇形对目标身后 /
-- 侧向的其他人欠警。整圆（range=RoarRange）与真实危险区一致，覆盖且不误导。
function TestBeachCombat:test_orca_roar_telegraph_is_radial_circle()
    local fish = drop(self, 'fish40Boss', 2)
    for t = 0.5, 9.5, 0.5 do self.now = t self.mgr:Update() end
    self.now = 10
    self.mgr:Update() -- 虎啸起手
    lu.assertEquals(fish.Move.Name, 'roar')
    local params = require('common.GameCfg').FishCombat.orca
    local lock
    for _, notice in ipairs(self.notices) do
        if notice.kind == 'lock' and notice.move == 'roar' then lock = notice end
    end
    lu.assertNotNil(lock, '虎啸没有发预警')
    lu.assertEquals(lock.shape, 'circle', '虎啸预警必须是整圆（径向距离结算）')
    lu.assertEquals(lock.halfAngleDeg, 180)
    lu.assertAlmostEquals(lock.range, params.RoarRange, 1e-9, '预警半径取 RoarRange')
end

-- ===== 虎鲸：鲸跃 25 秒、随机 15 米外落点、10 米范围 240；整圆预警 =====

function TestBeachCombat:test_orca_leap_every_25s_fifteen_m_ten_radius_240()
    local fish, damages = drop(self, 'fish40Boss', 20)
    local params = require('common.GameCfg').FishCombat.orca
    local savedRandom = math.random
    math.random = function() return 0 end -- 落点方向固定为 +x
    for t = 0.5, 24.5, 0.5 do self.now = t self.mgr:Update() end
    self.now = 25
    self.mgr:Update()
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'jump') and guard < 50 do
        self.now = self.now + 0.1
        self.mgr:Update()
        guard = guard + 1
    end
    math.random = savedRandom
    lu.assertEquals(fish.Move.Name, 'jump', '25 秒起到鲸跃')
    local dest = fish.Move.Destination
    local body = fish.Carrier.Body
    lu.assertAlmostEquals(dest.x - body.Position.x, 15, 1e-6, '随机 15 米外落点')
    -- 鲸跃落地是整圆范围预警（不是 90° 扇形）
    local lock
    for _, notice in ipairs(self.notices) do
        if notice.kind == 'lock' and notice.move == 'jump' then lock = notice end
    end
    lu.assertNotNil(lock, '到点没有起跳预警')
    lu.assertEquals(lock.shape, 'circle')
    lu.assertEquals(lock.halfAngleDeg, 180)
    lu.assertAlmostEquals(lock.range, 10, 1e-9, '预警半径取 JumpRadius')
    damages = {}
    self.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    self.player.Character.Position = vec(dest.x, 2, dest.z)
    self.now = 25 + 1.5 * 0.5
    self.mgr:Update()
    lu.assertEquals(damages, {}, '飞行中不结算')
    self.now = fish.Move.At + params.JumpSec
    self.mgr:Update()
    lu.assertEquals(damages, { 240 }, '落点 10 米内的玩家吃一次 240')
    lu.assertAlmostEquals(body.Position.x, dest.x, 1e-6, '落地停在落点')
end

function TestBeachCombat:test_orca_leap_displacement_failure_cancels_without_landing_damage()
    local fish, damages = drop(self, 'fish40Boss', 20)
    local savedRandom = math.random
    math.random = function() return 0 end
    for t = 0.5, 24.5, 0.5 do self.now = t self.mgr:Update() end
    self.now = 25
    self.mgr:Update()
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'jump') and guard < 50 do
        self.now = self.now + 0.1
        self.mgr:Update()
        guard = guard + 1
    end
    math.random = savedRandom
    lu.assertEquals(fish.Move.Name, 'jump')
    local dest = fish.Move.Destination
    damages = {}
    self.player.Character.Position = vec(dest.x, 2, dest.z) -- 落点范围内有玩家
    breakPosition(fish)
    self.now = 25 + 1.5 * 0.5
    self.mgr:Update() -- 飞行中段位移失败
    lu.assertNil(fish.Move, '中段位移失败必须取消招式 / 收起预警')
    lu.assertEquals(damages, {}, '位移失败不得按预定落点结算落地伤害')
    self.now = 25 + 1.5
    self.mgr:Update()
    lu.assertEquals(damages, {}, '取消后不得补结算落地伤害')
end

-- ===== 虎鲸：四招并集互斥不丢（顺序与截止时间钉住） =====

function TestBeachCombat:test_orca_four_skills_all_fire_in_order()
    local fish = drop(self, 'fish40Boss', 2)
    local seen, moves = {}, {}
    self.mgr.CombatPublisher = function(payload)
        if payload.move and payload.fishId == 'fish40Boss' then
            moves[#moves + 1] = payload.move
            if not seen[payload.move] then seen[payload.move] = #moves end
        end
    end
    self.now = 0
    self.mgr:Update()
    for t = 0.5, 26.5, 0.5 do
        self.now = t
        self.mgr:Update()
    end
    lu.assertNotNil(seen.claw, '爪击丢了')
    lu.assertNotNil(seen.roar, '虎啸丢了')
    lu.assertNotNil(seen.tail, '甩尾丢了')
    lu.assertNotNil(seen.jump, '鲸跃丢了')
    lu.assertTrue(seen.claw < seen.roar, '爪击应先于虎啸')
    lu.assertTrue(seen.roar < seen.tail, '虎啸应先于甩尾（同 10 秒节拍，优先级压住）')
    lu.assertTrue(seen.tail < seen.jump, '甩尾应先于鲸跃')
end

function TestBeachCombat:test_orca_chase_failure_logs_module_fish_and_error()
    local fish, damages = drop(self, 'fish40Boss', 20)
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
end
