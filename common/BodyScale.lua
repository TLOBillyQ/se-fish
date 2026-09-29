-- #132 T11 高风险能力原型 · 能力 A：三倍体型的纯逻辑与派生量契约。
-- 数值来源：GameSpec §2（体型 1 倍起、变大药水每个 +0.2 倍、上限 3 倍；血量 300 起、每个 +20%、上限 900）。
-- 本模块不碰引擎：只把「药水数 → 倍率/血量」和「倍率 → 胶囊高/相机距离/交互距离/挂点位移」算清楚，
-- 供 server/AbilityAPI.lua 的 SetScale 接缝与挂点装配消费；服务端单位与真机表现不在本模块职责内。
-- 失败方式与覆盖见 tests/gameplay/ability_proto_test.lua 顶部的清单。
local GameCfg = require('common.GameCfg')

local M = {}

local function cfg()
    return GameCfg.Ability.BodyScale
end

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

-- 药水数量净化：只接受非负整数；其余（负数、小数、非数、NaN、inf）一律按 0 个处理，
-- 不让「用了几个药水」这种外部输入把体型带偏。
local function potionCount(potions, maxPotions)
    if isBadNumber(potions) or potions < 0 then return 0 end
    local whole = math.floor(potions)
    if whole > maxPotions then return maxPotions end
    return whole
end

---药水数 → 目标体型与血量上限
---@param potions any 变大药水个数（非法值按 0 处理）
---@return table { Scale, Health, Potions, Capped, MaxScale, MaxHealth }
function M.Plan(potions)
    local c = cfg()
    -- 上限由配置推导而不是写死：MaxPotions 与 (Max-Base)/Step 取小，改配置时两条不会各自漂移
    local stepsByScale = math.floor((c.Max - c.Base) / c.Step + 1e-9)
    local maxPotions = math.min(c.MaxPotions, stepsByScale)
    local count = potionCount(potions, maxPotions)
    local scale = c.Base + c.Step * count
    if scale > c.Max then scale = c.Max end
    local health = c.HealthBase + c.HealthBase * c.HealthStepPercent / 100 * count
    if health > c.HealthMax then health = c.HealthMax end
    return {
        Scale = scale, Health = health, Potions = count,
        Capped = count >= maxPotions,
        MaxScale = c.Max, MaxHealth = c.HealthMax,
    }
end

---倍率净化：NaN / inf / ≤0 / 非数回落 1 倍，超上限夹到上限
---@param scale any
---@return number
function M.Sanitize(scale)
    local c = cfg()
    if isBadNumber(scale) or scale <= 0 then return c.Base end
    if scale < c.Base then return c.Base end
    if scale > c.Max then return c.Max end
    return scale
end

local function positiveOrZero(v)
    if isBadNumber(v) or v < 0 then return 0 end
    return v
end

---体型派生量：三倍体型下的胶囊高、相机距离、交互距离与挂点位移。
---挂点必须一起放大，否则挂件会陷进放大的身体（真机「挂点不穿出」的前置条件，见 issue #132）。
---@param scale number 净化前的倍率
---@param base? table { CapsuleHeight, CameraDistance, InteractRange, SocketOffset={x,y,z} }
---@return table { Scale, CapsuleHeight, CameraDistance, InteractRange, SocketOffset? }
function M.Derive(scale, base)
    local c = cfg()
    base = base or c
    local factor = M.Sanitize(scale)
    local derived = {
        Scale = factor,
        CapsuleHeight = positiveOrZero(base.CapsuleHeight) * factor,
        CameraDistance = positiveOrZero(base.CameraDistance) * factor,
        InteractRange = positiveOrZero(base.InteractRange) * factor,
    }
    local offset = base.SocketOffset
    if type(offset) == 'table' then
        derived.SocketOffset = {
            x = positiveOrZero(offset.x) * factor,
            y = positiveOrZero(offset.y) * factor,
            z = positiveOrZero(offset.z) * factor,
        }
    end
    return derived
end

return M
