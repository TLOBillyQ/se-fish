-- 钓场商店（#48，#28 规格）：单一通道 ShopAction{action='Buy', itemId, seq}，客户端只发意图。
-- 服务端复验：动作与整数 seq → 数据就绪 → seq 递增（同一请求重放 / 旧序号不结算，限频不代替去重）
-- → 在钓场老板范围内（复用 MgrInteract:InRange）→ 商品在白名单且商店等级够 → 目标容器放得下
-- → 扣币（PlayerData:SpendCoin，价格只取配置）与发货（PlayerData:GrantItem 按 Container 分流）同一次落地。
-- 任一条不过就不扣钱、不发货，把原因（item / range / full / coin）回给客户端做提示。
local GameCfg = require('common.GameCfg')

local Mgr = { LastSeq = {} }

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('ShopResult'):FireClient(player, payload)
end

-- 当前商店等级下上架的商品；不在白名单返回 nil
function Mgr:FindGoods(itemId)
    local shop = GameCfg.Shop
    for _, goods in ipairs(shop.Goods) do
        if goods.ItemId == itemId and goods.MinShopLevel <= shop.Level then return goods end
    end
end

function Mgr:Fail(player, itemId, reason)
    print('[MgrShop] 购买失败', player.UserId, tostring(itemId), reason)
    self:Reply(player, { ok = false, itemId = itemId, reason = reason })
    return false
end

function Mgr:Buy(player, data, itemId)
    local goods = self:FindGoods(itemId)
    if not goods then return self:Fail(player, itemId, 'item') end
    if not self.Interact:InRange(player, GameCfg.Shop) then return self:Fail(player, itemId, 'range') end
    local ok, reason = data:CanGrant(itemId, 1)
    if not ok then return self:Fail(player, itemId, reason == 'full' and 'full' or 'item') end
    if not data:SpendCoin(goods.Price, function() data:GrantItem(itemId, 1) end, 'shop:' .. itemId) then
        return self:Fail(player, itemId, 'coin')
    end
    print('[MgrShop] 购买', player.UserId, itemId, '-' .. tostring(goods.Price), 'FishCoin=' .. tostring(data.Data.FishCoin))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, itemId = itemId, price = goods.Price })
    return true
end

-- 处理一次商店请求；结算成功返回 true
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or payload.action ~= 'Buy' then return false end
    local seq = payload.seq
    if type(seq) ~= 'number' or seq ~= math.floor(seq) then return false end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return false end
    self.LastSeq[player.UserId] = seq
    return self:Buy(player, data, payload.itemId)
end

function Mgr:Start()
    _G.REUtil:GetRE('ShopAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'ShopAction', GameCfg.Items.ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
end

function Mgr:OnPlayerRemoving(player)
    self.LastSeq[player.UserId] = nil
end

return Mgr
