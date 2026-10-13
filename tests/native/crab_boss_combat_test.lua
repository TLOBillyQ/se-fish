-- #84 迁移：蟹老板首领战（原 tests/gameplay/crab_boss_combat_test.lua，8 例）。
-- 接缝：MgrFishUnit 的 crabBoss 状态机——正面蟹钳双击每击 20 / 冷却 4 秒、每 30 秒冲撞 20、
-- 每 25 秒旋转 5 秒碰触 30 且同秒槽只结算一次，三招互斥，逃跑 / 移除打断并收起预警。
-- 沿用 tests/support/fish_combat 共享夹具；describe/it 名称保留旧类名与方法名，
-- 并按方法名字典序注册以保持旧套件执行顺序。
local FishCombat = require('tests.support.fish_combat')

local function drop(env)
    env:prepare()
    env.player.Character.Controller.Health = 2000
    env.player.Character.Controller.TakeDamage = function() end
    local fish = env:heldFish(env.player, 'fish24Boss')
    env.mgr:Drop(env.player)
    assert.are.equal('combat', fish.State)
    assert.are.equal(300, fish.FleeAt) -- EscapeSec=300
    local p = fish.Carrier.Body.Position
    env.player.Character.Position = { x = p.x, y = p.y, z = p.z + 1 }
    env.other.Character.Controller.Health = 0
    return fish
end

describe('TestCrabBossCombat', function()
    local env

    before_each(function()
        env = FishCombat.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_charge_every_thirty_seconds_hits_twenty', function()
        -- 冲撞：每 30 秒一次，命中 20；冲撞窗口内不双击
        local fish = drop(env)
        env.mgr:Update()
        assert.are.equal('pinch', fish.Move.Name)
        -- 冲撞节拍 30 秒；25 秒已过的旋转顺延到 30 秒起手、持续 5 秒（30..35），冲撞再顺延
        env.now = 29.9
        env.mgr:Update()
        assert.is_not.equal('charge', fish.Move and fish.Move.Name, '冲撞提前发动')
        env.now = 30
        env.mgr:Update()
        assert.are.equal('spin', fish.Move.Name, '30 秒旋转起手')
        -- 旋转 35 秒收招帧不连起新招；下一帧冲撞起手
        env.now = 35.1
        env.mgr:Update()
        assert.is_nil(fish.Move, '旋转 35 秒收招')
        env.mgr:Update()
        assert.are.equal('charge', fish.Move.Name, '旋转结束后冲撞起手')
        -- 冲撞命中 20（窗口内结算一次）
        local before = #env.vitalsCalls
        env.now = 35.5
        env.mgr:Update()
        assert.are.equal(before + 1, #env.vitalsCalls, '冲撞命中一次')
        assert.are.equal(20, env.vitalsCalls[#env.vitalsCalls][3])
    end)

    it('test_chase_step_scales_with_frame_dt', function()
        -- 追击步长与帧率解耦：位移 = Speed × 实际帧间隔 dt（审查修复：原为 Speed × 0.1 硬编码）；
        -- 步长仍被咬距钳制，追进咬距即起手双击
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
        assert.are.equal('pinch', fish.Move.Name, '追进咬距即起手双击')
    end)

    it('test_combat_payload_carries_move_names', function()
        -- 战斗快照带招式名：pinch / spin 协议字段
        local fish = drop(env)
        local payloads = {}
        env.mgr.CombatPublisher = function(payload) payloads[#payloads + 1] = payload end
        env.mgr:Update()
        assert.are.equal('pinch', payloads[#payloads].move)
    end)

    it('test_flee_interrupts_spin_and_clears_warning', function()
        -- 逃跑打断：旋转进行中逃跑时限到，清招式、收预警、直线逃脱不再结算
        local fish = drop(env)
        env.mgr:Update()
        env.now = 25
        env.mgr:Update() -- pinch 收招帧
        env.mgr:Update() -- 收招帧后下一帧旋转起手
        assert.are.equal('spin', fish.Move.Name)
        local settled = #env.vitalsCalls
        env.now = 300
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
        assert.is_true(fish.StraightEscape)
        assert.is_nil(fish.Move)
        assert.are.equal('clear', env.notices[#env.notices].kind)
        assert.are.equal('gone', env.notices[#env.notices].reason)
        env.now = 301
        env.mgr:Update()
        assert.are.equal(settled, #env.vitalsCalls, '逃脱后不得结算')
    end)

    it('test_pinch_two_strikes_twenty_damage_four_second_cooldown', function()
        -- 双击：起手帧预警不结算，两击在起手后各间隔 0.2 秒结算、每击 20；冷却 4 秒后再起
        local fish = drop(env)
        env.mgr:Update()
        assert.are.equal('pinch', fish.Move.Name)
        assert.are.equal(0, #env.vitalsCalls, '起手帧只是预警')
        env.now = 0.2
        env.mgr:Update()
        env.mgr:Update() -- 同一击重复帧不重复结算
        assert.are.equal(1, #env.vitalsCalls)
        assert.are.equal(20, env.vitalsCalls[1][3])
        env.now = 0.4
        env.mgr:Update()
        assert.are.equal(2, #env.vitalsCalls, '第二击')
        assert.are.equal(20, env.vitalsCalls[2][3])
        env.now = 0.5
        env.mgr:Update()
        assert.is_nil(fish.Move, '双击后招式即收')
        -- 冷却 4 秒：3.9 秒不起手，4 秒后起第二轮
        env.now = 3.9
        env.mgr:Update()
        assert.are.equal(2, #env.vitalsCalls, '冷却中不得起手')
        env.now = 4.0
        env.mgr:Update()
        assert.are.equal('pinch', fish.Move.Name)
        env.now = 4.2
        env.mgr:Update()
        assert.are.equal(3, #env.vitalsCalls, '第二轮第一击')
    end)

    it('test_remove_during_pinch_clears_warning_and_stops_strikes', function()
        -- 移除打断：双击进行中鱼被打死清场，预警收起不再结算
        local fish = drop(env)
        env.mgr:Update()
        assert.are.equal('pinch', fish.Move.Name)
        env.mgr:Remove(fish)
        assert.are.equal('clear', env.notices[#env.notices].kind)
        assert.are.equal('gone', env.notices[#env.notices].reason)
        env.now = 0.4
        env.mgr:Update()
        assert.are.equal(0, #env.vitalsCalls)
    end)

    it('test_spin_charge_pinch_are_mutually_exclusive', function()
        -- 互斥：旋转期间不冲撞不双击；冲撞期间不旋转
        local fish = drop(env)
        env.mgr:Update()
        env.now = 25
        env.mgr:Update() -- pinch 收招帧
        env.mgr:Update() -- 收招帧后下一帧旋转起手
        assert.are.equal('spin', fish.Move.Name)
        -- 旋转持续期跨过 30 秒冲撞节拍：冲撞被旋转压住
        env.now = 29.9
        env.mgr:Update()
        assert.are.equal('spin', fish.Move.Name, '旋转中不得冲撞')
    end)

    it('test_spin_every_twentyfive_seconds_thirty_damage_once_per_second_slot', function()
        -- 旋转：25 秒节拍（首次 Update 后即起手）、持续 5 秒、碰触 30；同一旋转内同一玩家按秒槽只结算一次
        local fish = drop(env)
        env.mgr:Update()
        -- 25 秒节拍：首次起手 pinch 收招后，下一次无招式帧（now≥25）起 spin
        env.now = 25
        env.mgr:Update()
        -- pinch 已收、spin 未起（pinch 收招帧不连起 spin）；再一帧起 spin
        if not fish.Move then env.mgr:Update() end
        assert.are.equal('spin', fish.Move.Name)
        local spinStart = fish.Move.At
        local before = #env.vitalsCalls
        -- 旋转 5 秒：每秒槽一次碰触，同一秒槽重复帧不重复结算
        for tick = 1, 5 do
            env.now = spinStart + tick
            env.mgr:Update()
            env.mgr:Update()
        end
        assert.are.equal(5, #env.vitalsCalls - before, '旋转五秒每秒槽一次碰触')
        assert.are.equal(30, env.vitalsCalls[#env.vitalsCalls][3])
        -- 持续 5 秒后结束
        env.now = spinStart + 5.1
        env.mgr:Update()
        assert.is_not.equal('spin', fish.Move and fish.Move.Name, '旋转 5 秒后结束')
    end)
end)
