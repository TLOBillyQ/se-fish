-- #130 失败方式先列：
--   1. 50 行有效商品没有全部上架为可购买货架行（漏行、页名错、编号 27 混入）；
--   2. 分页过滤错（等级不够的行上架、金币页混入金币定价商品）；
--   3. 新品没置顶（minShopLevel == 摊位等级的当地新品须排最前），或同组顺序不稳定（table.sort 不稳定）；
--   4. 强化公式错：不是按基础线性叠加（复利/错位）、系数与商店表不符、弹容没向上取整；
--   5. 逐级价格与商店表行价不符；
--   6. 升级行没有稳定的购买键（itemKey 缺失时 number 必须可用）；
--   7. 旧白名单商品（钓具 9 行）换表后价格/等级漂移，不再兼容。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestShopCatalog = {}

-- 钓具 1-14、武器 15-26、升级 28-51（27 作废），共 50 行
function TestShopCatalog:test_goods_is_full_50_rows_with_pages_and_numbers()
    local goods = GameCfg.Shop.Goods
    lu.assertEquals(#goods, 50)
    lu.assertEquals(GameCfg.Shop.Pages, { '钓具', '武器', '升级', '金币' })
    local seen, perPage = {}, { ['钓具'] = 0, ['武器'] = 0, ['升级'] = 0, ['金币'] = 0 }
    for _, row in ipairs(goods) do
        lu.assertNotNil(row.Number, '货架行缺购买键 number')
        lu.assertNil(seen[row.Number], '编号重复 ' .. tostring(row.Number))
        seen[row.Number] = true
        lu.assertNotEquals(row.Number, 27)
        lu.assertNotNil(perPage[row.Page], '未知分页 ' .. tostring(row.Page))
        perPage[row.Page] = perPage[row.Page] + 1
        lu.assertTrue(row.Price > 0 and row.Price % 1 == 0)
        lu.assertTrue(row.MinShopLevel >= 1 and row.MinShopLevel <= 7)
        lu.assertTrue(row.PurchaseLimit >= 0 and row.PurchaseLimit % 1 == 0)
        lu.assertNotNil(row.Name)
        lu.assertNotNil(row.source)
        if row.Page ~= '升级' then lu.assertNotNil(row.ItemId, row.Name .. ' 缺物品') end
    end
    lu.assertNil(seen[27])
    lu.assertEquals(perPage, { ['钓具'] = 14, ['武器'] = 12, ['升级'] = 24, ['金币'] = 0 })
end

-- 旧白名单 9 行在新货架同价同等级（兼容旧商品）
function TestShopCatalog:test_legacy_goods_keep_price_and_level()
    local byItem = {}
    for _, row in ipairs(GameCfg.Shop.Goods) do if row.ItemId then byItem[row.ItemId] = row end end
    local legacy = { starterRod = { 5, 1 }, worm = { 1, 1 }, sausage = { 2, 2 }, shrimpRod = { 12, 2 },
        crabRod = { 24, 3 }, normalRod = { 50, 4 }, proRod = { 100, 5 },
        airforceRod = { 200, 6 }, unscientificRod = { 500, 7 } }
    for itemId, expect in pairs(legacy) do
        local row = byItem[itemId]
        lu.assertNotNil(row, itemId .. ' 不在货架')
        lu.assertEquals(row.Price, expect[1], itemId)
        lu.assertEquals(row.MinShopLevel, expect[2], itemId)
        lu.assertEquals(row.Page, '钓具', itemId)
    end
end

-- 分页过滤 + 新品置顶 + 同组按编号稳定升序
function TestShopCatalog:test_list_for_page_filters_sorts_and_pins_new()
    local shop = GameCfg.Shop
    lu.assertNotNil(shop.ListForPage, '缺分页列表函数')
    local function numbers(rows)
        local out = {}
        for i, row in ipairs(rows) do out[i] = row.Number end
        return out
    end
    -- 1 级摊位钓具页：蚯蚓/新手鱼竿都是当地新品
    lu.assertEquals(numbers(shop.ListForPage(1, '钓具')), { 13, 14 })
    -- 2 级：新品香肠(11)/钓虾竿(12) 置顶，其余按编号
    lu.assertEquals(numbers(shop.ListForPage(2, '钓具')), { 11, 12, 13, 14 })
    -- 7 级：新品科技假饵(1)/不科学鱼竿(2) 置顶，恰好与原序一致
    local all = numbers(shop.ListForPage(7, '钓具'))
    lu.assertEquals(#all, 14)
    for i = 1, 14 do lu.assertEquals(all[i], i) end
    -- 3 级升级页：新品 = 背包3(31)/远程1(38)/爆炸1(44)/近战3(49)，其余按编号稳定序
    lu.assertEquals(numbers(shop.ListForPage(3, '升级')), { 31, 38, 44, 49, 32, 33, 41, 50, 51 })
    -- 等级不够不上架：1 级摊位的武器页只有近战 1 级两件（指虎 26、匕首 25）
    lu.assertEquals(numbers(shop.ListForPage(1, '武器')), { 25, 26 })
    -- 金币页没有金币定价商品（平台购买是外部交付参数）
    lu.assertEquals(shop.ListForPage(7, '金币'), {})
    -- 未知页与非法等级容错
    lu.assertEquals(shop.ListForPage(1, '不存在'), {})
end

-- 强化参数由商店表行派生：种类、级数、增量、逐级价格
function TestShopCatalog:test_upgrade_kinds_derived_from_shop_rows()
    local kinds = GameCfg.Shop.UpgradeKinds
    lu.assertNotNil(kinds, '缺强化参数表')
    lu.assertEquals(kinds.melee.MaxLevel, 7)
    lu.assertAlmostEquals(kinds.melee.Increment, 0.1, 1e-9)
    lu.assertEquals(kinds.melee.Prices, { 50, 100, 200, 400, 800, 1600, 3200 })
    lu.assertEquals(kinds.ranged.MaxLevel, 5)
    lu.assertAlmostEquals(kinds.ranged.Increment, 0.1, 1e-9)
    lu.assertEquals(kinds.ranged.Prices, { 500, 1000, 2000, 4000, 8000 })
    lu.assertEquals(kinds.explosive.MaxLevel, 3)
    lu.assertAlmostEquals(kinds.explosive.Increment, 0.2, 1e-9)
    lu.assertEquals(kinds.explosive.Prices, { 400, 1600, 6400 })
    lu.assertEquals(kinds.magazine.MaxLevel, 3)
    lu.assertAlmostEquals(kinds.magazine.Increment, 0.5, 1e-9)
    lu.assertTrue(kinds.magazine.RoundUp)
    lu.assertEquals(kinds.magazine.Prices, { 200, 800, 3200 })
    -- 背包升级沿用同一表的价格序列（与 Items.UpgradePrices 同源）
    lu.assertEquals(kinds.backpack.MaxLevel, 6)
    lu.assertEquals(kinds.backpack.Prices, { 100, 200, 400, 800, 1600, 3200 })
    lu.assertEquals(kinds.backpack.Prices, GameCfg.Items.UpgradePrices)
end

-- 按基础线性叠加：scale = 1 + increment × level（满级 +70%/+50%/+60%）
function TestShopCatalog:test_damage_scale_is_linear_on_base()
    local shop = GameCfg.Shop
    lu.assertNotNil(shop.DamageScale, '缺伤害加成函数')
    lu.assertAlmostEquals(shop.DamageScale('melee', 0), 1.0, 1e-9)
    lu.assertAlmostEquals(shop.DamageScale('melee', 1), 1.1, 1e-9)
    lu.assertAlmostEquals(shop.DamageScale('melee', 7), 1.7, 1e-9)
    lu.assertAlmostEquals(shop.DamageScale('ranged', 5), 1.5, 1e-9)
    lu.assertAlmostEquals(shop.DamageScale('explosive', 3), 1.6, 1e-9)
    -- 非线性就过不了：复利 1.1^7 ≈ 1.9487 ≠ 1.7
    lu.assertTrue(math.abs(shop.DamageScale('melee', 7) - 1.1 ^ 7) > 0.1)
    -- 弹容不是伤害加成；未知种类与越界等级钳制
    lu.assertNil(shop.DamageScale('magazine', 1))
    lu.assertAlmostEquals(shop.DamageScale('melee', 99), 1.7, 1e-9)
    lu.assertAlmostEquals(shop.DamageScale('melee', -3), 1.0, 1e-9)
end

-- 弹容 = ceil(base × (1 + 0.5×level))：向上取整，满级 +150%
function TestShopCatalog:test_magazine_size_rounds_up()
    local shop = GameCfg.Shop
    lu.assertNotNil(shop.MagazineSize, '缺弹容函数')
    lu.assertEquals(shop.MagazineSize(10, 0), 10)
    lu.assertEquals(shop.MagazineSize(5, 1), 8)   -- 狙击 5→7.5→8
    lu.assertEquals(shop.MagazineSize(5, 2), 10)
    lu.assertEquals(shop.MagazineSize(5, 3), 13)  -- 12.5→13
    lu.assertEquals(shop.MagazineSize(2, 3), 5)   -- 霰弹 2→5
    lu.assertEquals(shop.MagazineSize(1, 3), 3)   -- 火箭筒 1→2.5→3
    lu.assertEquals(shop.MagazineSize(30, 3), 75)
    lu.assertEquals(shop.MagazineSize(10, 3), 25)
    -- 钳制：0 级与超上限
    lu.assertEquals(shop.MagazineSize(10, -1), 10)
    lu.assertEquals(shop.MagazineSize(10, 99), 25)
end

-- 满级实战结果（基础值来自 GameCfg.Ability，与商店表一致）
function TestShopCatalog:test_max_level_results_match_ticket()
    local shop, ability = GameCfg.Shop, GameCfg.Ability
    -- 近战 +70%：指虎 10→17、匕首 15→25.5、斧头 40→68
    lu.assertAlmostEquals(ability.MeleeWeapons.item134.Damage * shop.DamageScale('melee', 7), 17, 1e-9)
    lu.assertAlmostEquals(ability.MeleeWeapons.item135.Damage * shop.DamageScale('melee', 7), 25.5, 1e-9)
    lu.assertAlmostEquals(ability.MeleeWeapons.item136.Damage * shop.DamageScale('melee', 7), 68, 1e-9)
    -- 远程 +50%：手枪 10→15、狙击 200→300；火箭筒两段都只归远程：500→750、溅射 100→150
    lu.assertAlmostEquals(ability.Guns.item137.Damage * shop.DamageScale('ranged', 5), 15, 1e-9)
    lu.assertAlmostEquals(ability.Guns.item141.Damage * shop.DamageScale('ranged', 5), 300, 1e-9)
    lu.assertAlmostEquals(ability.Guns.item142.Damage * shop.DamageScale('ranged', 5), 750, 1e-9)
    lu.assertAlmostEquals(ability.Guns.item142.Splash.Damage * shop.DamageScale('ranged', 5), 150, 1e-9)
    -- 爆炸物 +60%：鞭炮 50→80、手雷 100→160、炸药 150→240
    lu.assertAlmostEquals(ability.Explosives.item143.Damage * shop.DamageScale('explosive', 3), 80, 1e-9)
    lu.assertAlmostEquals(ability.Explosives.item144.Damage * shop.DamageScale('explosive', 3), 160, 1e-9)
    lu.assertAlmostEquals(ability.Explosives.item145.Damage * shop.DamageScale('explosive', 3), 240, 1e-9)
end
