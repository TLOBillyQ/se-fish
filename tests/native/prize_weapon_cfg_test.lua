-- #139 T18 大奖成长切片 1：配置钉表。
-- 失败方式（先列后写）：
--   1. 大奖武器（item152-166）缺配置或数值偏离统一规格 §6.3（伤害/间隔/弹匣/溅射）；
--   2. 武器特效未声明或参数错：毒/灼烧叠层上限 5、霜冻减速 30%/3 秒不叠加、麻痹 0.5 秒不叠加；
--   3. 加速药水配置错：每个 +10% 基础移速、最多 20 个、封顶 3 倍（统一规格 §2）；
--   4. 大奖武器与抽奖组（common/cfg/Lottery.lua）/物品表（common/cfg/Items.lua）对不上号。
-- 接缝：common/GameCfg.lua 的 Ability 段是纯数据，loadfile 取全新实例断言。
-- 迁移自 tests/gameplay/prize_weapon_cfg_test.lua（#83）；旧 setUp 逐例执行，映射为 before_each。
describe("TestPrizeWeaponCfg", function()
  local cfg, Items, Lottery

  before_each(function()
    cfg = assert(loadfile('common/GameCfg.lua'))()
    Items = require('common.cfg.Items')
    Lottery = require('common.cfg.Lottery')
  end)

  -- 统一规格 §6.3 武器大奖表逐项钉死（毒匕/炽焰战斧的特效参数在 StatusEffects 钉表里验）
  it("test_move_speed_base_pinned", function()
    assert.same({ Base = 7 }, cfg.Ability.MoveSpeed)
  end)

  it("test_prize_guns_match_spec", function()
    local guns = cfg.Ability.Guns
    local expect = {
      item162 = { Damage = 15, IntervalSec = 1.0, Magazine = 15 }, -- 沙漠之鹰
      item163 = { Damage = 10, IntervalSec = 1.0, Magazine = 10 }, -- 霜之新星（霜冻 -30%/3s）
      item164 = { Damage = 10, IntervalSec = 1.0, Magazine = 10 }, -- 雷霆之力（麻痹 0.5s）
      item165 = { Damage = 30, IntervalSec = 0.2, Magazine = 30, Auto = true }, -- 黄金AK47
      item166 = { Damage = 500, IntervalSec = 1.0, Magazine = 10, Auto = true }, -- 连发火箭筒（溅射 5m/100）
    }
    for itemId, want in pairs(expect) do
      local got = guns[itemId]
      assert.is_not_nil(got, itemId .. ' 缺枪械配置')
      assert.are.equal(want.Damage, got.Damage, itemId .. ' 伤害')
      assert.are.equal(want.IntervalSec, got.IntervalSec, itemId .. ' 射击间隔')
      assert.are.equal(want.Magazine, got.Magazine, itemId .. ' 弹匣')
      assert.are.equal(want.Auto == true, got.Auto == true, itemId .. ' 自动射击标志')
    end
    -- 连发火箭筒溅射：5 米范围 100 点（与火箭筒 item142 同票面口径）
    assert.same({ Damage = 100, Radius = 5 }, guns.item166.Splash)
  end)

  it("test_prize_melee_weapons_match_spec", function()
    local melee = cfg.Ability.MeleeWeapons
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
      assert.is_not_nil(got, itemId .. ' 缺近战配置')
      assert.are.equal(want.Damage, got.Damage, itemId .. ' 伤害')
      assert.are.equal(want.IntervalSec, got.IntervalSec, itemId .. ' 攻击间隔')
      assert.is_true(type(got.Range) == 'number' and got.Range >= 2,
        itemId .. ' 射程须为正数（暂取值须显式标注）')
    end
  end)

  -- 对账：15 件大奖武器 = 抽奖三个武器组的并集，物品表全部存在且为武器分类
  it("test_prize_weapons_reconcile_with_lottery_groups_and_items", function()
    local groups = {}
    for _, entry in ipairs(Lottery.Patterns) do
      if entry.tripleReward and entry.tripleReward.kind == 'weaponChoice' then
        for _, itemKey in ipairs(entry.tripleReward.itemKeys) do
          groups[#groups + 1] = itemKey
        end
      end
    end
    assert.are.equal(15, #groups)
    for _, itemId in ipairs(groups) do
      local def = Items.Definitions[itemId]
      assert.is_not_nil(def, itemId .. ' 物品表缺定义')
      local inMelee = cfg.Ability.MeleeWeapons[itemId] ~= nil
      local inGuns = cfg.Ability.Guns[itemId] ~= nil
      assert.is_true(inMelee or inGuns, itemId .. ' 缺武器数值配置')
    end
  end)

  -- 加速药水（item167）：每个 +10% 基础移速，最多 20 个，封顶 3 倍（统一规格 §2）；
  -- 与物品表上限（GameCfg.Items.PotionLimits）同口径，禁止两处漂移
  it("test_speed_potion_cfg_matches_spec_and_limits", function()
    local potion = cfg.Ability.SpeedPotion
    assert.is_not_nil(potion)
    assert.are.equal('item167', potion.Item)
    assert.are.equal(10, potion.StepPercent)
    assert.are.equal(20, potion.MaxPotions)
    assert.are.equal(3, potion.MaxFactor)
    assert.are.equal(potion.MaxPotions, cfg.Items.PotionLimits.item167)
    -- 变大药水沿用 BodyScale 钉表（#132 原型）：步长/上限与规格 §2 一致
    local body = cfg.Ability.BodyScale
    assert.are.equal('item168', body.PotionItem)
    assert.are.equal(0.2, body.Step)
    assert.are.equal(10, body.MaxPotions)
    assert.are.equal(900, body.HealthMax)
    assert.are.equal(body.MaxPotions, cfg.Items.PotionLimits.item168)
  end)

  -- 持续效果钉表：毒/灼烧可叠 5 层、每秒一跳、3 秒；霜冻/麻痹不叠加只刷新
  it("test_status_effects_pinned", function()
    local fx = cfg.Ability.StatusEffects
    assert.is_not_nil(fx)
    assert.same({ MaxStacks = 5, TickSec = 1, DamagePerStack = 1, DurationSec = 3 }, fx.poison)
    assert.same({ MaxStacks = 5, TickSec = 1, DamagePerStack = 4, DurationSec = 3 }, fx.burn)
    assert.same({ SlowPercent = 30, DurationSec = 3, Stackable = false }, fx.frost)
    assert.same({ DurationSec = 0.5, Stackable = false }, fx.paralyze)
  end)

  -- 特效声明：只有规格写了特效的武器才挂 Effect，且指向 StatusEffects 里的合法条目
  it("test_weapon_effects_declared_only_where_spec_says", function()
    assert.same({ Kind = 'poison' }, cfg.Ability.MeleeWeapons.item152.Effect)
    assert.same({ Kind = 'burn' }, cfg.Ability.MeleeWeapons.item159.Effect)
    assert.same({ Kind = 'frost' }, cfg.Ability.Guns.item163.Effect)
    assert.same({ Kind = 'paralyze' }, cfg.Ability.Guns.item164.Effect)
    local noEffect = { 'item153', 'item154', 'item155', 'item156', 'item157', 'item158',
      'item160', 'item161' }
    for _, itemId in ipairs(noEffect) do
      assert.is_nil(cfg.Ability.MeleeWeapons[itemId].Effect, itemId .. ' 不应有特效')
    end
    for _, itemId in ipairs({ 'item162', 'item165', 'item166' }) do
      assert.is_nil(cfg.Ability.Guns[itemId].Effect, itemId .. ' 不应有特效')
    end
    for _, itemId in ipairs({ 'item134', 'item135', 'item136' }) do
      assert.is_nil(cfg.Ability.MeleeWeapons[itemId].Effect, itemId .. ' 商店武器不加特效')
    end
    for _, itemId in ipairs({ 'item137', 'item138', 'item139', 'item140', 'item141', 'item142' }) do
      assert.is_nil(cfg.Ability.Guns[itemId].Effect, itemId .. ' 商店武器不加特效')
    end
  end)
end)
