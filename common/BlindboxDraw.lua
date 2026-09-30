-- 盲盒抽样纯逻辑（#147 T26，GameSpec §15 与地图盲盒表）：单抽 10 金豆、十连 90 金豆的收费归
-- 平台适配层（server/Mgr/MgrPlatform.lua），这里只抽样与维护「连续未中大奖」计数：
-- 42 项按原表权重（总和 1000）抽样，个体倍率固定 1；连续 49 抽未出大奖，第 50 抽在
-- 极品美人鱼 / 极品蛇颈龙中等概率保底；任意抽出大奖（自然或保底）立即清零计数。
-- 只抽样与计数，不碰库存/存档/金豆；随机数经 rng(n)（返回 1..n 均匀整数）注入，默认 math.random。
-- 十连逐抽结算（DrawMany）：中途出大奖立即重置，余下的抽用新计数；任一抽 rng 越界整批返回 nil，
-- 调用方据此不结算（不落账、不扣费）。
local GameCfg = require('common.GameCfg')

local BlindboxDraw = {}

local function rngOf(rng)
    return type(rng) == 'function' and rng or math.random
end

local function entries()
    return GameCfg.Blindbox.Entries
end

local function pityCfg()
    return GameCfg.Blindbox.Pity
end

local function totalWeight()
    local total = 0
    for _, entry in ipairs(entries()) do total = total + entry.weight end
    return total
end

local function validRoll(roll, limit)
    return type(roll) == 'number' and roll == math.floor(roll) and roll >= 1 and roll <= limit
end

-- 权重抽取：roll 取 1..总权重均匀整数，按累计权重划区间；越界/非数返回 nil（配置或注入事故）
local function rollWeighted(source)
    local list, total = entries(), totalWeight()
    local roll = source(total)
    if not validRoll(roll, total) then return nil end
    local cursor = 0
    for index, entry in ipairs(list) do
        cursor = cursor + entry.weight
        if roll <= cursor then return index, entry end
    end
    return nil
end

-- 保底抽取：在 Pity.prizeItemKeys 中等概率取一件（equalChance 原表结论）；越界返回 nil
local function rollGuaranteed(source)
    local keys = pityCfg().prizeItemKeys
    local pick = source(#keys)
    if not validRoll(pick, #keys) then return nil end
    local wanted = keys[pick]
    for index, entry in ipairs(entries()) do
        if entry.itemKey == wanted then return index, entry end
    end
    return nil
end

-- 单抽：pity 是抽前连续未中大奖次数；达到 Pity.afterMisses（49）的本抽强制保底。
-- 返回 draw 表或 nil（rng 事故）：{ index, itemKey, itemName, basePrice, multiplier = 1,
--   jackpot, guaranteed, pityBefore, pityAfter }。
function BlindboxDraw.Draw(pity, rng)
    if type(pity) ~= 'number' or pity ~= math.floor(pity) or pity < 0 then return nil end
    local source = rngOf(rng)
    local guaranteed = pity >= pityCfg().afterMisses
    local index, entry
    if guaranteed then index, entry = rollGuaranteed(source)
    else index, entry = rollWeighted(source) end
    if not index then return nil end
    local jackpot = entry.jackpot == true
    return {
        index = index,
        itemKey = entry.itemKey,
        itemName = entry.itemName,
        basePrice = entry.basePrice,
        multiplier = 1, -- 盲盒个体倍率固定 1（GameSpec §15）
        jackpot = jackpot,
        guaranteed = guaranteed,
        pityBefore = pity,
        pityAfter = jackpot and 0 or pity + 1,
    }
end

-- 十连逐抽（也兼容单抽）：逐抽结算 pity，中途出大奖立即重置；返回 draws 数组与最终 pity。
-- count 合法区间 1..Pity 语义外的 10（十连）；任一抽失败整批 nil。
function BlindboxDraw.DrawMany(count, pity, rng)
    if type(count) ~= 'number' or count ~= math.floor(count) or count < 1 or count > 10 then
        return nil
    end
    if type(pity) ~= 'number' or pity ~= math.floor(pity) or pity < 0 then return nil end
    local source = rngOf(rng)
    local draws = {}
    local current = pity
    for index = 1, count do
        local draw = BlindboxDraw.Draw(current, source)
        if not draw then return nil end
        draws[index] = draw
        current = draw.pityAfter
    end
    return draws, current
end

return BlindboxDraw
