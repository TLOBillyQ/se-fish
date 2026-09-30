-- 抽奖机抽样纯逻辑（#138 T17，GameSpec §14）：三轴独立按同一权重抽样；三同优先仅得对应大奖，
-- 恰好两同得投入价值 × 对应倍数的金币，无两同无奖励。武器组三同在组内五件中均匀随机一件
-- （策划案「5 种全随机获得 1 种」）；大奖实例行为归 #139/#140，这里只决定发放哪一件。
-- 只抽样与判奖，不碰库存/金币/存档；随机数经 rng(n)（返回 1..n 均匀整数）注入，默认 math.random。
local GameCfg = require('common.GameCfg')

local LotteryDraw = {}

local function rngOf(rng)
    return type(rng) == 'function' and rng or math.random
end

local function patterns()
    return GameCfg.Lottery.Patterns
end

-- 单轴：roll 取 1..总权重均匀整数，按累计权重划区间；rng 越界/非数返回 nil（配置或注入事故）
function LotteryDraw.RollAxis(rng)
    local list = patterns()
    local total = 0
    for _, pattern in ipairs(list) do total = total + pattern.weight end
    local roll = rngOf(rng)(total)
    if type(roll) ~= 'number' or roll ~= math.floor(roll) or roll < 1 or roll > total then return nil end
    local cursor = 0
    for _, pattern in ipairs(list) do
        cursor = cursor + pattern.weight
        if roll <= cursor then return pattern.number end
    end
    return nil
end

-- 三轴独立抽样：返回 { 左, 右, 中 } 三个图案编号；任一轴抽样失败返回 nil
function LotteryDraw.RollAxes(rng)
    local source = rngOf(rng)
    local axes = {}
    for axis = 1, 3 do
        local number = LotteryDraw.RollAxis(source)
        if not number then return nil end
        axes[axis] = number
    end
    return axes
end

-- 判奖：三同优先（GameCfg.Lottery.TripleRule='tripleFirst'），恰两同（PairRule='exactlyTwo'）取相同一对的图案
function LotteryDraw.Evaluate(axes)
    if type(axes) ~= 'table' then return { outcome = 'none' } end
    local a, b, c = axes[1], axes[2], axes[3]
    if a == nil or b == nil or c == nil then return { outcome = 'none' } end
    if a == b and b == c then return { outcome = 'triple', pattern = a } end
    if a == b then return { outcome = 'pair', pattern = a } end
    if b == c then return { outcome = 'pair', pattern = b } end
    if a == c then return { outcome = 'pair', pattern = a } end
    return { outcome = 'none' }
end

-- 武器组五选一：组内 itemKeys 均匀随机一件；非 weaponChoice 大奖返回 nil
function LotteryDraw.ChooseWeapon(pattern, rng)
    local reward = type(pattern) == 'table' and pattern.tripleReward
    if type(reward) ~= 'table' or reward.kind ~= 'weaponChoice' then return nil end
    local keys = reward.itemKeys
    if type(keys) ~= 'table' or #keys < 1 then return nil end
    local pick = rngOf(rng)(#keys)
    if type(pick) ~= 'number' or pick ~= math.floor(pick) or pick < 1 or pick > #keys then return nil end
    return keys[pick]
end

return LotteryDraw
