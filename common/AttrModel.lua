-- 五类属性的存档/会话态投影；只产分量，不持有第二份成长权威值。
local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')
local M = {}
local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end
local function count(value, maximum)
    return finite(value) and math.min(maximum, math.max(0, math.floor(value))) or 0
end
local function components(base, extra, ratio)
    return { Base = base, BaseExtra = extra or 0, Ratio = ratio or 0, Bonus = 0 }
end
function M.Plan(input)
    input = input or {}
    local body = BodyScale.Plan(input.bodyPotions)
    local speedCfg = GameCfg.Ability.SpeedPotion
    local growth = math.min(speedCfg.MaxFactor, 1 + speedCfg.StepPercent / 100 * count(input.speedPotions, speedCfg.MaxPotions))
    local base = finite(input.baseSpeed) and input.baseSpeed > 0 and input.baseSpeed or GameCfg.Ability.MoveSpeed.Base
    local multiplier = finite(input.moveMultiplier) and math.max(0, math.min(1, input.moveMultiplier)) or 1
    local hunger = finite(input.hunger) and math.max(0, math.min(GameCfg.Vitals.MaxHunger, math.floor(input.hunger))) or GameCfg.Vitals.MaxHunger
    return { Body = body, Attributes = {
        PlayerMaxHealth = components(GameCfg.Ability.BodyScale.HealthBase, body.Health - GameCfg.Ability.BodyScale.HealthBase),
        PlayerWalkSpeed = components(base, 0, growth * multiplier - 1),
        PlayerBodyScale = components(GameCfg.Ability.BodyScale.Base, body.Scale - GameCfg.Ability.BodyScale.Base),
        PlayerHunger = components(hunger),
    } }
end
function M.WeaponComponents(kind, level)
    local spec = GameCfg.Shop.UpgradeKinds[kind]
    local maximum = spec and spec.MaxLevel or 0
    local scale = GameCfg.Shop.DamageScale(kind, count(level, maximum)) or 1
    return components(1, 0, scale - 1)
end
return M
