-- #53 公开接缝：根 AiAPI → MgrAi → 实际载体交接。
-- 失败方式（先列后写）：官方/轨迹同时写；控制释放不重建；目标重生沿用旧角色；
-- 删除后任务残留；多次启动叠加；无 Controller 静默成功；倍率重复；失败继续写位置。
local lu = require('luaunit')
local Loader = require('tests.tooling.official_ai_vendor_runtime')
require('tests.gameplay.fish_lift_test')
local GameCfg = require('common.GameCfg')
TestFishAiLifecycle = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts' }) do
    TestFishAiLifecycle[name] = TestFishLift[name]
end
function TestFishAiLifecycle:test_every_configured_fish_hands_off_on_release_and_remove()
    local calls = {}
    self.mgr.Ai = {
        Custom = function(_, fish) calls[fish] = (calls[fish] or 0) + 1; return true end,
        Remove = function(_, fish) calls[fish] = (calls[fish] or 0) + 1 end,
        MoveDirection = function() return true end, Stop = function() end,
    }
    for id in pairs(GameCfg.Fish) do
        local fish = self:land(self.player, id)
        fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
        self.mgr:Drop(self.player)
        lu.assertNotNil(calls[fish], '未交接鱼种：' .. id)
        local before = calls[fish]
        self.mgr:Remove(fish)
        lu.assertTrue(calls[fish] > before, '未清理鱼种：' .. id)
    end
end
function TestFishAiLifecycle:test_stop_cancels_pending_bite_and_start_preserves_escape_deadline()
    self.mgr.Ai = { Custom = function() return true end, Pause = function() end,
        Stop = function(self) self.Stopped = true end, Start = function(self) self.Stopped = false end }
    local fish = self:land(self.player)
    fish.BiteAim = { Target = self.player, StrikeAt = 1 }
    fish.FleeAt = 30
    self.mgr:Stop()
    lu.assertNil(fish.BiteAim)
    self.mgr:Start()
    lu.assertEquals(fish.FleeAt, 30)
end
TestAiMigration = {}
function TestAiMigration:setUp()
    self.ai, self.runtime = Loader.loadAi()
    local env = setmetatable({ Vector3 = { New = self.runtime.Vector }, require = function(name)
        if name == 'server.AiAPI' then return self.ai end
        return require(name)
    end }, { __index = _G })
    self.mgr = assert(loadfile('server/Mgr/MgrAi.lua', 't', env))()
    self.unit = self.runtime.newUnit(5301)
    self.fish = { Id = 1, Carrier = { Receiver = self.unit, Body = self.runtime.newUnit(5302) } }
end
function TestAiMigration:test_existing_skill_slot_counts_only_confirmed_cast_and_disconnects()
    local connected, handler, calls = false, nil, 0
    self.mgr.AbilityAPI = {
        GetAbility = function() return {} end,
        GetAbilityByScript = function() return { getSignals = function() return { CastStart = {
            Connect = function(_, fn) connected, handler = true, fn; return {
                Disconnect = function() connected = false end } end,
        } } end } end,
    }
    self.fish.AbilityRecord = { Ready = true, Receiver = self.unit, Entry = { Index = 2 } }
    self.mgr.AiAPI = { StopAI = function() end, StopMove = function() end,
        Configs = { CMD_ABILITY = 5 }, BasicCommand = function(_, command, slot)
            lu.assertEquals(command, 5); lu.assertEquals(slot, 2)
            calls = calls + 1
            if calls == 2 then handler() end
        end }
    lu.assertFalse(self.mgr:CastFish(self.fish))
    lu.assertFalse(connected)
    lu.assertTrue(self.mgr:CastFish(self.fish))
    lu.assertFalse(connected)
    lu.assertEquals(calls, 2)
end

function TestAiMigration:test_invalid_official_position_revokes_ownership_without_poisoning_body()
    local v = self.runtime.Vector
    self.mgr:MoveDirection(self.fish, v(1, 0, 0), 3)
    self.unit.Position = v(0/0, 0, 0)
    lu.assertFalse(self.mgr:Sync(self.fish))
    lu.assertFalse(self.fish.Carrier.AiOwnsMovement)
    lu.assertEquals(self.fish.Carrier.Body.Position.x, 0)
end

function TestAiMigration:test_target_character_replacement_rebuilds_chase_without_old_target()
    local a, b = self.runtime.newUnit(5303), self.runtime.newUnit(5304)
    a.Position = self.runtime.Vector(20, 0, 0)
    b.Position = self.runtime.Vector(0, 0, 20)
    self.mgr:Chase(self.fish, a, 3, 1, 30)
    self.runtime.task:pump(0.1)
    self.mgr:Chase(self.fish, b, 3, 1, 30)
    self.runtime.task:pump(0.1)
    local last = self.unit.Controller.moves[#self.unit.Controller.moves]
    lu.assertEquals(last.x, 0)
    lu.assertEquals(last.z, 1)
    b:Destroy()
    self.runtime.task:pump(0.2)
    lu.assertEquals(self.runtime.vecLen(self.unit.Controller.moves[#self.unit.Controller.moves]), 0)
end

function TestAiMigration:test_trajectory_fish_enters_official_stop_and_returns_receiver_to_body()
    local v = self.runtime.Vector
    self.unit.Position = v(90, 10, 90)
    self.fish.Carrier.Body.Position = v(1, 2, 3)
    lu.assertTrue(self.mgr:Custom(self.fish))
    lu.assertEquals(self.unit.Position.x, 1)
    lu.assertNotNil(self.unit.Controller.moves[1])
    lu.assertEquals(self.runtime.vecLen(self.unit.Controller.moves[1]), 0)
end

function TestAiMigration:test_death_revokes_commands_and_restart_rebuilds()
    local v = self.runtime.Vector
    self.mgr:MoveDirection(self.fish, v(1, 0, 0), 3)
    self.runtime.task:pump(0.1)
    self.mgr:Stop()
    self.mgr:Start()
    lu.assertTrue(self.mgr:MoveDirection(self.fish, v(0, 0, 1), 3))
    self.runtime.task:pump(0.1)
    self.mgr:Remove(self.fish)
    self.runtime.task:pump(1)
    lu.assertFalse(self.fish.Carrier.AiOwnsMovement)
    lu.assertEquals(self.runtime.vecLen(self.unit.Controller.moves[#self.unit.Controller.moves]), 0)
end

function TestAiMigration:test_official_move_yields_to_trajectory_and_rebuilds_after_control()
    local v = self.runtime.Vector
    lu.assertTrue(self.mgr:MoveDirection(self.fish, v(1, 0, 0), 3))
    self.runtime.task:pump(0.1)
    lu.assertEquals(self.unit.Controller.moves[#self.unit.Controller.moves].x, 1)
    self.mgr:Pause(self.fish, true)
    self.runtime.task:pump(0.1)
    lu.assertEquals(self.runtime.vecLen(self.unit.Controller.moves[#self.unit.Controller.moves]), 0)
    lu.assertFalse(self.mgr:MoveDirection(self.fish, v(0, 0, 1), 3))
    self.mgr:Pause(self.fish, false)
    lu.assertTrue(self.mgr:MoveDirection(self.fish, v(0, 0, 1), 3))
    self.runtime.task:pump(0.1)
    lu.assertEquals(self.unit.Controller.moves[#self.unit.Controller.moves].z, 1)
    self.mgr:Custom(self.fish)
    self.runtime.task:pump(0.1)
    lu.assertFalse(self.fish.Carrier.AiOwnsMovement)
    lu.assertEquals(self.runtime.vecLen(self.unit.Controller.moves[#self.unit.Controller.moves]), 0)
end
