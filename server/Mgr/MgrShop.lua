-- 钓场商店（#48，#28 规格；#90 多摊位）：单一通道 ShopAction{action='Buy', itemId, seq}，客户端只发意图。
-- 服务端复验：动作与整数 seq → 数据就绪 → seq 递增（同一请求重放 / 旧序号不结算，限频不代替去重）
-- → 站在某个摊位旁（Stands 逐摊复用 MgrInteract:InRange，摊位等级 = 钓鱼区序号）→ 商品在白名单
-- 且摊位等级够 → 目标容器放得下 → 扣币（PlayerData:SpendCoin，价格只取配置）与发货
-- （PlayerData:GrantItem 按 Container 分流）同一次落地。
-- 任一条不过就不扣钱、不发货，把原因（item / range / full / coin）回给客户端做提示。
local GameCfg = require('common.GameCfg')

local Mgr = { LastSeq = {} }

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('ShopResult'):FireClient(player, payload)
end

-- 当前摊位等级下上架的商品；不在白名单或等级不够返回 nil
function Mgr:FindGoods(itemId, level)
    for _, goods in ipairs(GameCfg.Shop.Goods) do
        if goods.ItemId == itemId and goods.MinShopLevel <= level then return goods end
    end
end

-- 玩家站在哪个摊位旁：返回 Stands 行（含 Level），不在任何摊位返回 nil
function Mgr:StandFor(player)
    local shop = GameCfg.Shop
    for _, stand in ipairs(shop.Stands) do
        if self.Interact:InRange(player,
            { AnchorName = stand.AnchorName, Radius = shop.Radius, Slack = shop.Slack }) then
            return stand
        end
    end
    return nil
end

function Mgr:Fail(player, itemId, reason)
    print('[MgrShop] 购买失败', player.UserId, tostring(itemId), reason)
    self:Reply(player, { ok = false, itemId = itemId, reason = reason })
    return false
end

function Mgr:Buy(player, data, itemId, seq)
    local stand = self:StandFor(player)
    if not stand then return self:Fail(player, itemId, 'range') end
    local goods = self:FindGoods(itemId, stand.Level)
    if not goods then return self:Fail(player, itemId, 'item') end
    local ok, reason = data:CanGrant(itemId, 1)
    if not ok then return self:Fail(player, itemId, reason == 'full' and 'full' or 'item') end
    if not data:SpendCoin(goods.Price, function() data:GrantItem(itemId, 1) end, 'shop:' .. itemId) then
        return self:Fail(player, itemId, 'coin')
    end
    print('[MgrShop] 购买', player.UserId, itemId, '-' .. tostring(goods.Price), 'FishCoin=' .. tostring(data.Data.FishCoin))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, itemId = itemId, price = goods.Price })
    -- 新手任务事实（#51）：玩家 + 严格递增的请求序号即这次购买的唯一 eventId
    if self.Quest then
        self.Quest:Notify('Buy', player, { itemId = itemId, eventId = 'shop:' .. tostring(player.UserId) .. ':' .. tostring(seq) })
    end
    return true
end

function Mgr:Upgrade(player, data)
    if not self:StandFor(player) then return self:Fail(player, nil, 'range') end
    local ok, price = data:UpgradeStorage()
    if not ok then return self:Fail(player, nil, price) end
    print('[MgrShop] 扩容', player.UserId, 'level=' .. tostring(data.Data.UpgradeLevel), '-' .. tostring(price))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, action = 'UpgradeStorage', price = price,
        level = data.Data.UpgradeLevel })
    return true
end

-- 处理一次商店请求；结算成功返回 true
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or (payload.action ~= 'Buy' and payload.action ~= 'UpgradeStorage') then return false end
    local seq = payload.seq
    if type(seq) ~= 'number' or seq ~= math.floor(seq) then return false end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return false end
    self.LastSeq[player.UserId] = seq
    if payload.action == 'UpgradeStorage' then return self:Upgrade(player, data) end
    return self:Buy(player, data, payload.itemId, seq)
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
