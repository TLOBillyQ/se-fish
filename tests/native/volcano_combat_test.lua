-- #90 迁移：火山岛战斗（原 tests/gameplay/volcano_combat_test.lua，1 类 12 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（单类，方法按字典序）。
-- #38 失败方式（编码前列出）：沧龙砸击永不落地/重复伤害、巡航不叼人、不移入水域；
-- 哥斯拉吐息零伤害、跟踪必中、无方向；阶段被携带挡住/跨阈值重复切换/旧预警残留；
-- 正常血量死亡、逃跑时限、玩家离线后还结算旧招。
-- 接缝沿用 #37 的真实管理器 SpawnLanded/Drop/Update、Controller 和对外预警。
--
-- 旧文件靠 `TestVolcanoCombat.setUp = TestReefCombat.setUp` 继承礁石岛夹具（LuaUnit 的全局类名互访）。
-- Busted 下两个 spec 各自 require 同一份 tests/support/isle_combat.lua，逐案例 open/close；
-- 本岛的差异只有：出生点换 7 号区安全点、补 RemoteEvent 全局、摘掉 server.AbilityAPI 的模块缓存，
-- 因此 close 之后再恢复这三样，顺序与旧 tearDown（先礁石后本岛补充）保持一致。
local Cfg = require('common.GameCfg')
local Islet = require('tests.support.isle_combat')

describe('TestVolcanoCombat', function()
    local env
    local savedExtra
    before_each(function()
        savedExtra = { remote = rawget(_G, 'RemoteEvent'), ability = package.loaded['server.AbilityAPI'] }
        env = Islet.open(7)
        _G.RemoteEvent = { New = function() return { OnServerEvent = {
            Connect = function() return { Disconnect = function() end } end } } end }
        package.loaded['server.AbilityAPI'] = nil
        local p = Cfg.Zones[7].Scene.SafePoint
        env.player.Character.Position = env.vec(p.x, p.y, p.z)
    end)
    after_each(function()
        Islet.close(env)
        _G.RemoteEvent = savedExtra.remote
        package.loaded['server.AbilityAPI'] = savedExtra.ability
    end)

    it('test_breath_has_reachable_range_and_player_can_dodge_sideways', function()
        env.player.Character.Controller.Health = 1000
        local fish = env:drop('fish56Boss')
        local p = fish.Carrier.Body.Position
        env.player.Character.Position = env.vec(p.x, p.y, p.z + 8)
        env.now = 30
        env.mgr:Update()
        local warning = env.notices[#env.notices]
        assert.is_not_nil(warning)
        assert.same('bossBreath', warning.move)
        env.player.Character.Position = env.vec(p.x + 4, p.y, p.z + 8)
        env.now = 32
        env.mgr:Update()
        assert.same(1000, env.player.Character.Controller.Health)
    end)

    -- 吐息只杀锁定的正前方一条线：预警期间不掉血，结算一次打到 0。
    it('test_breath_warns_then_kills_only_locked_forward_line', function()
        env.player.Character.Controller.Health = 1000
        env:drop('fish56Boss')
        env.now = 30
        env.mgr:Update()
        env.now = 30.1
        env.mgr:Update()
        env.now = 30.2
        env.mgr:Update()
        local warning = env.notices[#env.notices]
        assert.is_not_nil(warning)
        assert.same('bossBreath', warning.move)
        assert.same('line', warning.shape)
        assert.is_true(env.player.Character.Controller.Health > 0)
        env.now = 31.8
        env.mgr:Update()
        assert.same(0, env.player.Character.Controller.Health)
        assert.same('clear', env.notices[#env.notices].kind)
    end)

    -- 携带撞到旁边的人也要掉血，且一秒一次（不逐帧叠伤）。
    it('test_carry_contact_hits_nearby_bystander_once_per_second', function()
        env.player.Character.Controller.Health = 5000
        local fish = env:drop('fish55Elite')
        env:advance(18.7)
        local controller = { Health = 1000 }
        function controller:TakeDamage(amount) self.Health = math.max(0, self.Health - amount) end
        local peer = { UserId = 3802, SetAttribute = function() end,
            Character = { Controller = controller, Position = fish.Carrier.Body.Position } }
        env.players[2] = peer
        env.vitals:OnPlayerAdded(peer)
        controller.Health = 1000
        while env.now < 19.7 - 1e-8 do
            peer.Character.Position = fish.Carrier.Body.Position
            env.now = math.min(19.7, env.now + 0.05)
            env.mgr:Update()
        end
        env.vitals:OnPlayerRemoving(peer)
        env.players[2] = nil
        assert.same(850, controller.Health)
    end)

    -- 控制起手取消水中旧招；解除后平移冷却，不能立即补放控制期间到期的跳跃。
    it('test_control_cancels_aquatic_warning_and_resumes_without_overdue_leap', function()
        env.player.Character.Controller.Health = 5000
        env:drop('fish55Elite')
        env:advance(15.1)
        local controlled = true
        env.mgr.Ai = { Pause = function() end, Custom = function() return true end, Sync = function() return true end,
            Remove = function() end, Stop = function() end }
        env.mgr.Ability = { FishParalyzed = function() return controlled end, RemoveFish = function() end }
        env.now = 15.2
        env.mgr:Update()
        assert.same('clear', env.notices[#env.notices].kind)
        assert.same('controlled', env.notices[#env.notices].reason)
        env.now = 40
        env.mgr:Update()
        controlled = false
        env.now = 40.1
        env.mgr:Update()
        env.now = 41
        env.mgr:Update()
        assert.same('clear', env.notices[#env.notices].kind)
        env.mgr.Ai = nil
    end)

    -- 跨两个阈值只算一次切换；离线与死亡都要清掉待结算的吐息。
    it('test_cross_two_thresholds_and_offline_or_death_clear_pending_breath', function()
        local fish = env:drop('fish56Boss')
        env.player.Character.Controller.Health = 1000
        env.now = 30
        env.mgr:Update()
        env.now = 30.1
        env.mgr:Update()
        env.now = 30.2
        env.mgr:Update()
        fish.Carrier.Receiver.Controller:TakeDamage(21000)
        env.mgr:Update()
        assert.same('clear', env.notices[#env.notices].kind)
        assert.same('enraged', fish.Phase.Phase)
        assert.same(1, fish.Phase.Stats.Transitions)
        env.now = 41
        env.mgr:Update()
        env.now = 41.1
        env.mgr:Update()
        env.now = 41.2
        env.mgr:Update()
        env.mgr:OnPlayerRemoving(env.player)
        assert.same('clear', env.notices[#env.notices].kind)
        env.mgr:Remove(fish)
        env.now = 60
        env.mgr:Update()
        assert.is_true(env.player.Character.Controller.Health > 0)
    end)

    -- 携带不能推迟落地甩头；预警到期后必须清掉，不能带入水中才结算。
    it('test_head_warning_expires_at_landing_deadline_even_during_carry', function()
        env.player.Character.Controller.Health = 5000
        local fish = env:drop('fish55Elite')
        env:advance(15.1)
        env.now = 17.7
        env.mgr:Update()
        assert.is_not_nil(fish.Carry)
        assert.same('mosasaurHead', env.notices[#env.notices].move)
        env.now = 18.6
        env.mgr:Update()
        assert.same('clear', env.notices[#env.notices].kind)
        assert.same('head', env.notices[#env.notices].reason)
    end)

    -- 致命叼人不能留下携带态与挂点；玩家死亡要取消预警。
    it('test_lethal_grab_does_not_leave_carry_or_mount_and_death_cancels_warning', function()
        local fish = env:drop('fish55Elite')
        env:advance(15.1)
        env.now = 17.7
        env.mgr:Update()
        assert.same(0, env.player.Character.Controller.Health)
        assert.is_nil(fish.Carry)
        assert.is_nil(fish.CarryMount)
    end)

    -- 砸击或咬击同步触发 Died 后，旧跳跃不能再给死者建甩头预警。
    it('test_lethal_landing_or_grab_does_not_rebuild_a_head_warning', function()
        local controller = env.player.Character.Controller
        function controller:TakeDamage(amount)
            self.Health = math.max(0, self.Health - amount)
            self.HealthChanged:Fire(self.Health)
            if self.Health == 0 then self.Died:Fire() end
        end
        for _, health in ipairs({ 35, 300 }) do
            controller.Health = health
            env.vitals:OnPlayerRemoving(env.player)
            env.vitals:OnPlayerAdded(env.player)
            controller.Health = health
            local fish = env:drop('fish55Elite')
            env:advance(env.now + 15.1)
            env:advance(env.now + 2.6)
            assert.same(0, controller.Health)
            assert.same('clear', env.notices[#env.notices].kind)
            assert.is_nil(fish.BossWarn)
            assert.is_nil(fish.Aquatic.HeadAt)
            env.mgr:Remove(fish)
        end
    end)

    -- 沧龙：预警→落地一次伤害→把玩家叼向真正的水域。
    it('test_mosasaur_warns_lands_once_and_carries_player_toward_actual_water', function()
        env.player.Character.Controller.Health = 1000
        local fish = env:drop('fish55Elite')
        env:advance(15.1)
        assert.same('mosasaurLeap', env.notices[#env.notices].move)
        env:advance(18)
        assert.is_not_nil(fish.Carry)
        assert.is_true(env.player.Character.Controller.Health <= 665)
        local MathWater = require('common.MathWaterJudge')
        env:advance(25)
        assert.is_not_nil(MathWater.HitZone(Cfg.Water.Zones, env.player.Character.Position))
    end)

    -- 表/正文并集失败方式：有爪击却漏掉正文独立跺脚（2秒、脚边10米150）。
    it('test_stomp_warns_with_ten_metre_radius_and_deals_documented_damage', function()
        env.player.Character.Controller.Health = 1000
        local fish = env:drop('fish56Boss')
        local p = fish.Carrier.Body.Position
        env.player.Character.Position = env.vec(p.x, p.y, p.z + 8)
        env:advance(2.1)
        assert.same('bossStomp', env.notices[#env.notices].move)
        assert.same(10, env.notices[#env.notices].range)
        env:advance(3)
        assert.same(850, env.player.Character.Controller.Health)
    end)

    -- Stop 要同时取消水中与首领预警；本岛没有接官方 AI 适配器，路径必须自己走通。
    it('test_stop_cancels_aquatic_and_boss_warnings_without_ai_adapter', function()
        env:drop('fish55Elite')
        env:advance(15.1)
        env.mgr:Stop()
        assert.same('clear', env.notices[#env.notices].kind)
        assert.same('stop', env.notices[#env.notices].reason)
    end)

    -- 入水阶段要把鱼搬进真正的水域；狂暴打断携带与旧预警，且只切两次阈值。
    it('test_water_phase_reaches_water_and_enrage_interrupts_carry_and_old_warning_once', function()
        env.player.Character.Controller.Health = 5000
        local fish = env:drop('fish56Boss')
        fish.Carrier.Receiver.Controller:TakeDamage(11000)
        env.mgr:Update()
        env:advance(5)
        local MathWater = require('common.MathWaterJudge')
        assert.is_not_nil(MathWater.HitZone(Cfg.Water.Zones, fish.Carrier.Body.Position))
        env:advance(18)
        assert.is_not_nil(fish.Carry)
        fish.Carrier.Receiver.Controller:TakeDamage(10000)
        env.mgr:Update()
        assert.is_nil(fish.Carry)
        assert.is_nil(MathWater.HitZone(Cfg.Water.Zones, fish.Carrier.Body.Position))
        env.mgr:Update()
        env.mgr:Update()
        assert.same(2, fish.Phase.Stats.Transitions)
        assert.same('enraged', fish.Phase.Phase)
    end)
end)
