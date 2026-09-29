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

-- #130：按货架行编号购买（升级行无 itemKey，编号是稳定购买键）
function TestShop:buyNumber(number, extra)
    self.seq = self.seq + 1
    local payload = { action = 'Buy', number = number, seq = self.seq }
    for k, v in pairs(extra or {}) do payload[k] = v end
    return self.shop:Handle(self.me, payload)
end

-- 新档 5 金币可买 5 金新手鱼竿（#130 验收）；失败方式：定价错或余额校验错导致买不了/扣错
function TestShop:test_five_coin_profile_buys_starter_rod()
    self.data:AddCoin(5, nil, 'test')
    lu.assertTrue(self:buy('starterRod'))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertTrue(self.replies[#self.replies].ok)
end

-- 编号购买普通商品（鱼饵进计数库存），响应带名称与编号
function TestShop:test_buy_regular_goods_by_number()
    local worms = self.data.Data.Bait.worm
    self.data:AddCoin(10, nil, 'test')
    lu.assertTrue(self:buyNumber(13)) -- 蚯蚓 1 金
    lu.assertEquals(self.data.Data.Bait.worm, worms + 1)
    lu.assertEquals(self.data.Data.FishCoin, 9)
    local last = self.replies[#self.replies]
    lu.assertTrue(last.ok)
    lu.assertEquals(last.number, 13)
    lu.assertEquals(last.name, '蚯蚓')
    lu.assertEquals(last.price, 1)
end

-- 升级行购买：扣款 + 逐级生效 + 响应带名称；重复购买走限购拒绝且不扣钱
function TestShop:test_buy_upgrade_row_by_number_settles_once()
    self.data:AddCoin(1000, nil, 'test')
    lu.assertTrue(self:buyNumber(51)) -- 近战武器升级1，50 金
    lu.assertEquals(self.data.Data.FishCoin, 950)
    lu.assertEquals(self.data:ShopUpgradeLevel('melee'), 1)
    local last = self.replies[#self.replies]
    lu.assertEquals(last.name, '近战武器升级1')
    lu.assertEquals(last.number, 51)
    lu.assertEquals(last.kind, 'melee')
    lu.assertEquals(last.level, 1)
    lu.assertAlmostEquals(self.data:WeaponDamageScale('melee'), 1.1, 1e-9)
    -- 重复强化：限购拒绝，钱与等级都不动
    lu.assertFalse(self:buyNumber(51))
    lu.assertEquals(self:lastReason(), 'limit')
    lu.assertEquals(self.data.Data.FishCoin, 950)
    lu.assertEquals(self.data:ShopUpgradeLevel('melee'), 1)
end

-- 越级购买拒绝且不扣钱
function TestShop:test_upgrade_rejects_skip_without_charge()
    self.cfg.Shop = setmetatable({ Stands = { { AnchorName = 'TGUnitShop7', Level = 7 } } },
        { __index = self.savedShop })
    self.data:AddCoin(1000, nil, 'test')
    lu.assertFalse(self:buyNumber(50)) -- 近战 2 级，未买过 1 级
    lu.assertEquals(self:lastReason(), 'level')
    lu.assertEquals(self.data.Data.FishCoin, 1000)
    lu.assertEquals(self.data:ShopUpgradeLevel('melee'), 0)
end

-- 逐级链路与逐级价格（7 级摊位）：近战/远程/弹容/爆炸物满级
function TestShop:test_full_level_chains_and_step_prices()
    self.cfg.Shop = setmetatable({ Stands = { { AnchorName = 'TGUnitShop7', Level = 7 } } },
        { __index = self.savedShop })
    self.data:AddCoin(35000, nil, 'test')
    for _, number in ipairs({ 51, 50, 49, 48, 47, 46, 45 }) do lu.assertTrue(self:buyNumber(number)) end
    lu.assertEquals(self.data:ShopUpgradeLevel('melee'), 7)
    lu.assertAlmostEquals(self.data:WeaponDamageScale('melee'), 1.7, 1e-9)
    for _, number in ipairs({ 38, 37, 36, 35, 34 }) do lu.assertTrue(self:buyNumber(number)) end
    lu.assertEquals(self.data:ShopUpgradeLevel('ranged'), 5)
    lu.assertAlmostEquals(self.data:WeaponDamageScale('ranged'), 1.5, 1e-9)
    for _, number in ipairs({ 41, 40, 39 }) do lu.assertTrue(self:buyNumber(number)) end
    lu.assertEquals(self.data:ShopUpgradeLevel('magazine'), 3)
    lu.assertEquals(self.data:MagazineSize(5), 13)
    for _, number in ipairs({ 44, 43, 42 }) do lu.assertTrue(self:buyNumber(number)) end
    lu.assertEquals(self.data:ShopUpgradeLevel('explosive'), 3)
    lu.assertAlmostEquals(self.data:WeaponDamageScale('explosive'), 1.6, 1e-9)
    -- 满级后再买任一级：限购拒绝且不扣钱
    local coin = self.data.Data.FishCoin
    lu.assertFalse(self:buyNumber(45))
    lu.assertEquals(self:lastReason(), 'limit')
    lu.assertEquals(self.data.Data.FishCoin, coin)
    -- 逐级总价：近战 6350 + 远程 15500 + 弹容 4200 + 爆炸 8400
    lu.assertEquals(35000 - coin, 6350 + 15500 + 4200 + 8400)
end

-- 客户端带的价格不采用（编号路径同样忽略）
function TestShop:test_buy_number_ignores_client_price()
    self.data:AddCoin(100, nil, 'test')
    lu.assertTrue(self:buyNumber(51, { price = 1 }))
    lu.assertEquals(self.data.Data.FishCoin, 50)
end

-- 武器不占格：满格也能买（#130 修正 CanGrant）
function TestShop:test_weapon_buy_when_slots_full()
    self.data:AddCoin(1000, nil, 'test')
    while self.data:AddItem('carp', 1) do end
    lu.assertTrue(self:buy('item134'))
    lu.assertEquals(self.data:WeaponCount('item134'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 976)
    local last = self.replies[#self.replies]
    lu.assertEquals(last.name, '指虎')
    lu.assertEquals(last.number, 26)
end

-- 编号路径的等级门槛与作废编号
function TestShop:test_buy_number_respects_level_and_excluded_rows()
    lu.assertFalse(self:buyNumber(1)) -- 科技假饵要求 7 级摊位
    lu.assertEquals(self:lastReason(), 'item')
    self.data:AddCoin(100, nil, 'test')
    lu.assertFalse(self:buyNumber(27)) -- 作废编号不在货架
    lu.assertEquals(self:lastReason(), 'item')
    lu.assertEquals(self.data.Data.FishCoin, 100)
end

-- 畸形请求：既无 itemId 也无 number、编号非整数，直接拒绝
function TestShop:test_malformed_number_requests_are_rejected()
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', seq = 1 }))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', number = 1.5, seq = 2 }))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', number = -1, seq = 3 }))
    lu.assertFalse(self.shop:Handle(self.me, { action = 'Buy', number = 51 }))
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

-- #130 code-review：旧 UpgradeStorage 通道与新升级行同口径（逐级一次、摊位最低等级、限购计数），
-- 失败方式：旧通道绕过等级门槛任意摊位扩容；绕过限购重复扩容；越级/满级提示错。
function TestShop:test_legacy_upgrade_respects_level_gate_limit_and_note_purchase()
    self.data:AddCoin(10000, nil, 'test')
    -- 1 级摊位逐级扩容成功，且把行 33（背包升级1）计入购买次数
    self.seq = self.seq + 1
    lu.assertTrue(self.shop:Handle(self.me, { action = 'UpgradeStorage', seq = self.seq }))
    lu.assertEquals(self.data.Data.UpgradeLevel, 1)
    lu.assertEquals(self.data:PurchaseCount(33), 1)
    lu.assertEquals(self.data.Data.FishCoin, 9900)
    -- 限购：级别回滚后行 33 仍计数 1/1 → 'limit' 且不扣钱
    self.data.Data.UpgradeLevel = 0
    self.seq = self.seq + 1
    lu.assertFalse(self.shop:Handle(self.me, { action = 'UpgradeStorage', seq = self.seq }))
    lu.assertEquals(self:lastReason(), 'limit')
    lu.assertEquals(self.data.Data.FishCoin, 9900)
    -- 摊位等级门槛：1 级摊位已升 1 级，下一级（行 32）需 2 级摊位 → 'level'
    self.data.Data.UpgradeLevel = 1
    self.data.Extra.growth.purchases['33'] = 0
    self.seq = self.seq + 1
    lu.assertFalse(self.shop:Handle(self.me, { action = 'UpgradeStorage', seq = self.seq }))
    lu.assertEquals(self:lastReason(), 'level')
    -- 满级：6 级后再扩 → 'max'
    self.data.Data.UpgradeLevel = 6
    self.seq = self.seq + 1
    lu.assertFalse(self.shop:Handle(self.me, { action = 'UpgradeStorage', seq = self.seq }))
    lu.assertEquals(self:lastReason(), 'max')
end
