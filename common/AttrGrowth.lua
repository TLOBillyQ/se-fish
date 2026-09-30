-- #139 T18 大奖成长：属性成长的纯逻辑与唯一计算处。
-- 统一规格 §2：加速药水每个 +10% 基础移速、最多 20 个、封顶基础 3 倍；
-- 变大药水的血量上限委托 #132 的 BodyScale.Plan，不另起公式。
-- 「属性 = 基础 + 永久成长 + 临时虚弱」只在本模块算一次：MgrAbility:RefreshMoveSpeed 是唯一调用口，
-- 虚弱（MgrSurvival）、霜冻/麻痹（武器持续效果）都以开关形式传入，不在不同管理器反复乘。
-- 失败方式与覆盖见 tests/gameplay/attr_growth_test.lua 顶部的清单。
local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')

local M = {}

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

-- 与 BodyScale 同口径的药水数净化：非负整数，超上限夹到上限
local function potionCount(potions, maxPotions)
    if isBadNumber(potions) or potions < 0 then return 0 end
    local whole = math.floor(potions)
    if whole > maxPotions then return maxPotions end
    return whole
end

---加速药水数 → 移速倍率（1 + 10%×个数，封顶 MaxFactor）
---@param potions any 加速药水个数（非法值按 0 处理）
---@return number
function M.SpeedFactor(potions)
    local c = GameCfg.Ability.SpeedPotion
    local count = potionCount(potions, c.MaxPotions)
    local factor = 1 + c.StepPercent / 100 * count
    if factor > c.MaxFactor then factor = c.MaxFactor end
    return factor
end

---有效移速唯一计算：基础 × 加速成长 × 虚弱 0.5 × 霜冻 (1-30%)；麻痹直接为 0。
---@param base any 基础移速（非法值回落 GameCfg.Ability.MoveSpeed.Base）
---@param speedPotions any 加速药水个数
---@param mods? table { weak=bool, frost=bool, paralyzed=bool }
---@return number
function M.EffectiveSpeed(base, speedPotions, mods)
    if isBadNumber(base) or base <= 0 then base = GameCfg.Ability.MoveSpeed.Base end
    mods = mods or {}
    if mods.paralyzed then return 0 end
    local speed = base * M.SpeedFactor(speedPotions)
    if mods.weak then speed = speed * GameCfg.Survival.WeakSpeedScale end
    if mods.frost then
        speed = speed * (1 - GameCfg.Ability.StatusEffects.frost.SlowPercent / 100)
    end
    return speed
end

---血量上限：委托 BodyScale.Plan（变大药水数），两处不各算一遍
---@param bodyPotions any 变大药水个数
---@return number
function M.MaxHealth(bodyPotions)
    return BodyScale.Plan(bodyPotions).Health
end

return M
