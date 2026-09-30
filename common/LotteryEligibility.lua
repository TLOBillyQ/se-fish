-- 抽奖机投入资格（#134 可调用，#138 复用）：纯函数，只判「这一件能不能投」，不抽样、不扣物、不结算。
-- GameSpec §14：投入一件未烤制极品食物（极品鱼获或信物）；§13：烤鱼不可抽奖，烤过信物失去抽奖资格。
-- 条目取真实库存格位 { itemId, count, mult, saved } 或 GetItemBarSnapshot 的格位 { itemId, count, mult, cooked }：
--   * 烤制判定与 MgrInteract 同口径（见 GameCfg.Items.CookRate）：顶层 cooked 数值 > 0 为权威
--     （快照/读档/落物的烤制倍率，#137 起下降段取出可以 <1，仍算烤过）；
--   * 兼容旧布尔档 saved[GameCfg.Items.CookedFlag] == true（等价 CookRate 映射 1.5）；
--   * 序列化存档的 slot.k 是压缩存档协议，不是库存字段，这里不读。
-- 返回 true，或 false, reason：'malformed' | 'bad-item' | 'not-premium' | 'cooked'。
local GameCfg = require('common.GameCfg')

local LotteryEligibility = {}

LotteryEligibility.PremiumType = '极品食物'

-- 结构不合法返回 nil；否则返回是否烤过
local function cookedState(entry)
    local cooked = entry.cooked
    -- #137：烤制倍率是 (0, 1.5] 的数值，下降段取出可以 <1，仍算烤过
    if cooked ~= nil and (type(cooked) ~= 'number' or cooked ~= cooked or cooked <= 0 or cooked >= math.huge) then
        return nil
    end
    local saved = entry.saved
    if saved ~= nil and type(saved) ~= 'table' then return nil end
    local flag = saved and saved[GameCfg.Items.CookedFlag]
    if flag ~= nil and type(flag) ~= 'boolean' then return nil end
    return cooked ~= nil or flag == true
end

function LotteryEligibility.Check(entry)
    if type(entry) ~= 'table' or type(entry.itemId) ~= 'string' then return false, 'malformed' end
    -- 「投入一件」：库存格位恒为单件，缺省按一件
    if entry.count ~= nil and entry.count ~= 1 then return false, 'malformed' end
    local mult = entry.mult
    if mult ~= nil and (type(mult) ~= 'number' or mult ~= mult or mult < 1 or mult > 2) then
        return false, 'malformed'
    end
    local cooked = cookedState(entry)
    if cooked == nil then return false, 'malformed' end
    local definition = GameCfg.Items.Definitions[entry.itemId]
    if not definition then return false, 'bad-item' end
    if definition.Type ~= LotteryEligibility.PremiumType then return false, 'not-premium' end
    if cooked then return false, 'cooked' end
    return true
end

return LotteryEligibility
