-- #84 迁移：举鱼与新手任务事实（原 tests/gameplay/fish_lift_test.lua，12 例）。
-- 接缝：MgrFishUnit 的服务端抓举流程——上岸自动 Lift、挂点挂载、持有状态推送、任务事实上报。
-- describe/it 名称沿用旧 LuaUnit 类名与方法名，并用方法名字典序注册，
-- 保持与旧套件（LuaUnit 按类名、方法名排序执行）一致的加载与执行顺序。
local FishLift = require('tests.support.fish_lift')

local function vec(x, y, z)
    return Vector3.New(x, y, z)
end

-- 旧 TestFishLift:hold / :spyQuest 两个类内辅助，改为接收 env 的本地函数。
local function hold(env, player)
    local fish = env:land(player)
    fish.Carrier.Body.OnLiftedBegin:Fire(player.Character)
    assert.same(fish, env.mgr:GetHeld(player))
    return fish
end

local function spyQuest(env)
    env.facts = {}
    env.mgr.Quest = { Notify = function(_, kind, player, payload)
        env.facts[#env.facts + 1] = { kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId }
        return true
    end }
end

describe('TestFishLift', function()
    local env

    -- 逐例夹具：旧 LuaUnit 每个方法都走 setUp/tearDown，这里同样用 before_each/after_each，
    -- 使 setUp 失败时当前层级的 after_each 仍然执行清理。
    before_each(function()
        env = FishLift.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_collision_isolation_covers_players_receivers_and_other_fish', function()
        local first = env:land(env.player)
        local second = env:land(env.other, 'carp', 1.2)
        local a, b = first.Carrier, second.Carrier
        assert.is_true(b.Body.Pairs[env.player.Character])
        assert.is_true(b.Body.Pairs[env.other.Character])
        assert.is_true(b.Body.Pairs[a.Body] or a.Body.Pairs[b.Body])
        assert.is_true(b.Body.Pairs[a.Receiver])
        assert.is_true(a.Body.Pairs[b.Receiver])
        assert.is_false(a.Receiver.Controller.LiftedEnabled)
        local late = env:newPlayer(9, vec(0, 2, 0))
        assert.is_true(a.Body.Pairs[late.Character])
        local respawned = { Position = vec(0, 2, 0), Controller = {} }
        late.Character = respawned
        late.CharacterAdded:Fire(respawned)
        assert.is_true(a.Body.Pairs[respawned])
    end)

    it('test_drop_in_water_death_and_lift_end_do_not_notify', function()
        spyQuest(env)
        env.player.Character.Position = vec(-11.75, 2, -14)
        hold(env, env.player)
        env.mgr:Drop(env.player)
        env.player.Character.Position = vec(10, 2, -20)
        hold(env, env.player)
        env.mgr:OnDied(env.player)
        local fish = hold(env, env.player)
        env.mgr:Release(fish, 'liftEnd')
        assert.are.equal(0, #env.facts)
    end)

    it('test_drop_on_shore_notifies_holder_once', function()
        spyQuest(env)
        local fish = hold(env, env.player)
        assert.is_true(env.mgr:Drop(env.player))
        assert.is_false(env.mgr:Drop(env.player))
        env.mgr:Release(fish, 'liftEnd')
        assert.are.equal(1, #env.facts)
        assert.are.equal('DropShore', env.facts[1].kind)
        assert.same(env.player, env.facts[1].player)
        assert.are.equal('bass', env.facts[1].itemId)
        assert.is_not.is_nil(env.facts[1].eventId)
    end)

    it('test_duplicate_lifted_begin_keeps_one_mount_and_holder', function()
        local fish = env:land(env.player)
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        fish.Carrier.Body.OnLiftedBegin:Fire(env.other.Character)
        assert.are.equal(1, #env:mounts())
        assert.same(env.player, fish.Holder)
        assert.is_nil(env.mgr:GetHeld(env.other))
    end)

    it('test_held_info_keeps_species_and_multiplier_and_pushes_state', function()
        local fish = env:land(env.player, 'goldfish', 1.85)
        assert.is_nil(env.mgr:HeldInfo(env.player))
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        assert.same({ fishId = 'goldfish', mult = 1.85 }, env.mgr:HeldInfo(env.player))
        assert.same(env.player, env.pushed[#env.pushed])
    end)

    it('test_holding_blocks_new_lift_and_cast', function()
        local fish = env:land(env.player)
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        local second = env:land(env.player, 'carp', 1.1)
        assert.are.equal(1, #env.lifts)
        assert.are.equal('awaitLift', second.State)
        env.now = 10
        env.mgr:Update()
        assert.are.equal(1, #env.lifts)
        assert.is_false(env.mgr:CanCast(env.player))
        assert.is_true(env.mgr:CanCast(env.other))
    end)

    it('test_kill_is_attributed_to_owner_only_once', function()
        spyQuest(env)
        local fish = env:land(env.player)
        assert.is_not.is_nil(env.mgr:TakeKilled(fish))
        assert.is_nil(env.mgr:TakeKilled(fish))
        assert.are.equal(1, #env.facts)
        assert.are.equal('Kill', env.facts[1].kind)
        assert.same(env.player, env.facts[1].player)
        assert.are.equal('bass', env.facts[1].itemId)
        assert.is_not.is_nil(env.facts[1].eventId)
        local held = hold(env, env.other)
        env.mgr:TakeKilled(held)
        assert.are.equal(2, #env.facts)
        assert.same(env.other, env.facts[2].player)
        assert.are_not.equal(env.facts[1].eventId, env.facts[2].eventId)
    end)

    it('test_landing_lifts_once_and_mounts_on_head', function()
        local fish = env:land(env.player)
        assert.are.equal(1, #env.lifts)
        assert.same(env.player.Character, env.lifts[1])
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        fish.Carrier.Body.BodyType = 2
        assert.are.equal('held', fish.State)
        assert.same(fish, env.mgr:GetHeld(env.player))
        local mounts = env:mounts()
        assert.are.equal(1, #mounts)
        assert.are.equal('origin', mounts[1].SocketName)
        assert.same(env.player.Character, mounts[1].Parent)
        assert.near(1.9, mounts[1].SocketOffset.y, 1e-9)
        assert.are.equal(0, mounts[1].SocketOffset.x)
        assert.same(mounts[1], fish.Carrier.Body.Parent)
        env.now = 5
        env.mgr:Update()
        assert.are.equal(2, fish.Carrier.Body.BodyType)
        assert.are.equal(1, #env.lifts)
    end)

    it('test_lifted_begin_without_argument_uses_pending_lifter', function()
        local fish = env:land(env.player)
        fish.Carrier.Body.OnLiftedBegin:Fire()
        assert.same(env.player, fish.Holder)
    end)

    it('test_owner_leaving_removes_held_fish_and_mount', function()
        local fish = env:land(env.player)
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        env.mgr:OnPlayerRemoving(env.player)
        assert.is_nil(env.mgr:GetHeld(env.player))
        assert.are.equal(1, #env.despawned)
        assert.is_true(env:mounts()[1].Destroyed)
        env.mgr:Update()
    end)

    it('test_unconfirmed_lift_retries_after_confirm_window_with_cap', function()
        local fish = env:land(env.player)
        env.now = 0.3
        env.mgr:Update()
        assert.are.equal(1, #env.lifts)
        for step = 1, 40 do
            env.now = 0.3 + step * 0.5
            env.mgr:Update()
        end
        assert.are.equal(3, #env.lifts)
        assert.are.equal('awaitLift', fish.State)
    end)

    it('test_waiting_fish_is_held_still_and_nan_is_reset', function()
        local fish = env:land(env.player)
        local body = fish.Carrier.Body
        assert.is_false(fish.Carrier.Opts.GravityEnabled)
        local anchor = body.Position
        body.Position = vec(anchor.x + 0.4, anchor.y - 0.3, anchor.z)
        body.LinearVelocity = vec(1, 0, 0)
        env.mgr:Update()
        assert.near(anchor.x, body.Position.x, 1e-9)
        assert.near(anchor.y, body.Position.y, 1e-9)
        assert.are.equal(0, body.LinearVelocity.x)
        body.Position = vec(0 / 0, 1, 1)
        env.mgr:Update()
        assert.near(anchor.z, body.Position.z, 1e-9)
    end)
end)
