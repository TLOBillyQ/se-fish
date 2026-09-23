-- GM 发放（#47，#28 规格）：服务端单点裁决，只在 GameCfg.Debug.Enabled 打开时接受请求。
-- 客户端发 GMAction{action, target, ...}；target 缺省是发起者自己，给数字 UserId 则发给在线的那名玩家，
-- 查不到就失败、不落到别人身上。加 / 扣币走 PlayerData:AddCoin / SpendCoin 这一唯一入口（扣不成负数），
-- 发物品走 PlayerData:GrantItem 按物品表的 Container 路由（鱼竿进道具栏、蚯蚓进鱼饵库存）。
local GameCfg = require('common.GameCfg')

local Mgr = {}

local MaxItemCount = 99

local function isInt(n)
    return type(n) == 'number' and n == math.floor(n)
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('GMResult'):FireClient(player, payload)
end

function Mgr:ResolveTarget(player, target)
    if target == nil then return player end
    if not isInt(target) then return nil end
    for _, other in ipairs(game:GetService('Players'):GetPlayers()) do
        if other.UserId == target then return other end
    end
end

function Mgr:Coin(data, payload)
    local amount = payload.amount
    if not isInt(amount) or amount == 0 then return false end
    if amount > 0 then return data:AddCoin(amount, nil, 'gm') end
    return data:SpendCoin(-amount, nil, 'gm')
end

function Mgr:Item(data, payload)
    local count = payload.count
    if not GameCfg.Items.Definitions[payload.itemId] or not isInt(count) or count < 1 or count > MaxItemCount then
        return false
    end
    return (data:GrantItem(payload.itemId, count))
end

local Actions = { Coin = 'Coin', Item = 'Item' }

-- 处理一次 GM 请求；发放成功返回 true
function Mgr:Handle(player, payload)
    if not (GameCfg.Debug and GameCfg.Debug.Enabled) then
        print('[MgrGM] 调试开关关闭，拒绝', player and player.UserId)
        return false
    end
    if type(payload) ~= 'table' then return false end
    local method = Actions[payload.action]
    local target = method and self:ResolveTarget(player, payload.target)
    local data = target and self.PlayerData and self.PlayerData:GetDataInst(target)
    local ok = data and self[method](self, data, payload) or false
    print('[MgrGM]', ok and '发放' or '拒绝', player and player.UserId, '->', target and target.UserId,
        tostring(payload.action), tostring(payload.amount or payload.itemId), tostring(payload.count or ''))
    if ok then self.PlayerData:SendItemBar(target) end
    self:Reply(player, { ok = ok, action = payload.action, target = target and target.UserId })
    return ok
end

function Mgr:Start()
    _G.REUtil:GetRE('GMAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'GMAction', GameCfg.Items.ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
end

return Mgr
