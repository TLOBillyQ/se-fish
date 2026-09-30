-- #140 T19 特殊道具（风神之翼 item169 / 哥斯拉变身 item170）：纯逻辑。
-- 数值来源：物品表!R170「使用时可以飞行」、物品表!R171「更换皮肤，可以使用原子吐息」、
-- issue #140 票面（长按升空 / 松开缓降 / 20 米上限；吐息 3 秒直线 30 米、每目标总计 1000、
-- 冷却 20 秒）、GameSpec §8.2「不能借飞行跨区」与 #125 场景合同（Boundary.MaxFlightHeight=20）。
-- 标「暂取」的值票面未给，真机表现待试玩（见 issue #140 真机遗留）。
--
-- 本模块只做确定性判定，不碰引擎：
--   * Desired：选中槽物品 → 期望生效效果（选中即生效，GameSpec §3.2 两步规则的例外）；
--   * 飞行：垂直步进（长按升 / 松开缓降 / 上下限钳制）与水平钳制，边界来自
--     FlightPath.BoundsOf 的场景合同；非法 dt 不污染状态，超步长截断；
--   * 吐息：伤害计划按 tick 整数切分（总和恰为票面 TotalDamage）；每次施法一本台账，
--     每目标按 tick 段结算，同段重复 / 超段一律拒绝（无重复段、不超 1000）；
--   * 冷却：只看绝对时刻（lastCastAt + CooldownSec 与 now 比较），与变身状态解耦——
--     切换 / 丢弃 / 死亡清不掉冷却。
-- 首领哥斯拉（BossPhase.Attacks.breath，10 米 OneShot 秒杀）与玩家吐息配置严格分开，
-- 本模块只读 GameCfg.Ability.SpecialItem，绝不读 BossPhase。
local GameCfg = require('common.GameCfg')

local M = {}

local function cfg()
    return GameCfg.Ability.SpecialItem
end

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

---选中槽物品 → 期望生效的特殊效果：'wings' | 'godzilla' | nil。
---@param itemId? string
---@return string? effect
function M.Desired(itemId)
    if type(itemId) ~= 'string' then return nil end
    return cfg().Items[itemId]
end

---飞行垂直步进：holding 长按按 ClimbSpeed 升空、松开按 DescendSpeed 缓降；
---钳制在 [GroundY, CeilingY]（CeilingY = GroundY + MaxFlightHeight，20 米上限）；
---回到地面即落地（Airborne=false）。非法 dt（NaN/inf/负）整帧丢弃，超 MaxStepSec 截断。
---@param wingsCfg table GameCfg.Ability.SpecialItem.Wings
---@param state table { Y = number, Airborne = bool }
---@param holding bool 长按中
---@param dt number 距上一帧的秒数
---@param bounds table FlightPath.BoundsOf 的结果（GroundY / CeilingY）
---@return number y, bool airborne
function M.StepFlightY(wingsCfg, state, holding, dt, bounds)
    local y = state.Y
    local airborne = state.Airborne == true
    if isBadNumber(dt) or dt < 0 then return y, airborne end
    if dt > wingsCfg.MaxStepSec then dt = wingsCfg.MaxStepSec end
    if holding then
        y = y + wingsCfg.ClimbSpeed * dt
        airborne = true
    else
        y = y - wingsCfg.DescendSpeed * dt
    end
    if y > bounds.CeilingY then y = bounds.CeilingY end
    if y <= bounds.GroundY then
        y = bounds.GroundY
        airborne = false
    end
    return y, airborne
end

---水平钳制：把 x/z 夹回本区围栏（不能借飞行跨区，GameSpec §8.2）。
---@param bounds table FlightPath.BoundsOf 的结果
---@param x number
---@param z number
---@return number x, number z, bool clamped
function M.ClampXZ(bounds, x, z)
    local clamped = false
    if isBadNumber(x) then x = (bounds.MinX + bounds.MaxX) / 2 clamped = true end
    if isBadNumber(z) then z = (bounds.MinZ + bounds.MaxZ) / 2 clamped = true end
    if x < bounds.MinX then x = bounds.MinX clamped = true end
    if x > bounds.MaxX then x = bounds.MaxX clamped = true end
    if z < bounds.MinZ then z = bounds.MinZ clamped = true end
    if z > bounds.MaxZ then z = bounds.MaxZ clamped = true end
    return x, z, clamped
end

---吐息 tick 伤害计划：把 TotalDamage 整数切分到 DurationSec/TickSec 段，
---每段 floor 取整、余数补在最后一段，总和恰为 TotalDamage。
---@param totalDamage number 票面总伤害（1000）
---@param durationSec number 吐息持续秒数（3）
---@param tickSec number 结算间隔（0.25）
---@return number[] plan 每段伤害（正整数，和恰为 totalDamage）
function M.TickDamages(totalDamage, durationSec, tickSec)
    local count = math.floor(durationSec / tickSec + 1e-9)
    if count < 1 then count = 1 end
    local base = math.floor(totalDamage / count)
    local plan = {}
    local sum = 0
    for tick = 1, count do
        plan[tick] = base
        sum = sum + base
    end
    plan[count] = plan[count] + (totalDamage - sum)
    return plan
end

---每次施法一本台账：按 tick 段结算，每目标同段只结一次（无重复段）、
---计划外的段不给伤害（不超票面总伤害）。
---@param breathCfg table GameCfg.Ability.SpecialItem.Godzilla.Breath
---@return table ledger { Plan = number[], Targets = { [key] = { Hits = { [tick]=true }, Total = n } } }
function M.NewBreathLedger(breathCfg)
    return {
        Plan = M.TickDamages(breathCfg.TotalDamage, breathCfg.DurationSec, breathCfg.TickSec),
        Targets = {},
    }
end

---结算一个目标在某个 tick 段的吐息伤害；该段已结过或超出计划返回 nil。
---@param ledger table NewBreathLedger 的结果
---@param targetKey string 目标身份（玩家 'player:<UserId>' / 鱼 'fish:<Id>'）
---@param tick number 段序号（1..#Plan）
---@return number? amount
function M.BreathHit(ledger, targetKey, tick)
    if type(targetKey) ~= 'string' or type(tick) ~= 'number' then return nil end
    local amount = ledger.Plan[tick]
    if not amount then return nil end
    local entry = ledger.Targets[targetKey]
    if not entry then
        entry = { Hits = {}, Total = 0 }
        ledger.Targets[targetKey] = entry
    end
    if entry.Hits[tick] then return nil end
    entry.Hits[tick] = true
    entry.Total = entry.Total + amount
    return amount
end

---冷却剩余秒数：lastCastAt + cooldownSec 与 now 的差，<= 0 表示就绪；
---nil 记录视为就绪；时钟回拨按未就绪处理（不出现负冷却）。
---冷却只依赖绝对时刻，与变身 / 选中状态解耦（切换清不掉冷却）。
---@param lastCastAt? number 上次施法的绝对时刻（World:GetServerTime()）
---@param now number
---@param cooldownSec number
---@return number remaining
function M.CooldownRemaining(lastCastAt, now, cooldownSec)
    if isBadNumber(lastCastAt) or isBadNumber(now) then return 0 end
    local remaining = lastCastAt + cooldownSec - now
    if remaining < 0 then return 0 end
    return remaining
end

return M
