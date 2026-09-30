-- #90 虾池最小内容：虾池水区与鱼表、香肠（饵）、虾池商店（2 级摊位）、虾池钓鱼佬（多锚点回收）。
-- 失败方式（先列后写）：
--   1. 香肠没配 Container='bait'：买了占道具栏格、不进 Bait 计数，挂饵挂不上；
--   2. 摊位等级用错：一区摊能买香肠 / 钓虾竿，或虾池摊买不到；价格不是 2 / 12；
--   3. 摊位范围复验丢失：不在任何摊位旁也能买，或玩家位置不影响按哪个摊位结算；
--   4. 虾池鱼表配错：新手竿（竿 1）能出波龙及以上、不挂饵出不了虾米保底、
--      挂香肠竿 1 能出竿 2 的虾，或鱼表行指向 GameCfg.Fish 里不存在的鱼种；
--   5. 虾池水区没进 Water.Zones（抛竿选不到虾池鱼表），或与一区水区重叠（在虾池抛竿出一区鱼）；
--   6. 钓鱼佬多锚点回归：一区钓鱼佬失效，或虾池钓鱼佬（TGUnitFishShrimp）旁喂食不结算；
--   7. 抛竿竿种门：选中的不是竿（无 Level）也能抛，或钓虾竿抛出去竿级按 1 算（抽不出波龙）。
local lu = require('luaunit')

TestShrimpPond = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 两个商店摊与两个钓鱼佬锚点的假位置（虾池侧坐标与场景摆位一致：店 (106,-0.5,97)、钓鱼佬 (94,-4,100)）
local ANCHORS = {
    TGUnitShop = vec(0, 2, 0),
    TGUnitShopShrimp = vec(106, -0.5, 97),
    TGUnitFish = vec(0, 6, 10),
    TGUnitFishShrimp = vec(94, -4, 100),
}

local function newInteract()
    return {
        FindAnchor = function(_, name)
            local pos = ANCHORS[name]
            return pos and { Name = name, Position = pos } or nil
        end,
        InRange = function(_, player, point)
            local pos = player.Character and player.Character.Position
            local anchor = ANCHORS[point.AnchorName]
            if not pos or not anchor then return nil end
            local dx, dz = pos.x - anchor.x, pos.z - anchor.z
            if math.sqrt(dx * dx + dz * dz) > point.Radius + point.Slack then return nil end
            return { Name = point.AnchorName, Position = anchor }
        end,
    }
end

function TestShrimpPond:setUp()
    local env = self
    self.saved = {
        game = rawget(_G, 'game'),
        GameCfg = package.loaded['common.GameCfg'],
        REUtil = package.loaded['common.REUtil'],
        MgrPlayerData = package.loaded['server.Mgr.MgrPlayerData'],
        MgrFishUnit = package.loaded['server.Mgr.MgrFishUnit'],
    }
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    -- 与 shop_test 同一口径：吃 #49 调试白送的起始库存（鱼竿第 1 格、蚯蚓若干）
    self.cfg.Debug = { Enabled = true, InitialGrants = self.cfg.Debug.InitialGrants }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.me = { UserId = 1, Character = { Position = vec(0, 2, 2) }, SetAttribute = function() end }
    self.data = PlayerData.New(self.me)
    self.data:Init()
    self.replies = {}
    self.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
    self.shop.PlayerData = {
        GetDataInst = function(_, p) return p == env.me and env.data or nil end,
        SendItemBar = function() end,
    }
    self.shop.Interact = newInteract()
    self.shop.Reply = function(_, _, result) env.replies[#env.replies + 1] = result end
    self.seq = 0
    -- MgrCast 桩（与 boss_bait_test 同口径）：REUtil 记录下发，PlayerData/FishUnit 指向真数据
    self.me.Character.Rotation = { GetForward = function() return vec(0, 0, 1) end }
    self.now = 0
    self.sent = {}
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            env.sent[name] = env.sent[name] or {}
            return { FireClient = function(_, _, payload)
                env.sent[name][#env.sent[name] + 1] = payload
            end }
        end,
        CheckRECD = function() return false end,
    }
    package.loaded['server.Mgr.MgrPlayerData'] = {
        GetDataInst = function(_, p) return p == env.me and env.data or nil end,
        SendItemBar = function() end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = {
        HeldInfo = function() return nil end,
        CanCast = function() return true end,
    }
    self.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    self.cast.World = { GetServerTime = function() return env.now end }
    self.cast.ReelIn = { Begin = function() return true end }
end

function TestShrimpPond:tearDown()
    package.loaded['common.GameCfg'] = self.saved.GameCfg
    package.loaded['common.REUtil'] = self.saved.REUtil
    package.loaded['server.Mgr.MgrPlayerData'] = self.saved.MgrPlayerData
    package.loaded['server.Mgr.MgrFishUnit'] = self.saved.MgrFishUnit
    _G.game = self.saved.game
end

function TestShrimpPond:buy(itemId)
    self.seq = self.seq + 1
    return self.shop:Handle(self.me, { action = 'Buy', itemId = itemId, seq = self.seq })
end

function TestShrimpPond:lastReason()
    local last = self.replies[#self.replies]
    return last and last.reason
end

function TestShrimpPond:moveTo(name)
    local anchor = ANCHORS[name]
    self.me.Character.Position = vec(anchor.x + 1, anchor.y, anchor.z)
end

-- 配置钉住：香肠是饵（Container='bait'）、商店 2 金 2 级起售；虾池摊 2 级、一区摊 1 级
function TestShrimpPond:test_sausage_definition_and_shop_rows()
    local sausage = self.cfg.Items.Definitions.sausage
    lu.assertNotNil(sausage)
    lu.assertEquals(sausage.Container, 'bait')
    lu.assertEquals(self.cfg.Items.Id.Sausage, 'sausage')
    local goods
    for _, g in ipairs(self.cfg.Shop.Goods) do
        if g.ItemId == 'sausage' then goods = g end
    end
    lu.assertNotNil(goods)
    lu.assertEquals(goods.Price, 2)
    lu.assertEquals(goods.MinShopLevel, 2)
    -- 摊位表：一区摊 1 级、虾池摊 2 级、蟹湖摊 3 级（等级语义：第 N 钓鱼区起售竿级 N，#84；蟹湖摊 #136 接入）
    local stands = {}
    for _, stand in ipairs(self.cfg.Shop.Stands) do stands[stand.AnchorName] = stand.Level end
    lu.assertEquals(stands, { TGUnitShop = 1, TGUnitShopShrimp = 2, Z3_Shop = 3 })
end

-- 虾池摊买香肠：扣 2 金、进 Bait 计数、不占道具栏格
function TestShrimpPond:test_buy_sausage_at_shrimp_stand_goes_to_bait_counter()
    self:moveTo('TGUnitShopShrimp')
    self.data:AddCoin(10, nil, 'test')
    lu.assertTrue(self:buy('sausage'))
    lu.assertEquals(self.data.Data.FishCoin, 8)
    lu.assertEquals(self.data.Data.Bait.sausage, 1)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[2])
    lu.assertTrue(self.replies[#self.replies].ok)
    lu.assertEquals(self.replies[#self.replies].price, 2)
end

-- 一区摊买不到香肠与钓虾竿（'item' 且不扣钱）；两摊都能买蚯蚓
function TestShrimpPond:test_home_stand_cannot_sell_shrimp_goods()
    self:moveTo('TGUnitShop')
    self.data:AddCoin(20, nil, 'test')
    lu.assertFalse(self:buy('sausage'))
    lu.assertEquals(self:lastReason(), 'item')
    lu.assertFalse(self:buy('shrimpRod'))
    lu.assertEquals(self:lastReason(), 'item')
    lu.assertEquals(self.data.Data.FishCoin, 20)
    lu.assertTrue(self:buy('worm'))
    lu.assertEquals(self.data.Data.FishCoin, 19)
end

-- 虾池摊买钓虾竿 12 金进道具栏；等级语义沿用 FindGoods(itemId, level)
function TestShrimpPond:test_shrimp_stand_sells_shrimp_rod_at_level_two()
    self:moveTo('TGUnitShopShrimp')
    self.data:AddCoin(12, nil, 'test')
    lu.assertTrue(self:buy('shrimpRod'))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data:GetItemBarSnapshot().slots[2].itemId, 'shrimpRod')
    lu.assertNotNil(self.shop:FindGoods('shrimpRod', 2))
    lu.assertNil(self.shop:FindGoods('shrimpRod', 1))
    lu.assertNil(self.shop:FindGoods('sausage', 1))
end

-- 不在任何摊位旁：'range'，不扣钱
function TestShrimpPond:test_buy_away_from_all_stands_rejected()
    self.me.Character.Position = vec(50, 2, 50)
    self.data:AddCoin(10, nil, 'test')
    lu.assertFalse(self:buy('worm'))
    lu.assertEquals(self:lastReason(), 'range')
    lu.assertEquals(self.data.Data.FishCoin, 10)
end

-- 虾池水区进 Water.Zones 且与一区水区不相交（否则抛竿先命中一区鱼表）
function TestShrimpPond:test_shrimp_pool_water_zone_registered_and_disjoint()
    local pool
    for _, zone in ipairs(self.cfg.Water.Zones) do
        if zone.Id == 'ShrimpPool' then pool = zone end
    end
    lu.assertNotNil(pool)
    lu.assertEquals(pool.Center.x, 105)
    lu.assertEquals(pool.Center.z, 106)
    lu.assertEquals(pool.HalfXZ, 3)
    for _, zone in ipairs(self.cfg.Water.Zones) do
        if zone.Id ~= 'ShrimpPool' then
            local dx = math.abs(zone.Center.x - pool.Center.x)
            local dz = math.abs(zone.Center.z - pool.Center.z)
            -- #136 起蟹湖水区是长方形（HalfX/HalfZ），与正方形 HalfXZ 同口径比较
            local zx = zone.HalfXZ or zone.HalfX
            local zz = zone.HalfXZ or zone.HalfZ
            lu.assertTrue(dx > zx + pool.HalfXZ or dz > zz + pool.HalfXZ,
                'ShrimpPool 与 ' .. zone.Id .. ' 水平重叠')
        end
    end
end

local function collectSelectable(rows, rodLevel, baitId)
    local FishCatch = require('common.FishCatch')
    local total = 0
    for _, row in ipairs(rows) do
        if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then
            total = total + row.DrawWeight
        end
    end
    local found = {}
    for roll = 1, total do
        local id = FishCatch.Select(rows, rodLevel, baitId, function() return roll end)
        found[id] = true
    end
    return found
end

-- 虾池鱼表：竿 1 不挂饵只有虾米保底（含极品）；竿 1 挂香肠不出竿 2 的虾；
-- 竿 2 挂香肠六种全可出；每行 Id 都在 GameCfg.Fish
function TestShrimpPond:test_shrimp_pool_cast_table_gating()
    local rows = self.cfg.Casting.Zones.ShrimpPool
    lu.assertNotNil(rows)
    lu.assertEquals(#rows, 13)
    for _, row in ipairs(rows) do
        lu.assertNotNil(self.cfg.Fish[row.Id], row.Id .. ' 不在 GameCfg.Fish')
    end
    lu.assertEquals(collectSelectable(rows, 1, nil), { shrimp = true, rareShrimp = true })
    local rod1 = collectSelectable(rows, 1, 'sausage')
    lu.assertTrue(rod1.riverShrimp and rod1.crayfish)
    lu.assertNil(rod1.bostonLobster)
    lu.assertNil(rod1.aussieLobster)
    lu.assertNil(rod1.milkLobster)
    local rod2 = collectSelectable(rows, 2, 'sausage')
    for _, id in ipairs({ 'shrimp', 'riverShrimp', 'crayfish', 'bostonLobster', 'aussieLobster', 'milkLobster',
        'rareShrimp', 'rareRiverShrimp', 'rareCrayfish', 'rareBostonLobster', 'rareAussieLobster', 'rareMilkLobster', 'fish15Elite' }) do
        lu.assertTrue(rod2[id], id .. ' 竿 2 挂香肠应可出')
    end
    -- 权重钉住（钓鱼表）：普通 8/8/8/32/24/16，极品 2/2/2/8/6/4
    local weights = {}
    for _, row in ipairs(rows) do weights[row.Id] = row.DrawWeight end
    lu.assertEquals(weights, { shrimp = 8, riverShrimp = 8, crayfish = 8,
        bostonLobster = 32, aussieLobster = 24, milkLobster = 16,
        rareShrimp = 2, rareRiverShrimp = 2, rareCrayfish = 2,
        rareBostonLobster = 8, rareAussieLobster = 6, rareMilkLobster = 4, fish15Elite = 10 })
end

-- 钓鱼佬按区分派（#127）：一区锚点 TGUnitFish、虾池锚点 TGUnitFishShrimp 各一个；
-- 虾池钓鱼佬旁喂鱼获照价结算，一区钓鱼佬旁同样可用
function TestShrimpPond:test_fisherman_multi_anchor_feeds_at_shrimp_pond()
    lu.assertEquals(self.cfg.Interact.Fishermen[1].AnchorNames, { 'TGUnitFish' })
    lu.assertEquals(self.cfg.Interact.Fishermen[1].ZoneId, 'fishPond')
    lu.assertEquals(self.cfg.Interact.Fishermen[2].AnchorNames, { 'TGUnitFishShrimp' })
    lu.assertEquals(self.cfg.Interact.Fishermen[2].ZoneId, 'shrimpPond')
    _G.game = { GetService = function() return {} end }
    local mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    mgr.FindAnchor = function(_, name)
        local pos = ANCHORS[name]
        return pos and { Name = name, Position = pos } or nil
    end
    local replies = {}
    mgr.PlayerData = {
        GetDataInst = function() return self.data end,
        SendItemBar = function() end,
    }
    mgr.Reply = function(_, _, payload) replies[#replies + 1] = payload end
    -- 站在虾池钓鱼佬旁：选中一格沼虾喂出 10 金（BasePrice × 倍率 1）
    self:moveTo('TGUnitFishShrimp')
    lu.assertTrue(self.data:AddItem('riverShrimp'))
    local slot
    for index = 1, 8 do
        local entry = self.data.Data.Containers.itemBar[index]
        if entry and entry.itemId == 'riverShrimp' then slot = index end
    end
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(mgr:Handle(self.me, { target = 'fisherman', action = 'Feed', seq = 1 }))
    lu.assertEquals(self.data.Data.FishCoin, 10)
    lu.assertTrue(replies[#replies].ok)
    -- 一区钓鱼佬旁同样可用（按区分派：各自只认本区锚点，互不借用）
    self:moveTo('TGUnitFish')
    lu.assertTrue(self.data:AddItem('carp'))
    for index = 1, 8 do
        local entry = self.data.Data.Containers.itemBar[index]
        if entry and entry.itemId == 'carp' then slot = index end
    end
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(mgr:Handle(self.me, { target = 'fisherman', action = 'Feed', seq = 2 }))
    lu.assertEquals(self.data.Data.FishCoin, 14)
end

-- 站在虾池南岸（105,5,100）朝 +z 抛 5 米，落点 (105,?,105) 进虾池
function TestShrimpPond:standAtPool()
    self.me.Character.Position = vec(105, 5, 100)
end

-- 钓虾竿挂香肠抛虾池：会话记 zoneId=ShrimpPool、竿级 2、饵 sausage（#90 起不限新手竿）
function TestShrimpPond:test_cast_with_shrimp_rod_records_pool_zone_and_rod_level()
    self:standAtPool()
    lu.assertTrue(self.data:AddItem('shrimpRod'))
    lu.assertTrue(self.data:SelectSlot(2))
    self.data.Data.Bait.sausage = 1
    lu.assertTrue(self.data:SelectBait('sausage'))
    self.cast:Cast(self.me, { slot = 2, itemId = 'shrimpRod' })
    local session = self.cast.Sessions[1] and self.cast.Sessions[1].session
    lu.assertNotNil(session)
    lu.assertEquals(session.zoneId, 'ShrimpPool')
    lu.assertEquals(session.rodLevel, 2)
    lu.assertEquals(session.baitId, 'sausage')
end

-- 新手竿不挂饵抛虾池：上钩只可能是虾米保底（含极品），出不了香肠行的虾
function TestShrimpPond:test_starter_rod_without_bait_only_hooks_shrimp()
    self:standAtPool()
    lu.assertTrue(self.data:SelectSlot(1))
    self.cast:Cast(self.me, { slot = 1, itemId = 'starterRod' })
    local current = self.cast.Sessions[1]
    lu.assertNotNil(current)
    lu.assertEquals(current.session.zoneId, 'ShrimpPool')
    lu.assertEquals(current.session.rodLevel, 1)
    self.now = 10
    self.cast:Update()
    lu.assertEquals(current.session.phase, 'hooked')
    lu.assertTrue(current.session.fishId == 'shrimp' or current.session.fishId == 'rareShrimp',
        '竿 1 不挂饵应只出虾米，实际 ' .. tostring(current.session.fishId))
end

-- 选中的不是竿（物品表无 Level）：抛竿不受理，不起会话（竿种门回归）
function TestShrimpPond:test_cast_with_non_rod_selected_rejected()
    self:standAtPool()
    lu.assertTrue(self.data:AddItem('carp'))
    lu.assertTrue(self.data:SelectSlot(2))
    self.cast:Cast(self.me, { slot = 2, itemId = 'carp' })
    lu.assertNil(self.cast.Sessions[1])
end

