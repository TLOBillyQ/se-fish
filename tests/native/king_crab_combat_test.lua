-- #84 迁移：帝王蟹精英战（原 tests/gameplay/king_crab_combat_test.lua，6 例）。
-- 接缝：MgrFishUnit 的 kingCrab 状态机——进咬距起手乱刺预警、5 秒一轮左右钳各 3 下每下 15、
-- 同刺段重复帧不双结算且掉帧不追溯补刺，每活动 30 秒眩晕 5 秒，逃跑 / 移除打断并收起预警。
-- 沿用 tests/support/fish_combat 共享夹具；describe/it 名称保留旧类名与方法名，
-- 并按方法名字典序注册以保持旧套件执行顺序。
local FishCombat = require('tests.support.fish_combat')

local function drop(env)
    env:prepare()
    env.player.Character.Controller.Health = 2000
    env.player.Character.Controller.TakeDamage = function() end
    local fish = env:heldFish(env.player, 'fish23Elite')
    env.mgr:Drop(env.player)
    assert.are.equal('combat', fish.State)
    assert.are.equal(180, fish.FleeAt) -- EscapeSec=180
    local p = fish.Carrier.Body.Position
    -- 目标站进咬距：第一次 Update 即起手乱刺预警
    env.player.Character.Position = { x = p.x, y = p.y, z = p.z + 1 }
    env.other.Character.Controller.Health = 0
    return fish
end

describe('TestKingCrabCombat', function()
    local env

    before_each(function()
        env = FishCombat.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_chase_step_scales_with_frame_dt', function()
        -- 追击步长与帧率解耦：位移 = Speed × 实际帧间隔 dt（审查修复：原为 Speed × 0.1 硬编码，
        -- 60Hz 下追击速度约为鱼种 Speed 的 6 倍）；步长仍被咬距钳制，追进咬距即起手
        local fish = drop(env)
        local p = fish.Carrier.Body.Position
        env.player.Character.Position = { x = p.x, y = p.y, z = p.z + 20 } -- 咬距外 20 米
        env.mgr:Update() -- 首帧 dt=0，不位移
        local z0 = fish.Carrier.Body.Position.z
        env.now = 0.5
        env.mgr:Update()
        assert.near(10 * 0.5, fish.Carrier.Body.Position.z - z0, 1e-6, '追击步长 = Speed × dt')
        assert.is_nil(fish.Move, '追击帧不起手')
        -- 大 dt 帧：步长按实际间隔放大，但被咬距钳制（distance - BiteRange）
        env.now = 5.5
        env.mgr:Update()
        assert.near(20 - 2.5, fish.Carrier.Body.Position.z - z0, 1e-6, '大 dt 一帧追到咬距边')
        env.now = 5.6
        env.mgr:Update()
        assert.are.equal('jab', fish.Move.Name, '追进咬距即起手乱刺')
    end)

    it('test_combat_payload_carries_jab_move_name', function()
        -- 战斗快照带招式名：客户端标签协议字段 move='jab'
        local fish = drop(env)
        local payloads = {}
        env.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
        env.mgr:Update()
        assert.are.equal('jab', payloads[#payloads].move)
    end)

    it('test_flee_interrupts_jab_and_clears_warning', function()
        -- 逃跑打断：乱刺进行中逃跑时限到，清招式、收预警、直线逃脱不再结算
        local fish = drop(env)
        env.mgr:Update()
        env.now = 0.4
        env.mgr:Update()
        assert.are.equal(1, #env.vitalsCalls) -- 0.4 结算第一刺（起手帧只是预警）
        assert.is_not.is_nil(fish.Move)
        env.now = 180
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
        assert.is_true(fish.StraightEscape)
        assert.is_nil(fish.Move)
        assert.are.equal('clear', env.notices[#env.notices].kind)
        assert.are.equal('gone', env.notices[#env.notices].reason)
        env.now = 181
        env.mgr:Update()
        assert.are.equal(1, #env.vitalsCalls, '逃脱后不得结算剩余刺段')
    end)

    it('test_jab_combo_six_strikes_every_five_seconds_once_per_slot', function()
        -- 乱刺节奏：5 秒一轮、左右各 3 下、间隔 0.2、每下 15；起手帧是预警不结算，
        -- 六刺在 0.2、0.4、0.6、0.8、1.0、1.2 秒各结算一次（1.2 秒第六刺与收招同帧，先结算再收招）。
        -- 同一刺段重复帧不重复结算；掉帧只补当前刺段不追溯。
        local fish = drop(env)
        env.mgr:Update()
        assert.are.equal('jab', fish.Move.Name)
        assert.are.equal(0, #env.vitalsCalls, '起手帧只是预警')
        for i, t in ipairs({ 0.2, 0.4, 0.6, 0.8, 1.0, 1.2 }) do
            env.now = t
            env.mgr:Update()
            env.mgr:Update() -- 同一刺段重复帧不重复结算
            assert.are.equal(i, #env.vitalsCalls, '第 ' .. i .. ' 刺')
            assert.are.equal(15, env.vitalsCalls[#env.vitalsCalls][3])
        end
        assert.is_nil(fish.Move, '1.2 秒第六刺结算即收招')
        assert.are.equal('clear', env.notices[#env.notices].kind)
        env.now = 4.99
        env.mgr:Update()
        assert.are.equal(6, #env.vitalsCalls, '第二轮提前起刺')
        env.now = 5
        env.mgr:Update()
        assert.are.equal(6, #env.vitalsCalls, '第二轮起手帧只是预警')
        env.now = 5.2
        env.mgr:Update()
        assert.are.equal(7, #env.vitalsCalls)
        -- 掉帧大 dt：一轮只补当前刺段，不追溯历史
        env.now = 11.6
        env.mgr:Update()
        assert.are.equal(8, #env.vitalsCalls, '大 dt 不得补刺')
    end)

    it('test_remove_during_jab_clears_warning_and_stops_strikes', function()
        -- 移除打断：乱刺进行中鱼被打死清场，预警收起不再结算
        local fish = drop(env)
        env.mgr:Update()
        env.now = 0.4
        env.mgr:Update()
        assert.are.equal(1, #env.vitalsCalls) -- 起手帧只是预警，0.4 第一刺
        env.mgr:Remove(fish)
        assert.are.equal('clear', env.notices[#env.notices].kind)
        assert.are.equal('gone', env.notices[#env.notices].reason)
        env.now = 1
        env.mgr:Update()
        assert.are.equal(1, #env.vitalsCalls)
    end)

    it('test_stun_after_thirty_seconds_no_jab_while_stunned', function()
        -- 活动 30 秒眩晕 5 秒：眩晕中不起刺不结算；醒来后重新计活动与乱刺节拍
        local fish = drop(env)
        env.mgr:Update()
        env.now = 30
        env.mgr:Update()
        assert.are.equal('stunned', fish.State)
        assert.is_nil(fish.Move)
        assert.are.equal(35, fish.WakeAt)
        assert.are.equal(0, #env.vitalsCalls)
        env.now = 34.9
        env.mgr:Update()
        assert.are.equal(0, #env.vitalsCalls, '眩晕期间不得起刺')
        env.now = 35
        env.mgr:Update()
        assert.are.equal('combat', fish.State)
        assert.is_not.is_nil(fish.Move)
        assert.are.equal('jab', fish.Move.Name)
        -- 醒来后重新计时：40 秒时不眩晕，65 秒才第二轮眩晕
        env.now = 64.9
        env.mgr:Update()
        assert.are.equal('combat', fish.State)
        env.now = 65
        env.mgr:Update()
        assert.are.equal('stunned', fish.State)
    end)
end)
