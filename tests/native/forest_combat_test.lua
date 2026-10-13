-- #84 迁移：树林岛精英 / 首领战斗（原 tests/gameplay/forest_combat_test.lua，14 例）。
-- 接缝：MgrFishUnit 战斗状态机——剑鱼挥头 20 / 三头鲨扫头 25、翻滚接触独立段按秒槽去重、
-- 高跃周期与落点范围伤害、位移失败作废招式、追击失败可诊断。
-- 沿用 tests/support/fish_combat 共享夹具；breakPosition 是引擎拒绝写 Position 的边界代理，逐例回滚。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local FishCombat = require('tests.support.fish_combat')

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

describe('TestForestCombat', function()
    local env

    before_each(function()
        env = FishCombat.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_chase_failure_logs_module_operation_fish_and_error', function()
        for _, id in ipairs({ 'fish31Elite', 'fish32Boss' }) do
            local fish, damages = drop(env, id, 20)
            env.now = 0
            env.mgr:Update()
            breakPosition(fish)
            local savedPrint, lines = _G.print, {}
            -- Busted 把案例体放在沙箱 _ENV 里（写全局只进 context.env），
            -- 业务模块用的是真 _G，因此采集日志必须显式写 _G.print。
            _G.print = function(...)
                local words = {}
                for _, value in ipairs({ ... }) do words[#words + 1] = tostring(value) end
                lines[#lines + 1] = table.concat(words, ' ')
            end
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
        end
    end)

    it('test_combat_payload_carries_move_names', function()
        local fish = drop(env, 'fish32Boss', 2)
        local payloads = {}
        env.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
        env.now = 0
        env.mgr:Update()
        assert.are.equal('sweep', payloads[#payloads].move)
        assert.are.equal('fish32Boss', payloads[#payloads].fishId)
    end)

    it('test_jump_final_frame_displacement_failure_cancels_without_landing_damage', function()
        local fish, damages = drop(env, 'fish31Elite', 20)
        local savedRandom = math.random
        math.random = function() return 0 end
        env.now = 0
        env.mgr:Update()
        env.now = 50
        env.mgr:Update()
        local dest = fish.Move.Destination
        math.random = savedRandom
        env.player.Character.Position = vec(dest.x, 2, dest.z)
        breakPosition(fish)
        env.now = 50 + 1.5
        env.mgr:Update() -- 结算帧位移失败
        assert.is_nil(fish.Move, '最终帧位移失败必须取消招式 / 收起预警')
        assert.same({}, damages, '最终帧位移失败不得结算落地伤害')
    end)

    it('test_jump_midflight_displacement_failure_cancels_without_landing_damage', function()
        local fish, damages = drop(env, 'fish31Elite', 20)
        local savedRandom = math.random
        math.random = function() return 0 end
        env.now = 0
        env.mgr:Update()
        env.now = 50
        env.mgr:Update()
        assert.are.equal('jump', fish.Move.Name)
        local dest = fish.Move.Destination
        math.random = savedRandom
        env.player.Character.Position = vec(dest.x, 2, dest.z) -- 落点范围内有玩家
        breakPosition(fish)
        env.now = 50 + 1.5 * 0.5
        env.mgr:Update() -- 飞行中段位移失败
        assert.is_nil(fish.Move, '中段位移失败必须取消招式 / 收起预警')
        assert.same({}, damages, '位移失败不得按预定落点结算落地伤害')
        env.now = 50 + 1.5
        env.mgr:Update() -- 到点也不得补结算
        assert.same({}, damages, '取消后不得补结算落地伤害')
    end)

    it('test_jump_warning_is_full_circle_landing_range', function()
        local fish = drop(env, 'fish31Elite', 20)
        local savedRandom = math.random
        math.random = function() return 0 end
        env.now = 0
        env.mgr:Update()
        env.notices = {}
        env.now = 50
        env.mgr:Update()
        math.random = savedRandom
        local lock
        for _, notice in ipairs(env.notices) do
            if notice.kind == 'lock' and notice.move == 'jump' then lock = notice end
        end
        assert.is_not.is_nil(lock, '到点没有起跳预警')
        assert.are.equal('circle', lock.shape, '高跃落地是整圆范围，不是 90° 扇形')
        assert.are.equal(180, lock.halfAngleDeg)
        assert.near(5, lock.range, 1e-9, '预警半径取 JumpRadius')
    end)

    it('test_roll_contact_uses_actual_position_when_chase_fails', function()
        local fish = drop(env, 'fish32Boss', 20)
        env.other.Character.Controller.Health = 9000
        local rolled = {}
        env.other.Character.Controller.TakeDamage = function(_, d) rolled[#rolled + 1] = d end
        env.now = 0
        env.mgr:Update()
        local start = fish.Carrier.Body.Position
        -- 第二名玩家摆在「本该滚到」的位置（追击路径中段）
        env.other.Character.Position = vec(start.x, 2, start.z + 10)
        breakPosition(fish) -- 位移失败：鱼实际没有滚过去
        env.now = 1
        env.mgr:Update()
        assert.same({}, rolled, '位移失败不得按未到达的滚动路径结算接触')
    end)

    it('test_shark_drop_chases_and_flees_at_300', function()
        local fish = drop(env, 'fish32Boss', 20)
        assert.are.equal(300, fish.FleeAt)
        local body = fish.Carrier.Body
        local z0 = body.Position.z
        env.now = 0
        env.mgr:Update()
        env.now = 0.5
        env.mgr:Update()
        assert.near(12 * 0.5, body.Position.z - z0, 1e-6)
        env.now = 300
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
    end)

    it('test_shark_head_sweep_25_on_three_second_cadence', function()
        local fish, damages = drop(env, 'fish32Boss', 2)
        env.now = 0
        env.mgr:Update()
        assert.are.equal('sweep', fish.Move.Name)
        assert.same({}, damages, '起手帧只是预警')
        env.mgr:Update()
        assert.same({}, damages)
        env.now = 3
        env.mgr:Update()
        assert.same({ 25 }, damages)
    end)

    it('test_shark_jumps_every_20s_fifteen_meters_ten_radius_two_hundred', function()
        local fish, damages = drop(env, 'fish32Boss', 20)
        local body = fish.Carrier.Body
        local savedRandom = math.random
        math.random = function() return 0 end
        env.now = 0
        env.mgr:Update()
        env.now = 19.9
        env.mgr:Update()
        assert.is_nil(fish.Move, '20 秒前不得起跳')
        env.now = 20
        damages = {} -- 只记录本次高跃，此前真实翻滚接触另有用例覆盖
        env.player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
        env.mgr:Update()
        assert.are.equal('jump', fish.Move.Name)
        local dest = fish.Move.Destination
        assert.near(15, dest.x - body.Position.x, 1e-6)
        math.random = savedRandom
        env.player.Character.Position = vec(dest.x, 2, dest.z)
        env.now = 20 + 1.5
        env.mgr:Update()
        assert.same({ 200 }, damages)
    end)

    it('test_shark_roll_contact_25_dedup_per_second_slot', function()
        local fish = drop(env, 'fish32Boss', 20) -- 目标玩家在 20 米外
        local body = fish.Carrier.Body
        env.other.Character.Controller.Health = 9000
        local rolled = {}
        env.other.Character.Controller.TakeDamage = function(_, d) rolled[#rolled + 1] = d end
        -- 仇恨落在远处玩家：追击目标仍是 player，贴身的 other 被“滚到”
        env.mgr:NoteDamage(fish, env.player, 30)
        env.other.Character.Position = vec(body.Position.x, 2, body.Position.z + 2)
        env.now = 0
        env.mgr:Update()
        env.now = 0.1
        env.mgr:Update() -- 首个真实滚动帧才结算接触
        assert.same({ 25 }, rolled)
        env.mgr:Update() -- 同秒槽重复帧不重复结算
        assert.same({ 25 }, rolled)
        -- 下一秒槽再结算一次
        env.other.Character.Position = vec(body.Position.x, 2, body.Position.z + 2)
        env.now = 1
        env.mgr:Update()
        assert.same({ 25, 25 }, rolled)
    end)

    it('test_shark_roll_contact_hits_the_single_chased_target', function()
        local fish, damages = drop(env, 'fish32Boss', 20) -- other 已倒下，唯一玩家就是目标
        env.now = 0
        env.mgr:Update() -- 首帧 dt=0 不位移
        assert.same({}, damages)
        env.now = 2
        env.mgr:Update() -- 翻滚 17.5 米贴到咬距边缘：滚到唯一玩家
        assert.same({ 25 }, damages, '单人追击也要结算翻滚接触伤害')
        assert.is_nil(fish.Move, '接触伤害是独立段，不与扫头同帧并发')
    end)

    it('test_swordfish_drop_chases_and_flees_at_180', function()
        local fish = drop(env, 'fish31Elite', 20)
        assert.are.equal(180, fish.FleeAt)
        local body = fish.Carrier.Body
        local z0 = body.Position.z
        env.now = 0
        env.mgr:Update() -- 首帧 dt=0，不位移
        assert.near(z0, body.Position.z, 1e-9)
        env.now = 0.5
        env.mgr:Update()
        assert.near(12 * 0.5, body.Position.z - z0, 1e-6, '追击步长 = Speed × dt')
        assert.is_nil(fish.Move, '追击帧不起手')
        env.now = 180
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
        assert.is_true(fish.StraightEscape)
    end)

    it('test_swordfish_head_swing_20_damage_on_cadence', function()
        local fish, damages = drop(env, 'fish31Elite', 2)
        env.now = 0
        env.mgr:Update()
        assert.are.equal('swing', fish.Move.Name)
        assert.same({}, damages, '起手帧只是预警')
        env.mgr:Update() -- 同击重复帧不重复结算
        assert.same({}, damages)
        env.now = 2 -- SwingCooldownSec
        env.mgr:Update()
        assert.same({ 20 }, damages)
        assert.are.equal(1, #env.vitalsCalls)
        assert.same(fish, env.vitalsCalls[1][1].source)
        assert.are.equal('fishAttack', env.vitalsCalls[1][1].category)
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
        assert.same({ 20 }, damages)
    end)

    it('test_swordfish_jumps_every_50s_ten_meters_five_radius_hundred', function()
        local fish, damages = drop(env, 'fish31Elite', 20)
        local body = fish.Carrier.Body
        local savedRandom = math.random
        math.random = function() return 0 end -- 落点方向固定为 +x
        env.now = 0
        env.mgr:Update()
        env.now = 49.9
        env.mgr:Update()
        assert.is_nil(fish.Move, '50 秒前不得起跳')
        env.now = 50
        env.mgr:Update()
        assert.are.equal('jump', fish.Move.Name)
        local dest = fish.Move.Destination
        assert.near(10, dest.x - body.Position.x, 1e-6, '随机 10 米外落点')
        assert.near(0, dest.z - body.Position.z, 1e-6)
        math.random = savedRandom
        -- 落在落点 5 米内的玩家吃 100
        env.player.Character.Position = vec(dest.x, 2, dest.z)
        env.now = 50 + 1.5 * 0.5
        env.mgr:Update()
        assert.same({}, damages, '飞行中不结算')
        env.now = 50 + 1.5
        env.mgr:Update()
        assert.same({ 100 }, damages)
        assert.near(dest.x, body.Position.x, 1e-6, '落地停在落点')
    end)
end)
