-- #84 迁移：放下逃脱与在逃数量上限（原 tests/gameplay/fish_escape_test.lua，11 例）。
-- 接缝：MgrFishUnit 的放下→逃脱链路——释放路径幂等、朝水转向、射线限频、入水吞掉与在逃上限。
-- 沿用 tests/support/fish_escape 共享夹具；describe/it 名称保留旧类名与方法名，
-- 并按方法名字典序注册以保持与旧套件一致的执行顺序。
local FishEscape = require('tests.support.fish_escape')

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

local WALL = { Name = 'Wall' }

local function speed(v)
    return math.sqrt(v.x * v.x + v.z * v.z)
end

describe('TestFishEscape', function()
    local env

    before_each(function()
        env = FishEscape.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_death_drops_held_fish_and_breaks_cast', function()
        env:prepare()
        local aborted = {}
        env.mgr.Cast.Abort = function(_, player) aborted[#aborted + 1] = player end
        local fish = env:heldFish()
        env.player.Character.Controller.Died:Fire()
        assert.are.equal('escaping', fish.State)
        assert.same({ env.player }, aborted)
        assert.is_nil(env.mgr:GetHeld(env.player))
    end)

    it('test_drop_releases_in_front_and_starts_toward_water_without_throw', function()
        env:prepare()
        local threw = 0
        env.player.Character.Controller.Throw = function() threw = threw + 1 end
        env.player.Character.Rotation = { GetForward = function() return vec(1, 0, 0) end }
        local fish = env:heldFish(env.player, 'bass', 1.4)
        assert.is_true(env.mgr:Drop(env.player))
        local body = fish.Carrier.Body
        assert.are.equal(0, threw)
        assert.are.equal('escaping', fish.State)
        assert.same(env.world, body.Parent)
        assert.is_true(env:mounts()[1].Destroyed)
        assert.are.equal(2, body.BodyType)
        assert.is_true(body.Position.x > 10 and body.Position.x <= 12.5)
        assert.near(-20, body.Position.z, 1e-9)
        assert.near(3, speed(body.LinearVelocity), 1e-6)
        -- 墙外水区已覆盖南岸，这个落点朝南即可回水。
        assert.is_true(body.LinearVelocity.z < 0)
        assert.is_nil(env.mgr:GetHeld(env.player))
        assert.are.equal('bass', fish.FishId)
        assert.are.equal(1.4, fish.Mult)
        assert.same(env.player, env.pushed[#env.pushed])
    end)

    it('test_each_player_keeps_one_escaping_fish', function()
        env:prepare()
        local first = env:heldFish(env.player, 'bass', 1)
        env.mgr:Drop(env.player)
        env.now = 1
        local second = env:heldFish(env.player, 'carp', 1)
        env.mgr:Drop(env.player)
        assert.is_nil(env.mgr.Fish[first.Id])
        assert.same(second, env.mgr.Fish[second.Id])
        assert.same(first.Carrier, env.despawned[1])
    end)

    it('test_engine_lift_end_releases_through_same_path', function()
        env:prepare()
        local fish = env:heldFish()
        fish.Carrier.Body.OnLiftedEnd:Fire()
        assert.are.equal('escaping', fish.State)
        assert.near(3, speed(fish.Carrier.Body.LinearVelocity), 1e-6)
    end)

    it('test_global_cap_is_online_times_two_and_kicks_oldest', function()
        env:prepare()
        local third = env:newPlayer(9, vec(10, 2, 5))
        -- 数量上限用例把三条鱼都留在墙内，避免先触发入水回收。
        env.other.Character.Position = vec(10, 2, -5)
        local a = env:heldFish(env.player)
        env.mgr:Drop(env.player)
        env.now = 1
        local b = env:heldFish(env.other)
        env.mgr:Drop(env.other)
        env.now = 2
        local c = env:heldFish(third)
        env.mgr:Drop(third)
        assert.is_not.is_nil(env.mgr.Fish[a.Id])
        -- 两人离线（鱼留在场上）：在线 1 人 ⇒ 全局上限 2，踢掉最旧的
        table.remove(env.players, 2)
        table.remove(env.players, 2)
        env.now = 3
        env.mgr:Update()
        assert.is_nil(env.mgr.Fish[a.Id])
        assert.is_not.is_nil(env.mgr.Fish[b.Id])
        assert.is_not.is_nil(env.mgr.Fish[c.Id])
    end)

    it('test_only_escaping_fish_vanish_on_water_xz', function()
        env:prepare()
        local waiting = env:land(env.other, 'carp', 1)
        waiting.Anchor = vec(-11.75, 5, -12.25)
        waiting.Carrier.Body.Position = waiting.Anchor
        local held = env:heldFish(env.player)
        held.Carrier.Body.Position = vec(-11, 3, -13)
        env.mgr:Update()
        assert.is_not.is_nil(env.mgr.Fish[waiting.Id])
        assert.is_not.is_nil(env.mgr.Fish[held.Id])
        env.mgr:Drop(env.player)
        -- 岸上高度 y=3 高于水面 2.183，(x,z) 在池塘里就算入水
        held.Carrier.Body.Position = vec(-10, 3, -12)
        env.mgr:Update()
        assert.is_nil(env.mgr.Fish[held.Id])
        assert.same(held.Carrier, env.despawned[#env.despawned])
    end)

    it('test_other_player_cannot_drop_my_fish', function()
        env:prepare()
        local fish = env:heldFish()
        assert.is_false(env.mgr:Drop(env.other))
        assert.are.equal('held', fish.State)
    end)

    it('test_ray_rate_is_capped_and_non_walls_are_ignored', function()
        env:prepare()
        local fish = env:heldFish()
        env.mgr:Drop(env.player)
        local body = fish.Carrier.Body
        local trigger = { Name = 'TGUnitShop', IsA = function(_, name) return name == 'TriggerUnit' end }
        local ghost = { Name = 'Ghost', CanCollide = false }
        env.hits = { { Instance = trigger, Distance = 0.5 }, { Instance = env.other.Character, Distance = 0.6 },
            { Instance = ghost, Distance = 0.7 } }
        local before = body.LinearVelocity
        for frame = 1, 30 do
            env.now = 0.5 + frame / 30
            env.mgr:Update()
        end
        local ticks, seen = 0, {}
        for _, ray in ipairs(env.rays) do
            if not seen[ray.now] then seen[ray.now] = true ticks = ticks + 1 end
        end
        assert.is_true(ticks >= 5 and ticks <= 10, 'ticks=' .. ticks)
        assert.same(before, body.LinearVelocity)
        local excluded = {}
        for _, unit in ipairs(env.rays[1].params.FilterDescendantsInstances) do excluded[unit] = true end
        assert.is_true(excluded[env.player.Character])
        assert.is_true(excluded[body])
        assert.is_true(excluded[fish.Carrier.Receiver])
    end)

    it('test_reheads_toward_the_nearest_zone_after_moving', function()
        env:prepare()
        local fish = env:heldFish()
        env.mgr:Drop(env.player)
        local body = fish.Carrier.Body
        -- 虾池水面中心 (240,-44)，南北边缘 -56/-32：两个落点均在水区之外、离虾池最近。
        body.Position = vec(240, 1, -28)
        env.now = env.now + 3.05
        env.mgr:Update()
        assert.near(0, body.LinearVelocity.x, 1e-6)
        assert.near(-3, body.LinearVelocity.z, 1e-6)
        -- 挪到虾池另一侧：同一个 3 秒整点重算，方位从正南翻成正北
        body.Position = vec(240, 1, -60)
        env.now = env.now + 2.9
        env.mgr:Update()
        assert.near(-3, body.LinearVelocity.z, 1e-6)
        env.now = env.now + 0.2
        env.mgr:Update()
        assert.near(0, body.LinearVelocity.x, 1e-6)
        assert.near(3, body.LinearVelocity.z, 1e-6)
    end)

    it('test_release_paths_are_idempotent', function()
        env:prepare()
        local fish = env:heldFish()
        assert.is_true(env.mgr:Drop(env.player))
        local velocity = fish.Carrier.Body.LinearVelocity
        local escapedAt = fish.EscapeAt
        env.now = 0.5
        assert.is_false(env.mgr:Drop(env.player))
        fish.Carrier.Body.OnLiftedEnd:Fire()
        env.player.Character.Controller.Died:Fire()
        assert.same(velocity, fish.Carrier.Body.LinearVelocity)
        assert.are.equal(escapedAt, fish.EscapeAt)
    end)

    it('test_turns_every_three_seconds_and_ninety_degrees_on_wall', function()
        env:prepare()
        local fish = env:heldFish()
        env.mgr:Drop(env.player)
        local body = fish.Carrier.Body
        local start = body.LinearVelocity
        -- 被别的方向带偏后，3 秒整点重新朝水
        body.LinearVelocity = vec(0, 0, -3)
        env.now = 2.9
        env.mgr:Update()
        assert.are.equal(-3, body.LinearVelocity.z)
        env.now = 3.05
        env.mgr:Update()
        assert.near(start.x, body.LinearVelocity.x, 0.2)
        assert.near(start.z, body.LinearVelocity.z, 0.2)
        -- 前方 1.5 米内有墙：转 90°
        local before = body.LinearVelocity
        env.hits = { { Instance = WALL, Distance = 1.2 } }
        env.now = 3.3
        env.mgr:Update()
        local after = body.LinearVelocity
        assert.near(0, before.x * after.x + before.z * after.z, 1e-6)
        assert.near(3, speed(after), 1e-6)
    end)
end)
