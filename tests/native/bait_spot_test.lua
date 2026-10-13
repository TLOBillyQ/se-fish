-- #84 迁移：固定点位拾饵与十五秒刷新（原 tests/gameplay/bait_spot_test.lua，6 例）。
-- 接缝：MgrLoot 的点位鱼获——每点一份、进 Bait 计数不占道具栏、2 米复验、按点位独立计时刷新。
-- 沿用 tests/support/fish_loot 共享夹具；本类的 BaitSpots 配置替换与还原逐例进行（原类自带 setUp/tearDown）。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local FishLoot = require('tests.support.fish_loot')
local GameCfg = require('common.GameCfg')

local function vec3(x, y, z)
    return { x = x, y = y, z = z }
end

local function spot(env, id)
    for _, loot in pairs(env.loot.Loots) do
        if loot.SpotId == id then return loot end
    end
end

local function spotCount(env, id)
    local n = 0
    for _, loot in pairs(env.loot.Loots) do
        if loot.SpotId == id then n = n + 1 end
    end
    return n
end

local function baitUnits(env)
    local list = {}
    for _, unit in ipairs(env.created) do
        if tostring(unit.Name):find('^BaitSpot_') and not unit.Destroyed then list[#list + 1] = unit end
    end
    return list
end

local function worms(env, player)
    return env.data[player.UserId].Data.Bait.worm
end

-- 原 TestBaitSpot:setUp / :tearDown 的差量：夹具之外还要换掉 BaitSpots 配置。
local function setUp(env)
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    env.savedGrantDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = true, InitialGrants = env.savedGrantDebug.InitialGrants }
    env.savedSpots = GameCfg.BaitSpots
    GameCfg.BaitSpots = {
        RespawnSec = 15, Mesh = 'official://mesh/7000571', Scale = 0.3,
        Spots = {
            { Id = 'a', ItemId = 'worm', Count = 1, Position = { x = 10, y = 5, z = 20 } },
            { Id = 'b', ItemId = 'worm', Count = 2, Position = { x = 40, y = 5, z = 20 } },
        },
    }
    env.keepSpots = true
    env:setUp()
end

local function tearDown(env)
    GameCfg.Debug = env.savedGrantDebug
    env:tearDown()
    GameCfg.BaitSpots = env.savedSpots
end

describe('TestBaitSpot', function()
    local env

    before_each(function()
        env = FishLoot.new()
        setUp(env)
    end)
    -- 夹具 setUp 失败也要按已保存状态回滚，after_each 与旧 tearDown 一样照常执行。
    after_each(function()
        tearDown(env)
    end)

    it('test_each_configured_spot_spawns_exactly_one_bait', function()
        assert.are.equal(1, spotCount(env, 'a'))
        assert.are.equal(1, spotCount(env, 'b'))
        assert.are.equal(2, #baitUnits(env))
        local a = spot(env, 'a')
        assert.are.equal('bait', a.Kind)
        assert.are.equal('worm', a.ItemId)
        assert.are.equal(10, a.Position.x)
        assert.are.equal(20, a.Position.z)
        assert.is_true(a.Position.y >= env.groundY and a.Position.y < 2)
        assert.are.equal('official://mesh/7000571', baitUnits(env)[1].RenderMeshId)
        assert.is_false(baitUnits(env)[1].CanCollide)
        assert.is_false(baitUnits(env)[1].Liftable)
        env.now = 100
        env.loot:Update()
        assert.are.equal(1, spotCount(env, 'a'))
        assert.are.equal(2, #baitUnits(env))
        assert.are.equal('bait', env.loot:Snapshot()[1].kind)
    end)

    it('test_fish_loot_is_not_refreshed_or_expired', function()
        local fish = env:land(env.player, 'bass', 1.3)
        env:kill(fish)
        local fishLoot
        for _, loot in pairs(env.loot.Loots) do
            if loot.Kind == 'fish' then fishLoot = loot end
        end
        assert.is_not.is_nil(fishLoot)
        env.player.Character.Position = fishLoot.Position
        assert.is_true(env.loot:Pickup(env.player, fishLoot.Id))
        env.now = 3600
        env.loot:Update()
        for _, loot in pairs(env.loot.Loots) do assert.are.equal('bait', loot.Kind) end
        assert.are.equal(0, #env:lootUnits())
    end)

    it('test_pickup_goes_to_bait_count_not_item_bar_even_when_full', function()
        local data = env.data[env.player.UserId]
        for i = 1, 6 do assert.is_true(data:AddItem('carp', 1 + i / 10)) end
        local before = worms(env, env.player)
        local b = spot(env, 'b')
        env.player.Character.Position = vec3(b.Position.x + 1.5, b.Position.y, b.Position.z)
        assert.is_true(env.loot:Pickup(env.player, b.Id))
        assert.are.equal(before + 2, worms(env, env.player))
        assert.are.equal('carp', env:bar(env.player)[2].itemId)
        assert.are.equal('carp', data:GetItemBarSnapshot().backpack[5].itemId)
        assert.same({ env.player }, env.synced)
        assert.are.equal(0, spotCount(env, 'b'))
        assert.are.equal(1, #baitUnits(env))
    end)

    it('test_pickup_rechecks_distance_and_id', function()
        local a = spot(env, 'a')
        local before = worms(env, env.other)
        env.other.Character.Position = vec3(a.Position.x + 3, a.Position.y, a.Position.z)
        assert.is_false(env.loot:Pickup(env.other, a.Id))
        assert.is_false(env.loot:Pickup(env.other, 'a'))
        assert.are.equal(before, worms(env, env.other))
        assert.are.equal(1, spotCount(env, 'a'))
    end)

    it('test_race_and_replay_give_only_one', function()
        local a = spot(env, 'a')
        env.player.Character.Position = a.Position
        env.other.Character.Position = a.Position
        local p0, o0 = worms(env, env.player), worms(env, env.other)
        assert.is_true(env.loot:Pickup(env.player, a.Id))
        assert.is_false(env.loot:Pickup(env.other, a.Id))
        assert.is_false(env.loot:Pickup(env.player, a.Id))
        assert.are.equal(p0 + 1, worms(env, env.player))
        assert.are.equal(o0, worms(env, env.other))
        env.now = 15
        env.loot:Update()
        -- 刷新出来的是新的一份，旧 id 重放仍然无效
        assert.is_false(env.loot:Pickup(env.player, a.Id))
        assert.are.equal(p0 + 1, worms(env, env.player))
    end)

    it('test_respawns_after_fifteen_seconds_once_and_timers_are_per_spot', function()
        local a = spot(env, 'a')
        env.player.Character.Position = a.Position
        env.now = 10
        assert.is_true(env.loot:Pickup(env.player, a.Id))
        env.now = 20
        local b = spot(env, 'b')
        env.other.Character.Position = b.Position
        assert.is_true(env.loot:Pickup(env.other, b.Id))
        env.now = 24.9
        env.loot:Update()
        assert.are.equal(0, spotCount(env, 'a'))
        env.now = 25
        env.loot:Update()
        env.loot:Update()
        assert.are.equal(1, spotCount(env, 'a'))
        assert.are.equal(0, spotCount(env, 'b'))
        assert.are_not.equal(a.Id, spot(env, 'a').Id)
        env.now = 35
        env.loot:Update()
        assert.are.equal(1, spotCount(env, 'b'))
        assert.are.equal(2, #baitUnits(env))
    end)
end)
