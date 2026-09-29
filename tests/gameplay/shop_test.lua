-- #48 钓场商店购买（真 PlayerData + 假交互点距离）。
-- 失败方式（先列后写）：
--   1. 余额不足也发货，或把余额扣成负数；
--   2. 道具栏满格买鱼竿仍扣钱（钱扣了货没发）；
--   3. 越出钓场老板范围仍能结算；
--   4. 不在白名单 / 商店等级不够的商品也能买，或采用了客户端带来的价格；
--   5. 同一请求（同一 seq）重放结算两次、旧 seq 仍结算，或新 seq 不能再次购买；
--   6. 鱼竿进了鱼饵库存、蚯蚓占了道具栏格；
--   7. 失败时不回失败原因（客户端无从提示），成功后不推送库存（HUD 与库存不一致）。
local lu = require('luaunit')

TestShop = {}

function TestShop:setUp()
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.savedGrantDebug = require('common.GameCfg').Debug
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
    local env = self
    self.cfg = require('common.GameCfg')
    self.savedShop = self.cfg.Shop
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.me = { UserId = 1, Character = { Position = { x = 0, y = 0, z = 0 } }, SetAttribute = function() end }
    self.data = PlayerData.New(self.me)
    self.data:Init()
    self.inRange = true
    self.replies = {}
    self.synced = 0
    self.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
    self.shop.PlayerData = {
        GetDataInst = function(_, p) return p == env.me and env.data or nil end,
        SendItemBar = function() env.synced = env.synced + 1 end,
    }
    self.shop.Interact = { InRange = function() return env.inRange end }
    self.shop.Reply = function(_, _, result) env.replies[#env.replies + 1] = result end
    self.seq = 0
end

function TestShop:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
    self.cfg.Shop = self.savedShop
end

function TestShop:buy(itemId, extra)
    self.seq = self.seq + 1
    local payload = { action = 'Buy', itemId = itemId, seq = self.seq }
    for k, v in pairs(extra or {}) do payload[k] = v end
    return self.shop:Handle(self.me, payload)
end

function TestShop:lastReason()
    local last = self.replies[#self.replies]
    return last and last.reason
end

function TestShop:test_prices_come_from_shop_table()
    local prices = {}
    for _, goods in ipairs(self.cfg.Shop.Goods) do
        if goods.ItemId then prices[goods.ItemId] = goods.Price end -- 升级行无物品，按编号购买（#130）
    end
    -- #84 七级鱼竿统一进商店表；钓虾竿起的六级竿要求商店等级 ≥ 竿级；#90 香肠 2 金 2 级起售
    lu.assertEquals(prices, { starterRod = 5, worm = 1, sausage = 2, shrimpRod = 12, crabRod = 24, normalRod = 50,
        proRod = 100, airforceRod = 200, unscientificRod = 500,
        item115 = 3, item116 = 4, item117 = 5, item118 = 6, item119 = 7,
        item134 = 24, item135 = 50, item136 = 100, item137 = 150, item138 = 200, item139 = 500,
        item140 = 1000, item141 = 2000, item142 = 5000, item143 = 24, item144 = 50, item145 = 100 })
end

function TestShop:test_rod_table_unified_seven_levels()
    local defs = self.cfg.Items.Definitions
    local rods = { 'starterRod', 'shrimpRod', 'crabRod', 'normalRod', 'proRod', 'airforceRod', 'unscientificRod' }
    local prices = { 5, 12, 24, 50, 100, 200, 500 }
    for level, id in ipairs(rods) do
        lu.assertEquals(defs[id].Level, level, id)
        local goods
        for _, g in ipairs(self.cfg.Shop.Goods) do
            if g.ItemId == id then goods = g end
        end
        lu.assertNotNil(goods, id .. ' 不在商店表')
        lu.assertEquals(goods.Price, prices[level], id)
        lu.assertEquals(goods.MinShopLevel, level, id) -- 第 N 钓鱼区起售竿级 N（GameSpec §4.5）
    end
    -- 一区摊等级 1：只有新手鱼竿可购（虾池摊等级 2 的购买路径见 shrimp_pond_test）
    lu.assertNotNil(self.shop:FindGoods('starterRod', 1))
    for level = 2, 7 do lu.assertNil(self.shop:FindGoods(rods[level], 1), rods[level]) end
end

function TestShop:test_buy_rod_and_worm_into_their_containers()
    self.data:AddCoin(6, nil, 'test')
    local worms = self.data.Data.Bait.worm
    lu.assertTrue(self:buy('starterRod'))
    lu.assertEquals(self.data.Data.FishCoin, 1)
    local slots = self.data:GetItemBarSnapshot().slots
    lu.assertEquals(slots[2].itemId, 'starterRod')
    lu.assertTrue(self:buy('worm'))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data.Data.Bait.worm, worms + 1)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[3])
    lu.assertTrue(self.replies[#self.replies].ok)
    lu.assertEquals(self.synced, 2)
end

function TestShop:test_insufficient_coin_changes_nothing()
    self.data:AddCoin(4, nil, 'test')
    lu.assertFalse(self:buy('starterRod'))
    lu.assertEquals(self:lastReason(), 'coin')
    lu.assertEquals(self.data.Data.FishCoin, 4)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[2])
end

function TestShop:test_full_item_bar_keeps_coin()
    self.data:AddCoin(20, nil, 'test')
    for _ = 1, 7 do self.data:AddItem('carp', 1) end
    lu.assertFalse(self:buy('starterRod'))
    lu.assertEquals(self:lastReason(), 'full')
    lu.assertEquals(self.data.Data.FishCoin, 20)
    -- 蚯蚓不占格，满格照样能买
    lu.assertTrue(self:buy('worm'))
    lu.assertEquals(self.data.Data.FishCoin, 19)
end

function TestShop:test_out_of_range_is_rejected()
    self.data:AddCoin(5, nil, 'test')
    self.inRange = false
    lu.assertFalse(self:buy('starterRod'))
    lu.assertEquals(self:lastReason(), 'range')
    lu.assertEquals(self.data.Data.FishCoin, 5)
end

function TestShop:test_whitelist_level_and_client_price_are_ignored()
    self.data:AddCoin(5, nil, 'test')
    for _, itemId in ipairs({ 'carp', 'gold', 42 }) do
        lu.assertFalse(self:buy(itemId))
        lu.assertEquals(self:lastReason(), 'item')
    end
    -- 客户端带的价格不采用
    lu.assertTrue(self:buy('starterRod', { price = 0 }))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    -- 摊位等级不够的商品不上架
    self.cfg.Shop = setmetatable({ Stands = { { AnchorName = 'TGUnitShop', Level = 1 } }, Goods = {
        { ItemId = 'worm', Price = 1, Page = '钓具', MinShopLevel = 2, PurchaseLimit = 0 },
    } }, { __index = self.savedShop })
    self.data:AddCoin(1, nil, 'test')
    lu.assertFalse(self:buy('worm'))
    lu.assertEquals(self:lastReason(), 'item')
    lu.assertEquals(self.data.Data.FishCoin, 1)
end

function TestShop:test_replay_settles_once_and_new_request_buys_again()
    self.data:AddCoin(15, nil, 'test')
    lu.assertTrue(self:buy('starterRod'))
    local replay = { action = 'Buy', itemId = 'starterRod', seq = self.seq }
    lu.assertFalse(self.shop:Handle(self.me, replay))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', itemId = 'starterRod', seq = self.seq - 1 }))
    lu.assertEquals(self.data.Data.FishCoin, 10)
    lu.assertTrue(self:buy('starterRod'))
    lu.assertEquals(self.data.Data.FishCoin, 5)
    local rods = 0
    for _, slot in pairs(self.data:GetItemBarSnapshot().slots) do
        if slot.itemId == 'starterRod' then rods = rods + 1 end
    end
    for _, slot in pairs(self.data:GetItemBarSnapshot().backpack) do
        if slot.itemId == 'starterRod' then rods = rods + 1 end
    end
    lu.assertEquals(rods, 3)
end

function TestShop:test_upgrade_is_authoritative_and_replay_does_not_charge_again()
    self.data:AddCoin(100, nil, 'test')
    self.seq = self.seq + 1
    local request = { action = 'UpgradeStorage', seq = self.seq, price = 0 }
    lu.assertTrue(self.shop:Handle(self.me, request))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data:GetItemBarSnapshot().slotCount, 3)
    lu.assertEquals(self.data:GetItemBarSnapshot().backpackCount, 10)
    lu.assertFalse(self.shop:Handle(self.me, request))
    lu.assertEquals(self.data:GetItemBarSnapshot().slotCount, 3)
    lu.assertEquals(self.data.Data.FishCoin, 0)
end

function TestShop:test_upgrade_rejects_insufficient_coin_and_range()
    self.inRange = false
    self.seq = self.seq + 1
    lu.assertFalse(self.shop:Handle(self.me, { action = 'UpgradeStorage', seq = self.seq }))
    lu.assertEquals(self:lastReason(), 'range')
    self.inRange = true
    self.seq = self.seq + 1
    lu.assertFalse(self.shop:Handle(self.me, { action = 'UpgradeStorage', seq = self.seq }))
    lu.assertEquals(self:lastReason(), 'coin')
    lu.assertEquals(self.data:GetItemBarSnapshot().slotCount, 2)
end

function TestShop:test_malformed_requests_are_rejected()
    self.data:AddCoin(5, nil, 'test')
    lu.assertFalse(self.shop:Handle(self.me, 'Buy'))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Sell', itemId = 'worm', seq = 100 }))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', itemId = 'worm', seq = 1.5 }))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', itemId = 'worm' }))
    lu.assertEquals(self.data.Data.FishCoin, 5)
end
