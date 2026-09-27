-- #42 放下逃脱与在逃数量上限（沿用 tests/gameplay/fish_lift_test.lua 的假引擎）。
-- 失败方式（先列后写）：
--   1. 放下调用 Throw，或不离开挂点 / 不回世界 / 不切 Kinematic / 起步没有速度；
--   2. 主动放下、OnLiftedEnd、死亡重复触发时释放多次或重排逃跑；
--   3. 落点不在玩家面前；速度不取鱼种配置、方向不朝水；
--   4. 不每 3 秒转向，撞墙不转 90°，射线频率超 10Hz，或被触发器 / 玩家 / 命中盒 / 鱼挡住就原地打转；
--   5. 入水判定用 y 阈值漏判，或举着 / 待抓的鱼也被入水吞掉，入水后仍有收益；
--   6. 每玩家在逃超过 1 条、全局超过在线人数 × 2，或清的不是最旧的（每人 1 条已保证优先清触发者自己的）；
--   7. 死亡不放鱼、不断线；别人能放下我的鱼。
local lu = require('luaunit')
require('tests.gameplay.fish_lift_test')

TestFishEscape = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts' }) do
    TestFishEscape[name] = TestFishLift[name]
end

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

local WALL = { Name = 'Wall' }

function TestFishEscape:prepare()
    local env = self
    self.rays = {}
    self.hits = {}
    _G.RaycastParams = { New = function() return { FilterDescendantsInstances = {} } end }
    self.physics = { Raycast = function(_, origin, direction, params)
        env.rays[#env.rays + 1] = { now = env.now, origin = origin, direction = direction, params = params }
        local excluded = {}
        for _, unit in ipairs(params and params.FilterDescendantsInstances or {}) do excluded[unit] = true end
        for _, hit in ipairs(env.hits) do
            if not excluded[hit.Instance] then return hit end
        end
    end }
    local get = _G.game.GetService
    _G.game = { GetService = function(s, name)
        if name == 'PhysicsService' then return env.physics end
        return get(s, name)
    end }
end

function TestFishEscape:heldFish(player, fishId, mult)
    player = player or self.player
    local fish = self:land(player, fishId, mult)
    fish.Carrier.Body.OnLiftedBegin:Fire(player.Character)
    fish.Carrier.Body.BodyType = 2
    return fish
end

local function speed(v)
    return math.sqrt(v.x * v.x + v.z * v.z)
end

function TestFishEscape:test_drop_releases_in_front_and_starts_toward_water_without_throw()
    self:prepare()
    local threw = 0
    self.player.Character.Controller.Throw = function() threw = threw + 1 end
    self.player.Character.Rotation = { GetForward = function() return vec(1, 0, 0) end }
    local fish = self:heldFish(self.player, 'bass', 1.4)
    lu.assertTrue(self.mgr:Drop(self.player))
    local body = fish.Carrier.Body
    lu.assertEquals(threw, 0)
    lu.assertEquals(fish.State, 'escaping')
    lu.assertEquals(body.Parent, self.world)
    lu.assertTrue(self:mounts()[1].Destroyed)
    lu.assertEquals(body.BodyType, 2)
    lu.assertTrue(body.Position.x > 10 and body.Position.x <= 12.5)
    lu.assertAlmostEquals(body.Position.z, 20, 1e-9)
    lu.assertAlmostEquals(speed(body.LinearVelocity), 3, 1e-6)
    -- 墙外水区已覆盖南岸，这个落点朝南即可回水。
    lu.assertTrue(body.LinearVelocity.z < 0)
    lu.assertNil(self.mgr:GetHeld(self.player))
    lu.assertEquals(fish.FishId, 'bass')
    lu.assertEquals(fish.Mult, 1.4)
    lu.assertEquals(self.pushed[#self.pushed], self.player)
end

function TestFishEscape:test_release_paths_are_idempotent()
    self:prepare()
    local fish = self:heldFish()
    lu.assertTrue(self.mgr:Drop(self.player))
    local velocity = fish.Carrier.Body.LinearVelocity
    local escapedAt = fish.EscapeAt
    self.now = 0.5
    lu.assertFalse(self.mgr:Drop(self.player))
    fish.Carrier.Body.OnLiftedEnd:Fire()
    self.player.Character.Controller.Died:Fire()
    lu.assertEquals(fish.Carrier.Body.LinearVelocity, velocity)
    lu.assertEquals(fish.EscapeAt, escapedAt)
end

function TestFishEscape:test_engine_lift_end_releases_through_same_path()
    self:prepare()
    local fish = self:heldFish()
    fish.Carrier.Body.OnLiftedEnd:Fire()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertAlmostEquals(speed(fish.Carrier.Body.LinearVelocity), 3, 1e-6)
end

function TestFishEscape:test_other_player_cannot_drop_my_fish()
    self:prepare()
    local fish = self:heldFish()
    lu.assertFalse(self.mgr:Drop(self.other))
    lu.assertEquals(fish.State, 'held')
end

function TestFishEscape:test_turns_every_three_seconds_and_ninety_degrees_on_wall()
    self:prepare()
    local fish = self:heldFish()
    self.mgr:Drop(self.player)
    local body = fish.Carrier.Body
    local start = body.LinearVelocity
    -- 被别的方向带偏后，3 秒整点重新朝水
    body.LinearVelocity = vec(0, 0, -3)
    self.now = 2.9
    self.mgr:Update()
    lu.assertEquals(body.LinearVelocity.z, -3)
    self.now = 3.05
    self.mgr:Update()
    lu.assertAlmostEquals(body.LinearVelocity.x, start.x, 0.2)
    lu.assertAlmostEquals(body.LinearVelocity.z, start.z, 0.2)
    -- 前方 1.5 米内有墙：转 90°
    local before = body.LinearVelocity
    self.hits = { { Instance = WALL, Distance = 1.2 } }
    self.now = 3.3
    self.mgr:Update()
    local after = body.LinearVelocity
    lu.assertAlmostEquals(before.x * after.x + before.z * after.z, 0, 1e-6)
    lu.assertAlmostEquals(speed(after), 3, 1e-6)
end

function TestFishEscape:test_ray_rate_is_capped_and_non_walls_are_ignored()
    self:prepare()
    local fish = self:heldFish()
    self.mgr:Drop(self.player)
    local body = fish.Carrier.Body
    local trigger = { Name = 'TGUnitShop', IsA = function(_, name) return name == 'TriggerUnit' end }
    local ghost = { Name = 'Ghost', CanCollide = false }
    self.hits = { { Instance = trigger, Distance = 0.5 }, { Instance = self.other.Character, Distance = 0.6 },
        { Instance = ghost, Distance = 0.7 } }
    local before = body.LinearVelocity
    for frame = 1, 30 do
        self.now = 0.5 + frame / 30
        self.mgr:Update()
    end
    local ticks, seen = 0, {}
    for _, ray in ipairs(self.rays) do
        if not seen[ray.now] then seen[ray.now] = true ticks = ticks + 1 end
    end
    lu.assertTrue(ticks >= 5 and ticks <= 10, 'ticks=' .. ticks)
    lu.assertEquals(body.LinearVelocity, before)
    local excluded = {}
    for _, unit in ipairs(self.rays[1].params.FilterDescendantsInstances) do excluded[unit] = true end
    lu.assertTrue(excluded[self.player.Character])
    lu.assertTrue(excluded[body])
    lu.assertTrue(excluded[fish.Carrier.Receiver])
end

function TestFishEscape:test_only_escaping_fish_vanish_on_water_xz()
    self:prepare()
    local waiting = self:land(self.other, 'carp', 1)
    waiting.Anchor = vec(-11.75, 5, 27.75)
    waiting.Carrier.Body.Position = waiting.Anchor
    local held = self:heldFish(self.player)
    held.Carrier.Body.Position = vec(-11, 3, 27)
    self.mgr:Update()
    lu.assertNotNil(self.mgr.Fish[waiting.Id])
    lu.assertNotNil(self.mgr.Fish[held.Id])
    self.mgr:Drop(self.player)
    -- 岸上高度 y=3 高于水面 2.183，(x,z) 在池塘里就算入水
    held.Carrier.Body.Position = vec(-10, 3, 28)
    self.mgr:Update()
    lu.assertNil(self.mgr.Fish[held.Id])
    lu.assertEquals(self.despawned[#self.despawned], held.Carrier)
end

function TestFishEscape:test_each_player_keeps_one_escaping_fish()
    self:prepare()
    local first = self:heldFish(self.player, 'bass', 1)
    self.mgr:Drop(self.player)
    self.now = 1
    local second = self:heldFish(self.player, 'carp', 1)
    self.mgr:Drop(self.player)
    lu.assertNil(self.mgr.Fish[first.Id])
    lu.assertEquals(self.mgr.Fish[second.Id], second)
    lu.assertEquals(self.despawned[1], first.Carrier)
end

function TestFishEscape:test_global_cap_is_online_times_two_and_kicks_oldest()
    self:prepare()
    local third = self:newPlayer(9, vec(10, 2, 45))
    -- 数量上限用例把三条鱼都留在墙内，避免先触发入水回收。
    self.other.Character.Position = vec(10, 2, 35)
    local a = self:heldFish(self.player)
    self.mgr:Drop(self.player)
    self.now = 1
    local b = self:heldFish(self.other)
    self.mgr:Drop(self.other)
    self.now = 2
    local c = self:heldFish(third)
    self.mgr:Drop(third)
    lu.assertNotNil(self.mgr.Fish[a.Id])
    -- 两人离线（鱼留在场上）：在线 1 人 ⇒ 全局上限 2，踢掉最旧的
    table.remove(self.players, 2)
    table.remove(self.players, 2)
    self.now = 3
    self.mgr:Update()
    lu.assertNil(self.mgr.Fish[a.Id])
    lu.assertNotNil(self.mgr.Fish[b.Id])
    lu.assertNotNil(self.mgr.Fish[c.Id])
end

function TestFishEscape:test_death_drops_held_fish_and_breaks_cast()
    self:prepare()
    local aborted = {}
    self.mgr.Cast.Abort = function(_, player) aborted[#aborted + 1] = player end
    local fish = self:heldFish()
    self.player.Character.Controller.Died:Fire()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertEquals(aborted, { self.player })
    lu.assertNil(self.mgr:GetHeld(self.player))
end
