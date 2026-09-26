-- #45 固定点位拾饵与十五秒刷新（沿用 tests/gameplay/fish_loot_test.lua 的假引擎与真 PlayerData）。
-- 失败方式（先列后写）：
--   1. 点位不生成，或同一点位同时出现多份（开局 / 刷新叠加）；点位不走配置，多个点位共用一个计时；
--   2. 拾取不复用 2 米复验：越距、坏 id 也能领；
--   3. 蚯蚓进了道具栏占格，或道具栏满时被拒收；进的不是既有 Bait 计数（另建库存 / 数量不对）；
--   4. 拾取后不刷新、不到 15 秒提前刷新、到点刷出多份；
--   5. 同一轮多人争抢或请求重放发出多份；
--   6. 刷新计时误用到鱼获：鱼获被刷新、到时消失。
local lu = require('luaunit')
require('tests.gameplay.fish_loot_test')

TestBaitSpot = {}

local function vec3(x, y, z)
    return { x = x, y = y, z = z }
end

function TestBaitSpot:setUp()
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.savedGrantDebug = require('common.GameCfg').Debug
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
    self.cfg = require('common.GameCfg')
    self.savedSpots = self.cfg.BaitSpots
    self.cfg.BaitSpots = {
        RespawnSec = 15, Mesh = 'official://mesh/7000571', Scale = 0.3,
        Spots = {
            { Id = 'a', ItemId = 'worm', Count = 1, Position = { x = 10, y = 5, z = 20 } },
            { Id = 'b', ItemId = 'worm', Count = 2, Position = { x = 40, y = 5, z = 20 } },
        },
    }
    self.keepSpots = true
    TestFishLoot.setUp(self)
end

function TestBaitSpot:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
    TestFishLoot.tearDown(self)
    self.cfg.BaitSpots = self.savedSpots
end

TestBaitSpot.land = TestFishLoot.land
TestBaitSpot.kill = TestFishLoot.kill
TestBaitSpot.bar = TestFishLoot.bar
TestBaitSpot.lootUnits = TestFishLoot.lootUnits
TestBaitSpot.mounts = TestFishLoot.mounts
TestBaitSpot.newPlayer = TestFishLoot.newPlayer

function TestBaitSpot:spot(id)
    for _, loot in pairs(self.loot.Loots) do
        if loot.SpotId == id then return loot end
    end
end

function TestBaitSpot:spotCount(id)
    local n = 0
    for _, loot in pairs(self.loot.Loots) do
        if loot.SpotId == id then n = n + 1 end
    end
    return n
end

function TestBaitSpot:baitUnits()
    local list = {}
    for _, unit in ipairs(self.created) do
        if tostring(unit.Name):find('^BaitSpot_') and not unit.Destroyed then list[#list + 1] = unit end
    end
    return list
end

function TestBaitSpot:worms(player)
    return self.data[player.UserId].Data.Bait.worm
end

function TestBaitSpot:test_each_configured_spot_spawns_exactly_one_bait()
    lu.assertEquals(self:spotCount('a'), 1)
    lu.assertEquals(self:spotCount('b'), 1)
    lu.assertEquals(#self:baitUnits(), 2)
    local a = self:spot('a')
    lu.assertEquals(a.Kind, 'bait')
    lu.assertEquals(a.ItemId, 'worm')
    lu.assertEquals(a.Position.x, 10)
    lu.assertEquals(a.Position.z, 20)
    lu.assertTrue(a.Position.y >= self.groundY and a.Position.y < 2)
    lu.assertEquals(self:baitUnits()[1].RenderMeshId, 'official://mesh/7000571')
    lu.assertFalse(self:baitUnits()[1].CanCollide)
    lu.assertFalse(self:baitUnits()[1].Liftable)
    self.now = 100
    self.loot:Update()
    lu.assertEquals(self:spotCount('a'), 1)
    lu.assertEquals(#self:baitUnits(), 2)
    lu.assertEquals(self.loot:Snapshot()[1].kind, 'bait')
end

function TestBaitSpot:test_pickup_goes_to_bait_count_not_item_bar_even_when_full()
    local data = self.data[self.player.UserId]
    for i = 1, 6 do lu.assertTrue(data:AddItem('carp', 1 + i / 10)) end
    local before = self:worms(self.player)
    local b = self:spot('b')
    self.player.Character.Position = vec3(b.Position.x + 1.5, b.Position.y, b.Position.z)
    lu.assertTrue(self.loot:Pickup(self.player, b.Id))
    lu.assertEquals(self:worms(self.player), before + 2)
    lu.assertEquals(self:bar(self.player)[2].itemId, 'carp')
    lu.assertEquals(data:GetItemBarSnapshot().backpack[5].itemId, 'carp')
    lu.assertEquals(self.synced, { self.player })
    lu.assertEquals(self:spotCount('b'), 0)
    lu.assertEquals(#self:baitUnits(), 1)
end

function TestBaitSpot:test_pickup_rechecks_distance_and_id()
    local a = self:spot('a')
    local before = self:worms(self.other)
    self.other.Character.Position = vec3(a.Position.x + 3, a.Position.y, a.Position.z)
    lu.assertFalse(self.loot:Pickup(self.other, a.Id))
    lu.assertFalse(self.loot:Pickup(self.other, 'a'))
    lu.assertEquals(self:worms(self.other), before)
    lu.assertEquals(self:spotCount('a'), 1)
end

function TestBaitSpot:test_respawns_after_fifteen_seconds_once_and_timers_are_per_spot()
    local a = self:spot('a')
    self.player.Character.Position = a.Position
    self.now = 10
    lu.assertTrue(self.loot:Pickup(self.player, a.Id))
    self.now = 20
    local b = self:spot('b')
    self.other.Character.Position = b.Position
    lu.assertTrue(self.loot:Pickup(self.other, b.Id))
    self.now = 24.9
    self.loot:Update()
    lu.assertEquals(self:spotCount('a'), 0)
    self.now = 25
    self.loot:Update()
    self.loot:Update()
    lu.assertEquals(self:spotCount('a'), 1)
    lu.assertEquals(self:spotCount('b'), 0)
    lu.assertNotEquals(self:spot('a').Id, a.Id)
    self.now = 35
    self.loot:Update()
    lu.assertEquals(self:spotCount('b'), 1)
    lu.assertEquals(#self:baitUnits(), 2)
end

function TestBaitSpot:test_race_and_replay_give_only_one()
    local a = self:spot('a')
    self.player.Character.Position = a.Position
    self.other.Character.Position = a.Position
    local p0, o0 = self:worms(self.player), self:worms(self.other)
    lu.assertTrue(self.loot:Pickup(self.player, a.Id))
    lu.assertFalse(self.loot:Pickup(self.other, a.Id))
    lu.assertFalse(self.loot:Pickup(self.player, a.Id))
    lu.assertEquals(self:worms(self.player), p0 + 1)
    lu.assertEquals(self:worms(self.other), o0)
    self.now = 15
    self.loot:Update()
    -- 刷新出来的是新的一份，旧 id 重放仍然无效
    lu.assertFalse(self.loot:Pickup(self.player, a.Id))
    lu.assertEquals(self:worms(self.player), p0 + 1)
end

function TestBaitSpot:test_fish_loot_is_not_refreshed_or_expired()
    local fish = self:land(self.player, 'bass', 1.3)
    self:kill(fish)
    local fishLoot
    for _, loot in pairs(self.loot.Loots) do
        if loot.Kind == 'fish' then fishLoot = loot end
    end
    lu.assertNotNil(fishLoot)
    self.player.Character.Position = fishLoot.Position
    lu.assertTrue(self.loot:Pickup(self.player, fishLoot.Id))
    self.now = 3600
    self.loot:Update()
    for _, loot in pairs(self.loot.Loots) do lu.assertEquals(loot.Kind, 'bait') end
    lu.assertEquals(#self:lootUnits(), 0)
end
