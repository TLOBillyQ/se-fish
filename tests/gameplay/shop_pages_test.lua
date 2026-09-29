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

-- 背包升级行描述与商店表原表一致（#130 code-review：升级6 同为「背包格+5」，按 design 原表）
function TestShopCatalog:test_backpack_rows_match_source_sheet_wording()
    for _, row in ipairs(GameCfg.Shop.Goods) do
        if row.Upgrade and row.Upgrade.kind == 'backpack' then
            lu.assertEquals(row.Desc, '购买后，道具栏+1，背包格+5', '行 ' .. row.Number)
        end
    end
end

-- 旧白名单 9 行在新货架同价同等级（兼容旧商品）
function TestShopCatalog:test_legacy_goods_keep_price_and_level()    local byItem = {}
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

-- ===== PlayerData 成长与限购状态（#130 持久字段）=====
-- 失败方式：强化等级/购买次数不走持久字段（重进丢失）；越级或重复强化生效；满级继续扣钱；
-- 武器购买被背包满格误拒（武器独立库存不占格）；损坏的 growth 存档被静默接受。
local PlayerData = require('server.Data.PlayerData')

TestShopGrowth = {}

local function newData(userId)
    local data = PlayerData.New({ UserId = userId, SetAttribute = function() end })
    data:Init()
    return data
end

local function upgradeRow(number)
    for _, row in ipairs(GameCfg.Shop.Goods) do
        if row.Number == number then return row end
    end
    lu.fail('缺商店行 ' .. tostring(number))
end

function TestShopGrowth:test_upgrade_levels_start_at_zero()
    local data = newData(101)
    for _, kind in ipairs({ 'melee', 'ranged', 'explosive', 'magazine', 'backpack' }) do
        lu.assertEquals(data:ShopUpgradeLevel(kind), 0, kind)
    end
    lu.assertEquals(data:WeaponDamageScale('melee'), 1)
    lu.assertEquals(data:MagazineSize(5), 5)
end

function TestShopGrowth:test_apply_upgrade_is_one_level_at_a_time()
    local data = newData(102)
    local melee1, melee2 = upgradeRow(51).Upgrade, upgradeRow(50).Upgrade -- 近战 1/2 级
    lu.assertEquals(melee1.kind, 'melee')
    -- 越级：0 级直接买 2 级拒绝
    local ok, reason = data:CanShopUpgrade(melee2)
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'level')
    -- 逐级：1 级生效
    lu.assertTrue(data:CanShopUpgrade(melee1))
    lu.assertTrue(data:ApplyShopUpgrade(melee1))
    lu.assertEquals(data:ShopUpgradeLevel('melee'), 1)
    lu.assertAlmostEquals(data:WeaponDamageScale('melee'), 1.1, 1e-9)
    -- 重复：再买 1 级拒绝
    local okRepeat, reasonRepeat = data:CanShopUpgrade(melee1)
    lu.assertFalse(okRepeat)
    lu.assertEquals(reasonRepeat, 'level')
    -- 2 级生效后伤害 1.2
    lu.assertTrue(data:ApplyShopUpgrade(melee2))
    lu.assertAlmostEquals(data:WeaponDamageScale('melee'), 1.2, 1e-9)
end

function TestShopGrowth:test_max_level_reports_max()
    local data = newData(103)
    for level = 1, 3 do
        lu.assertTrue(data:ApplyShopUpgrade(upgradeRow(({ 41, 40, 39 })[level]).Upgrade)) -- 弹容 1/2/3
    end
    lu.assertEquals(data:ShopUpgradeLevel('magazine'), 3)
    lu.assertEquals(data:MagazineSize(5), 13)
    local ok, reason = data:CanShopUpgrade({ kind = 'magazine', level = 3, increment = 0.5 })
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'max')
end

function TestShopGrowth:test_backpack_upgrade_drives_storage_level()
    local data = newData(104)
    lu.assertTrue(data:ApplyShopUpgrade(upgradeRow(33).Upgrade)) -- 背包升级 1
    lu.assertEquals(data:ShopUpgradeLevel('backpack'), 1)
    lu.assertEquals(data.Data.UpgradeLevel, 1)
    lu.assertEquals(data:ItemBarCapacity(), 3)
    lu.assertEquals(data:BackpackCapacity(), 10)
    -- 跳级买背包 3 拒绝
    local ok, reason = data:CanShopUpgrade(upgradeRow(31).Upgrade)
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'level')
end

function TestShopGrowth:test_unknown_or_bad_upgrade_rejected()
    local data = newData(105)
    local ok, reason = data:CanShopUpgrade({ kind = 'gold', level = 1 })
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'bad')
    lu.assertFalse(data:CanShopUpgrade(nil))
end

function TestShopGrowth:test_purchase_count_persists_across_save()
    local data = newData(106)
    lu.assertEquals(data:PurchaseCount(13), 0)
    data:NotePurchase(13)
    data:NotePurchase(13)
    data:NotePurchase(51)
    lu.assertEquals(data:PurchaseCount(13), 2)
    local restored = newData(106)
    lu.assertTrue(restored:ApplySave(data:Serialize()))
    lu.assertEquals(restored:PurchaseCount(13), 2)
    lu.assertEquals(restored:PurchaseCount(51), 1)
    lu.assertEquals(restored:PurchaseCount(14), 0)
end

function TestShopGrowth:test_upgrade_levels_persist_across_save()
    local data = newData(107)
    lu.assertTrue(data:ApplyShopUpgrade(upgradeRow(51).Upgrade)) -- 近战 1
    lu.assertTrue(data:ApplyShopUpgrade(upgradeRow(50).Upgrade)) -- 近战 2
    lu.assertTrue(data:ApplyShopUpgrade(upgradeRow(33).Upgrade)) -- 背包 1
    local restored = newData(107)
    lu.assertTrue(restored:ApplySave(data:Serialize()))
    lu.assertEquals(restored:ShopUpgradeLevel('melee'), 2)
    lu.assertEquals(restored:ShopUpgradeLevel('backpack'), 1)
    lu.assertAlmostEquals(restored:WeaponDamageScale('melee'), 1.2, 1e-9)
    lu.assertEquals(restored:ItemBarCapacity(), 3)
end

-- 武器进独立库存（#124），购买不受道具栏/背包满格影响
function TestShopGrowth:test_weapon_purchase_not_blocked_by_full_slots()
    local data = newData(108)
    while data:AddItem('carp') do end -- 填满道具栏与背包
    lu.assertTrue(data:CanGrant('item134', 1), '武器不占格，满格不应拒绝')
    lu.assertTrue(data:GrantItem('item134', 1))
    lu.assertEquals(data:WeaponCount('item134'), 1)
    -- 普通物品仍受满格限制
    local ok, reason = data:CanGrant('starterRod', 1)
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'full')
end

function TestShopGrowth:test_migrate_rejects_corrupt_growth()
    local data = newData(109)
    data:NotePurchase(13)
    lu.assertTrue(data:ApplyShopUpgrade(upgradeRow(51).Upgrade))
    local snapshot = data:Serialize()
    -- 强化等级超上限
    local corrupt1 = data:Migrate(snapshot)
    lu.assertNotNil(corrupt1)
    corrupt1.extra.growth.upgrades.melee = 99
    local restored = newData(109)
    lu.assertFalse(restored:ApplySave(corrupt1))
    -- 购买次数非整数
    local corrupt2 = data:Migrate(snapshot)
    corrupt2.extra.growth.purchases['13'] = 1.5
    lu.assertFalse(restored:ApplySave(corrupt2))
    -- upgrades/purchases 子表缺失
    local corrupt3 = data:Migrate(snapshot)
    corrupt3.extra.growth.upgrades = nil
    lu.assertFalse(restored:ApplySave(corrupt3))
    -- 完好快照仍能恢复
    lu.assertTrue(restored:ApplySave(data:Migrate(snapshot)))
    lu.assertEquals(restored:ShopUpgradeLevel('melee'), 1)
    lu.assertEquals(restored:PurchaseCount(13), 1)
end

-- 未初始化/未知种类的兜底：不加成、不取整
function TestShopGrowth:test_uninitialized_data_returns_base()
    local data = PlayerData.New({ UserId = 110, SetAttribute = function() end })
    lu.assertEquals(data:ShopUpgradeLevel('melee'), 0)
    lu.assertEquals(data:WeaponDamageScale('melee'), 1)
    lu.assertEquals(data:WeaponDamageScale('gold'), 1)
    lu.assertEquals(data:MagazineSize(5), 5)
    lu.assertEquals(data:PurchaseCount(13), 0)
end
