-- #43 挥砍杀鱼并拾取鱼获（沿用 tests/fish_lift_test.lua 的假引擎，另接真 PlayerData）。
-- 失败方式（先列后写）：
--   1. 鱼死亡生成 0 份或多份鱼获（Died 与 HealthChanged 双路都来），鱼获丢了鱼种 / 个体倍率；
--   2. 举着时被杀不先释放（挂点残留、持有者仍算持鱼），鱼获悬空在头顶而不是持有者脚下地面；
--   3. 鱼获不是官方鱼模型、参与物理 / 可碰撞 / 可被抓举，死亡时自动入栏，或放久了自己消失；
--   4. 拾取不校验目标、身份、距离（2 米）：越距、坏 id、不存在的鱼获都能领；
--   5. 道具栏 8 格满时仍发放或把鱼获吞掉，不给提示；鱼获叠加进同一格、个体倍率丢失；
--   6. 请求重放或两人争抢发出两份；成功后不销毁地面实体、不同步库存与鱼获列表；
--   7. 鱼种表没收敛：极品鱼仍能被钓到或留在鱼种表里。
local lu = require('luaunit')
require('tests.fish_lift_test')

TestFishLoot = {}

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

function TestFishLoot:setUp()
    TestFishLift.setUp(self)
    local env = self
    self.lootModule = package.loaded['server.Mgr.MgrLoot']
    self.diedSubs = {}
    package.loaded['server.Mgr.MgrFishCarrier'].SubscribeDied = function(_, fn)
        env.diedSubs[#env.diedSubs + 1] = fn
        return true
    end
    self.groundY = 1.0
    self.physics = { Raycast = function(_, origin, direction)
        if direction.y < 0 then return { Position = vec(origin.x, env.groundY, origin.z), Distance = 1 } end
    end }
    _G.RaycastParams = { New = function() return { FilterDescendantsInstances = {} } end }
    local get = _G.game.GetService
    _G.game = { GetService = function(s, name)
        if name == 'PhysicsService' then return env.physics end
        return get(s, name)
    end }
    self.data = {}
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    for _, player in ipairs({ self.player, self.other }) do
        player.SetAttribute = function() end
        local data = PlayerData.New(player)
        data:Init()
        self.data[player.UserId] = data
    end
    self.synced = {}
    self.broadcasts = 0
    self.replies = {}
    package.loaded['server.Mgr.MgrLoot'] = nil
    self.loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
    self.loot.FishUnit = self.mgr
    self.loot.PlayerData = {
        GetDataInst = function(_, player) return env.data[player.UserId] end,
        SendItemBar = function(_, player) env.synced[#env.synced + 1] = player end,
    }
    self.loot.Broadcast = function() env.broadcasts = env.broadcasts + 1 end
    self.loot.Reply = function(_, player, payload) env.replies[#env.replies + 1] = { player = player, payload = payload } end
    self.loot.Listen = function() end
    self.loot:Start()
end

function TestFishLoot:tearDown()
    package.loaded['server.Mgr.MgrLoot'] = self.lootModule
    TestFishLift.tearDown(self)
end

TestFishLoot.newPlayer = TestFishLift.newPlayer
TestFishLoot.land = TestFishLift.land
TestFishLoot.mounts = TestFishLift.mounts

function TestFishLoot:kill(fish)
    for _, fn in ipairs(self.diedSubs) do fn(fish.Carrier) end
end

function TestFishLoot:lootUnits()
    local list = {}
    for _, unit in ipairs(self.created) do
        if unit.UnitType == 'WorldUnit' and tostring(unit.Name):find('^FishLoot_') and not unit.Destroyed then
            list[#list + 1] = unit
        end
    end
    return list
end

function TestFishLoot:onlyLoot()
    local ids = {}
    for id in pairs(self.loot.Loots) do ids[#ids + 1] = id end
    lu.assertEquals(#ids, 1)
    return self.loot.Loots[ids[1]]
end

function TestFishLoot:bar(player)
    return self.data[player.UserId]:GetItemBarSnapshot().slots
end

function TestFishLoot:test_death_spawns_one_static_loot_with_species_and_mult()
    lu.assertEquals(#self.diedSubs, 1)
    local fish = self:land(self.player, 'catfish', 1.6)
    fish.Carrier.Body.Position = vec(4, 3, 8)
    fish.Anchor = fish.Carrier.Body.Position
    self:kill(fish)
    self:kill(fish)
    local loot = self:onlyLoot()
    lu.assertEquals(loot.FishId, 'catfish')
    lu.assertEquals(loot.Mult, 1.6)
    lu.assertNil(self.mgr.Fish[fish.Id])
    lu.assertEquals(self.despawned[#self.despawned], fish.Carrier)
    local units = self:lootUnits()
    lu.assertEquals(#units, 1)
    local unit = units[1]
    lu.assertEquals(unit.RenderMeshId, 'official://mesh/7000553')
    lu.assertFalse(unit.PhysicsActive)
    lu.assertFalse(unit.CanCollide)
    lu.assertFalse(unit.Liftable)
    lu.assertEquals(unit.Position.x, 4)
    lu.assertEquals(unit.Position.z, 8)
    lu.assertTrue(unit.Position.y >= self.groundY and unit.Position.y < 2)
    -- 不自动入栏；放很久也不消失
    lu.assertNil(self:bar(self.player)[2])
    self.now = 3600
    self.mgr:Update()
    self.loot:Update()
    lu.assertEquals(#self:lootUnits(), 1)
    lu.assertTrue(self.broadcasts >= 1)
end

function TestFishLoot:test_held_fish_killed_is_released_and_loot_lands_at_holders_feet()
    local fish = self:land(self.player, 'bass', 1.3)
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    self.pushed = {}
    self.groundY = 0.2
    self:kill(fish)
    lu.assertNil(self.mgr:GetHeld(self.player))
    lu.assertTrue(self:mounts()[1].Destroyed)
    lu.assertEquals(self.pushed[#self.pushed], self.player)
    local unit = self:lootUnits()[1]
    lu.assertEquals(unit.Position.x, self.player.Character.Position.x)
    lu.assertEquals(unit.Position.z, self.player.Character.Position.z)
    lu.assertTrue(unit.Position.y >= 0.2 and unit.Position.y < 1)
    lu.assertEquals(self:onlyLoot().Mult, 1.3)
    lu.assertTrue(self.mgr:CanCast(self.player))
end

function TestFishLoot:test_pickup_checks_target_and_distance()
    local fish = self:land(self.player, 'bass', 1.3)
    self:kill(fish)
    local loot = self:onlyLoot()
    for _, bad in ipairs({ 'x', 1.5, -1, 999 }) do
        lu.assertFalse(self.loot:Pickup(self.player, bad))
    end
    self.other.Character.Position = vec(loot.Position.x + 3, loot.Position.y, loot.Position.z)
    lu.assertFalse(self.loot:Pickup(self.other, loot.Id))
    lu.assertNotNil(self.loot.Loots[loot.Id])
    lu.assertNil(self:bar(self.other)[2])
    self.other.Character.Position = vec(loot.Position.x + 1.8, loot.Position.y + 0.8, loot.Position.z)
    lu.assertTrue(self.loot:Pickup(self.other, loot.Id))
    lu.assertEquals(self:bar(self.other)[2], { itemId = 'bass', count = 1, containerId = 'itemBar', mult = 1.3 })
end

function TestFishLoot:test_pickup_success_destroys_loot_syncs_and_replay_gives_nothing()
    local fish = self:land(self.player, 'goldfish', 1.9)
    self:kill(fish)
    local loot = self:onlyLoot()
    local unit = self:lootUnits()[1]
    self.other.Character.Position = loot.Position
    self.player.Character.Position = loot.Position
    local before = self.broadcasts
    lu.assertTrue(self.loot:Pickup(self.player, loot.Id))
    lu.assertFalse(self.loot:Pickup(self.player, loot.Id))
    lu.assertFalse(self.loot:Pickup(self.other, loot.Id))
    lu.assertTrue(unit.Destroyed)
    lu.assertNil(self.loot.Loots[loot.Id])
    lu.assertEquals(self.synced, { self.player })
    lu.assertTrue(self.broadcasts > before)
    lu.assertNil(self:bar(self.other)[2])
    local count = 0
    for _, entry in pairs(self:bar(self.player)) do
        if entry.itemId == 'goldfish' then count = count + 1 end
    end
    lu.assertEquals(count, 1)
end

function TestFishLoot:test_each_loot_takes_own_slot_and_full_bar_refuses_with_notice()
    local data = self.data[self.player.UserId]
    local mults = { 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7 }
    for _, mult in ipairs(mults) do lu.assertTrue(data:AddItem('carp', mult)) end
    local slots = self:bar(self.player)
    for index = 2, 8 do
        lu.assertEquals(slots[index].count, 1)
        lu.assertEquals(slots[index].mult, mults[index - 1])
    end
    local fish = self:land(self.player, 'bass', 1.3)
    self:kill(fish)
    local loot = self:onlyLoot()
    self.player.Character.Position = loot.Position
    lu.assertFalse(self.loot:Pickup(self.player, loot.Id))
    lu.assertNotNil(self.loot.Loots[loot.Id])
    lu.assertFalse(self:lootUnits()[1].Destroyed)
    lu.assertEquals(self.replies[#self.replies].player, self.player)
    lu.assertEquals(self.replies[#self.replies].payload.reason, 'full')
    lu.assertFalse(data:AddItem('carp', 1))
end

function TestFishLoot:test_fish_table_keeps_only_six_normal_pond_fish()
    local cfg = assert(loadfile('common/GameCfg.lua'))()
    local ids = {}
    for id, species in pairs(cfg.Fish) do
        ids[#ids + 1] = id
        lu.assertEquals(species.Grade, 'normal', id)
        lu.assertNotNil(cfg.Items.Definitions[id], id .. ' 没有物品定义')
    end
    lu.assertEquals(#ids, 6)
    for _, rows in pairs(cfg.Casting.Zones) do
        for _, row in ipairs(rows) do lu.assertNotNil(cfg.Fish[row.Id], row.Id) end
        lu.assertEquals(#rows, 6)
    end
end
