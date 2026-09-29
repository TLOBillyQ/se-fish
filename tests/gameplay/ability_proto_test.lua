-- #132 T11 原型（能力 A：三倍体型）单测。纯逻辑在 common/BodyScale.lua，数值在 GameCfg.Ability.BodyScale。
-- 失败方式（先列后写）：
--   1. 药水数越界：负数 / 小数 / 非数 / 超过上限仍继续变大；上限那一档没有封顶标记；
--   2. 倍率污染：NaN / inf / ≤0 / 非数的倍率被写进单位，派生量随之变 NaN；
--   3. 派生量不是线性放大：胶囊高 / 相机距离 / 交互距离仍按 1 倍算，三倍角色够不到地面物与抛竿点；
--   4. 挂点位移不随体型放大：三倍角色身上的挂件陷进身体（真机「挂点不穿出」的前置条件）；
--   5. 血量成长与体型成长脱钩：10 个药水不是 900 血 / 3 倍，或超限后血量继续涨。
local lu = require('luaunit')

TestBodyScale = {}

function TestBodyScale:setUp()
    self.Cfg = require('common.GameCfg')
    self.BodyScale = require('common.BodyScale')
end

function TestBodyScale:test_config_matches_spec_linear_growth_and_caps()
    local c = self.Cfg.Ability.BodyScale
    lu.assertEquals(c.Base, 1)
    lu.assertEquals(c.Step, 0.2)
    lu.assertEquals(c.Max, 3)
    lu.assertEquals(c.MaxPotions, 10)
    lu.assertEquals(c.HealthBase, 300)
    lu.assertEquals(c.HealthMax, 900)
    lu.assertEquals(c.HealthStepPercent, 20)
end

function TestBodyScale:test_plan_grows_linearly_and_caps_at_ten_potions()
    local plan = self.BodyScale.Plan(0)
    lu.assertEquals(plan.Scale, 1)
    lu.assertEquals(plan.Health, 300)
    lu.assertFalse(plan.Capped)
    plan = self.BodyScale.Plan(5)
    lu.assertEquals(plan.Scale, 2)
    lu.assertEquals(plan.Health, 600)
    plan = self.BodyScale.Plan(10)
    lu.assertEquals(plan.Scale, 3)
    lu.assertEquals(plan.Health, 900)
    lu.assertTrue(plan.Capped)
    -- 超限不再提升，且仍然给出上限值（业务侧据此拒绝使用，见 GameSpec §2）
    for _, over in ipairs({ 11, 99 }) do
        local capped = self.BodyScale.Plan(over)
        lu.assertEquals(capped.Scale, 3, tostring(over))
        lu.assertEquals(capped.Health, 900, tostring(over))
        lu.assertTrue(capped.Capped, tostring(over))
    end
end

function TestBodyScale:test_plan_rejects_non_numbers_and_negatives_as_zero()
    for _, bad in ipairs({ -1, -0.5, '3', nil, 0 / 0, math.huge }) do
        local plan = self.BodyScale.Plan(bad)
        lu.assertEquals(plan.Scale, 1, tostring(bad))
        lu.assertEquals(plan.Health, 300, tostring(bad))
        lu.assertEquals(plan.Potions, 0, tostring(bad))
    end
    -- 小数不是「非法」而是「不足一个」：向下取整，不把玩家的成长一笔抹掉
    local floored = self.BodyScale.Plan(1.5)
    lu.assertEquals(floored.Potions, 1)
    lu.assertEquals(floored.Scale, 1.2)
    lu.assertFalse(floored.Capped)
end

function TestBodyScale:test_sanitize_never_lets_a_bad_factor_through()
    local c = self.Cfg.Ability.BodyScale
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge, 0, -2, '2', nil }) do
        lu.assertEquals(self.BodyScale.Sanitize(bad), c.Base, tostring(bad))
    end
    lu.assertEquals(self.BodyScale.Sanitize(2.4), 2.4)
    lu.assertEquals(self.BodyScale.Sanitize(99), c.Max)
    lu.assertEquals(self.BodyScale.Sanitize(0.1), c.Base)
end

function TestBodyScale:test_derive_scales_capsule_camera_interact_and_socket()
    local c = self.Cfg.Ability.BodyScale
    local base = { CapsuleHeight = c.CapsuleHeight, CameraDistance = c.CameraDistance,
        InteractRange = c.InteractRange, SocketOffset = { x = 0, y = 2.4, z = 0 } }
    local one = self.BodyScale.Derive(1, base)
    lu.assertEquals(one, { Scale = 1, CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2,
        SocketOffset = { x = 0, y = 2.4, z = 0 } })
    local three = self.BodyScale.Derive(3, base)
    lu.assertEquals(three.CapsuleHeight, 6)
    lu.assertEquals(three.CameraDistance, 18)
    lu.assertEquals(three.InteractRange, 6)
    lu.assertAlmostEquals(three.SocketOffset.x, 0, 1e-9)
    lu.assertAlmostEquals(three.SocketOffset.y, 7.2, 1e-9)
    lu.assertAlmostEquals(three.SocketOffset.z, 0, 1e-9)
    -- 挂点位移必须随体型放大，否则三倍角色身上的挂件陷进身体
    lu.assertTrue(three.SocketOffset.y > one.SocketOffset.y)
end

function TestBodyScale:test_derive_falls_back_to_one_x_when_factor_is_bad()
    local base = { CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2 }
    for _, bad in ipairs({ 0 / 0, math.huge, 0, -1, nil, '3' }) do
        local derived = self.BodyScale.Derive(bad, base)
        lu.assertEquals(derived.Scale, 1, tostring(bad))
        lu.assertEquals(derived.CapsuleHeight, 2, tostring(bad))
        lu.assertEquals(derived.SocketOffset, nil, tostring(bad))
    end
    -- 基准量本身是坏值时也不能产出 NaN
    local derived = self.BodyScale.Derive(3, { CapsuleHeight = 0 / 0, CameraDistance = 'x' })
    lu.assertEquals(derived.CapsuleHeight, 0)
    lu.assertEquals(derived.CameraDistance, 0)
    lu.assertEquals(#tostring(derived), #tostring(derived)) -- 只保证不抛错
    lu.assertNotNil(derived)
    lu.assertFalse(derived.CapsuleHeight ~= derived.CapsuleHeight)
end

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

TestFlightPath = {}

function TestFlightPath:setUp()
    self.Cfg = require('common.GameCfg')
    self.Fly = require('common.FlightPath')
    self.FlightCfg = self.Cfg.Ability.Flight
end

function TestFlightPath:test_bounds_come_from_zone_scene_and_cap_the_ceiling()
    local zone = self.Cfg.Zones[1].Scene
    local bounds = self.Fly.BoundsOf(zone, self.FlightCfg)
    lu.assertEquals(bounds.MinX, zone.Boundary.MinX)
    lu.assertEquals(bounds.MaxZ, zone.Boundary.MaxZ)
    lu.assertEquals(bounds.GroundY, zone.SafePoint.y)
    lu.assertEquals(bounds.CeilingY, zone.SafePoint.y + self.FlightCfg.MaxHeight)
    -- 场景合同缺 MaxFlightHeight 时用配置兜底，不能没有天花板
    local patched = {}
    for k, v in pairs(zone.Boundary) do patched[k] = v end
    patched.MaxFlightHeight = nil
    lu.assertEquals(self.Fly.BoundsOf({ Boundary = patched, SafePoint = zone.SafePoint }, self.FlightCfg).CeilingY,
        zone.SafePoint.y + self.FlightCfg.MaxHeight)
    -- 没有围栏就没有飞行（不能无边界乱飞）
    lu.assertEquals(self.Fly.BoundsOf(nil, self.FlightCfg), nil)
    lu.assertEquals(self.Fly.BoundsOf({ SafePoint = zone.SafePoint }, self.FlightCfg), nil)
    lu.assertEquals(self.Fly.BoundsOf({ Boundary = { MinX = 0 / 0 } }, self.FlightCfg), nil)
end

function TestFlightPath:test_target_outside_bounds_is_clamped_every_frame()
    local Fly, state = newFlight(self.FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.SetTarget(state, { x = 999, y = 999, z = -999 })
    local clamps = 0
    for step = 1, 600 do
        local events = Fly.Step(state, 100 + step * 0.05, 0.05)
        clamps = clamps + (events.clamped or 0)
        lu.assertTrue(state.Pos.x >= -10 and state.Pos.x <= 10, 'x ' .. tostring(state.Pos.x))
        lu.assertTrue(state.Pos.z >= -10 and state.Pos.z <= 10, 'z ' .. tostring(state.Pos.z))
        lu.assertTrue(state.Pos.y <= 22, 'y ' .. tostring(state.Pos.y))
        lu.assertTrue(state.Pos.y >= -5, 'y ' .. tostring(state.Pos.y))
    end
    lu.assertTrue(clamps > 0, '越界必须被记录')
    lu.assertEquals(state.Stats.Clamps, clamps)
    lu.assertTrue(#state.ClampLog > 0)
    lu.assertEquals(state.ClampLog[1].axis, 'x')
end

function TestFlightPath:test_ceiling_clamp_keeps_the_fish_under_the_flight_ceiling()
    -- 票面「20 米飞行」：巡航目标高得离谱时也必须顶在天花板（地面 + MaxHeight）上
    local Fly, state = newFlight(self.FlightCfg, { CruiseHeight = 999, DiveIntervalSec = 20 })
    local ceiling, yLogged = 0, false
    for step = 1, 60 do
        Fly.Step(state, 100 + step * 0.05, 0.05)
        ceiling = math.max(ceiling, state.Pos.y)
        lu.assertTrue(state.Pos.y <= 22, 'y ' .. tostring(state.Pos.y))
    end
    lu.assertTrue(ceiling > 21.9 and ceiling <= 22, '必须顶到天花板，实际 ' .. tostring(ceiling))
    for _, entry in ipairs(state.ClampLog) do
        if entry.axis == 'y' then yLogged = true end
    end
    lu.assertTrue(yLogged, '高度上限越界必须记进 ClampLog')
end

function TestFlightPath:test_huge_dt_cannot_step_over_the_fence()
    local Fly, state = newFlight(self.FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.SetTarget(state, { x = 500, y = 12, z = 0 })
    local before = state.Pos.x
    Fly.Step(state, 101, 5) -- 一帧补算 5 秒
    lu.assertTrue(state.Pos.x - before <= self.FlightCfg.MaxStepSec * self.FlightCfg.DiveSpeed + 1e-9)
    lu.assertTrue(state.Pos.x <= 10)
    lu.assertEquals(state.Stats.StepTruncations, 1)
end

function TestFlightPath:test_nan_position_recovers_to_last_legal_point()
    local Fly, state = newFlight(self.FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.Step(state, 100.1, 0.1)
    local safe = { x = state.Pos.x, y = state.Pos.y, z = state.Pos.z }
    state.Pos.x = 0 / 0
    local events = Fly.Step(state, 100.2, 0.1)
    lu.assertEquals(events.nan, true)
    lu.assertEquals(state.Stats.NanRecoveries, 1)
    lu.assertEquals(state.Pos.x, safe.x)
    lu.assertEquals(state.Pos.z, safe.z)
    lu.assertEquals(state.Vel, { x = 0, y = 0, z = 0 })
    -- inf 与速度里的坏值同理
    state.Vel.y = math.huge
    lu.assertEquals(Fly.Step(state, 100.3, 0.1).nan, true)
    lu.assertEquals(state.Stats.NanRecoveries, 2)
    local ok, finite = pcall(function()
        return state.Pos.x == state.Pos.x and math.abs(state.Pos.x) < math.huge
            and math.abs(state.Pos.y) < math.huge and math.abs(state.Pos.z) < math.huge
    end)
    lu.assertTrue(ok and finite)
end

function TestFlightPath:test_external_shove_is_pulled_back_to_the_route()
    local Fly, state = newFlight(self.FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20 })
    Fly.Step(state, 100.1, 0.1)
    local route = { x = state.Pos.x, y = state.Pos.y, z = state.Pos.z }
    state.Pos.x = state.Pos.x + 30 -- 被顶飞
    local events = Fly.Step(state, 100.2, 0.1)
    lu.assertEquals(events.drift, true)
    lu.assertEquals(state.Stats.Drifts, 1)
    lu.assertTrue(math.abs(state.Pos.x - route.x) < 1e-9)
    lu.assertTrue(state.Last.x < 10, '回退点必须是合法点')
end

function TestFlightPath:test_dive_cadence_and_recovery_without_target()
    local Fly, state = newFlight(self.FlightCfg, { CruiseHeight = 12, DiveIntervalSec = 20, DiveDamage = 30 })
    Fly.SetTarget(state, { x = 0, y = 2, z = 0 })
    local now, dives, minY = 100, 0, state.Pos.y
    for step = 1, 1210 do -- 60.5 秒（第 3 次俯冲在 60 秒整触发，多跑半秒避免边界抖动）
        now = now + 0.05
        local events = Fly.Step(state, now, 0.05)
        if events.dive then dives = dives + 1 end
        minY = math.min(minY, state.Pos.y)
    end
    lu.assertEquals(dives, 3) -- 20 秒一次，60 秒三次
    lu.assertEquals(state.Stats.Dives, 3)
    lu.assertTrue(minY < 12, '俯冲必须真的降低高度')
    lu.assertTrue(minY >= 2, '俯冲不得钻到地面以下')
    -- 第三次俯冲在 60 秒整刚好触发，再跑 4 秒让它落底并爬回
    for step = 1, 80 do
        now = now + 0.05
        Fly.Step(state, now, 0.05)
        minY = math.min(minY, state.Pos.y)
    end
    lu.assertTrue(state.Pos.y > 12, '俯冲结束必须爬回巡航高度')
    lu.assertEquals(state.Phase, 'cruise')
    lu.assertEquals(state.Stats.Dives, 3, '爬回过程不得再触发俯冲')
    -- 无目标时只巡航，不俯冲
    Fly.SetTarget(state, nil)
    local solo = 0
    for step = 1, 600 do
        now = now + 0.05
        if Fly.Step(state, now, 0.05).dive then solo = solo + 1 end
    end
    lu.assertEquals(solo, 0)
    lu.assertEquals(state.Stats.Dives, 3)
end

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

TestCarryMount = {}

function TestCarryMount:setUp()
    self.Cfg = require('common.GameCfg')
    self.Carry = require('common.CarryMount')
    self.CarryCfg = self.Cfg.Ability.Carry
end

function TestCarryMount:test_config_matches_spec()
    lu.assertEquals(self.CarryCfg.GrabDamage, 300) -- GameSpec §12：沧龙咬中 300
    lu.assertEquals(self.CarryCfg.Socket, 'LiftSocket') -- 与顶鱼挂点同名
    lu.assertEquals(self.CarryCfg.MaxCarrySec, 20)
end

function TestCarryMount:test_mount_offset_must_clear_both_bodies()
    local cfg = self.CarryCfg
    local need = cfg.HostHalfHeight + cfg.CarriedHalfHeight
    -- 配置里的嘴部挂点本身必须已经在宿主体外
    local offset = { x = cfg.Offset.x, y = cfg.Offset.y, z = cfg.Offset.z }
    local safe = self.Carry.SafeOffset(offset, cfg.HostHalfHeight, cfg.CarriedHalfHeight)
    lu.assertFalse(safe.Corrected, '默认挂点不该需要纠正')
    lu.assertTrue(self.Carry.Length(safe.Offset) >= need, '默认挂点必须清空宿主与携带物')
    -- 贴脸的挂点必须被推出去，且保留原方向
    local squeezed = self.Carry.SafeOffset({ x = 0, y = 0.3, z = 0.4 }, cfg.HostHalfHeight, cfg.CarriedHalfHeight)
    lu.assertTrue(squeezed.Corrected)
    lu.assertTrue(self.Carry.Length(squeezed.Offset) >= need)
    lu.assertTrue(squeezed.Offset.z > 0.4, '必须在原方向上推出去')
    lu.assertAlmostEquals(squeezed.Offset.z / squeezed.Offset.y, 0.4 / 0.3, 1e-9)
    -- 零位移没有方向可用：给一个确定性方向而不是 NaN
    local zero = self.Carry.SafeOffset({ x = 0, y = 0, z = 0 }, 1, 1)
    lu.assertTrue(self.Carry.Length(zero.Offset) >= 2)
    lu.assertTrue(zero.Offset.z > 0)
    lu.assertEquals(zero.Offset.x, 0)
end

function TestCarryMount:test_mount_point_uses_host_pose_and_scaled_offset()
    local offset = { x = 0, y = 2, z = 2 }
    local host = { x = 10, y = 5, z = -3 }
    local point = self.Carry.MountPoint(host, offset, 0)
    lu.assertEquals(point, { x = 10, y = 7, z = -1 })
    -- 转身 90 度：挂点跟着宿主朝向走
    local turned = self.Carry.MountPoint(host, offset, math.pi / 2)
    lu.assertAlmostEquals(turned.x, 12, 1e-9)
    lu.assertAlmostEquals(turned.y, 7, 1e-9)
    lu.assertAlmostEquals(turned.z, -3, 1e-9)
    -- 三倍体型：挂点位移随体型放大，挂件才不会陷进放大的身体
    local BodyScale = require('common.BodyScale')
    local base = { CapsuleHeight = self.Cfg.Ability.BodyScale.CapsuleHeight,
        SocketOffset = { x = 0, y = 2, z = 2 } }
    local one = BodyScale.Derive(1, base)
    local three = BodyScale.Derive(3, base)
    local p1 = self.Carry.MountPoint(host, one.SocketOffset, 0)
    local p3 = self.Carry.MountPoint(host, three.SocketOffset, 0)
    lu.assertTrue(p3.y > p1.y and p3.z > p1.z)
    lu.assertEquals(p3.y, 11)
end

function TestCarryMount:test_attach_needs_a_target_inside_grab_range()
    local Carry, state = newCarry(self.CarryCfg)
    lu.assertFalse(Carry.Attach(state, nil, 100).Ok)
    lu.assertEquals(Carry.Attach(state, nil, 100).Reason, 'noTarget')
    local far = { x = 99, y = 0, z = 0 }
    lu.assertFalse(Carry.Attach(state, far, 100).Ok)
    lu.assertEquals(Carry.Attach(state, far, 100).Reason, 'outOfRange')
    lu.assertFalse(Carry.Carried(state))
    local near = { x = 1, y = 0, z = 1 }
    local attach = Carry.Attach(state, near, 100)
    lu.assertTrue(attach.Ok)
    lu.assertEquals(attach.Damage, self.CarryCfg.GrabDamage)
    lu.assertTrue(Carry.Carried(state))
    -- 没有挂点的宿主不吃这套（不能凭空抱走）
    local Bare, bareState = newCarry({ Socket = nil, GrabRange = 2.5, GrabDamage = 300,
        Offset = { x = 0, y = 0, z = 2 }, FollowTolerance = 3, MaxCarrySec = 20 })
    lu.assertFalse(Bare.Attach(bareState, near, 100).Ok)
    lu.assertEquals(Bare.Attach(bareState, near, 100).Reason, 'noSocket')
end

function TestCarryMount:test_carried_body_is_snapped_back_when_it_drifts()
    local Carry, state = newCarry(self.CarryCfg)
    Carry.Attach(state, { x = 1, y = 0, z = 1 }, 100)
    local mount = self.Carry.MountPoint(state.Host, state.Offset, state.Yaw)
    -- 容差内不动它，避免每帧都被「纠正」而抖动
    local near = { x = mount.x + 0.1, y = mount.y, z = mount.z }
    local kept = Carry.Follow(state, near, 100, 0.05)
    lu.assertFalse(kept.Snapped)
    lu.assertEquals(kept.Position, near)
    lu.assertEquals(state.Stats.Snaps, 0)
    -- 被甩开后整段钳回挂点
    local away = { x = mount.x + 20, y = mount.y, z = mount.z }
    local snapped = Carry.Follow(state, away, 100, 0.05)
    lu.assertTrue(snapped.Snapped)
    lu.assertEquals(snapped.Position, mount)
    lu.assertEquals(state.Stats.Snaps, 1)
    -- NaN 目标直接释放，绝不把 NaN 写回玩家身上
    local nan = Carry.Follow(state, { x = 0 / 0, y = 1, z = 2 }, 101, 0.05)
    lu.assertTrue(nan.Released)
    lu.assertEquals(nan.Reason, 'nan')
    lu.assertFalse(Carry.Carried(state))
    lu.assertFalse(nan.Position.x ~= nan.Position.x)
end

function TestCarryMount:test_carry_expires_and_drops_ahead_of_the_host()
    local Carry, state = newCarry(self.CarryCfg)
    Carry.Attach(state, { x = 1, y = 0, z = 1 }, 100)
    state.Host = { x = 0, y = 3, z = 0 }
    state.GroundY = 2
    local last = nil
    for step = 1, 600 do
        last = Carry.Step(state, 100 + step * 0.05, 0.05)
        if last.Released then break end
    end
    lu.assertTrue(last.Released)
    lu.assertEquals(last.Reason, 'timeout')
    lu.assertFalse(Carry.Carried(state))
    -- 落点在宿主前方 DropForward 米、离地 DropHeight 米
    local drop = last.DropPoint
    lu.assertAlmostEquals(drop.y, state.GroundY + self.CarryCfg.DropHeight, 1e-9)
    lu.assertTrue(math.abs(drop.z - self.CarryCfg.DropForward) < 1e-9)
    -- 释放后不再重复触发，也不残留挂点
    local again = Carry.Step(state, 200, 0.05)
    lu.assertFalse(again.Released)
    lu.assertEquals(Carry.Release(state, 200, 'manual').Ok, false)
    lu.assertEquals(Carry.Release(state, 200, 'manual').Reason, 'notCarrying')
end

function TestCarryMount:test_step_without_carry_is_a_noop()
    local Carry, state = newCarry(self.CarryCfg)
    local events = Carry.Step(state, 100.05, 0.05)
    lu.assertFalse(events.Released)
    lu.assertEquals(events.Position, nil)
    lu.assertEquals(state.Stats.Frames, 1)
end
