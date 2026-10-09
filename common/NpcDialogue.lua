-- 七区钓鱼佬说明：物品名、兑换产物、烧烤点与航线从当前配置读取，避免文案另维护一套信物链。
local GameCfg = require('common.GameCfg')
local Dialogue = {}

local function zoneName(id)
    for _, zone in ipairs(GameCfg.Zones) do if zone.Id == id then return zone.Name end end
    return tostring(id)
end

local function itemName(id)
    local achievement = type(id) == 'string' and id:match('^achievement%.(.+)$')
    if achievement then return GameCfg.Achievements[achievement].Name end
    local item = GameCfg.Items.Definitions[id]
    return item and item.Name or tostring(id)
end

function Dialogue.Lines(zoneId)
    local zone, npc, chain
    for _, value in ipairs(GameCfg.Zones) do if value.Id == zoneId then zone = value end end
    for _, value in ipairs(GameCfg.Interact.Fishermen) do if value.ZoneId == zoneId then npc = value end end
    for _, value in ipairs(GameCfg.Content.Exchanges) do if value.ZoneId == zoneId then chain = value end end
    if not zone or not npc or not chain then return nil end
    local lines = {
        zone.Name .. '的钓鱼佬：我什么都吃！选中鱼获或鱼饵再喂食，就能换金币。',
        '未烤的' .. itemName(chain.EliteToken) .. '换' .. itemName(npc.Exchange[chain.EliteToken])
            .. '；首领饵在任何水域都能钓出对应首领。',
        '未烤的' .. itemName(chain.BossToken) .. '换' .. itemName(npc.Exchange[chain.BossToken]) .. '。',
    }
    if zoneId == 'volcanoIsland' then
        lines[#lines + 1] = '交付' .. itemName(chain.BossToken)
            .. '后达成通关成就；成就不占格，已达成后不会再次消耗信物。'
    else
        lines[#lines + 1] = '交船票后倒计时出发，船边其他玩家可搭便船；返程按人支付金币。'
    end
    for _, route in ipairs(GameCfg.Ferry.Routes) do
        if route.FromZoneId == zoneId then
            lines[#lines + 1] = '交' .. itemName(route.Outbound.Ticket) .. '后'
                .. route.Outbound.CountdownSec .. '秒前往' .. zoneName(route.ToZoneId)
                .. '；从那里返程每人' .. route.Return.Price .. '金币。'
        elseif route.ToZoneId == zoneId then
            lines[#lines + 1] = '从本区返回' .. zoneName(route.FromZoneId)
                .. '，每人支付' .. route.Return.Price .. '金币后立即出发。'
        end
    end
    if zone.Scene.GrillName then
        lines[#lines + 1] = '本区有烧烤点。烤制后按取出时的程度变现或恢复；烤糊会损毁并伤人。'
    else
        lines[#lines + 1] = '本区没有烧烤点，蟹湖起可以烤鱼。'
    end
    lines[#lines + 1] = '烤制后的信物只能变现，不能兑换；烤鱼不能抽奖。'
    lines[#lines + 1] = '抽奖只收未烤的极品鱼获和信物：两同图案返金币，三同图案得大奖。'
    lines[#lines + 1] = '满格交信物先用本次释放的格位放产物；抽奖时放不下的占格大奖会落地。'
    lines[#lines + 1] = '满格取不出烤鱼时留在烧烤点，先腾出格位再取。'
    return lines
end

function Dialogue.Describe(zoneId)
    local lines = Dialogue.Lines(zoneId)
    return lines and table.concat(lines, '\n') or nil
end

return Dialogue
