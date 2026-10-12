-- #86 迁移（原 tests/gameplay/shop_test.lua，#48 钓场商店购买：真 PlayerData + 假交互点距离）。
-- 失败方式（先列后写）：
--   1. 余额不足也发货，或把余额扣成负数；
--   2. 道具栏满格买鱼竿仍扣钱（钱扣了货没发）；
--   3. 越出钓场老板范围仍能结算；
--   4. 不在白名单 / 商店等级不够的商品也能买，或采用了客户端带来的价格；
--   5. 同一请求（同一 seq）重放结算两次、旧 seq 仍结算，或新 seq 不能再次购买；
--   6. 鱼竿进了鱼饵库存、蚯蚓占了道具栏格；
--   7. 失败时不回失败原因（客户端无从提示），成功后不推送库存（HUD 与库存不一致）。
local GameCfg = require('common.GameCfg')

describe("钓场商店购买", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对。
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）。
    before_each(function()
        ctx = { replies = {}, synced = 0, seq = 0, inRange = true }
        ctx.savedGrantDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = true, InitialGrants = ctx.savedGrantDebug.InitialGrants }
        ctx.cfg = GameCfg
        ctx.savedShop = ctx.cfg.Shop
        local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
        ctx.me = { UserId = 1, Character = { Position = { x = 0, y = 0, z = 0 } }, SetAttribute = function() end }
        ctx.data = PlayerData.New(ctx.me)
        ctx.data:Init()
        ctx.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
        ctx.shop.PlayerData = {
            GetDataInst = function(_, p) return p == ctx.me and ctx.data or nil end,
            SendItemBar = function() ctx.synced = ctx.synced + 1 end,
        }
        ctx.shop.Interact = { InRange = function() return ctx.inRange end }
        ctx.shop.Reply = function(_, _, result) ctx.replies[#ctx.replies + 1] = result end
    end)

    -- 调试开关与商店表逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        GameCfg.Debug = ctx.savedGrantDebug
        ctx.cfg.Shop = ctx.savedShop
    end)

    local function buy(itemId, extra)
        ctx.seq = ctx.seq + 1
        local payload = { action = 'Buy', itemId = itemId, seq = ctx.seq }
        for k, v in pairs(extra or {}) do payload[k] = v end
        return ctx.shop:Handle(ctx.me, payload)
    end

    local function lastReason()
        local last = ctx.replies[#ctx.replies]
        return last and last.reason
    end

    -- #130：按货架行编号购买（升级行无 itemKey，编号是稳定购买键）
    local function buyNumber(number, extra)
        ctx.seq = ctx.seq + 1
        local payload = { action = 'Buy', number = number, seq = ctx.seq }
        for k, v in pairs(extra or {}) do payload[k] = v end
        return ctx.shop:Handle(ctx.me, payload)
    end

    -- 新档 5 金币可买 5 金新手鱼竿（#130 验收）；失败方式：定价错或余额校验错导致买不了/扣错
    it("test_five_coin_profile_buys_starter_rod", function()
        ctx.data:AddCoin(5, nil, 'test')
        assert.is_true(buy('starterRod'))
        assert.same(0, ctx.data.Data.FishCoin)
        assert.is_true(ctx.replies[#ctx.replies].ok)
    end)

    -- 编号购买普通商品（鱼饵进计数库存），响应带名称与编号
    it("test_buy_regular_goods_by_number", function()
        local worms = ctx.data.Data.Bait.worm
        ctx.data:AddCoin(10, nil, 'test')
        assert.is_true(buyNumber(13)) -- 蚯蚓 1 金
        assert.same(worms + 1, ctx.data.Data.Bait.worm)
        assert.same(9, ctx.data.Data.FishCoin)
        local last = ctx.replies[#ctx.replies]
        assert.is_true(last.ok)
        assert.same(13, last.number)
        assert.same('蚯蚓', last.name)
        assert.same(1, last.price)
    end)

    -- 升级行购买：扣款 + 逐级生效 + 响应带名称；重复购买走限购拒绝且不扣钱
    it("test_buy_upgrade_row_by_number_settles_once", function()
        ctx.data:AddCoin(1000, nil, 'test')
        assert.is_true(buyNumber(51)) -- 近战武器升级1，50 金
        assert.same(950, ctx.data.Data.FishCoin)
        assert.same(1, ctx.data:ShopUpgradeLevel('melee'))
        local last = ctx.replies[#ctx.replies]
        assert.same('近战武器升级1', last.name)
        assert.same(51, last.number)
        assert.same('melee', last.kind)
        assert.same(1, last.level)
        assert.near(1.1, ctx.data:WeaponDamageScale('melee'), 1e-9)
        -- 重复强化：限购拒绝，钱与等级都不动
        assert.is_false(buyNumber(51))
        assert.same('limit', lastReason())
        assert.same(950, ctx.data.Data.FishCoin)
        assert.same(1, ctx.data:ShopUpgradeLevel('melee'))
    end)

    -- 越级购买拒绝且不扣钱
    it("test_upgrade_rejects_skip_without_charge", function()
        ctx.cfg.Shop = setmetatable({ Stands = { { AnchorName = 'TGUnitShop7', Level = 7 } } },
            { __index = ctx.savedShop })
        ctx.data:AddCoin(1000, nil, 'test')
        assert.is_false(buyNumber(50)) -- 近战 2 级，未买过 1 级
        assert.same('level', lastReason())
        assert.same(1000, ctx.data.Data.FishCoin)
        assert.same(0, ctx.data:ShopUpgradeLevel('melee'))
    end)

    -- 逐级链路与逐级价格（7 级摊位）：近战/远程/弹容/爆炸物满级
    it("test_full_level_chains_and_step_prices", function()
        ctx.cfg.Shop = setmetatable({ Stands = { { AnchorName = 'TGUnitShop7', Level = 7 } } },
            { __index = ctx.savedShop })
        ctx.data:AddCoin(35000, nil, 'test')
        for _, number in ipairs({ 51, 50, 49, 48, 47, 46, 45 }) do assert.is_true(buyNumber(number)) end
        assert.same(7, ctx.data:ShopUpgradeLevel('melee'))
        assert.near(1.7, ctx.data:WeaponDamageScale('melee'), 1e-9)
        for _, number in ipairs({ 38, 37, 36, 35, 34 }) do assert.is_true(buyNumber(number)) end
        assert.same(5, ctx.data:ShopUpgradeLevel('ranged'))
        assert.near(1.5, ctx.data:WeaponDamageScale('ranged'), 1e-9)
        for _, number in ipairs({ 41, 40, 39 }) do assert.is_true(buyNumber(number)) end
        assert.same(3, ctx.data:ShopUpgradeLevel('magazine'))
        assert.same(13, ctx.data:MagazineSize(5))
        for _, number in ipairs({ 44, 43, 42 }) do assert.is_true(buyNumber(number)) end
        assert.same(3, ctx.data:ShopUpgradeLevel('explosive'))
        assert.near(1.6, ctx.data:WeaponDamageScale('explosive'), 1e-9)
        -- 满级后再买任一级：限购拒绝且不扣钱
        local coin = ctx.data.Data.FishCoin
        assert.is_false(buyNumber(45))
        assert.same('limit', lastReason())
        assert.same(coin, ctx.data.Data.FishCoin)
        -- 逐级总价：近战 6350 + 远程 15500 + 弹容 4200 + 爆炸 8400
        assert.same(6350 + 15500 + 4200 + 8400, 35000 - coin)
    end)

    -- 客户端带的价格不采用（编号路径同样忽略）
    it("test_buy_number_ignores_client_price", function()
        ctx.data:AddCoin(100, nil, 'test')
        assert.is_true(buyNumber(51, { price = 1 }))
        assert.same(50, ctx.data.Data.FishCoin)
    end)

    -- 武器不占格：满格也能买（#130 修正 CanGrant）
    it("test_weapon_buy_when_slots_full", function()
        ctx.data:AddCoin(1000, nil, 'test')
        while ctx.data:AddItem('carp', 1) do end
        assert.is_true(buy('item134'))
        assert.same(1, ctx.data:WeaponCount('item134'))
        assert.same(976, ctx.data.Data.FishCoin)
        local last = ctx.replies[#ctx.replies]
        assert.same('指虎', last.name)
        assert.same(26, last.number)
    end)

    -- 编号路径的等级门槛与作废编号
    it("test_buy_number_respects_level_and_excluded_rows", function()
        assert.is_false(buyNumber(1)) -- 科技假饵要求 7 级摊位
        assert.same('item', lastReason())
        ctx.data:AddCoin(100, nil, 'test')
        assert.is_false(buyNumber(27)) -- 作废编号不在货架
        assert.same('item', lastReason())
        assert.same(100, ctx.data.Data.FishCoin)
    end)

    -- 畸形请求：既无 itemId 也无 number、编号非整数，直接拒绝
    it("test_malformed_number_requests_are_rejected", function()
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', seq = 1 }))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', number = 1.5, seq = 2 }))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', number = -1, seq = 3 }))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', number = 51 }))
    end)

    it("test_prices_come_from_shop_table", function()
        local prices = {}
        for _, goods in ipairs(ctx.cfg.Shop.Goods) do
            if goods.ItemId then prices[goods.ItemId] = goods.Price end -- 升级行无物品，按编号购买（#130）
        end
        -- #84 七级鱼竿统一进商店表；钓虾竿起的六级竿要求商店等级 ≥ 竿级；#90 香肠 2 金 2 级起售
        assert.same({ starterRod = 5, worm = 1, sausage = 2, shrimpRod = 12, crabRod = 24, normalRod = 50,
            proRod = 100, airforceRod = 200, unscientificRod = 500,
            item115 = 3, item116 = 4, item117 = 5, item118 = 6, item119 = 7,
            item134 = 24, item135 = 50, item136 = 100, item137 = 150, item138 = 200, item139 = 500,
            item140 = 1000, item141 = 2000, item142 = 5000, item143 = 24, item144 = 50, item145 = 100 }, prices)
    end)

    it("test_rod_table_unified_seven_levels", function()
        local defs = ctx.cfg.Items.Definitions
        local rods = { 'starterRod', 'shrimpRod', 'crabRod', 'normalRod', 'proRod', 'airforceRod', 'unscientificRod' }
        local prices = { 5, 12, 24, 50, 100, 200, 500 }
        for level, id in ipairs(rods) do
            assert.same(level, defs[id].Level, id)
            local goods
            for _, g in ipairs(ctx.cfg.Shop.Goods) do
                if g.ItemId == id then goods = g end
            end
            assert.is_not_nil(goods, id .. ' 不在商店表')
            assert.same(prices[level], goods.Price, id)
            assert.same(level, goods.MinShopLevel, id) -- 第 N 钓鱼区起售竿级 N（GameSpec §4.5）
        end
        -- 一区摊等级 1：只有新手鱼竿可购（虾池摊等级 2 的购买路径见 shrimp_pond_test）
        assert.is_not_nil(ctx.shop:FindGoods('starterRod', 1))
        for level = 2, 7 do assert.is_nil(ctx.shop:FindGoods(rods[level], 1), rods[level]) end
    end)

    it("test_buy_rod_and_worm_into_their_containers", function()
        ctx.data:AddCoin(6, nil, 'test')
        local worms = ctx.data.Data.Bait.worm
        assert.is_true(buy('starterRod'))
        assert.same(1, ctx.data.Data.FishCoin)
        local slots = ctx.data:GetItemBarSnapshot().slots
        assert.same('starterRod', slots[2].itemId)
        assert.is_true(buy('worm'))
        assert.same(0, ctx.data.Data.FishCoin)
        assert.same(worms + 1, ctx.data.Data.Bait.worm)
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[3])
        assert.is_true(ctx.replies[#ctx.replies].ok)
        assert.same(2, ctx.synced)
    end)

    it("test_insufficient_coin_changes_nothing", function()
        ctx.data:AddCoin(4, nil, 'test')
        assert.is_false(buy('starterRod'))
        assert.same('coin', lastReason())
        assert.same(4, ctx.data.Data.FishCoin)
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[2])
    end)

    it("test_full_item_bar_keeps_coin", function()
        ctx.data:AddCoin(20, nil, 'test')
        for _ = 1, 7 do ctx.data:AddItem('carp', 1) end
        assert.is_false(buy('starterRod'))
        assert.same('full', lastReason())
        assert.same(20, ctx.data.Data.FishCoin)
        -- 蚯蚓不占格，满格照样能买
        assert.is_true(buy('worm'))
        assert.same(19, ctx.data.Data.FishCoin)
    end)

    it("test_out_of_range_is_rejected", function()
        ctx.data:AddCoin(5, nil, 'test')
        ctx.inRange = false
        assert.is_false(buy('starterRod'))
        assert.same('range', lastReason())
        assert.same(5, ctx.data.Data.FishCoin)
    end)

    it("test_whitelist_level_and_client_price_are_ignored", function()
        ctx.data:AddCoin(5, nil, 'test')
        for _, itemId in ipairs({ 'carp', 'gold', 42 }) do
            assert.is_false(buy(itemId))
            assert.same('item', lastReason())
        end
        -- 客户端带的价格不采用
        assert.is_true(buy('starterRod', { price = 0 }))
        assert.same(0, ctx.data.Data.FishCoin)
        -- 摊位等级不够的商品不上架
        ctx.cfg.Shop = setmetatable({ Stands = { { AnchorName = 'TGUnitShop', Level = 1 } }, Goods = {
            { ItemId = 'worm', Price = 1, Page = '钓具', MinShopLevel = 2, PurchaseLimit = 0 },
        } }, { __index = ctx.savedShop })
        ctx.data:AddCoin(1, nil, 'test')
        assert.is_false(buy('worm'))
        assert.same('item', lastReason())
        assert.same(1, ctx.data.Data.FishCoin)
    end)

    it("test_replay_settles_once_and_new_request_buys_again", function()
        ctx.data:AddCoin(15, nil, 'test')
        assert.is_true(buy('starterRod'))
        local replay = { action = 'Buy', itemId = 'starterRod', seq = ctx.seq }
        assert.is_false(ctx.shop:Handle(ctx.me, replay))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', itemId = 'starterRod', seq = ctx.seq - 1 }))
        assert.same(10, ctx.data.Data.FishCoin)
        assert.is_true(buy('starterRod'))
        assert.same(5, ctx.data.Data.FishCoin)
        local rods = 0
        for _, slot in pairs(ctx.data:GetItemBarSnapshot().slots) do
            if slot.itemId == 'starterRod' then rods = rods + 1 end
        end
        for _, slot in pairs(ctx.data:GetItemBarSnapshot().backpack) do
            if slot.itemId == 'starterRod' then rods = rods + 1 end
        end
        assert.same(3, rods)
    end)

    it("test_upgrade_is_authoritative_and_replay_does_not_charge_again", function()
        ctx.data:AddCoin(100, nil, 'test')
        ctx.seq = ctx.seq + 1
        local request = { action = 'UpgradeStorage', seq = ctx.seq, price = 0 }
        assert.is_true(ctx.shop:Handle(ctx.me, request))
        assert.same(0, ctx.data.Data.FishCoin)
        assert.same(3, ctx.data:GetItemBarSnapshot().slotCount)
        assert.same(10, ctx.data:GetItemBarSnapshot().backpackCount)
        assert.is_false(ctx.shop:Handle(ctx.me, request))
        assert.same(3, ctx.data:GetItemBarSnapshot().slotCount)
        assert.same(0, ctx.data.Data.FishCoin)
    end)

    it("test_upgrade_rejects_insufficient_coin_and_range", function()
        ctx.inRange = false
        ctx.seq = ctx.seq + 1
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'UpgradeStorage', seq = ctx.seq }))
        assert.same('range', lastReason())
        ctx.inRange = true
        ctx.seq = ctx.seq + 1
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'UpgradeStorage', seq = ctx.seq }))
        assert.same('coin', lastReason())
        assert.same(2, ctx.data:GetItemBarSnapshot().slotCount)
    end)

    it("test_malformed_requests_are_rejected", function()
        ctx.data:AddCoin(5, nil, 'test')
        assert.is_false(ctx.shop:Handle(ctx.me, 'Buy'))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Sell', itemId = 'worm', seq = 100 }))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', itemId = 'worm', seq = 1.5 }))
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'Buy', itemId = 'worm' }))
        assert.same(5, ctx.data.Data.FishCoin)
    end)

    -- #130 code-review：旧 UpgradeStorage 通道与新升级行同口径（逐级一次、摊位最低等级、限购计数），
    -- 失败方式：旧通道绕过等级门槛任意摊位扩容；绕过限购重复扩容；越级/满级提示错。
    it("test_legacy_upgrade_respects_level_gate_limit_and_note_purchase", function()
        ctx.data:AddCoin(10000, nil, 'test')
        -- 1 级摊位逐级扩容成功，且把行 33（背包升级1）计入购买次数
        ctx.seq = ctx.seq + 1
        assert.is_true(ctx.shop:Handle(ctx.me, { action = 'UpgradeStorage', seq = ctx.seq }))
        assert.same(1, ctx.data.Data.UpgradeLevel)
        assert.same(1, ctx.data:PurchaseCount(33))
        assert.same(9900, ctx.data.Data.FishCoin)
        -- 限购：级别回滚后行 33 仍计数 1/1 → 'limit' 且不扣钱
        ctx.data.Data.UpgradeLevel = 0
        ctx.seq = ctx.seq + 1
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'UpgradeStorage', seq = ctx.seq }))
        assert.same('limit', lastReason())
        assert.same(9900, ctx.data.Data.FishCoin)
        -- 摊位等级门槛：1 级摊位已升 1 级，下一级（行 32）需 2 级摊位 → 'level'
        ctx.data.Data.UpgradeLevel = 1
        ctx.data.Extra.growth.purchases['33'] = 0
        ctx.seq = ctx.seq + 1
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'UpgradeStorage', seq = ctx.seq }))
        assert.same('level', lastReason())
        -- 满级：6 级后再扩 → 'max'
        ctx.data.Data.UpgradeLevel = 6
        ctx.seq = ctx.seq + 1
        assert.is_false(ctx.shop:Handle(ctx.me, { action = 'UpgradeStorage', seq = ctx.seq }))
        assert.same('max', lastReason())
    end)
end)
