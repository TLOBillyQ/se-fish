-- #86 迁移（原 tests/gameplay/shop_pages_test.lua，#130）。失败方式先列：
--   1. 50 行有效商品没有全部上架为可购买货架行（漏行、页名错、编号 27 混入）；
--   2. 分页过滤错（等级不够的行上架、金币页混入金币定价商品）；
--   3. 新品没置顶（minShopLevel == 摊位等级的当地新品须排最前），或同组顺序不稳定（table.sort 不稳定）；
--   4. 强化公式错：不是按基础线性叠加（复利/错位）、系数与商店表不符、弹容没向上取整；
--   5. 逐级价格与商店表行价不符；
--   6. 升级行没有稳定的购买键（itemKey 缺失时 number 必须可用）；
--   7. 旧白名单商品（钓具 9 行）换表后价格/等级漂移，不再兼容。
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

-- 钓具 1-14、武器 15-26、升级 28-51（27 作废），共 50 行
describe("钓场商店货架表", function()

    -- 背包升级行描述与商店表原表一致（#130 code-review：升级6 同为「背包格+5」，按 design 原表）
    it("test_backpack_rows_match_source_sheet_wording", function()
        for _, row in ipairs(GameCfg.Shop.Goods) do
            if row.Upgrade and row.Upgrade.kind == 'backpack' then
                assert.same('购买后，道具栏+1，背包格+5', row.Desc, '行 ' .. row.Number)
            end
        end
    end)

    -- 按基础线性叠加：scale = 1 + increment × level（满级 +70%/+50%/+60%）
    it("test_damage_scale_is_linear_on_base", function()
        local shop = GameCfg.Shop
        assert.is_not_nil(shop.DamageScale, '缺伤害加成函数')
        assert.near(1.0, shop.DamageScale('melee', 0), 1e-9)
        assert.near(1.1, shop.DamageScale('melee', 1), 1e-9)
        assert.near(1.7, shop.DamageScale('melee', 7), 1e-9)
        assert.near(1.5, shop.DamageScale('ranged', 5), 1e-9)
        assert.near(1.6, shop.DamageScale('explosive', 3), 1e-9)
        -- 非线性就过不了：复利 1.1^7 ≈ 1.9487 ≠ 1.7
        assert.is_true(math.abs(shop.DamageScale('melee', 7) - 1.1 ^ 7) > 0.1)
        -- 弹容不是伤害加成；未知种类与越界等级钳制
        assert.is_nil(shop.DamageScale('magazine', 1))
        assert.near(1.7, shop.DamageScale('melee', 99), 1e-9)
        assert.near(1.0, shop.DamageScale('melee', -3), 1e-9)
    end)
    it("test_goods_is_full_50_rows_with_pages_and_numbers", function()
        local goods = GameCfg.Shop.Goods
        assert.same(50, #goods)
        assert.same({ '钓具', '武器', '升级', '金币' }, GameCfg.Shop.Pages)
        local seen, perPage = {}, { ['钓具'] = 0, ['武器'] = 0, ['升级'] = 0, ['金币'] = 0 }
        for _, row in ipairs(goods) do
            assert.is_not_nil(row.Number, '货架行缺购买键 number')
            assert.is_nil(seen[row.Number], '编号重复 ' .. tostring(row.Number))
            seen[row.Number] = true
            assert.is_not.equal(27, row.Number)
            assert.is_not_nil(perPage[row.Page], '未知分页 ' .. tostring(row.Page))
            perPage[row.Page] = perPage[row.Page] + 1
            assert.is_true(row.Price > 0 and row.Price % 1 == 0)
            assert.is_true(row.MinShopLevel >= 1 and row.MinShopLevel <= 7)
            assert.is_true(row.PurchaseLimit >= 0 and row.PurchaseLimit % 1 == 0)
            assert.is_not_nil(row.Name)
            assert.is_not_nil(row.source)
            if row.Page ~= '升级' then assert.is_not_nil(row.ItemId, row.Name .. ' 缺物品') end
        end
        assert.is_nil(seen[27])
        assert.same({ ['钓具'] = 14, ['武器'] = 12, ['升级'] = 24, ['金币'] = 0 }, perPage)
    end)

    -- 旧白名单 9 行在新货架同价同等级（兼容旧商品）
    it("test_legacy_goods_keep_price_and_level", function()
        local byItem = {}
        for _, row in ipairs(GameCfg.Shop.Goods) do if row.ItemId then byItem[row.ItemId] = row end end
        local legacy = { starterRod = { 5, 1 }, worm = { 1, 1 }, sausage = { 2, 2 }, shrimpRod = { 12, 2 },
            crabRod = { 24, 3 }, normalRod = { 50, 4 }, proRod = { 100, 5 },
            airforceRod = { 200, 6 }, unscientificRod = { 500, 7 } }
        for itemId, expect in pairs(legacy) do
            local row = byItem[itemId]
            assert.is_not_nil(row, itemId .. ' 不在货架')
            assert.same(expect[1], row.Price, itemId)
            assert.same(expect[2], row.MinShopLevel, itemId)
            assert.same('钓具', row.Page, itemId)
        end
    end)

    -- 分页过滤 + 新品置顶 + 同组按编号稳定升序
    it("test_list_for_page_filters_sorts_and_pins_new", function()
        local shop = GameCfg.Shop
        assert.is_not_nil(shop.ListForPage, '缺分页列表函数')
        local function numbers(rows)
            local out = {}
            for i, row in ipairs(rows) do out[i] = row.Number end
            return out
        end
        -- 1 级摊位钓具页：蚯蚓/新手鱼竿都是当地新品
        assert.same({ 13, 14 }, numbers(shop.ListForPage(1, '钓具')))
        -- 2 级：新品香肠(11)/钓虾竿(12) 置顶，其余按编号
        assert.same({ 11, 12, 13, 14 }, numbers(shop.ListForPage(2, '钓具')))
        -- 7 级：新品科技假饵(1)/不科学鱼竿(2) 置顶，恰好与原序一致
        local all = numbers(shop.ListForPage(7, '钓具'))
        assert.same(14, #all)
        for i = 1, 14 do assert.same(i, all[i]) end
        -- 3 级升级页：新品 = 背包3(31)/远程1(38)/爆炸1(44)/近战3(49)，其余按编号稳定序
        assert.same({ 31, 38, 44, 49, 32, 33, 41, 50, 51 }, numbers(shop.ListForPage(3, '升级')))
        -- 等级不够不上架：1 级摊位的武器页只有近战 1 级两件（指虎 26、匕首 25）
        assert.same({ 25, 26 }, numbers(shop.ListForPage(1, '武器')))
        -- 金币页没有金币定价商品（平台购买是外部交付参数）
        assert.same({}, shop.ListForPage(7, '金币'))
        -- 未知页与非法等级容错
        assert.same({}, shop.ListForPage(1, '不存在'))
    end)

    -- 弹容 = ceil(base × (1 + 0.5×level))：向上取整，满级 +150%
    it("test_magazine_size_rounds_up", function()
        local shop = GameCfg.Shop
        assert.is_not_nil(shop.MagazineSize, '缺弹容函数')
        assert.same(10, shop.MagazineSize(10, 0))
        assert.same(8, shop.MagazineSize(5, 1))   -- 狙击 5→7.5→8
        assert.same(10, shop.MagazineSize(5, 2))
        assert.same(13, shop.MagazineSize(5, 3))  -- 12.5→13
        assert.same(5, shop.MagazineSize(2, 3))   -- 霰弹 2→5
        assert.same(3, shop.MagazineSize(1, 3))   -- 火箭筒 1→2.5→3
        assert.same(75, shop.MagazineSize(30, 3))
        assert.same(25, shop.MagazineSize(10, 3))
        -- 钳制：0 级与超上限
        assert.same(10, shop.MagazineSize(10, -1))
        assert.same(25, shop.MagazineSize(10, 99))
    end)

    -- 满级实战结果（基础值来自 GameCfg.Ability，与商店表一致）
    it("test_max_level_results_match_ticket", function()
        local shop, ability = GameCfg.Shop, GameCfg.Ability
        -- 近战 +70%：指虎 10→17、匕首 15→25.5、斧头 40→68
        assert.near(17, ability.MeleeWeapons.item134.Damage * shop.DamageScale('melee', 7), 1e-9)
        assert.near(25.5, ability.MeleeWeapons.item135.Damage * shop.DamageScale('melee', 7), 1e-9)
        assert.near(68, ability.MeleeWeapons.item136.Damage * shop.DamageScale('melee', 7), 1e-9)
        -- 远程 +50%：手枪 10→15、狙击 200→300；火箭筒两段都只归远程：500→750、溅射 100→150
        assert.near(15, ability.Guns.item137.Damage * shop.DamageScale('ranged', 5), 1e-9)
        assert.near(300, ability.Guns.item141.Damage * shop.DamageScale('ranged', 5), 1e-9)
        assert.near(750, ability.Guns.item142.Damage * shop.DamageScale('ranged', 5), 1e-9)
        assert.near(150, ability.Guns.item142.Splash.Damage * shop.DamageScale('ranged', 5), 1e-9)
        -- 爆炸物 +60%：鞭炮 50→80、手雷 100→160、炸药 150→240
        assert.near(80, ability.Explosives.item143.Damage * shop.DamageScale('explosive', 3), 1e-9)
        assert.near(160, ability.Explosives.item144.Damage * shop.DamageScale('explosive', 3), 1e-9)
        assert.near(240, ability.Explosives.item145.Damage * shop.DamageScale('explosive', 3), 1e-9)
    end)

    -- 强化参数由商店表行派生：种类、级数、增量、逐级价格
    it("test_upgrade_kinds_derived_from_shop_rows", function()
        local kinds = GameCfg.Shop.UpgradeKinds
        assert.is_not_nil(kinds, '缺强化参数表')
        assert.same(7, kinds.melee.MaxLevel)
        assert.near(0.1, kinds.melee.Increment, 1e-9)
        assert.same({ 50, 100, 200, 400, 800, 1600, 3200 }, kinds.melee.Prices)
        assert.same(5, kinds.ranged.MaxLevel)
        assert.near(0.1, kinds.ranged.Increment, 1e-9)
        assert.same({ 500, 1000, 2000, 4000, 8000 }, kinds.ranged.Prices)
        assert.same(3, kinds.explosive.MaxLevel)
        assert.near(0.2, kinds.explosive.Increment, 1e-9)
        assert.same({ 400, 1600, 6400 }, kinds.explosive.Prices)
        assert.same(3, kinds.magazine.MaxLevel)
        assert.near(0.5, kinds.magazine.Increment, 1e-9)
        assert.is_true(kinds.magazine.RoundUp)
        assert.same({ 200, 800, 3200 }, kinds.magazine.Prices)
        -- 背包升级沿用同一表的价格序列（与 Items.UpgradePrices 同源）
        assert.same(6, kinds.backpack.MaxLevel)
        assert.same({ 100, 200, 400, 800, 1600, 3200 }, kinds.backpack.Prices)
        assert.same(GameCfg.Items.UpgradePrices, kinds.backpack.Prices)
    end)
end)

-- ===== PlayerData 成长与限购状态（#130 持久字段）=====
-- 失败方式：强化等级/购买次数不走持久字段（重进丢失）；越级或重复强化生效；满级继续扣钱；
-- 武器购买被背包满格误拒（武器独立库存不占格）；损坏的 growth 存档被静默接受。
local function newData(userId)
    local data = PlayerData.New({ UserId = userId, SetAttribute = function() end })
    data:Init()
    return data
end

local function upgradeRow(number)
    for _, row in ipairs(GameCfg.Shop.Goods) do
        if row.Number == number then return row end
    end
    error('缺商店行 ' .. tostring(number))
end

describe("商店成长与限购", function()

    it("test_apply_upgrade_is_one_level_at_a_time", function()
        local data = newData(102)
        local melee1, melee2 = upgradeRow(51).Upgrade, upgradeRow(50).Upgrade -- 近战 1/2 级
        assert.same('melee', melee1.kind)
        -- 越级：0 级直接买 2 级拒绝
        local ok, reason = data:CanShopUpgrade(melee2)
        assert.is_false(ok)
        assert.same('level', reason)
        -- 逐级：1 级生效
        assert.is_true(data:CanShopUpgrade(melee1))
        assert.is_true(data:ApplyShopUpgrade(melee1))
        assert.same(1, data:ShopUpgradeLevel('melee'))
        assert.near(1.1, data:WeaponDamageScale('melee'), 1e-9)
        -- 重复：再买 1 级拒绝
        local okRepeat, reasonRepeat = data:CanShopUpgrade(melee1)
        assert.is_false(okRepeat)
        assert.same('level', reasonRepeat)
        -- 2 级生效后伤害 1.2
        assert.is_true(data:ApplyShopUpgrade(melee2))
        assert.near(1.2, data:WeaponDamageScale('melee'), 1e-9)
    end)

    it("test_backpack_upgrade_drives_storage_level", function()
        local data = newData(104)
        assert.is_true(data:ApplyShopUpgrade(upgradeRow(33).Upgrade)) -- 背包升级 1
        assert.same(1, data:ShopUpgradeLevel('backpack'))
        assert.same(1, data.Data.UpgradeLevel)
        assert.same(3, data:ItemBarCapacity())
        assert.same(10, data:BackpackCapacity())
        -- 跳级买背包 3 拒绝
        local ok, reason = data:CanShopUpgrade(upgradeRow(31).Upgrade)
        assert.is_false(ok)
        assert.same('level', reason)
    end)

    it("test_max_level_reports_max", function()
        local data = newData(103)
        for level = 1, 3 do
            assert.is_true(data:ApplyShopUpgrade(upgradeRow(({ 41, 40, 39 })[level]).Upgrade)) -- 弹容 1/2/3
        end
        assert.same(3, data:ShopUpgradeLevel('magazine'))
        assert.same(13, data:MagazineSize(5))
        local ok, reason = data:CanShopUpgrade({ kind = 'magazine', level = 3, increment = 0.5 })
        assert.is_false(ok)
        assert.same('max', reason)
    end)

    it("test_migrate_rejects_corrupt_growth", function()
        local data = newData(109)
        data:NotePurchase(13)
        assert.is_true(data:ApplyShopUpgrade(upgradeRow(51).Upgrade))
        local snapshot = data:Serialize()
        -- 强化等级超上限
        local corrupt1 = data:Migrate(snapshot)
        assert.is_not_nil(corrupt1)
        corrupt1.extra.growth.upgrades.melee = 99
        local restored = newData(109)
        assert.is_false(restored:ApplySave(corrupt1))
        -- 购买次数非整数
        local corrupt2 = data:Migrate(snapshot)
        corrupt2.extra.growth.purchases['13'] = 1.5
        assert.is_false(restored:ApplySave(corrupt2))
        -- upgrades/purchases 子表缺失
        local corrupt3 = data:Migrate(snapshot)
        corrupt3.extra.growth.upgrades = nil
        assert.is_false(restored:ApplySave(corrupt3))
        -- 完好快照仍能恢复
        assert.is_true(restored:ApplySave(data:Migrate(snapshot)))
        assert.same(1, restored:ShopUpgradeLevel('melee'))
        assert.same(1, restored:PurchaseCount(13))
    end)

    it("test_purchase_count_persists_across_save", function()
        local data = newData(106)
        assert.same(0, data:PurchaseCount(13))
        data:NotePurchase(13)
        data:NotePurchase(13)
        data:NotePurchase(51)
        assert.same(2, data:PurchaseCount(13))
        local restored = newData(106)
        assert.is_true(restored:ApplySave(data:Serialize()))
        assert.same(2, restored:PurchaseCount(13))
        assert.same(1, restored:PurchaseCount(51))
        assert.same(0, restored:PurchaseCount(14))
    end)

    -- 未初始化/未知种类的兜底：不加成、不取整
    it("test_uninitialized_data_returns_base", function()
        local data = PlayerData.New({ UserId = 110, SetAttribute = function() end })
        assert.same(0, data:ShopUpgradeLevel('melee'))
        assert.same(1, data:WeaponDamageScale('melee'))
        assert.same(1, data:WeaponDamageScale('gold'))
        assert.same(5, data:MagazineSize(5))
        assert.same(0, data:PurchaseCount(13))
    end)

    it("test_unknown_or_bad_upgrade_rejected", function()
        local data = newData(105)
        local ok, reason = data:CanShopUpgrade({ kind = 'gold', level = 1 })
        assert.is_false(ok)
        assert.same('bad', reason)
        assert.is_false(data:CanShopUpgrade(nil))
    end)

    it("test_upgrade_levels_persist_across_save", function()
        local data = newData(107)
        assert.is_true(data:ApplyShopUpgrade(upgradeRow(51).Upgrade)) -- 近战 1
        assert.is_true(data:ApplyShopUpgrade(upgradeRow(50).Upgrade)) -- 近战 2
        assert.is_true(data:ApplyShopUpgrade(upgradeRow(33).Upgrade)) -- 背包 1
        local restored = newData(107)
        assert.is_true(restored:ApplySave(data:Serialize()))
        assert.same(2, restored:ShopUpgradeLevel('melee'))
        assert.same(1, restored:ShopUpgradeLevel('backpack'))
        assert.near(1.2, restored:WeaponDamageScale('melee'), 1e-9)
        assert.same(3, restored:ItemBarCapacity())
    end)
    it("test_upgrade_levels_start_at_zero", function()
        local data = newData(101)
        for _, kind in ipairs({ 'melee', 'ranged', 'explosive', 'magazine', 'backpack' }) do
            assert.same(0, data:ShopUpgradeLevel(kind), kind)
        end
        assert.same(1, data:WeaponDamageScale('melee'))
        assert.same(5, data:MagazineSize(5))
    end)

    -- 武器进独立库存（#124），购买不受道具栏/背包满格影响
    it("test_weapon_purchase_not_blocked_by_full_slots", function()
        local data = newData(108)
        while data:AddItem('carp') do end -- 填满道具栏与背包
        assert.is_true(data:CanGrant('item134', 1), '武器不占格，满格不应拒绝')
        assert.is_true(data:GrantItem('item134', 1))
        assert.same(1, data:WeaponCount('item134'))
        -- 普通物品仍受满格限制
        local ok, reason = data:CanGrant('starterRod', 1)
        assert.is_false(ok)
        assert.same('full', reason)
    end)
end)
