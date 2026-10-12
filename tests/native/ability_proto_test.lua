-- #132 T11 原型（能力 A：三倍体型）单测。纯逻辑在 common/BodyScale.lua，数值在 GameCfg.Ability.BodyScale。
-- 失败方式（先列后写）：
--   1. 药水数越界：负数 / 小数 / 非数 / 超过上限仍继续变大；上限那一档没有封顶标记；
--   2. 倍率污染：NaN / inf / ≤0 / 非数的倍率被写进单位，派生量随之变 NaN；
--   3. 派生量不是线性放大：胶囊高 / 相机距离 / 交互距离仍按 1 倍算，三倍角色够不到地面物与抛竿点；
--   4. 挂点位移不随体型放大：三倍角色身上的挂件陷进身体（真机「挂点不穿出」的前置条件）；
--   5. 血量成长与体型成长脱钩：10 个药水不是 900 血 / 3 倍，或超限后血量继续涨。
-- 迁移自 tests/gameplay/ability_proto_test.lua（#83）。旧入口有 4 个 LuaUnit 类（BodyScale / BossPhase /
-- CarryMount / FlightPath），每类 setUp 只做 require 与取值、没有 tearDown；
-- 按「类名字典序 + 类内方法名字典序」展开（等价于旧入口对 ClassName.method 全名的排序），
-- 每类保留逐例 before_each。it 顺序与迁移前逐条对账。
-- 断言口径：旧 assertEquals 两侧同为 table 时深比较 → assert.same，标量 → assert.are.equal；
-- 旧 assertAlmostEquals(number) → assert.near(期望, 实际, 容差)；旧 assertTrue/assertFalse 是
-- assertIsTrue/assertIsFalse 的别名（要求恰为 true/false）→ is_true / is_false，语义一致。

describe("TestBodyScale", function()
  local Cfg, BodyScale

  before_each(function()
    Cfg = require('common.GameCfg')
    BodyScale = require('common.BodyScale')
  end)

  it("test_config_matches_spec_linear_growth_and_caps", function()
    local c = Cfg.Ability.BodyScale
    assert.are.equal(1, c.Base)
    assert.are.equal(0.2, c.Step)
    assert.are.equal(3, c.Max)
    assert.are.equal(10, c.MaxPotions)
    assert.are.equal(300, c.HealthBase)
    assert.are.equal(900, c.HealthMax)
    assert.are.equal(20, c.HealthStepPercent)
  end)

  it("test_derive_falls_back_to_one_x_when_factor_is_bad", function()
    local base = { CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2 }
    for _, bad in ipairs({ 0 / 0, math.huge, 0, -1, nil, '3' }) do
      local derived = BodyScale.Derive(bad, base)
      assert.are.equal(1, derived.Scale, tostring(bad))
      assert.are.equal(2, derived.CapsuleHeight, tostring(bad))
      assert.is_nil(derived.SocketOffset, tostring(bad))
    end
    -- 基准量本身是坏值时也不能产出 NaN
    local derived = BodyScale.Derive(3, { CapsuleHeight = 0 / 0, CameraDistance = 'x' })
    assert.are.equal(0, derived.CapsuleHeight)
    assert.are.equal(0, derived.CameraDistance)
    assert.are.equal(#tostring(derived), #tostring(derived)) -- 只保证不抛错
    assert.is_not_nil(derived)
    assert.is_false(derived.CapsuleHeight ~= derived.CapsuleHeight)
  end)

  it("test_derive_scales_capsule_camera_interact_and_socket", function()
    local c = Cfg.Ability.BodyScale
    local base = { CapsuleHeight = c.CapsuleHeight, CameraDistance = c.CameraDistance,
      InteractRange = c.InteractRange, SocketOffset = { x = 0, y = 2.4, z = 0 } }
    local one = BodyScale.Derive(1, base)
    assert.same({ Scale = 1, CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2,
      SocketOffset = { x = 0, y = 2.4, z = 0 } }, one)
    local three = BodyScale.Derive(3, base)
    assert.are.equal(6, three.CapsuleHeight)
    assert.are.equal(18, three.CameraDistance)
    assert.are.equal(6, three.InteractRange)
    assert.near(0, three.SocketOffset.x, 1e-9)
    assert.near(7.2, three.SocketOffset.y, 1e-9)
    assert.near(0, three.SocketOffset.z, 1e-9)
    -- 挂点位移必须随体型放大，否则三倍角色身上的挂件陷进身体
    assert.is_true(three.SocketOffset.y > one.SocketOffset.y)
  end)

  it("test_plan_grows_linearly_and_caps_at_ten_potions", function()
    local plan = BodyScale.Plan(0)
    assert.are.equal(1, plan.Scale)
    assert.are.equal(300, plan.Health)
    assert.is_false(plan.Capped)
    plan = BodyScale.Plan(5)
    assert.are.equal(2, plan.Scale)
    assert.are.equal(600, plan.Health)
    plan = BodyScale.Plan(10)
    assert.are.equal(3, plan.Scale)
    assert.are.equal(900, plan.Health)
    assert.is_true(plan.Capped)
    -- 超限不再提升，且仍然给出上限值（业务侧据此拒绝使用，见 GameSpec §2）
    for _, over in ipairs({ 11, 99 }) do
      local capped = BodyScale.Plan(over)
      assert.are.equal(3, capped.Scale, tostring(over))
      assert.are.equal(900, capped.Health, tostring(over))
      assert.is_true(capped.Capped, tostring(over))
    end
  end)

  it("test_plan_rejects_non_numbers_and_negatives_as_zero", function()
    -- 注意：表构造里的 nil 不占位，旧入口 ipairs 同样只跑到第 3 项（-1 / -0.5 / '3'）。
    -- 这里原样保留，不在迁移中悄悄扩大覆盖范围（要补 0/0 与 inf 请另开单）。
    for _, bad in ipairs({ -1, -0.5, '3', nil, 0 / 0, math.huge }) do
      local plan = BodyScale.Plan(bad)
      assert.are.equal(1, plan.Scale, tostring(bad))
      assert.are.equal(300, plan.Health, tostring(bad))
      assert.are.equal(0, plan.Potions, tostring(bad))
    end
    -- 小数不是「非法」而是「不足一个」：向下取整，不把玩家的成长一笔抹掉
    local floored = BodyScale.Plan(1.5)
    assert.are.equal(1, floored.Potions)
    assert.are.equal(1.2, floored.Scale)
    assert.is_false(floored.Capped)
  end)

  it("test_sanitize_never_lets_a_bad_factor_through", function()
    local c = Cfg.Ability.BodyScale
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge, 0, -2, '2', nil }) do
      assert.are.equal(c.Base, BodyScale.Sanitize(bad), tostring(bad))
    end
    assert.are.equal(2.4, BodyScale.Sanitize(2.4))
    assert.are.equal(c.Max, BodyScale.Sanitize(99))
    assert.are.equal(c.Base, BodyScale.Sanitize(0.1))
  end)
end)

-- 能力 D：首领分阶段（60%/20% 阈值、一帧跨两阈值、途中失目标、死亡打断）。
-- 失败方式（先列后写）：
--   1. 阈值抖动：血量在 60%/20% 附近反复横跳时阶段来回切、日志刷屏；
--   2. 一帧跨两阈值：一次掉到 5% 时补一遍中间阶段或漏掉最终阶段；
--   3. 招式不确定：同一帧多个招式到期时顺序随机，或血线推进后冷却不重排；
--   4. 失目标不干净：待发吐息不撤销、目标一回来立刻秒杀、冷却被重置成「白赚」；
--   5. 死亡残留：死后仍有攻击落地、待发攻击不清空、打断被重复计数。
describe("TestBossPhase", function()
  local Cfg, Boss, BossCfg, Target

  before_each(function()
    Cfg = require('common.GameCfg')
    Boss = require('common.BossPhase')
    BossCfg = Cfg.Ability.BossPhase
    Target = { x = 1, y = 0, z = 0 }
  end)

  -- 旧类的 self:input / self:run 是不以 test 开头的辅助方法（旧入口不会收集），这里还原为局部函数。
  local function input(health, target)
    return { Health = health, MaxHealth = 10000, Alive = true, Target = target }
  end

  -- 从 0 推进到 upto 秒，收集本段内触发过的攻击
  local function run(state, from, upto, inp)
    local fired = {}
    local step = 0
    while from + step * 0.05 <= upto + 1e-9 do
      step = step + 1
      local now = from + step * 0.05
      local events = Boss.Update(state, now, 0.05, inp)
      if events.Attack then fired[#fired + 1] = events.Attack end
      if events.Interrupted then fired.Interrupted = events.Reason end
    end
    return fired
  end

  it("test_attack_cycle_is_deterministic_and_suspends_without_a_target", function()
    local state = Boss.New(BossCfg, 0)
    local inp = input(10000, Target)
    local fired = run(state, 0, 2.1, inp)
    assert.are.equal(1, #fired)
    assert.are.equal('claw', fired[1].Name) -- 2 秒爪击
    assert.are.equal(50, fired[1].Damage)
    assert.are.equal(1, state.Stats.Attacks)
    -- 失目标：不再出招，也不残留待发
    inp.Target = nil
    local after = state.Stats.Attacks
    run(state, 2.1, 32.1, inp)
    assert.are.equal(after, state.Stats.Attacks)
    assert.is_nil(state.Pending)
    assert.is_nil(state.Target)
    -- 目标回来后接着打（冷却保留：不是从头再等，也不是立刻白赚）
    inp.Target = Target
    local resumed = run(state, 32.1, 32.4, inp)
    assert.are.equal('claw', resumed[1].Name)
    assert.are.equal(50, resumed[1].Damage)
    local names = {}
    for _, attack in ipairs(resumed) do names[attack.Name] = true end
    assert.is_true(names.tail, '失目标期间冷却保留，目标回来接着出招')
  end)

  it("test_config_matches_spec", function()
    local thresholds = BossCfg.Thresholds
    assert.are.equal(60, thresholds[1].Percent)
    assert.are.equal('water', thresholds[1].Phase)
    assert.are.equal(1000, thresholds[1].BiteDamage)
    assert.are.equal(20, thresholds[2].Percent)
    assert.are.equal('enraged', thresholds[2].Phase)
    assert.are.equal(50, thresholds[2].DamageBonusPercent)
    assert.are.equal(10, thresholds[2].BreathIntervalSec)
    assert.are.equal(2, BossCfg.Attacks.claw.IntervalSec)
    assert.are.equal(50, BossCfg.Attacks.claw.Damage)
    assert.are.equal(6, BossCfg.Attacks.tail.IntervalSec)
    assert.are.equal(30, BossCfg.Attacks.breath.IntervalSec)
    assert.are.equal(10, BossCfg.Attacks.breath.Range)
    assert.is_true(BossCfg.Attacks.breath.OneShot)
  end)

  it("test_death_interrupts_and_leaves_no_residual_attack", function()
    local state = Boss.New(BossCfg, 0)
    local inp = input(10000, Target)
    run(state, 0, 30.2, inp)
    assert.is_not_nil(state.Pending)
    local attacks = state.Stats.Attacks
    inp.Alive = false
    local events = Boss.Update(state, 30.25, 0.05, inp)
    assert.is_true(events.Interrupted)
    assert.are.equal('death', events.Reason)
    assert.is_nil(events.Attack)
    assert.is_nil(state.Pending)
    assert.are.equal(1, state.Stats.Interrupts)
    -- 死亡后不再有任何攻击落地
    local after = run(state, 30.25, 45.25, inp)
    assert.are.equal(0, #after)
    assert.are.equal(attacks, state.Stats.Attacks)
    assert.is_false(Boss.Update(state, 45.3, 0.05, inp).Interrupted, '打断只算一次')
  end)

  it("test_enraged_buffs_damage_and_shortens_the_breath", function()
    local normal = Boss.New(BossCfg, 0)
    run(normal, 0, 12, input(10000, Target))
    for _, attack in ipairs(normal.AttackLog) do
      assert.are_not.equal('breath', attack.Name, '正常阶段 30 秒才吐息')
    end
    local state = Boss.New(BossCfg, 0)
    local fired = run(state, 0, 12, input(1500, Target))
    assert.are.equal('enraged', state.Phase)
    assert.are.equal('claw', fired[1].Name)
    assert.are.equal(75, fired[1].Damage, '爪击 50 × 1.5')
    local breath = false
    for _, attack in ipairs(state.AttackLog) do
      if attack.Name == 'breath' then
        breath = true
        assert.is_true(attack.Lethal, '原子吐息是正前 10 米秒杀')
      end
    end
    assert.is_true(breath, '狂暴后吐息改为每 10 秒')
  end)

  it("test_one_frame_crossing_two_thresholds_lands_in_one_phase", function()
    local state = Boss.New(BossCfg, 0)
    Boss.Update(state, 0.1, 0.1, input(10000, Target))
    local events = Boss.Update(state, 0.2, 0.1, input(500, Target))
    assert.are.equal('enraged', events.Phase)
    assert.is_true(events.PhaseChanged)
    assert.are.equal(1, state.Stats.Transitions, '一帧只算一次切换')
    assert.are.equal('normal', state.Log[1].From)
    assert.are.equal('enraged', state.Log[1].To)
    assert.same({ 'water' }, state.Log[1].Skipped, '被跳过的阶段必须记下来')
    assert.are.equal(1, state.Stats.Skipped)
    assert.are.equal(5, state.Percent)
  end)

  it("test_thresholds_escalate_only_below_the_line", function()
    local state = Boss.New(BossCfg, 0)
    -- 满血：正常阶段，也没有日志
    assert.are.equal('normal', Boss.Update(state, 0.1, 0.1, input(10000, Target)).Phase)
    -- 正好 60% / 20% 不入下一阶段（正文是「低于 60%」「低于 20%」）
    assert.are.equal('normal', Boss.Update(state, 0.2, 0.1, input(6000, Target)).Phase)
    assert.are.equal('water', Boss.Update(state, 0.3, 0.1, input(5990, Target)).Phase)
    assert.are.equal('water', Boss.Update(state, 0.4, 0.1, input(2000, Target)).Phase)
    assert.are.equal('enraged', Boss.Update(state, 0.5, 0.1, input(1990, Target)).Phase)
    assert.are.equal(2, state.Stats.Transitions)
    assert.are.equal(2, #state.Log)
    assert.are.equal('normal', state.Log[1].From)
    assert.are.equal('water', state.Log[1].To)
    assert.same({}, state.Log[1].Skipped)
    assert.are.equal('enraged', state.Log[2].To)
    -- 同一档内血量反复变化不产生新日志；回血也不退回上一阶段（只进不退，见模块说明）
    for i = 1, 20 do
      Boss.Update(state, 0.6 + i * 0.05, 0.05, input(1900 + i * 10, Target))
    end
    assert.are.equal(2, state.Stats.Transitions)
    assert.are.equal(2, #state.Log)
    assert.are.equal(21, state.Percent)
    assert.are.equal('enraged', state.Phase, '回血不倒退阶段')
  end)

  it("test_water_phase_bites_with_the_phase_damage", function()
    local state = Boss.New(BossCfg, 0)
    local fired = run(state, 0, 12, input(5000, Target))
    assert.are.equal('water', state.Phase)
    assert.are.equal('bite', fired[1].Name)
    assert.are.equal(1000, fired[1].Damage, '入水后咬中 1000')
    for _, attack in ipairs(state.AttackLog) do
      assert.are_not.equal('breath', attack.Name, '入水阶段不吐息')
    end
  end)

  it("test_windup_is_cancelled_when_the_target_is_lost", function()
    local state = Boss.New(BossCfg, 0)
    local inp = input(10000, Target)
    run(state, 0, 30.2, inp) -- 吐息 30 秒起手，起手 1.5 秒
    assert.is_not_nil(state.Pending)
    assert.are.equal('breath', state.Pending.Name)
    -- 吐息 30 秒到期、起手 1.5 秒；容差按帧粒度（同一帧先落地的爪击会占掉 30 秒那一帧）
    assert.near(30 + BossCfg.Attacks.breath.WindupSec, state.Pending.ReadyAt, 0.15)
    local attacks = state.Stats.Attacks
    inp.Target = nil
    local events = Boss.Update(state, 30.25, 0.05, inp)
    assert.is_true(events.Interrupted)
    assert.are.equal('lostTarget', events.Reason)
    assert.is_nil(events.Attack)
    assert.is_nil(state.Pending)
    assert.are.equal(attacks, state.Stats.Attacks)
    assert.are.equal(1, state.Stats.Interrupts)
    -- 目标回来后吐息要重新计时，不能立刻落地
    inp.Target = Target
    local fired = run(state, 30.25, 32.25, inp)
    for _, attack in ipairs(fired) do
      assert.are_not.equal('breath', attack.Name)
    end
  end)
end)

-- 能力 C：巡航叼人（挂点附着、携带跟随、释放）。
-- 失败方式（先列后写）：
--   1. 挂点落在宿主体内：携带物与宿主身体重叠（真机「挂点不穿出」的判定前提）；
--   2. 挂点坐标不随宿主位姿/体型变化：三倍体型或转身后挂点仍按 1 倍、按原始朝向算；
--   3. 携带物被甩开/瞬移：偏离挂点后不回收，或每帧都被判定偏离而抖在原地；
--   4. 越界携带：超出抓取距离仍能叼走；无挂点/无目标也能叼；
--   5. 释放不干净：超时或目标出 NaN 后仍处于携带态、能重复释放、落点算不出。
local function newCarry(cfg, host)
  local Carry = require('common.CarryMount')
  return Carry, Carry.New(cfg, host or { x = 0, y = 0, z = 0 }, 0, 100)
end

describe("TestCarryMount", function()
  local Cfg, Carry, CarryCfg

  before_each(function()
    Cfg = require('common.GameCfg')
    Carry = require('common.CarryMount')
    CarryCfg = Cfg.Ability.Carry
  end)

  it("test_attach_needs_a_target_inside_grab_range", function()
    local state
    Carry, state = newCarry(CarryCfg)
    assert.is_false(Carry.Attach(state, nil, 100).Ok)
    assert.are.equal('noTarget', Carry.Attach(state, nil, 100).Reason)
    local far = { x = 99, y = 0, z = 0 }
    assert.is_false(Carry.Attach(state, far, 100).Ok)
    assert.are.equal('outOfRange', Carry.Attach(state, far, 100).Reason)
    assert.is_false(Carry.Carried(state))
    local near = { x = 1, y = 0, z = 1 }
    local attach = Carry.Attach(state, near, 100)
    assert.is_true(attach.Ok)
    assert.are.equal(CarryCfg.GrabDamage, attach.Damage)
    assert.is_true(Carry.Carried(state))
    -- 没有挂点的宿主不吃这套（不能凭空抱走）
    local bareCfg = { Socket = nil, GrabRange = 2.5, GrabDamage = 300,
      Offset = { x = 0, y = 0, z = 2 }, FollowTolerance = 3, MaxCarrySec = 20 }
    local Bare, bareState = newCarry(bareCfg)
    assert.is_false(Bare.Attach(bareState, near, 100).Ok)
    assert.are.equal('noSocket', Bare.Attach(bareState, near, 100).Reason)
  end)

  it("test_carried_body_is_snapped_back_when_it_drifts", function()
    local state
    Carry, state = newCarry(CarryCfg)
    Carry.Attach(state, { x = 1, y = 0, z = 1 }, 100)
    local mount = Carry.MountPoint(state.Host, state.Offset, state.Yaw)
    -- 容差内不动它，避免每帧都被「纠正」而抖动
    local near = { x = mount.x + 0.1, y = mount.y, z = mount.z }
    local kept = Carry.Follow(state, near, 100, 0.05)
    assert.is_false(kept.Snapped)
    assert.same(near, kept.Position)
    assert.are.equal(0, state.Stats.Snaps)
    -- 被甩开后整段钳回挂点
    local away = { x = mount.x + 20, y = mount.y, z = mount.z }
    local snapped = Carry.Follow(state, away, 100, 0.05)
    assert.is_true(snapped.Snapped)
    assert.same(mount, snapped.Position)
    assert.are.equal(1, state.Stats.Snaps)
    -- NaN 目标直接释放，绝不把 NaN 写回玩家身上
    local nan = Carry.Follow(state, { x = 0 / 0, y = 1, z = 2 }, 101, 0.05)
    assert.is_true(nan.Released)
    assert.are.equal('nan', nan.Reason)
    assert.is_false(Carry.Carried(state))
    assert.is_false(nan.Position.x ~= nan.Position.x)
  end)

  it("test_carry_expires_and_drops_ahead_of_the_host", function()
    local state
    Carry, state = newCarry(CarryCfg)
    Carry.Attach(state, { x = 1, y = 0, z = 1 }, 100)
    state.Host = { x = 0, y = 3, z = 0 }
    state.GroundY = 2
    local last = nil
    for step = 1, 600 do
      last = Carry.Step(state, 100 + step * 0.05, 0.05)
      if last.Released then break end
    end
    assert.is_true(last.Released)
    assert.are.equal('timeout', last.Reason)
    assert.is_false(Carry.Carried(state))
    -- 落点在宿主前方 DropForward 米、离地 DropHeight 米
    local drop = last.DropPoint
    assert.near(state.GroundY + CarryCfg.DropHeight, drop.y, 1e-9)
    assert.is_true(math.abs(drop.z - CarryCfg.DropForward) < 1e-9)
    -- 释放后不再重复触发，也不残留挂点
    local again = Carry.Step(state, 200, 0.05)
    assert.is_false(again.Released)
    assert.are.equal(false, Carry.Release(state, 200, 'manual').Ok)
    assert.are.equal('notCarrying', Carry.Release(state, 200, 'manual').Reason)
  end)

  it("test_config_matches_spec", function()
    assert.are.equal(300, CarryCfg.GrabDamage) -- GameSpec §12：沧龙咬中 300
    assert.are.equal('LiftSocket', CarryCfg.Socket) -- 与顶鱼挂点同名
    assert.are.equal(20, CarryCfg.MaxCarrySec)
  end)

  it("test_mount_offset_must_clear_both_bodies", function()
    local cfg = CarryCfg
    local need = cfg.HostHalfHeight + cfg.CarriedHalfHeight
    -- 配置里的嘴部挂点本身必须已经在宿主体外
    local offset = { x = cfg.Offset.x, y = cfg.Offset.y, z = cfg.Offset.z }
    local safe = Carry.SafeOffset(offset, cfg.HostHalfHeight, cfg.CarriedHalfHeight)
    assert.is_false(safe.Corrected, '默认挂点不该需要纠正')
    assert.is_true(Carry.Length(safe.Offset) >= need, '默认挂点必须清空宿主与携带物')
    -- 贴脸的挂点必须被推出去，且保留原方向
    local squeezed = Carry.SafeOffset({ x = 0, y = 0.3, z = 0.4 }, cfg.HostHalfHeight, cfg.CarriedHalfHeight)
    assert.is_true(squeezed.Corrected)
    assert.is_true(Carry.Length(squeezed.Offset) >= need)
    assert.is_true(squeezed.Offset.z > 0.4, '必须在原方向上推出去')
    assert.near(0.4 / 0.3, squeezed.Offset.z / squeezed.Offset.y, 1e-9)
    -- 零位移没有方向可用：给一个确定性方向而不是 NaN
    local zero = Carry.SafeOffset({ x = 0, y = 0, z = 0 }, 1, 1)
    assert.is_true(Carry.Length(zero.Offset) >= 2)
    assert.is_true(zero.Offset.z > 0)
    assert.are.equal(0, zero.Offset.x)
  end)

  it("test_mount_point_uses_host_pose_and_scaled_offset", function()
    local offset = { x = 0, y = 2, z = 2 }
    local host = { x = 10, y = 5, z = -3 }
    local point = Carry.MountPoint(host, offset, 0)
    assert.same({ x = 10, y = 7, z = -1 }, point)
    -- 转身 90 度：挂点跟着宿主朝向走
    local turned = Carry.MountPoint(host, offset, math.pi / 2)
    assert.near(12, turned.x, 1e-9)
    assert.near(7, turned.y, 1e-9)
    assert.near(-3, turned.z, 1e-9)
    -- 三倍体型：挂点位移随体型放大，挂件才不会陷进放大的身体
    local BodyScale = require('common.BodyScale')
    local base = { CapsuleHeight = Cfg.Ability.BodyScale.CapsuleHeight,
      SocketOffset = { x = 0, y = 2, z = 2 } }
    local one = BodyScale.Derive(1, base)
    local three = BodyScale.Derive(3, base)
    local p1 = Carry.MountPoint(host, one.SocketOffset, 0)
    local p3 = Carry.MountPoint(host, three.SocketOffset, 0)
    assert.is_true(p3.y > p1.y and p3.z > p1.z)
    assert.are.equal(11, p3.y)
  end)

  it("test_step_without_carry_is_a_noop", function()
    local state
    Carry, state = newCarry(CarryCfg)
    local events = Carry.Step(state, 100.05, 0.05)
    assert.is_false(events.Released)
    assert.is_nil(events.Position)
    assert.are.equal(1, state.Stats.Frames)
  end)
end)

-- 能力 B：飞行与俯冲（common/FlightPath.lua）。
-- 失败方式（先列后写）：
--   1. 越界：飞过钓鱼区围栏（借飞行跨区）、超过 20 米高度上限、掉到地面以下；
--   2. 一帧过大：dt 补算让单帧位移越过围栏（钳制被跳过）；
--   3. NaN 污染：位置或速度里出现 NaN/inf 后一直传播，单位从此不可见也救不回来；
--   4. 漂移：被外力顶飞后不回归航线，或每帧都被判定漂移而抖在原地；
--   5. 俯冲节奏：不俯冲 / 每帧都俯冲 / 俯冲后不回巡航高度 / 无目标时仍朝空目标俯冲。
local function flightBounds()
  return { MinX = -10, MaxX = 10, MinZ = -10, MaxZ = 10, BottomY = -5, TopY = 40,
    GroundY = 2, CeilingY = 22 }
end

local function newFlight(cfg, profile, start)
  local FlightPath = require('common.FlightPath')
  local state = FlightPath.New(flightBounds(), cfg, profile or {}, start or { x = 0, y = 14, z = 0 }, 100)
  return FlightPath, state
end

describe("TestFlightPath", function()
  local Cfg, Fly, FlightCfg

  before_each(function()
    Cfg = require('common.GameCfg')
    Fly = require('common.FlightPath')
    FlightCfg = Cfg.Ability.Flight
  end)

  it("test_bounds_come_from_zone_scene_and_cap_the_ceiling", function()
    local zone = Cfg.Zones[1].Scene
    local bounds = Fly.BoundsOf(zone, FlightCfg)
    assert.are.equal(zone.Boundary.MinX, bounds.MinX)
    assert.are.equal(zone.Boundary.MaxZ, bounds.MaxZ)
    assert.are.equal(zone.SafePoint.y, bounds.GroundY)
    assert.are.equal(zone.SafePoint.y + FlightCfg.MaxHeight, bounds.CeilingY)
    -- 场景合同缺 MaxFlightHeight 时用配置兜底，不能没有天花板
    local patched = {}
    for k, v in pairs(zone.Boundary) do patched[k] = v end
    patched.MaxFlightHeight = nil
    assert.are.equal(zone.SafePoint.y + FlightCfg.MaxHeight,
      Fly.BoundsOf({ Boundary = patched, SafePoint = zone.SafePoint }, FlightCfg).CeilingY)
    -- 没有围栏就没有飞行（不能无边界乱飞）
    assert.is_nil(Fly.BoundsOf(nil, FlightCfg))
    assert.is_nil(Fly.BoundsOf({ SafePoint = zone.SafePoint }, FlightCfg))
    assert.is_nil(Fly.BoundsOf({ Boundary = { MinX = 0 / 0 } }, FlightCfg))
  end)

  it("test_ceiling_clamp_keeps_the_fish_under_the_flight_ceiling", function()
    -- 票面「20 米飞行」：巡航目标高得离谱时也必须顶在天花板（地面 + MaxHeight）上
    local state
    Fly, state = newFlight(FlightCfg, { CruiseHeight = 999, DiveIntervalSec = 20 })
    local ceiling, yLogged = 0, false
    for step = 1, 60 do
      Fly.Step(state, 100 + step * 0.05, 0.05)
      ceiling = math.max(ceiling, state.Pos.y)
      assert.is_true(state.Pos.y <= 22, 'y ' .. tostring(state.Pos.y))
    end
    assert.is_true(ceiling > 21.9 and ceiling <= 22, '必须顶到天花板，实际 ' .. tostring(ceiling))
    for _, entry in ipairs(state.ClampLog) do
      if entry.axis == 'y' then yLogged = true end
    end
    assert.is_true(yLogged, '高度上限越界必须记进 ClampLog')
  end)

  it("test_dive_cadence_and_recovery_without_target", function()
    local state
    Fly, state = newFlight(FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20, DiveDamage = 30 })
    Fly.SetTarget(state, { x = 0, y = 2, z = 0 })
    local now, dives, minY = 100, 0, state.Pos.y
    for step = 1, 1210 do -- 60.5 秒（第 3 次俯冲在 60 秒整触发，多跑半秒避免边界抖动）
      now = now + 0.05
      local events = Fly.Step(state, now, 0.05)
      if events.dive then dives = dives + 1 end
      minY = math.min(minY, state.Pos.y)
    end
    assert.are.equal(3, dives) -- 20 秒一次，60 秒三次
    assert.are.equal(3, state.Stats.Dives)
    assert.is_true(minY < 12, '俯冲必须真的降低高度')
    assert.is_true(minY >= 2, '俯冲不得钻到地面以下')
    -- 第三次俯冲在 60 秒整刚好触发，再跑 4 秒让它落底并爬回
    for step = 1, 80 do
      now = now + 0.05
      Fly.Step(state, now, 0.05)
      minY = math.min(minY, state.Pos.y)
    end
    assert.is_true(state.Pos.y > 12, '俯冲结束必须爬回巡航高度')
    assert.are.equal('cruise', state.Phase)
    assert.are.equal(3, state.Stats.Dives, '爬回过程不得再触发俯冲')
    -- 无目标时只巡航，不俯冲
    Fly.SetTarget(state, nil)
    local solo = 0
    for step = 1, 600 do
      now = now + 0.05
      if Fly.Step(state, now, 0.05).dive then solo = solo + 1 end
    end
    assert.are.equal(0, solo)
    assert.are.equal(3, state.Stats.Dives)
  end)

  it("test_external_shove_is_pulled_back_to_the_route", function()
    local state
    Fly, state = newFlight(FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.Step(state, 100.1, 0.1)
    local route = { x = state.Pos.x, y = state.Pos.y, z = state.Pos.z }
    state.Pos.x = state.Pos.x + 30 -- 被顶飞
    local events = Fly.Step(state, 100.2, 0.1)
    assert.is_true(events.drift)
    assert.are.equal(1, state.Stats.Drifts)
    assert.is_true(math.abs(state.Pos.x - route.x) < 1e-9)
    assert.is_true(state.Last.x < 10, '回退点必须是合法点')
  end)

  it("test_huge_dt_cannot_step_over_the_fence", function()
    local state
    Fly, state = newFlight(FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.SetTarget(state, { x = 500, y = 12, z = 0 })
    local before = state.Pos.x
    Fly.Step(state, 101, 5) -- 一帧补算 5 秒
    assert.is_true(state.Pos.x - before <= FlightCfg.MaxStepSec * FlightCfg.DiveSpeed + 1e-9)
    assert.is_true(state.Pos.x <= 10)
    assert.are.equal(1, state.Stats.StepTruncations)
  end)

  it("test_nan_position_recovers_to_last_legal_point", function()
    local state
    Fly, state = newFlight(FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.Step(state, 100.1, 0.1)
    local safe = { x = state.Pos.x, y = state.Pos.y, z = state.Pos.z }
    state.Pos.x = 0 / 0
    local events = Fly.Step(state, 100.2, 0.1)
    assert.is_true(events.nan)
    assert.are.equal(1, state.Stats.NanRecoveries)
    assert.are.equal(safe.x, state.Pos.x)
    assert.are.equal(safe.z, state.Pos.z)
    assert.same({ x = 0, y = 0, z = 0 }, state.Vel)
    -- inf 与速度里的坏值同理
    state.Vel.y = math.huge
    assert.is_true(Fly.Step(state, 100.3, 0.1).nan)
    assert.are.equal(2, state.Stats.NanRecoveries)
    local ok, finite = pcall(function()
      return state.Pos.x == state.Pos.x and math.abs(state.Pos.x) < math.huge
        and math.abs(state.Pos.y) < math.huge and math.abs(state.Pos.z) < math.huge
    end)
    assert.is_true(ok and finite)
  end)

  it("test_target_outside_bounds_is_clamped_every_frame", function()
    local state
    Fly, state = newFlight(FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.SetTarget(state, { x = 999, y = 999, z = -999 })
    local clamps = 0
    for step = 1, 600 do
      local events = Fly.Step(state, 100 + step * 0.05, 0.05)
      clamps = clamps + (events.clamped or 0)
      assert.is_true(state.Pos.x >= -10 and state.Pos.x <= 10, 'x ' .. tostring(state.Pos.x))
      assert.is_true(state.Pos.z >= -10 and state.Pos.z <= 10, 'z ' .. tostring(state.Pos.z))
      assert.is_true(state.Pos.y <= 22, 'y ' .. tostring(state.Pos.y))
      assert.is_true(state.Pos.y >= -5, 'y ' .. tostring(state.Pos.y))
    end
    assert.is_true(clamps > 0, '越界必须被记录')
    assert.are.equal(clamps, state.Stats.Clamps)
    assert.is_true(#state.ClampLog > 0)
    assert.are.equal('x', state.ClampLog[1].axis)
  end)
end)
