-- #84 迁移：沙滩岛精英 / 首领战斗（原 tests/gameplay/beach_combat_test.lua，18 例）。
-- 接缝：MgrFishUnit 战斗状态机——海象甩头 25 / 40 秒直线突击 20 米撞 120 与走廊预警、
-- 虎鲸四招并集互斥（爪 30/2 秒、虎啸 10 秒远程 30、甩尾身后 160、鲸跃 25 秒 15 米 10 范围 240）、
-- 位移失败作废招式并可从日志诊断。
-- 沿用 tests/support/fish_combat 共享夹具。Busted 把案例体放进沙箱 _ENV，
-- 采集业务日志必须写 _G.print（裸 `print =` 只进沙箱，业务模块读不到）。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local FishCombat = require('tests.support.fish_combat')
local GameCfg = require('common.GameCfg')

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 放下鱼并把目标玩家摆到鱼身 (0, dz) 处；返回鱼与伤害记录表
local function drop(env, fishId, dz)
    env:prepare()
    local damages = {}
    env.player.Character.Controller.Health = 9000
    env.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    local fish = env:heldFish(env.player, fishId)
    env.mgr:Drop(env.player)
    assert.are.equal('combat', fish.State)
    local p = fish.Carrier.Body.Position
    env.player.Character.Position = vec(p.x, 2, p.z + (dz or 2))
    env.other.Character.Controller.Health = 0
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

local function walrusParams() return GameCfg.FishCombat.walrus end

-- 推进到 40 秒突击节拍并等预警起手（40 秒帧可能压着上一记甩头的预警，做有界等待）；
-- 返回起手的 charge move 与鱼身位置（预警 / 冲锋期间位置不变）。
local function startCharge(env, fish)
    for t = 0.5, 39.5, 0.5 do env.now = t env.mgr:Update() end
    env.now = 40
    env.mgr:Update()
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'charge') and guard < 50 do
        env.now = env.now + 0.1
        env.mgr:Update()
        guard = guard + 1
    end
    assert.is_not.is_nil(fish.Move, '40 秒起到突击预警')
    assert.are.equal('charge', fish.Move.Name)
    return fish.Move, fish.Carrier.Body.Position
end

-- 采集 _G.print 输出（位移失败日志的验收证据）
local function capturePrint()
    local saved, lines = _G.print, {}
    _G.print = function(...)
        local words = {}
        for _, value in ipairs({ ... }) do words[#words + 1] = tostring(value) end
        lines[#lines + 1] = table.concat(words, ' ')
    end
    return saved, lines
end

describe('TestBeachCombat', function()
    local env

    before_each(function()
        env = FishCombat.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    -- ===== 虎鲸 =====

    it('test_orca_chase_failure_logs_module_fish_and_error', function()
        local fish, damages = drop(env, 'fish40Boss', 20)
        env.now = 0
        env.mgr:Update()
        breakPosition(fish)
        local savedPrint, lines = capturePrint()
        env.now = 1
        local ok, err = pcall(function() env.mgr:Update() end)
        _G.print = savedPrint
        assert.is_true(ok, tostring(err))
        local text = table.concat(lines, '\n')
        assert.matches('[MgrFishUnit]', text, nil, true)
        assert.matches('追击位移失败', text, nil, true)
        assert.matches('fish=' .. tostring(fish.Id), text, nil, true)
        assert.matches('position-write-failed', text, nil, true)
        assert.same({}, damages)
    end)

    it('test_orca_claw_30_every_2s_in_bite_range', function()
        local fish, damages = drop(env, 'fish40Boss', 2)
        env.now = 0
        env.mgr:Update()
        assert.are.equal('claw', fish.Move.Name)
        assert.same({}, damages, '起手帧只是预警')
        env.mgr:Update() -- 同击重复帧不重复结算
        assert.same({}, damages)
        for t = 0.5, 5.5, 0.5 do -- 0.5 秒帧连续推进：1 / 3 / 5 秒各结算一爪
            env.now = t
            env.mgr:Update()
        end
        assert.same({ 30, 30, 30 }, damages)
        for _, d in ipairs(damages) do assert.are.equal(30, d) end
    end)

    it('test_orca_drop_chases_and_flees_at_300', function()
        local fish = drop(env, 'fish40Boss', 20)
        assert.are.equal(300, fish.FleeAt)
        local body = fish.Carrier.Body
        local z0 = body.Position.z
        env.now = 0
        env.mgr:Update() -- 首帧 dt=0，不位移
        assert.near(z0, body.Position.z, 1e-9)
        env.now = 0.5
        env.mgr:Update()
        assert.near(13 * 0.5, body.Position.z - z0, 1e-6, '追击步长 = Speed(13) × dt')
        assert.is_nil(fish.Move, '追击帧不起手')
        env.now = 300
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
        assert.is_true(fish.StraightEscape)
    end)

    it('test_orca_four_skills_all_fire_in_order', function()
        local fish = drop(env, 'fish40Boss', 2)
        local seen, moves = {}, {}
        env.mgr.CombatPublisher = function(payload)
            if payload.move and payload.fishId == 'fish40Boss' then
                moves[#moves + 1] = payload.move
                if not seen[payload.move] then seen[payload.move] = #moves end
            end
        end
        env.now = 0
        env.mgr:Update()
        for t = 0.5, 26.5, 0.5 do
            env.now = t
            env.mgr:Update()
        end
        assert.is_not.is_nil(seen.claw, '爪击丢了')
        assert.is_not.is_nil(seen.roar, '虎啸丢了')
        assert.is_not.is_nil(seen.tail, '甩尾丢了')
        assert.is_not.is_nil(seen.jump, '鲸跃丢了')
        assert.is_true(seen.claw < seen.roar, '爪击应先于虎啸')
        assert.is_true(seen.roar < seen.tail, '虎啸应先于甩尾（同 10 秒节拍，优先级压住）')
        assert.is_true(seen.tail < seen.jump, '甩尾应先于鲸跃')
    end)

    it('test_orca_leap_displacement_failure_cancels_without_landing_damage', function()
        local fish, damages = drop(env, 'fish40Boss', 20)
        local savedRandom = math.random
        math.random = function() return 0 end
        for t = 0.5, 24.5, 0.5 do env.now = t env.mgr:Update() end
        env.now = 25
        env.mgr:Update()
        local guard = 0
        while (not fish.Move or fish.Move.Name ~= 'jump') and guard < 50 do
            env.now = env.now + 0.1
            env.mgr:Update()
            guard = guard + 1
        end
        math.random = savedRandom
        assert.are.equal('jump', fish.Move.Name)
        local dest = fish.Move.Destination
        damages = {}
        env.player.Character.Position = vec(dest.x, 2, dest.z) -- 落点范围内有玩家
        breakPosition(fish)
        env.now = 25 + 1.5 * 0.5
        env.mgr:Update() -- 飞行中段位移失败
        assert.is_nil(fish.Move, '中段位移失败必须取消招式 / 收起预警')
        assert.same({}, damages, '位移失败不得按预定落点结算落地伤害')
        env.now = 25 + 1.5
        env.mgr:Update()
        assert.same({}, damages, '取消后不得补结算落地伤害')
    end)

    it('test_orca_leap_every_25s_fifteen_m_ten_radius_240', function()
        local fish, damages = drop(env, 'fish40Boss', 20)
        local params = GameCfg.FishCombat.orca
        local savedRandom = math.random
        math.random = function() return 0 end -- 落点方向固定为 +x
        for t = 0.5, 24.5, 0.5 do env.now = t env.mgr:Update() end
        env.now = 25
        env.mgr:Update()
        local guard = 0
        while (not fish.Move or fish.Move.Name ~= 'jump') and guard < 50 do
            env.now = env.now + 0.1
            env.mgr:Update()
            guard = guard + 1
        end
        math.random = savedRandom
        assert.are.equal('jump', fish.Move.Name, '25 秒起到鲸跃')
        local dest = fish.Move.Destination
        local body = fish.Carrier.Body
        assert.near(15, dest.x - body.Position.x, 1e-6, '随机 15 米外落点')
        -- 鲸跃落地是整圆范围预警（不是 90° 扇形）
        local lock
        for _, notice in ipairs(env.notices) do
            if notice.kind == 'lock' and notice.move == 'jump' then lock = notice end
        end
        assert.is_not.is_nil(lock, '到点没有起跳预警')
        assert.are.equal('circle', lock.shape)
        assert.are.equal(180, lock.halfAngleDeg)
        assert.near(10, lock.range, 1e-9, '预警半径取 JumpRadius')
        damages = {}
        env.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
        env.player.Character.Position = vec(dest.x, 2, dest.z)
        env.now = 25 + 1.5 * 0.5
        env.mgr:Update()
        assert.same({}, damages, '飞行中不结算')
        env.now = fish.Move.At + params.JumpSec
        env.mgr:Update()
        assert.same({ 240 }, damages, '落点 10 米内的玩家吃一次 240')
        assert.near(dest.x, body.Position.x, 1e-6, '落地停在落点')
    end)

    it('test_orca_roar_10s_ranged_30_outside_bite_range', function()
        local fish, damages = drop(env, 'fish40Boss', 2)
        local params = GameCfg.FishCombat.orca
        for t = 0.5, 9.5, 0.5 do env.now = t env.mgr:Update() end
        damages = {}
        env.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
        local bp = fish.Carrier.Body.Position
        env.player.Character.Position = vec(bp.x, 2, bp.z + 12) -- 咬距外、虎啸射程内
        env.now = 10
        env.mgr:Update()
        assert.are.equal('roar', fish.Move.Name, '10 秒起到虎啸预警')
        assert.near(1, fish.Facing.z, 1e-9)
        assert.same({}, damages, '虎啸预警帧不结算')
        env.now = 10.5
        env.mgr:Update()
        assert.same({}, damages, '前摇途中不结算')
        env.now = 10 + params.RoarWindupSec
        env.mgr:Update()
        assert.same({ 30 }, damages, '咬距外的目标也被虎啸远程结算 30')
        assert.is_nil(fish.Move, '虎啸收招')
    end)

    it('test_orca_roar_telegraph_is_radial_circle', function()
        -- 虎啸预警对齐径向结算：实际只按锁定目标的径向距离结算，前向 90° 扇形对目标身后 /
        -- 侧向的其他人欠警。整圆（range=RoarRange）与真实危险区一致，覆盖且不误导。
        local fish = drop(env, 'fish40Boss', 2)
        for t = 0.5, 9.5, 0.5 do env.now = t env.mgr:Update() end
        env.now = 10
        env.mgr:Update() -- 虎啸起手
        assert.are.equal('roar', fish.Move.Name)
        local params = GameCfg.FishCombat.orca
        local lock
        for _, notice in ipairs(env.notices) do
            if notice.kind == 'lock' and notice.move == 'roar' then lock = notice end
        end
        assert.is_not.is_nil(lock, '虎啸没有发预警')
        assert.are.equal('circle', lock.shape, '虎啸预警必须是整圆（径向距离结算）')
        assert.are.equal(180, lock.halfAngleDeg)
        assert.near(params.RoarRange, lock.range, 1e-9, '预警半径取 RoarRange')
    end)

    it('test_orca_tail_160_hits_rear_player_only', function()
        local fish, damages = drop(env, 'fish40Boss', 2) -- 目标玩家在身前咬距内
        env.other.Character.Controller.Health = 9000
        local rolled = {}
        env.other.Character.Controller.TakeDamage = function(_, d) rolled[#rolled + 1] = d end
        local p = fish.Carrier.Body.Position
        env.other.Character.Position = vec(p.x, 2, p.z - 4) -- 身后 4 米（甩尾半径内）
        for t = 0.5, 9.5, 0.5 do env.now = t env.mgr:Update() end
        damages = {}
        env.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
        env.now = 10
        env.mgr:Update() -- 虎啸（RoarAt=10 先到，尾 At 也是 10：鲸跃 > 虎啸 > 甩尾 > 爪）
        assert.are.equal('roar', fish.Move.Name)
        env.now = 11
        env.mgr:Update() -- 虎啸结算（身前目标 30），随后让位甩尾
        local guard = 0
        while (not fish.Move or fish.Move.Name ~= 'tail') and guard < 50 do
            env.now = env.now + 0.1
            env.mgr:Update()
            guard = guard + 1
        end
        assert.are.equal('tail', fish.Move.Name)
        env.now = fish.Move.StrikeAt + 0.1
        env.mgr:Update()
        assert.same({ 160 }, rolled, '身后的玩家被甩尾结算一次 160')
        local hitFront = false
        for _, d in ipairs(damages) do if d == 160 then hitFront = true end end
        assert.is_false(hitFront, '身前的目标不得被甩尾打到')
    end)

    it('test_orca_tail_telegraph_is_full_circle', function()
        -- 甩尾预警必须是整圆：真实伤害打身后 TailRadius 半圆，前向 90° 扇形盖不住 180° 半圆、
        -- 且方向性误导（双轴审查 P2，与 #141 合并前修复同类）。整圆覆盖身后，前向超警属安全方向。
        local fish = drop(env, 'fish40Boss', 2)
        for t = 0.5, 9.5, 0.5 do env.now = t env.mgr:Update() end
        env.now = 10
        env.mgr:Update() -- 虎啸先起手（同 10 秒节拍，优先级压住甩尾）
        assert.are.equal('roar', fish.Move.Name)
        local guard = 0
        while (not fish.Move or fish.Move.Name ~= 'tail') and guard < 50 do
            env.now = env.now + 0.1
            env.mgr:Update()
            guard = guard + 1
        end
        assert.are.equal('tail', fish.Move.Name)
        local params = GameCfg.FishCombat.orca
        local lock
        for _, notice in ipairs(env.notices) do
            if notice.kind == 'lock' and notice.move == 'tail' then lock = notice end
        end
        assert.is_not.is_nil(lock, '甩尾没有发预警')
        assert.are.equal('circle', lock.shape, '甩尾预警必须是整圆（真实伤害区是身后半圆）')
        assert.are.equal(180, lock.halfAngleDeg)
        assert.near(params.TailRadius, lock.range, 1e-9, '预警半径取 TailRadius')
    end)

    -- ===== 海象 =====

    it('test_walrus_charge_displacement_failure_cancels_without_damage', function()
        local fish, damages = drop(env, 'fish39Elite', 20)
        local params = walrusParams()
        local move, bp = startCharge(env, fish)
        damages = {}
        env.player.Character.Position = vec(bp.x, 2, bp.z + 10) -- 冲锋路径上
        breakPosition(fish) -- 引擎拒绝位移
        env.now = move.At + params.ChargeWindupSec + 0.2
        env.mgr:Update()
        assert.is_nil(fish.Move, '突击位移失败必须取消招式 / 收起预警')
        assert.same({}, damages, '位移失败不得按预定冲锋路径结算伤害')
        env.now = 43
        env.mgr:Update()
        assert.same({}, damages, '取消后不得补结算')
    end)

    it('test_walrus_charge_every_40s_hits_player_on_path_once', function()
        local fish, damages = drop(env, 'fish39Elite', 20)
        local params = walrusParams()
        local move, bp = startCharge(env, fish)
        -- 预警起手后重新记录伤害，把玩家摆到锁定冲锋方向（+z）的路径上
        damages = {}
        env.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
        env.player.Character.Position = vec(bp.x, 2, bp.z + 10)
        assert.same({}, damages, '突击预警帧不结算')
        env.now = move.At + params.ChargeWindupSec + 0.3
        env.mgr:Update()
        assert.are.equal('charge', fish.Move.Name)
        assert.same({}, damages, '冲锋途中不逐帧结算')
        env.now = fish.Move.StrikeAt + 0.1
        env.mgr:Update()
        assert.is_nil(fish.Move, '冲完 20 米收招')
        assert.same({ 120 }, damages, '路径上的玩家只被撞到一次 120')
        assert.near(params.ChargeDistance, fish.Carrier.Body.Position.z - bp.z, 1e-6, '直线冲锋 20 米')
    end)

    it('test_walrus_charge_misses_player_off_path', function()
        local fish, damages = drop(env, 'fish39Elite', 20)
        local move, bp = startCharge(env, fish)
        damages = {}
        -- 路径外侧 5 米（> 接触距离 2.5）：不得被冲锋撞到
        env.player.Character.Position = vec(bp.x + 5, 2, bp.z + 10)
        env.now = move.At + GameCfg.FishCombat.walrus.ChargeWindupSec + 0.3
        env.mgr:Update()
        env.now = fish.Move.StrikeAt + 0.1
        env.mgr:Update()
        assert.same({}, damages, '路径外的玩家不得被冲锋撞到')
    end)

    it('test_walrus_charge_telegraph_covers_corridor', function()
        -- 突击预警必须覆盖真实危险区：20 米冲锋走廊（双轴审查 P2，与 #141 同类合并前修复；
        -- 预警 range 只给接触距离 2.5 米属严重欠警）。朝向目标的前向扇形 + 冲程半径可覆盖走廊，
        -- 走廊两侧之外属横向超警（安全方向）。
        local fish = drop(env, 'fish39Elite', 20)
        local params = walrusParams()
        startCharge(env, fish)
        local lock
        for _, notice in ipairs(env.notices) do
            if notice.kind == 'lock' and notice.move == 'charge' then lock = notice end
        end
        assert.is_not.is_nil(lock, '突击没有发预警')
        assert.near(params.ChargeDistance, lock.range, 1e-9, '突击预警半径必须取冲程 20 米（走廊），不能只给接触距离')
    end)

    it('test_walrus_charge_windup_locks_facing', function()
        -- 突击预警期间锁定朝向：目标挪开也不转头（直线冲锋不是跟踪导弹）
        local fish, damages = drop(env, 'fish39Elite', 20)
        local params = walrusParams()
        local move, bp = startCharge(env, fish)
        damages = {}
        assert.near(1, fish.Facing.z, 1e-9, '起手朝向锁定 +z')
        env.player.Character.Position = vec(bp.x, 2, bp.z - 10) -- 预警中挪到身后（仍活着）
        env.now = move.At + params.ChargeWindupSec + 0.2
        env.mgr:Update()
        assert.near(1, fish.Facing.z, 1e-9, '预警 / 冲锋期间不跟着目标转头')
        env.now = fish.Move.StrikeAt + 0.1
        env.mgr:Update()
        assert.same({}, damages, '挪到身后的目标不得被冲锋撞到')
        assert.near(params.ChargeDistance, fish.Carrier.Body.Position.z - bp.z, 1e-6)
    end)

    it('test_walrus_displacement_failures_log_module_fish_and_error', function()
        -- 追击失败日志（与 #141 同口径）
        local fish, damages = drop(env, 'fish39Elite', 20)
        env.now = 0
        env.mgr:Update()
        breakPosition(fish)
        local savedPrint, lines = capturePrint()
        env.now = 1
        local ok, err = pcall(function() env.mgr:Update() end)
        _G.print = savedPrint
        assert.is_true(ok, tostring(err))
        local text = table.concat(lines, '\n')
        assert.matches('[MgrFishUnit]', text, nil, true)
        assert.matches('追击位移失败', text, nil, true)
        assert.matches('fish=' .. tostring(fish.Id), text, nil, true)
        assert.matches('position-write-failed', text, nil, true)
        assert.same({}, damages)
        env.mgr:Remove(fish)
        -- 突击位移失败日志
        fish, damages = drop(env, 'fish39Elite', 20)
        local move = startCharge(env, fish)
        damages = {}
        breakPosition(fish)
        lines = {}
        _G.print = function(...)
            local words = {}
            for _, value in ipairs({ ... }) do words[#words + 1] = tostring(value) end
            lines[#lines + 1] = table.concat(words, ' ')
        end
        env.now = move.At + GameCfg.FishCombat.walrus.ChargeWindupSec + 0.2
        local ok2, err2 = pcall(function() env.mgr:Update() end)
        _G.print = savedPrint
        assert.is_true(ok2, tostring(err2))
        local text2 = table.concat(lines, '\n')
        assert.matches('[MgrFishUnit]', text2, nil, true)
        assert.matches('突击位移失败', text2, nil, true)
        assert.matches('fish=' .. tostring(fish.Id), text2, nil, true)
        assert.matches('position-write-failed', text2, nil, true)
        assert.same({}, damages)
    end)

    it('test_walrus_drop_chases_and_flees_at_180', function()
        local fish = drop(env, 'fish39Elite', 20)
        assert.are.equal(180, fish.FleeAt)
        local body = fish.Carrier.Body
        local z0 = body.Position.z
        env.now = 0
        env.mgr:Update() -- 首帧 dt=0，不位移
        assert.near(z0, body.Position.z, 1e-9)
        env.now = 0.5
        env.mgr:Update()
        assert.near(11 * 0.5, body.Position.z - z0, 1e-6, '追击步长 = Speed(11) × dt')
        assert.is_nil(fish.Move, '追击帧不起手')
        env.now = 180
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
        assert.is_true(fish.StraightEscape)
    end)

    it('test_walrus_head_swing_25_on_cadence', function()
        local fish, damages = drop(env, 'fish39Elite', 2)
        env.now = 0
        env.mgr:Update()
        assert.are.equal('swing', fish.Move.Name)
        assert.same({}, damages, '起手帧只是预警')
        env.mgr:Update() -- 同击重复帧不重复结算
        assert.same({}, damages)
        env.now = 2 -- SwingCooldownSec（配置细化）
        env.mgr:Update()
        assert.same({ 25 }, damages)
        -- 预警中绕到身后（仍在咬距内）：锁定朝向不跟着转头，结算落空
        local p = fish.Carrier.Body.Position
        env.now = 2.1
        env.mgr:Update() -- 冷却过后重新起手，朝向锁定 +z
        assert.are.equal('swing', fish.Move.Name)
        assert.near(1, fish.Facing.z, 1e-9)
        env.player.Character.Position = vec(p.x, 2, p.z - 2)
        env.now = 2.5
        env.mgr:Update() -- 预警中不转头
        assert.near(1, fish.Facing.z, 1e-9)
        env.now = 2.1 + 2
        env.mgr:Update() -- 结算帧：身后算后身，不结算
        assert.same({ 25 }, damages)
    end)
end)
