-- #90 迁移：礁石岛战斗（原 tests/gameplay/reef_combat_test.lua，1 类 13 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（单类，方法按字典序）。
-- #37 失败方式（编码前列出）：空中鱼仍不可抽取；飞过水面即消失；投掷未执行或重复结算；
-- 预警不锁落点导致无法躲避；俯冲不预警；死亡/超时留下攻击；本体与受击体错帧。
-- 接缝：真实业务管理器的 SpawnLanded/Drop/Update、RemoteEvent 和 Controller 血量。
-- 仅替换引擎对象、时间和 RemoteEvent，不替换业务管理器；不作为编辑器 E2E 证据。
--
-- 假引擎世界搬到 tests/support/isle_combat.lua：旧套件里 volcano_combat 用
-- `TestVolcanoCombat.setUp = TestReefCombat.setUp` 直接继承这份夹具（靠 LuaUnit 的全局类名互访），
-- Busted 下两个 spec 各自 open/close 同一个 support 模块，逐案例新建世界，口径不变。
local Cfg = require('common.GameCfg')
local Islet = require('tests.support.isle_combat')

describe('TestReefCombat', function()
    local env
    before_each(function()
        env = Islet.open(6)
    end)
    after_each(function()
        Islet.close(env)
    end)

    -- 失败方式：空中普通鱼与企鹅朝最近水区逃脱，且不因「一秒时限」被提前移除。
    it('test_air_normal_and_penguin_escape_toward_water_without_one_second_removal', function()
        local air = env:drop('item81')
        assert.same('escaping', air.State)
        env:advance(1.05)
        assert.same(air, env.mgr.Fish[air.Id])
        assert.is_true(air.Carrier.Body.LinearVelocity.z > 0)
        local penguin = env:drop('item82')
        assert.same('escaping', penguin.State)
    end)

    -- 同一快照重复下发不重复建单位；解除抓钩要清掉视觉本体。
    it('test_air_source_client_reuses_snapshot_and_clears_when_unhooked', function()
        local visual = require('client.LocalCastSource')
        local s = { phase = 'hooked', castId = 37, fishId = 'item81', hookPosition = { x = 880, y = 15, z = 144 } }
        visual:Show(s)
        local count = #env.units
        visual:Show(s)
        assert.same(count, #env.units)
        local body
        for _, u in ipairs(env.units) do if u.Name == 'CastSource_37' then body = u end end
        assert.is_not_nil(body)
        assert.same(15, body.Position.y)
        visual:Show({ phase = 'unhooked', castId = 37 })
        assert.is_true(body.Destroyed)
    end)

    -- 首领在别处水域被召唤时，飞行边界仍取当前区，不跟着水区换。
    it('test_boss_summoned_at_other_water_keeps_the_current_zone_flight_bounds', function()
        local safe = Cfg.Zones[1].Scene.SafePoint
        env.player.Character.Position = env.vec(safe.x, safe.y, safe.z)
        local fish = env:drop('fish48Boss')
        env:advance(0.05)
        local b = Cfg.Zones[1].Scene.Boundary
        assert.is_true(fish.Carrier.Body.Position.x >= b.MinX and fish.Carrier.Body.Position.x <= b.MaxX)
    end)

    -- 抓举状态回灌：air 来源要把钩位抬到空中，water 来源保持落点原样。
    it('test_cast_state_exposes_air_origin_and_preserves_water_landing', function()
        local cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
        local session = { phase = 'hooked', castId = 37, fishId = 'item81', landing = { x = 880, y = 3, z = 144 } }
        cast:SendState(env.player, session)
        local s = env.castStates[#env.castStates]
        assert.same('air', s.catchSource)
        assert.same({ x = 880, y = 15, z = 144 }, s.hookPosition)
        assert.same({ x = 880, y = 3, z = 144 }, s.landing)
        session.fishId = 'item82'
        cast:SendState(env.player, session)
        assert.same(session.landing, env.castStates[#env.castStates].hookPosition)
    end)

    -- 官方 AI 的停止/恢复是外部边界，业务驱动与预警/Vitals 仍走真实 Update。
    it('test_control_cancels_air_warning_and_never_hits_old_locked_point', function()
        local fish = env:drop('fish48Boss')
        env:advance(4)
        local attack = fish.AirAttacks.airThrow
        assert.is_not_nil(attack)
        env.mgr.Ai = { Stopped = true, Sync = function() return true end, Pause = function() end, Custom = function() end }
        env.mgr:Update()
        assert.same({ kind = 'clear', fishId = attack.Id, reason = 'controlled' }, env.notices[#env.notices])
        env:advance(6)
        env.mgr.Ai.Stopped = false
        env.mgr:Update()
        assert.same(300, env.player.Character.Controller.Health)
        assert.is_nil(fish.AirAttacks.airThrow)
        env.mgr.Ai = nil
    end)

    -- 控制期间冻结投掷/俯冲冷却，解除后平移而不是补放积压招式。
    it('test_control_freezes_throw_and_dive_cooldowns_without_catchup', function()
        local fish = env:drop('fish48Boss')
        env:advance(3)
        env.mgr.Ai = { Stopped = true, Sync = function() return true end, Pause = function() end, Custom = function() end }
        env.mgr:Update()
        local throwAt, diveAt = fish.NextThrowAt, fish.NextReefDiveAt
        env:advance(13)
        env.mgr.Ai.Stopped = false
        env.mgr:Update()
        assert.near(throwAt + 10, fish.NextThrowAt, 1e-6)
        assert.near(diveAt + 10, fish.NextReefDiveAt, 1e-6)
        assert.is_nil(fish.AirAttacks.airThrow)
        env:advance(14)
        assert.is_not_nil(fish.AirAttacks.airThrow)
        assert.same(300, env.player.Character.Controller.Health)
        env.mgr.Ai = nil
    end)

    -- 失败方式：俯冲不能跟着目标游出本区围栏（越区追击）。
    it('test_dive_cannot_follow_a_target_outside_reef_boundary', function()
        local fish = env:drop('fish47Elite')
        local b = Cfg.Zones[6].Scene.Boundary
        env.player.Character.Position = env.vec(b.MaxX + 10, 6, Cfg.Zones[6].Scene.SafePoint.z)
        env:advance(20)
        while env.now < 21.75 do
            env:advance(env.now + 0.05)
            assert.is_true(fish.Carrier.Body.Position.x <= b.MaxX)
        end
    end)

    -- 失败方式：飞过水面即消失。真机契约是鱼群在水面上方存活，受击体与本体同帧跟随。
    it('test_flying_above_water_survives_and_receiver_follows_same_frame', function()
        local fish = env:drop('fish47Elite')
        local water = Cfg.Zones[6].Scene.Waters[1]
        fish.Carrier.Body.Position = env.vec(water.Center.x, water.SurfaceY + 12, water.Center.z)
        -- 重新起飞以这条真实世界坐标作为轨迹起点。
        env.mgr:StartFlight(fish, env.now)
        env:advance(0.05)
        assert.same('flying', fish.State)
        assert.same(fish.Carrier.Body.Position, fish.Carrier.Receiver.Position)
    end)

    -- 失败方式：投掷预警必须锁地面落点，命中只结算一次。
    it('test_pterosaur_throw_warns_then_hits_locked_ground_once', function()
        env:drop('fish48Boss')
        env:advance(4)
        local notice = env.notices[#env.notices]
        assert.is_not_nil(notice)
        assert.same('airThrow', notice.move)
        assert.same(5, notice.range)
        assert.same(300, env.player.Character.Controller.Health)
        env:advance(5.3)
        assert.same(200, env.player.Character.Controller.Health)
        env.mgr:Update()
        env.mgr:Update()
        assert.same(200, env.player.Character.Controller.Health)
    end)

    -- 失败方式：空中鱼仍不可抽取（进不了普通抽取池）；抓取来源口径 air/water 被合并。
    it('test_reef_fish_enter_normal_draw_pool_and_distinguish_air_source', function()
        local FishCatch = require('common.FishCatch')
        local rows = Cfg.Casting.Zones['reefIsland.water']
        assert.same('item81', FishCatch.Select(rows, 1, nil, function() return 0 end))
        assert.same('air', Cfg.Fish.item81.CatchSource)
        assert.same('water', Cfg.Fish.item82.CatchSource)
        assert.same('water', Cfg.Fish.item88.CatchSource)
    end)

    -- Stop 清掉旧招后 Start 必须恢复现存礁石鱼的冷却，不能永久停攻或补结算旧预警。
    it('test_restart_restores_existing_air_fish_attack_after_a_fresh_cooldown', function()
        env:drop('fish48Boss')
        env:advance(4)
        env.mgr:Stop()
        env.mgr:Start()
        env:advance(7.9)
        assert.same(300, env.player.Character.Controller.Health)
        env:advance(8.1)
        assert.same('airThrow', env.notices[#env.notices].move)
        env:advance(9.4)
        assert.same(200, env.player.Character.Controller.Health)
    end)

    -- 失败方式：管理器 Stop 后在飞的预警必须清除，且不能把待结算的命中补上。
    it('test_stop_clears_inflight_warning_without_applying_pending_hit', function()
        env:drop('fish48Boss')
        env:advance(4)
        env.mgr:Stop()
        assert.same('clear', env.notices[#env.notices].kind)
        assert.same('stop', env.notices[#env.notices].reason)
    end)

    -- 客户端预警：投掷表现建下落体，clear 必须销毁它（不留在场景里）。
    it('test_throw_client_displays_falling_body_and_clear_destroys_it', function()
        local warn = require('client.LocalGarBite')
        warn:Start()
        local n = require('common.GarBiteNotice')
        local p = n.Lock(-37, { x = 0, y = 6, z = 0 }, 0, 1, 5, 180, 1.2)
        p.move, p.shape, p.flightOrigin = 'airThrow', 'circle', { x = 0, y = 21, z = 0 }
        warn:Show(p)
        local body
        for _, u in ipairs(env.units) do if u.Name == 'FlightThrow_-37' then body = u end end
        assert.is_not_nil(body)
        env.now = 0.6
        env.heartbeat:Fire()
        assert.is_true(body.Position.y > 6 and body.Position.y < 21)
        warn:Show(n.Clear(-37, 'miss'))
        assert.is_true(body.Destroyed)
        warn:Stop()
    end)
end)
