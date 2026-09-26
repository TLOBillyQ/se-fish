-- #43 挥砍杀鱼并拾取鱼获（沿用 tests/gameplay/fish_lift_test.lua 的假引擎，另接真 PlayerData）。
-- 失败方式（先列后写）：
--   1. 鱼死亡生成 0 份或多份鱼获（Died 与 HealthChanged 双路都来），鱼获丢了鱼种 / 个体倍率；
--   2. 举着时被杀不先释放（挂点残留、持有者仍算持鱼），鱼获悬空在头顶而不是持有者脚下地面；
--   3. 鱼获不是官方鱼模型、参与物理 / 可碰撞 / 可被抓举，死亡时自动入栏，或放久了自己消失；
--   4. 拾取不校验目标、身份、距离（2 米）：越距、坏 id、不存在的鱼获都能领；
--   5. 道具栏 8 格满时仍发放或把鱼获吞掉，不给提示；鱼获叠加进同一格、个体倍率丢失；
--   6. 请求重放或两人争抢发出两份；成功后不销毁地面实体、不同步库存与鱼获列表；
--   7. 鱼种表没收敛：极品鱼仍能被钓到或留在鱼种表里。
local lu = require('luaunit')
require('tests.gameplay.fish_lift_test')

TestFishLoot = {}

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

function TestFishLoot:setUp()
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.savedGrantDebug = self.savedGrantDebug or require('common.GameCfg').Debug -- TestBaitSpot 复用本 setUp，别把已打开的开关存成原值
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
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
    -- 固定点位鱼饵（#45）另有 tests/gameplay/bait_spot_test.lua，这里不生成，免得混进鱼获断言
    if not self.keepSpots then self.loot.StartSpots = function() end end
    self.loot:Start()
end

function TestFishLoot:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
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
    local mults = { 1.1, 1.2, 1.3, 1.4, 1.5, 1.6 }
    for _, mult in ipairs(mults) do lu.assertTrue(data:AddItem('carp', mult)) end
    local slots = self:bar(self.player)
    for index = 2, 2 do
        lu.assertEquals(slots[index].count, 1)
        lu.assertEquals(slots[index].mult, mults[index - 1])
    end
    local backpack = data:GetItemBarSnapshot().backpack
    for index = 1, 5 do
        lu.assertEquals(backpack[index].mult, mults[index + 1])
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

function TestFishLoot:test_fish_table_matches_m1_spec()
    local cfg = assert(loadfile('common/GameCfg.lua'))()
    -- 鱼种表（#84，GameSpec §5.1/§5.2）：鱼塘 6 普通 + 精英电鳗 + 首领鳄雀鳝；虾池 6 普通 + 6 极品
    local expected = {
        tilapia = 'normal', carp = 'normal', knifeFish = 'normal', bass = 'normal', catfish = 'normal', goldfish = 'normal',
        eel = 'elite', alligatorGar = 'boss',
        shrimp = 'normal', riverShrimp = 'normal', crayfish = 'normal',
        bostonLobster = 'normal', aussieLobster = 'normal', milkLobster = 'normal',
        rareShrimp = 'rare', rareRiverShrimp = 'rare', rareCrayfish = 'rare',
        rareBostonLobster = 'rare', rareAussieLobster = 'rare', rareMilkLobster = 'rare',
    }
    local count = 0
    for id, species in pairs(cfg.Fish) do
        count = count + 1
        lu.assertEquals(species.Grade, expected[id], id)
    end
    lu.assertEquals(count, 20)
    -- 极品版数值与普通版一致（GameSpec §5.2「同上」），防双写漂移
    for _, pair in ipairs({ { 'shrimp', 'rareShrimp' }, { 'riverShrimp', 'rareRiverShrimp' }, { 'crayfish', 'rareCrayfish' },
        { 'bostonLobster', 'rareBostonLobster' }, { 'aussieLobster', 'rareAussieLobster' }, { 'milkLobster', 'rareMilkLobster' } }) do
        local base, rare = cfg.Fish[pair[1]], cfg.Fish[pair[2]]
        lu.assertEquals({ rare.Health, rare.BaseWeight, rare.BasePrice, rare.Model, rare.Speed },
            { base.Health, base.BaseWeight, base.BasePrice, base.Model, base.Speed }, pair[2])
        lu.assertEquals(rare.Name, '极品' .. base.Name, pair[2])
    end
    -- 普通/极品的鱼获即自身（同名物品定义）；精英/首领不掉自身，Drops 逐项落到已有物品定义
    for id, species in pairs(cfg.Fish) do
        if species.Drops then
            for _, drop in ipairs(species.Drops) do
                lu.assertNotNil(cfg.Items.Definitions[drop.ItemId], id .. ' 的掉落 ' .. drop.ItemId .. ' 没有物品定义')
                lu.assertTrue(drop.Count >= 1, id .. ' 的掉落 ' .. drop.ItemId .. ' 数量')
            end
        else
            lu.assertNotNil(cfg.Items.Definitions[id], id .. ' 没有物品定义')
        end
    end
    -- 精英/首领数值（GameSpec §5.1 第 7/8 行与已确认结论）
    lu.assertEquals({ cfg.Fish.eel.Health, cfg.Fish.eel.Attack, cfg.Fish.eel.EscapeSec }, { 300, 10, 180 })
    lu.assertEquals({ cfg.Fish.alligatorGar.Health, cfg.Fish.alligatorGar.Attack, cfg.Fish.alligatorGar.EscapeSec }, { 600, 30, 300 })
    lu.assertEquals(cfg.Fish.eel.Drops, { { ItemId = 'eelMeat', Count = 2 }, { ItemId = 'eelHead', Count = 1 } })
    lu.assertEquals(cfg.Fish.alligatorGar.Drops, { { ItemId = 'garMeat', Count = 2 }, { ItemId = 'garHead', Count = 1 } })
    -- 信物 / 首领饵 / 船票物品定义（鸭子挂饵必出鳄雀鳝的钓取逻辑在 #88 落地）
    local defs = cfg.Items.Definitions
    lu.assertEquals(defs.eelHead.Name, '电鳗头')     -- 精英信物
    lu.assertEquals(defs.garHead.Name, '鳄雀鳝鱼头') -- 首领信物
    lu.assertEquals(defs.duck.Name, '鸭子')
    lu.assertNil(defs.duck.Container) -- #85：首领饵占道具栏或背包格
    lu.assertEquals(defs.shrimpTicket.Name, '虾池船票')
    lu.assertNil(defs.shrimpTicket.EatPercent) -- 过关道具不能吃
    -- #86：电鳗加入蚯蚓抽签表；鳄雀鳝与虾池水区随 #88/#90 接入。
    for _, rows in pairs(cfg.Casting.Zones) do
        for _, row in ipairs(rows) do lu.assertNotNil(cfg.Fish[row.Id], row.Id) end
        lu.assertEquals(#rows, 7)
        lu.assertEquals(rows[7], { Id = 'eel', Bait = 'worm', RodLevel = 1, DrawWeight = 10 })
    end
end
