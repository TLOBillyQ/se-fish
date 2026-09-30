-- #132 T11 高风险能力原型 · 单进程多身份探针（可重跑，确定性输出）。
--
-- 用法（仓库根）：lua tests/probes/ability_proto.lua
-- 退出码 0 = 全部通过；1 = 有断言失败（输出里逐条 [FAIL]）。
--
-- 本探针在同一个进程里模拟多个玩家身份（1001 / 1002，只用 UserId 与坐标区分），
-- 把四类能力的纯逻辑与配置一起跑一遍，并打印关键量：
--   A 三倍体型 → 缩放后的挂点世界坐标（1 倍 vs 3 倍）
--   B 飞行     → 越界钳制记录（ClampLog / Stats）与坏值、漂移防护后的坐标
--   C 巡航叼人 → 挂点净空判定、携带跟随、两个身份先后被叼
--   D 分阶段首领 → 阶段切换序列（含一帧跨两阈值）、失目标与死亡打断
--
-- 边界：探针只证明「逻辑与数据契约自洽」，**不替代真机试玩**——碰撞、相机、挂点是否穿模、
-- 动画表现都必须在编辑器窗口里验证（见 issue #132 的待办清单）。探针不连接编辑器。
package.path = table.concat({ "./?.lua", "./?/init.lua", package.path }, ";")

local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')
local FlightPath = require('common.FlightPath')
local CarryMount = require('common.CarryMount')
local BossPhase = require('common.BossPhase')

local Pass, Fail = 0, 0
local function check(name, ok, detail)
    if ok then Pass = Pass + 1 else Fail = Fail + 1 end
    print(string.format('[%s] %s%s', ok and 'PASS' or 'FAIL', name,
        detail and ('  ' .. tostring(detail)) or ''))
end

-- 关键量：以 K 前缀单独成行，便于从运行输出里直接抄进台账。
local function quantity(label, value)
    print(string.format('K %s = %s', label, tostring(value)))
end

local function fmt(p)
    return string.format('(%.3f, %.3f, %.3f)', p.x, p.y, p.z)
end

local function finite(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function finitePoint(p)
    return type(p) == 'table' and finite(p.x) and finite(p.y) and finite(p.z)
end

local function samePoint(a, b, eps)
    eps = eps or 1e-6
    return math.abs(a.x - b.x) <= eps and math.abs(a.y - b.y) <= eps and math.abs(a.z - b.z) <= eps
end

-- =====================================================================================
-- 多身份：1001 = 近岛玩家（会被叼走），1002 = 外圈玩家（诱导越界 / 远距离打鱼）
-- =====================================================================================
local Players = {
    { UserId = 1001, Pos = { x = 101.0, y = 2, z = 52.0 }, Tag = 'P1001' },
    { UserId = 1002, Pos = { x = 999.0, y = 0, z = 999.0 }, Tag = 'P1002' },
}
print('== 身份：' .. Players[1].Tag .. ' 近岛 ' .. fmt(Players[1].Pos)
    .. ' / ' .. Players[2].Tag .. ' 远点 ' .. fmt(Players[2].Pos))

-- =====================================================================================
-- A 三倍体型：药水成长、派生量与缩放后的挂点坐标
-- =====================================================================================
print('== A 三倍体型与挂点坐标')
local B = GameCfg.Ability.BodyScale
local Carry = GameCfg.Ability.Carry

local plan0 = BodyScale.Plan(0)
local plan10 = BodyScale.Plan(10)
local plan11 = BodyScale.Plan(11)
local planBad = BodyScale.Plan(0 / 0)
quantity('A 体型 0 瓶', string.format('scale=%.1f health=%.0f capped=%s',
    plan0.Scale, plan0.Health, tostring(plan0.Capped)))
quantity('A 体型 10 瓶', string.format('scale=%.1f health=%.0f capped=%s',
    plan10.Scale, plan10.Health, tostring(plan10.Capped)))
check('A 起手 1 倍 / 300 血', plan0.Scale == B.Base and plan0.Health == B.HealthBase)
check('A 满 10 瓶 = 3 倍 / 900 血且封顶',
    plan10.Scale == B.Max and plan10.Health == B.HealthMax and plan10.Capped)
check('A 超出上限的瓶数不越界', plan11.Scale == B.Max and plan11.Potions == plan10.Potions)
check('A NaN 瓶数按 0 处理（不污染体型）',
    planBad.Scale == B.Base and planBad.Health == B.HealthBase)
check('A 倍率净化：NaN/负数/超上限都落回有限值',
    BodyScale.Sanitize(0 / 0) == 1 and BodyScale.Sanitize(-2) == 1 and BodyScale.Sanitize(99) == B.Max)

-- 挂点位移按体型放大（与真实宿主同口径：base 提供 SocketOffset，Derive 逐轴乘倍率）
local base = {
    CapsuleHeight = B.CapsuleHeight, CameraDistance = B.CameraDistance,
    InteractRange = B.InteractRange, SocketOffset = Carry.Offset,
}
local d1 = BodyScale.Derive(1, base)
local d3 = BodyScale.Derive(3, base)
quantity('A 派生量 1 倍', string.format('capsule=%.1f camera=%.1f interact=%.1f',
    d1.CapsuleHeight, d1.CameraDistance, d1.InteractRange))
quantity('A 派生量 3 倍', string.format('capsule=%.1f camera=%.1f interact=%.1f',
    d3.CapsuleHeight, d3.CameraDistance, d3.InteractRange))
check('A 胶囊/相机/交互距离随倍率等比放大',
    d3.CapsuleHeight == d1.CapsuleHeight * 3 and d3.CameraDistance == d1.CameraDistance * 3
    and d3.InteractRange == d1.InteractRange * 3)

local Host = { x = 100, y = 2, z = 50 }   -- 两条身份共用的宿主（哥斯拉）位置
local Yaw = math.pi / 2                    -- 宿主朝向：+x
local mount1 = CarryMount.MountPoint(Host, d1.SocketOffset, Yaw)
local mount3 = CarryMount.MountPoint(Host, d3.SocketOffset, Yaw)
quantity('A 挂点世界坐标 1 倍', fmt(mount1))
quantity('A 挂点世界坐标 3 倍', fmt(mount3))
local delta1 = { x = mount1.x - Host.x, y = mount1.y - Host.y, z = mount1.z - Host.z }
local delta3 = { x = mount3.x - Host.x, y = mount3.y - Host.y, z = mount3.z - Host.z }
check('A 挂点坐标随体型等比外推（3 倍 = 1 倍 × 3）',
    math.abs(delta3.x - delta1.x * 3) < 1e-9 and math.abs(delta3.y - delta1.y * 3) < 1e-9
    and math.abs(delta3.z - delta1.z * 3) < 1e-9)
check('A 两种体型下挂点坐标都是有限值', finitePoint(mount1) and finitePoint(mount3))

-- 挂点不穿出：中心距 ≥ 宿主半高 + 携带物半高（两者都随体型放大，比值不变）
local safe1 = CarryMount.SafeOffset(d1.SocketOffset, Carry.HostHalfHeight, Carry.CarriedHalfHeight)
local safe3 = CarryMount.SafeOffset(d3.SocketOffset, Carry.HostHalfHeight * 3, Carry.CarriedHalfHeight * 3)
quantity('A 挂点位移长度 1 倍 / 3 倍',
    string.format('%.3f / %.3f（净空要求 %.3f / %.3f）',
        CarryMount.Length(d1.SocketOffset), CarryMount.Length(d3.SocketOffset),
        Carry.HostHalfHeight + Carry.CarriedHalfHeight,
        (Carry.HostHalfHeight + Carry.CarriedHalfHeight) * 3))
check('A 1 倍与 3 倍体型下挂点都在宿主体外（无需纠正）',
    safe1.Corrected == false and safe3.Corrected == false)
local tight = CarryMount.SafeOffset({ x = 0, y = 0.1, z = 0.1 }, Carry.HostHalfHeight, Carry.CarriedHalfHeight)
quantity('A 贴脸位移纠正后', fmt(tight.Offset))
check('A 贴脸位移被判为穿出并推出到净空距离', tight.Corrected == true
    and CarryMount.Length(tight.Offset) >= Carry.HostHalfHeight + Carry.CarriedHalfHeight - 1e-9)
check('A 零位移兜底不产出 NaN 方向',
    finitePoint(CarryMount.SafeOffset({ x = 0, y = 0, z = 0 }, 1, 1).Offset))

-- =====================================================================================
-- B 飞行：围栏钳制、俯冲节奏、坏值与漂移防护
-- =====================================================================================
print('== B 飞行边界与防护')
local F = GameCfg.Ability.Flight
local zone = nil
for _, entry in ipairs(GameCfg.Zones) do
    if entry.Id == 'reefIsland' then zone = entry.Scene end
end
local bounds = FlightPath.BoundsOf(zone, F)
check('B 钓鱼区场景合同给出了有限围栏', bounds ~= nil and finite(bounds.MinX) and finite(bounds.CeilingY))
quantity('B 围栏', string.format('x[%.1f,%.1f] z[%.1f,%.1f] ground=%.1f ceiling=%.1f',
    bounds.MinX, bounds.MaxX, bounds.MinZ, bounds.MaxZ, bounds.GroundY, bounds.CeilingY))
check('B 高度上限 = 地面 + MaxFlightHeight（#125 合同的 20 米）',
    math.abs(bounds.CeilingY - (bounds.GroundY + bounds.MaxHeight)) < 1e-9)
check('B 场景缺失时返回 nil（无边界不飞）', FlightPath.BoundsOf(nil, F) == nil
    and FlightPath.BoundsOf({}, F) == nil)

-- 目标故意放到围栏外（用身份 1002 的远点）：飞行每帧都会被夹回本区
local fly = FlightPath.New(bounds, F, F.Species.fish47Elite,
    { x = 0, y = bounds.GroundY + 12, z = 0 }, 0)
FlightPath.SetTarget(fly, Players[2].Pos)
local violations = 0
local now = 0
for _ = 1, 1210 do    -- 60.5 秒，按 0.05 秒一帧
    now = now + 0.05
    FlightPath.Step(fly, now, 0.05)
    local p = fly.Pos
    if p.x > bounds.MaxX + 1e-9 or p.x < bounds.MinX - 1e-9
        or p.z > bounds.MaxZ + 1e-9 or p.z < bounds.MinZ - 1e-9
        or p.y > bounds.CeilingY + 1e-9 then
        violations = violations + 1
    end
end
quantity('B 60.5 秒后坐标', fmt(fly.Pos))
quantity('B Stats', string.format('frames=%d clamps=%d dives=%d trunc=%d',
    fly.Stats.Frames, fly.Stats.Clamps, fly.Stats.Dives, fly.Stats.StepTruncations))
quantity('B 越界钳制记录条数', #fly.ClampLog)
for index = 1, math.min(#fly.ClampLog, 4) do
    local entry = fly.ClampLog[index]
    print(string.format('K B 钳制[%d] axis=%s %.3f -> %.3f phase=%s',
        index, entry.axis, entry.from, entry.to, entry.phase))
end
check('B 全程没有任何一帧飞出围栏', violations == 0, 'violations=' .. violations)
check('B 越界被钳制并计数（ClampLog 非空）', fly.Stats.Clamps > 0 and #fly.ClampLog > 0)
check('B 俯冲按 20 秒节奏触发（60 秒内 3 次）', fly.Stats.Dives == 3, 'dives=' .. fly.Stats.Dives)

-- 坏值与漂移：新状态单独验，不干扰上面的钳制记录
local guard = FlightPath.New(bounds, F, F.Species.fish48Boss,
    { x = 0, y = bounds.GroundY + 15, z = 0 }, 0)
FlightPath.SetTarget(guard, Players[1].Pos)
guard.Pos.x = 0 / 0
local nanEvent = FlightPath.Step(guard, 1, 0.05)
quantity('B NaN 恢复后坐标', fmt(nanEvent.position or guard.Pos))
check('B NaN 被识别并退回上一合法点（速度清零）',
    nanEvent.nan == true and guard.Stats.NanRecoveries == 1
    and finitePoint(guard.Pos) and guard.Vel.x == 0 and guard.Vel.y == 0 and guard.Vel.z == 0)
guard.Pos = { x = guard.Last.x + 500, y = guard.Last.y, z = guard.Last.z }
local driftEvent = FlightPath.Step(guard, 2, 0.05)
quantity('B 漂移钳回后坐标', fmt(driftEvent.position or guard.Pos))
check('B 被外力顶飞时整段钳回（不瞬移）',
    driftEvent.drift == true and guard.Stats.Drifts == 1 and samePoint(guard.Pos, guard.Last))
local huge = FlightPath.Step(guard, 3, 5)   -- dt 过大：截断成最大步长
check('B 超大 dt 被截断（补算不得一帧跨过围栏）',
    huge.truncated == true and guard.Stats.StepTruncations == 1)
check('B 防护后坐标始终有限（无 NaN/漂移残留）', finitePoint(guard.Pos))

-- 跃起（沧龙 fish55Elite：每 15 秒高高跃起）：抛物线到 LeapHeight 再回到水面高度。
-- 用沧龙自己的钓鱼区（volcanoIsland）围栏，而不是白头鹰所在的礁岛。
local volcano = nil
for _, entry in ipairs(GameCfg.Zones) do
    if entry.Id == 'volcanoIsland' then volcano = entry.Scene end
end
local leapBounds = FlightPath.BoundsOf(volcano, F)
check('B 火山岛（沧龙所在区）场景合同给出有限围栏',
    leapBounds ~= nil and finite(leapBounds.MinX) and finite(leapBounds.CeilingY))
quantity('B 火山岛围栏', string.format('x[%.1f,%.1f] z[%.1f,%.1f] ground=%.1f ceiling=%.1f',
    leapBounds.MinX, leapBounds.MaxX, leapBounds.MinZ, leapBounds.MaxZ, leapBounds.GroundY,
    leapBounds.CeilingY))
local center = { x = (leapBounds.MinX + leapBounds.MaxX) / 2, z = (leapBounds.MinZ + leapBounds.MaxZ) / 2 }
local leap = FlightPath.New(leapBounds, F, F.Species.fish55Elite,
    { x = center.x, y = leapBounds.GroundY, z = center.z }, 0)
local apex, leapViolations = 0, 0
for step = 1, 400 do    -- 20 秒
    FlightPath.Step(leap, step * 0.05, 0.05)
    if leap.Pos.y - leapBounds.GroundY > apex then apex = leap.Pos.y - leapBounds.GroundY end
    if leap.Pos.y > leapBounds.CeilingY + 1e-9 or leap.Pos.y < leapBounds.GroundY - 1e-9 then
        leapViolations = leapViolations + 1
    end
end
quantity('B 沧龙跃起最高点（相对水面）', string.format('%.3f（配置 LeapHeight=%.1f）', apex, F.LeapHeight))
quantity('B 沧龙 20 秒内跃起次数 / 结束阶段', string.format('%d / %s', leap.Stats.Dives, leap.Phase))
check('B 沧龙跃起达到配置高度并落回水面（不越界）',
    leap.Stats.Dives == 1 and apex > F.LeapHeight * 0.95 and apex <= F.LeapHeight
    and leapViolations == 0 and leap.Phase == 'cruise')

-- =====================================================================================
-- C 巡航叼人：挂点净空、携带跟随、两个身份先后被叼、释放幂等
-- =====================================================================================
print('== C 巡航叼人')
local carry = CarryMount.New(Carry, Host, Yaw, 0)
carry.GroundY = Host.y
quantity('C 挂点位移', fmt(carry.Offset))
quantity('C 挂点世界坐标', fmt(CarryMount.MountPoint(Host, carry.Offset, Yaw)))
check('C 宿主外挂点（净空足够，无需纠正）', carry.Corrected == false
    and CarryMount.Length(carry.Offset) >= Carry.HostHalfHeight + Carry.CarriedHalfHeight)

local tooFar = CarryMount.Attach(carry, Players[2].Pos, 0)
check('C 超出抓取距离不叼', tooFar.Ok == false and tooFar.Reason == 'outOfRange')
local grabbed = CarryMount.Attach(carry, Players[1].Pos, 0)
quantity('C 咬中伤害', grabbed.Damage)
check('C 就近身份 1001 被叼走（咬中 300）', grabbed.Ok == true and grabbed.Damage == Carry.GrabDamage)
check('C 叼中时的挂点坐标有限', finitePoint(CarryMount.MountPoint(carry.Host, carry.Offset, carry.Yaw)))

Players[1].Pos = { x = Host.x + 1, y = Host.y, z = Host.z + 1 }   -- 容差内的小幅漂移
local hold = CarryMount.Follow(carry, Players[1].Pos, 0.05, 0.05)
check('C 容差内不写回（避免每帧抖动）', hold.Snapped == false and samePoint(hold.Position, Players[1].Pos))
Players[1].Pos = { x = 999, y = 0, z = 999 }                      -- 被甩开
local snapped = CarryMount.Follow(carry, Players[1].Pos, 0.1, 0.05)
quantity('C 甩开后钳回坐标', fmt(snapped.Position))
check('C 超出容差整段钳回挂点并计数',
    snapped.Snapped == true and carry.Stats.Snaps == 1
    and samePoint(snapped.Position, CarryMount.MountPoint(carry.Host, carry.Offset, carry.Yaw)))
local timedOut = CarryMount.Step(carry, Carry.MaxCarrySec, 0.05)
quantity('C 超时落点', fmt(timedOut.DropPoint or {}))
check('C 超时自动释放（落点有限、离地 DropHeight）',
    timedOut.Released == true and timedOut.Reason == 'timeout'
    and finitePoint(timedOut.DropPoint)
    and math.abs(timedOut.DropPoint.y - (carry.GroundY + Carry.DropHeight)) < 1e-9)
check('C 重复释放是空操作', CarryMount.Release(carry, Carry.MaxCarrySec + 1, 'again').Reason == 'notCarrying')

-- 第二个身份：同一个宿主的下一次叼人
local carry2 = CarryMount.New(Carry, Host, Yaw, 0)
carry2.GroundY = Host.y
Players[2].Pos = { x = Host.x + 1, y = Host.y, z = Host.z }
local grabbed2 = CarryMount.Attach(carry2, Players[2].Pos, 100)
check('C 同一宿主可叼起第二个身份 1002', grabbed2.Ok == true and carry2.Target ~= nil)
local nanTarget = CarryMount.Follow(carry2, { x = 0 / 0, y = Host.y, z = 0 }, 100.5, 0.05)
quantity('C 目标坏值时的落点', fmt(nanTarget.Position or {}))
check('C 目标坐标坏值立即释放且落点有限（不把 NaN 写回玩家）',
    nanTarget.Released == true and nanTarget.Reason == 'nan' and finitePoint(nanTarget.Position))

-- =====================================================================================
-- D 分阶段首领：阶段切换序列、一帧跨两阈值、失目标与死亡打断
-- =====================================================================================
print('== D 分阶段首领')
local Boss = GameCfg.Ability.BossPhase
local boss = BossPhase.New(Boss, 0, { x = 100, y = 2, z = 50 })
local jumped = BossPhase.Update(boss, 0.05, 0.05, {
    Health = 1000, MaxHealth = 10000, Alive = true,
    Target = Players[1].Pos, Pos = { x = 100, y = 2, z = 50 },
})
quantity('D 一帧跨两阈值', string.format('from=%s to=%s skipped=[%s] percent=%.1f',
    tostring(jumped.From), tostring(jumped.To), table.concat(jumped.Skipped or {}, ','), jumped.Percent))
check('D 一帧跨两阈值只进最终合法阶段',
    jumped.PhaseChanged == true and jumped.From == 'normal' and jumped.To == 'enraged'
    and #jumped.Skipped == 1 and jumped.Skipped[1] == 'water' and boss.Stats.Skipped == 1)
local healed = BossPhase.Update(boss, 1, 0.95, {
    Health = 9000, MaxHealth = 10000, Alive = true, Target = Players[1].Pos,
})
check('D 阶段只升级不倒退（回血不退回）',
    healed.PhaseChanged == nil and healed.Phase == 'enraged' and boss.Percent == 90)
for index, entry in ipairs(boss.Log) do
    print(string.format('K D 切换序列[%d] t=%.2f %s -> %s percent=%.1f skipped=[%s]',
        index, entry.At, tostring(entry.From), tostring(entry.To), entry.Percent or -1,
        table.concat(entry.Skipped or {}, ',')))
end

-- 吐息起手：真配置里爪击/甩尾先到期，这里用只留吐息的裁剪配置隔离起手路径
local breathOnly = {
    Thresholds = {},
    AttackSets = { normal = { 'breath' } },
    Attacks = { breath = { IntervalSec = 10, Range = 10, OneShot = true, WindupSec = 1.5 } },
}
local inRange = { x = 104, y = 2, z = 50 }   -- 身份 1001：距首领 4 米，吐息射程 10 米内
local outRange = { x = 130, y = 2, z = 50 }  -- 身份 1002：距首领 30 米，射程外

local w = BossPhase.New(breathOnly, 0, { x = 100, y = 2, z = 50 })
BossPhase.Update(w, 10, 10, { Health = 25000, MaxHealth = 25000, Alive = true, Target = inRange })
check('D 到期吐息先起手再落地（不是瞬发）', BossPhase.Winding(w) == true)
local interrupted = BossPhase.Update(w, 10.1, 0.1, {
    Health = 25000, MaxHealth = 25000, Alive = true, Target = nil,
})
check('D 途中失目标立即撤销起手并重新计时',
    interrupted.Interrupted == true and interrupted.Reason == 'lostTarget'
    and BossPhase.Winding(w) == false and w.Stats.Interrupts == 1)
-- 目标回来后重新计时 10 秒 + 起手 1.5 秒才应落地：这里跑满 12 秒，检查中间没有补发
local landed, earlyAttacks = nil, 0
for step = 1, 240 do
    local at = 10.1 + step * 0.05
    local event = BossPhase.Update(w, at, 0.05, {
        Health = 25000, MaxHealth = 25000, Alive = true, Target = inRange })
    if event.Attack then
        landed = event.Attack
        if event.Attack.At < 20.1 then earlyAttacks = earlyAttacks + 1 end
    end
end
check('D 目标回来不会立刻补发秒杀（重新计时窗口内无落地）', earlyAttacks == 0)
quantity('D 重新计时后落地', landed and string.format('t=%.2f name=%s lethal=%s',
    landed.At, landed.Name, tostring(landed.Lethal)) or 'nil')
check('D 重新计时满后吐息正常落地（原子吐息为秒杀）',
    landed ~= nil and landed.Name == 'breath' and landed.Lethal == true)

-- 射程门：两个身份一近一远，超过 10 米不出招
local range = BossPhase.New(breathOnly, 0, { x = 100, y = 2, z = 50 })
BossPhase.Update(range, 10, 10, { Health = 25000, MaxHealth = 25000, Alive = true, Target = outRange })
for step = 1, 10 do
    BossPhase.Update(range, 10 + step * 0.2, 0.2, {
        Health = 25000, MaxHealth = 25000, Alive = true, Target = outRange })
end
check('D 正前 10 米外（身份 1002）不出手', range.Stats.Attacks == 0 and BossPhase.Winding(range) == false)

-- 死亡打断：起手中死亡 → 撤销且之后不再有攻击
local dead = BossPhase.New(breathOnly, 0, { x = 100, y = 2, z = 50 })
BossPhase.Update(dead, 10, 10, { Health = 25000, MaxHealth = 25000, Alive = true, Target = inRange })
local died = BossPhase.Update(dead, 10.1, 0.1, { Health = 0, MaxHealth = 25000, Alive = false })
check('D 起手中死亡被识别为打断',
    died.Interrupted == true and died.Reason == 'death' and BossPhase.Winding(dead) == false)
for step = 1, 40 do
    BossPhase.Update(dead, 10.1 + step * 0.2, 0.2, { Health = 0, MaxHealth = 25000, Alive = false })
end
quantity('D 死亡后攻击序列', #dead.AttackLog .. ' 条（预期 0）')
check('D 死亡后不再有任何攻击落地且打断只计一次',
    #dead.AttackLog == 0 and dead.Stats.Interrupts == 1 and dead.Stats.Attacks == 0)

-- =====================================================================================
print(string.format('== 探针结果：%d 通过 / %d 失败', Pass, Fail))
print('== 说明：本探针只证明逻辑与数据契约自洽，真机试玩（碰撞/相机/挂点穿模/动画）待编辑器窗口验证')
os.exit(Fail == 0 and 0 or 1)
