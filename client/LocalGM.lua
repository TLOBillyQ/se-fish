-- GM 客户端入口（#47，#28 规格）：控制台调用 _G.GM.Coin(amount, target) / _G.GM.Item(itemId, count, target)，
-- _G.GM.SetHealth(value, target) / _G.GM.SetHunger(value, target)（#53），
-- 只发 GMAction 请求；是否放行由服务端按 GameCfg.Debug.Enabled 裁决（默认关闭），target 缺省为自己。
local REUtil = require('common.REUtil')

local LocalGM = {}

local function notice(msg)
    print('[LocalGM]', msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

function LocalGM:Send(payload)
    REUtil:GetRE('GMAction'):FireServer(payload)
end

function LocalGM:Start()
    _G.GM = {
        Coin = function(amount, target) self:Send({ action = 'Coin', amount = amount, target = target }) end,
        Item = function(itemId, count, target)
            self:Send({ action = 'Item', itemId = itemId, count = count or 1, target = target })
        end,
        SetHealth = function(value, target) self:Send({ action = 'SetHealth', value = value, target = target }) end,
        SetHunger = function(value, target) self:Send({ action = 'SetHunger', value = value, target = target }) end,
    }
    REUtil:GetRE('GMResult').OnClientEvent:Connect(function(result)
        if type(result) ~= 'table' then return end
        notice('GM ' .. tostring(result.action) .. (result.ok and ' 成功' or ' 被拒')
            .. ' 目标 ' .. tostring(result.target))
    end)
end

return LocalGM
