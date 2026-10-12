-- #84 迁移：AI 生命周期与官方 AI 接管（原 tests/gameplay/ai_migration_test.lua，3 + 9 例）。
-- 接缝：根 AiAPI → MgrAi → 实际载体交接；以及 MgrFishUnit 侧的释放 / 删除必交接、失败交接不启动业务移动。
-- TestFishAiLifecycle 沿用 tests/support/fish_lift 共享夹具；TestAiMigration 用官方 AI vendor 运行时。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序
-- （旧套件里 TestAiMigration 整体先于 TestFishAiLifecycle，按类名字典序）。
local Loader = require('tests.support.official_ai_vendor_runtime')
local FishLift = require('tests.support.fish_lift')
local GameCfg = require('common.GameCfg')

describe('TestAiMigration', function()
    local env

    before_each(function()
        env = {}
        env.ai, env.runtime = Loader.loadAi()
        local e = setmetatable({ Vector3 = { New = env.runtime.Vector }, require = function(name)
            if name == 'server.AiAPI' then return env.ai end
            return require(name)
        end }, { __index = _G })
        env.mgr = assert(loadfile('server/Mgr/MgrAi.lua', 't', e))()
        env.unit = env.runtime.newUnit(5301)
        env.fish = { Id = 1, Carrier = { Receiver = env.unit, Body = env.runtime.newUnit(5302) } }
    end)
    after_each(function()
        -- 旧类没有 tearDown：vendor 运行时是用例内新建的独立实例，不写进程全局，无需回滚。
        env = nil
    end)

    it('test_chase_parameter_changes_take_effect_on_same_target', function()
        local target = env.runtime.newUnit(5303)
        target.Position = env.runtime.Vector(10, 0, 0)
        env.mgr:Chase(env.fish, target, 3, 1, 30)
        env.runtime.task:pump(0.1)
        env.mgr:Chase(env.fish, target, 3, 15, 30)
        env.runtime.task:pump(0.1)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
        env.mgr:Chase(env.fish, target, 3, 1, 30)
        env.runtime.task:pump(0.1)
        env.mgr:Chase(env.fish, target, 3, 1, 5)
        env.runtime.task:pump(0.1)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
    end)

    it('test_completed_vendor_chase_resumes_same_target_without_restarting_active_task', function()
        -- 失败方式：同目标到距自然结束后退远，缓存仍报运行；参数变化被忽略。
        local target = env.runtime.newUnit(5303)
        target.Position = env.runtime.Vector(20, 0, 0)
        assert.is_true(env.mgr:Chase(env.fish, target, 3, 2.5, 30))
        env.runtime.task:pump(0.1)
        local tasks = #env.runtime.task.tasks
        assert.is_true(env.mgr:Chase(env.fish, target, 3, 2.5, 30))
        assert.are.equal(tasks, #env.runtime.task.tasks)
        target.Position = env.runtime.Vector(1, 0, 0)
        env.runtime.task:pump(0.1)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
        target.Position = env.runtime.Vector(20, 0, 0)
        assert.is_true(env.mgr:Chase(env.fish, target, 3, 2.5, 30))
        env.runtime.task:pump(0.2)
        assert.are.equal(1, env.unit.Controller.moves[#env.unit.Controller.moves].x)
    end)

    it('test_death_revokes_commands_and_restart_rebuilds', function()
        local v = env.runtime.Vector
        env.mgr:MoveDirection(env.fish, v(1, 0, 0), 3)
        env.runtime.task:pump(0.1)
        env.mgr:Stop()
        env.mgr:Start()
        assert.is_true(env.mgr:MoveDirection(env.fish, v(0, 0, 1), 3))
        env.runtime.task:pump(0.1)
        env.mgr:Remove(env.fish)
        env.runtime.task:pump(1)
        assert.is_false(env.fish.Carrier.AiOwnsMovement)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
    end)

    it('test_existing_skill_slot_counts_only_confirmed_cast_and_disconnects', function()
        local connected, handler, calls = false, nil, 0
        env.mgr.AbilityAPI = {
            GetAbility = function() return {} end,
            GetAbilityByScript = function() return { getSignals = function() return { CastStart = {
                Connect = function(_, fn) connected, handler = true, fn; return {
                    Disconnect = function() connected = false end } end,
            } } end } end,
        }
        env.fish.AbilityRecord = { Ready = true, Receiver = env.unit, Entry = { Index = 2 } }
        env.mgr.AiAPI = { StopAI = function() end, StopMove = function() end,
            Configs = { CMD_ABILITY = 5 }, BasicCommand = function(_, command, slot)
                assert.are.equal(5, command)
                assert.are.equal(2, slot)
                calls = calls + 1
                if calls == 2 then handler() end
            end }
        assert.is_false(env.mgr:CastFish(env.fish))
        assert.is_false(connected)
        assert.is_true(env.mgr:CastFish(env.fish))
        assert.is_false(connected)
        assert.are.equal(2, calls)
    end)

    it('test_failed_stop_rejects_same_frame_custom_handoff', function()
        env.unit.Controller.Move = function() error('stop-denied') end
        assert.is_false(env.mgr:Custom(env.fish))
        assert.is_false(env.mgr:Custom(env.fish))
        assert.is_false(env.mgr:Chase(env.fish, env.runtime.newUnit(5303), 3, 1, 30))
    end)

    it('test_invalid_official_position_revokes_ownership_without_poisoning_body', function()
        local v = env.runtime.Vector
        env.mgr:MoveDirection(env.fish, v(1, 0, 0), 3)
        env.unit.Position = v(0 / 0, 0, 0)
        assert.is_false(env.mgr:Sync(env.fish))
        assert.is_false(env.fish.Carrier.AiOwnsMovement)
        assert.are.equal(0, env.fish.Carrier.Body.Position.x)
    end)

    it('test_official_move_yields_to_trajectory_and_rebuilds_after_control', function()
        local v = env.runtime.Vector
        assert.is_true(env.mgr:MoveDirection(env.fish, v(1, 0, 0), 3))
        env.runtime.task:pump(0.1)
        assert.are.equal(1, env.unit.Controller.moves[#env.unit.Controller.moves].x)
        env.mgr:Pause(env.fish, true)
        env.runtime.task:pump(0.1)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
        assert.is_false(env.mgr:MoveDirection(env.fish, v(0, 0, 1), 3))
        env.mgr:Pause(env.fish, false)
        assert.is_true(env.mgr:MoveDirection(env.fish, v(0, 0, 1), 3))
        env.runtime.task:pump(0.1)
        assert.are.equal(1, env.unit.Controller.moves[#env.unit.Controller.moves].z)
        env.mgr:Custom(env.fish)
        env.runtime.task:pump(0.1)
        assert.is_false(env.fish.Carrier.AiOwnsMovement)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
    end)

    it('test_target_character_replacement_rebuilds_chase_without_old_target', function()
        local a, b = env.runtime.newUnit(5303), env.runtime.newUnit(5304)
        a.Position = env.runtime.Vector(20, 0, 0)
        b.Position = env.runtime.Vector(0, 0, 20)
        env.mgr:Chase(env.fish, a, 3, 1, 30)
        env.runtime.task:pump(0.1)
        env.mgr:Chase(env.fish, b, 3, 1, 30)
        env.runtime.task:pump(0.1)
        local last = env.unit.Controller.moves[#env.unit.Controller.moves]
        assert.are.equal(0, last.x)
        assert.are.equal(1, last.z)
        b:Destroy()
        env.runtime.task:pump(0.2)
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[#env.unit.Controller.moves]))
    end)

    it('test_trajectory_fish_enters_official_stop_and_returns_receiver_to_body', function()
        local v = env.runtime.Vector
        env.unit.Position = v(90, 10, 90)
        env.fish.Carrier.Body.Position = v(1, 2, 3)
        assert.is_true(env.mgr:Custom(env.fish))
        assert.are.equal(1, env.unit.Position.x)
        assert.is_not.is_nil(env.unit.Controller.moves[1])
        assert.are.equal(0, env.runtime.vecLen(env.unit.Controller.moves[1]))
    end)
end)

describe('TestFishAiLifecycle', function()
    local env

    before_each(function()
        env = setmetatable({}, { __index = FishLift })
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_every_configured_fish_hands_off_on_release_and_remove', function()
        local calls = {}
        env.mgr.Ai = {
            Custom = function(_, fish) calls[fish] = (calls[fish] or 0) + 1; return true end,
            Remove = function(_, fish) calls[fish] = (calls[fish] or 0) + 1 end,
            MoveDirection = function() return true end, Stop = function() end,
        }
        for id in pairs(GameCfg.Fish) do
            local fish = env:land(env.player, id)
            fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
            env.mgr:Drop(env.player)
            assert.is_not.is_nil(calls[fish], '未交接鱼种：' .. id)
            local before = calls[fish]
            env.mgr:Remove(fish)
            assert.is_true(calls[fish] > before, '未清理鱼种：' .. id)
        end
    end)

    it('test_failed_handoff_does_not_start_business_move', function()
        env.mgr.Ai = { Custom = function() return false end, Stop = function() end }
        local fish = env:land(env.player)
        env.mgr:StartMove(fish, 'peck', { x = 0, y = 0, z = 0 }, nil, nil, 1, 2, 3)
        assert.is_nil(fish.Move)
    end)

    it('test_stop_cancels_pending_bite_and_start_preserves_escape_deadline', function()
        env.mgr.Ai = { Custom = function() return true end, Pause = function() end,
            Stop = function(self) self.Stopped = true end, Start = function(self) self.Stopped = false end }
        local fish = env:land(env.player)
        fish.BiteAim = { Target = env.player, StrikeAt = 1 }
        fish.FleeAt = 30
        env.mgr:Stop()
        assert.is_nil(fish.BiteAim)
        env.mgr:Start()
        assert.are.equal(30, fish.FleeAt)
    end)
end)
