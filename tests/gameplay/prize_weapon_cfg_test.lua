-- #139 T18 大奖成长切片 1：配置钉表。
-- 失败方式（先列后写）：
--   1. 大奖武器（item152-166）缺配置或数值偏离统一规格 §6.3（伤害/间隔/弹匣/溅射）；
--   2. 武器特效未声明或参数错：毒/灼烧叠层上限 5、霜冻减速 30%/3 秒不叠加、麻痹 0.5 秒不叠加；
--   3. 加速药水配置错：每个 +10% 基础移速、最多 20 个、封顶 3 倍（统一规格 §2）；
--   4. 大奖武器与抽奖组（common/cfg/Lottery.lua）/物品表（common/cfg/Items.lua）对不上号。
-- 接缝：common/GameCfg.lua 的 Ability 段是纯数据，loadfile 取全新实例断言。
local lu = require('luaunit')

TestPrizeWeaponCfg = {}

function TestPrizeWeaponCfg:setUp()
    self.cfg = assert(loadfile('common/GameCfg.lua'))()
    self.Items = require('common.cfg.Items')
    self.Lottery = require('common.cfg.Lottery')
end

-- 统一规格 §6.3 武器大奖表逐项钉死（毒匕/炽焰战斧的特效参数在 StatusEffects 钉表里验）
function TestPrizeWeaponCfg:test_prize_melee_weapons_match_spec()
    local melee = self.cfg.Ability.MeleeWeapons
    local expect = {
        item152 = { Damage = 15, IntervalSec = 0.5 }, -- 淬毒匕首（毒 1/s/3s/5 层）
        item153 = { Damage = 18, IntervalSec = 0.5 }, -- 秘银匕首
        item154 = { Damage = 18, IntervalSec = 0.5 }, -- 黄金匕首
        item155 = { Damage = 18, IntervalSec = 0.5 }, -- 黑曜石匕首
        item156 = { Damage = 18, IntervalSec = 0.5 }, -- 锯齿匕首
        item157 = { Damage = 52, IntervalSec = 1.0 }, -- 银斧
        item158 = { Damage = 52, IntervalSec = 1.0 }, -- 金斧
        item159 = { Damage = 40, IntervalSec = 1.0 }, -- 炽焰战斧（灼烧 4/s/3s/5 层）
        item160 = { Damage = 60, IntervalSec = 1.0 }, -- 血吼
        item161 = { Damage = 68, IntervalSec = 1.0 }, -- 无坚不摧之力
    }
    for itemId, want in pairs(expect) do
        local got = melee[itemId]
        lu.assertNotNil(got, itemId .. ' 缺近战配置')
        lu.assertEquals(got.Damage, want.Damage, itemId .. ' 伤害')
        lu.assertEquals(got.IntervalSec, want.IntervalSec, itemId .. ' 攻击间隔')
        lu.assertTrue(type(got.Range) == 'number' and got.Range >= 2,
            itemId .. ' 射程须为正数（暂取值须显式标注）')
    end
end

function TestPrizeWeaponCfg:test_prize_guns_match_spec()
    local guns = self.cfg.Ability.Guns
    local expect = {
        item162 = { Damage = 15, IntervalSec = 1.0, Magazine = 15 }, -- 沙漠之鹰
        item163 = { Damage = 10, IntervalSec = 1.0, Magazine = 10 }, -- 霜之新星（霜冻 -30%/3s）
        item164 = { Damage = 10, IntervalSec = 1.0, Magazine = 10 }, -- 雷霆之力（麻痹 0.5s）
        item165 = { Damage = 30, IntervalSec = 0.2, Magazine = 30, Auto = true }, -- 黄金AK47
        item166 = { Damage = 500, IntervalSec = 1.0, Magazine = 10, Auto = true }, -- 连发火箭筒（溅射 5m/100）
    }
    for itemId, want in pairs(expect) do
        local got = guns[itemId]
        lu.assertNotNil(got, itemId .. ' 缺枪械配置')
        lu.assertEquals(got.Damage, want.Damage, itemId .. ' 伤害')
        lu.assertEquals(got.IntervalSec, want.IntervalSec, itemId .. ' 射击间隔')
        lu.assertEquals(got.Magazine, want.Magazine, itemId .. ' 弹匣')
        lu.assertEquals(got.Auto == true, want.Auto == true, itemId .. ' 自动射击标志')
    end
    -- 连发火箭筒溅射：5 米范围 100 点（与火箭筒 item142 同票面口径）
    lu.assertEquals(guns.item166.Splash, { Damage = 100, Radius = 5 })
end

-- 特效声明：只有规格写了特效的武器才挂 Effect，且指向 StatusEffects 里的合法条目
function TestPrizeWeaponCfg:test_weapon_effects_declared_only_where_spec_says()
    lu.assertEquals(self.cfg.Ability.MeleeWeapons.item152.Effect, { Kind = 'poison' })
    lu.assertEquals(self.cfg.Ability.MeleeWeapons.item159.Effect, { Kind = 'burn' })
    lu.assertEquals(self.cfg.Ability.Guns.item163.Effect, { Kind = 'frost' })
    lu.assertEquals(self.cfg.Ability.Guns.item164.Effect, { Kind = 'paralyze' })
    local noEffect = { 'item153', 'item154', 'item155', 'item156', 'item157', 'item158',
        'item160', 'item161' }
    for _, itemId in ipairs(noEffect) do
        lu.assertNil(self.cfg.Ability.MeleeWeapons[itemId].Effect, itemId .. ' 不应有特效')
    end
    for _, itemId in ipairs({ 'item162', 'item165', 'item166' }) do
        lu.assertNil(self.cfg.Ability.Guns[itemId].Effect, itemId .. ' 不应有特效')
    end
    for _, itemId in ipairs({ 'item134', 'item135', 'item136' }) do
        lu.assertNil(self.cfg.Ability.MeleeWeapons[itemId].Effect, itemId .. ' 商店武器不加特效')
    end
    for _, itemId in ipairs({ 'item137', 'item138', 'item139', 'item140', 'item141', 'item142' }) do
        lu.assertNil(self.cfg.Ability.Guns[itemId].Effect, itemId .. ' 商店武器不加特效')
    end
end

-- 持续效果钉表：毒/灼烧可叠 5 层、每秒一跳、3 秒；霜冻/麻痹不叠加只刷新
function TestPrizeWeaponCfg:test_status_effects_pinned()
    local fx = self.cfg.Ability.StatusEffects
    lu.assertNotNil(fx)
    lu.assertEquals(fx.poison, { MaxStacks = 5, TickSec = 1, DamagePerStack = 1, DurationSec = 3 })
    lu.assertEquals(fx.burn, { MaxStacks = 5, TickSec = 1, DamagePerStack = 4, DurationSec = 3 })
    lu.assertEquals(fx.frost, { SlowPercent = 30, DurationSec = 3, Stackable = false })
    lu.assertEquals(fx.paralyze, { DurationSec = 0.5, Stackable = false })
end

-- 加速药水（item167）：每个 +10% 基础移速，最多 20 个，封顶 3 倍（统一规格 §2）；
-- 与物品表上限（GameCfg.Items.PotionLimits）同口径，禁止两处漂移
function TestPrizeWeaponCfg:test_speed_potion_cfg_matches_spec_and_limits()
    local potion = self.cfg.Ability.SpeedPotion
    lu.assertNotNil(potion)
    lu.assertEquals(potion.Item, 'item167')
    lu.assertEquals(potion.StepPercent, 10)
    lu.assertEquals(potion.MaxPotions, 20)
    lu.assertEquals(potion.MaxFactor, 3)
    lu.assertEquals(self.cfg.Items.PotionLimits.item167, potion.MaxPotions)
    -- 变大药水沿用 BodyScale 钉表（#132 原型）：步长/上限与规格 §2 一致
    local body = self.cfg.Ability.BodyScale
    lu.assertEquals(body.PotionItem, 'item168')
    lu.assertEquals(body.Step, 0.2)
    lu.assertEquals(body.MaxPotions, 10)
    lu.assertEquals(body.HealthMax, 900)
    lu.assertEquals(self.cfg.Items.PotionLimits.item168, body.MaxPotions)
end

-- 移速基准：BaseController 默认 WalkSpeed 7.0（editor-cli manual BaseController.mdx 已核实）
function TestPrizeWeaponCfg:test_move_speed_base_pinned()
    lu.assertEquals(self.cfg.Ability.MoveSpeed, { Base = 7 })
end

-- 对账：15 件大奖武器 = 抽奖三个武器组的并集，物品表全部存在且为武器分类
function TestPrizeWeaponCfg:test_prize_weapons_reconcile_with_lottery_groups_and_items()
    local groups = {}
    for _, entry in ipairs(self.Lottery.Patterns) do
        if entry.tripleReward and entry.tripleReward.kind == 'weaponChoice' then
            for _, itemKey in ipairs(entry.tripleReward.itemKeys) do
                groups[#groups + 1] = itemKey
            end
        end
    end
    lu.assertEquals(#groups, 15)
    for _, itemId in ipairs(groups) do
        local def = self.Items.Definitions[itemId]
        lu.assertNotNil(def, itemId .. ' 物品表缺定义')
        local inMelee = self.cfg.Ability.MeleeWeapons[itemId] ~= nil
        local inGuns = self.cfg.Ability.Guns[itemId] ~= nil
        lu.assertTrue(inMelee or inGuns, itemId .. ' 缺武器数值配置')
    end
end
