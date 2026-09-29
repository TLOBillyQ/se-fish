-- 钓场商店（#48/#90/#123）：Buy / UpgradeStorage 都由服务端复验范围、白名单、容量与价格。
-- 注入 Save 时只改隔离 draft，扣费与结果同键落账后才发布库存、回包与任务事实。
-- 请求 seq 按服务端会话和业务通道去重；响应中的 operation 支持原身份重试，只回历史结果。
-- 未注入 Save 的独立纯逻辑模式保留原有同步结算与 LastSeq 去重。
local GameCfg = require('common.GameCfg')

local Mgr = { LastSeq = {} }

-- 同通道相同 seq 重放原结果；完整 operation 可跨重连重试，身份校验归 Save。
local function resolve(mgr, player, data, payload)
    local requestId = payload.operation
    if requestId ~= nil and type(requestId) ~= 'table' then return nil, false end
    if requestId == nil then requestId = payload.seq end
    local operation, mode = mgr.Save:ResolveRequest(player, data, 'shop', requestId)
    if not operation then return nil, false end
    if mode ~= 'replay' then return operation end
    local accepted = mgr.Save:Execute(player, data, operation, function() return nil, 'expired' end,
        function(ok, result)
            if ok then result.operation = operation mgr:Reply(player, result) end
        end)
    return nil, accepted
end

local function execute(mgr, player, data, operation, transform, done)
    if not operation then return false end
    return mgr.Save:Execute(player, data, operation, transform, function(ok, result)
        if ok then result.operation = operation end
        done(ok, result, operation)
    end)
end
local function itemCount(data, itemId)
    return data.Data.Bait[itemId] or data:ItemCount(itemId)
end

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

function Mgr:Buy(player, data, itemId, seq, operation)
    local stand = self:StandFor(player)
    if not stand then return self:Fail(player, itemId, 'range') end
    local goods = self:FindGoods(itemId, stand.Level)
    if not goods then return self:Fail(player, itemId, 'item') end
    local ok, reason = data:CanGrant(itemId, 1)
    if not ok then return self:Fail(player, itemId, reason == 'full' and 'full' or 'item') end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            local allowed, failure = draft:CanGrant(itemId, 1)
            if not allowed then return nil, failure end
            local beforeCoin, beforeItem = draft.Data.FishCoin, itemCount(draft, itemId)
            if not draft:SpendCoin(goods.Price, function() draft:GrantItem(itemId, 1) end, 'shop:' .. itemId) then
                return nil, 'coin'
            end
            return { ok = true, itemId = itemId, price = goods.Price,
                coinBefore = beforeCoin, coinAfter = draft.Data.FishCoin,
                itemBefore = beforeItem, itemAfter = itemCount(draft, itemId) }
        end, function(written, result, operation)
            if not written then self:Fail(player, itemId, result) return end
            print('[MgrShop] 购买落账', player.UserId, operation.id, itemId,
                'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter,
                'itemBefore=' .. result.itemBefore, 'itemAfter=' .. result.itemAfter)
            self.PlayerData:SendItemBar(player)
            self:Reply(player, result)
            if self.Quest then self.Quest:Notify('Buy', player, { itemId = itemId, eventId = operation.id }) end
        end)
    end
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

function Mgr:Upgrade(player, data, operation)
    if not self:StandFor(player) then return self:Fail(player, nil, 'range') end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            local beforeCoin, beforeLevel = draft.Data.FishCoin, draft.Data.UpgradeLevel
            local upgraded, cost = draft:UpgradeStorage()
            if not upgraded then return nil, cost end
            return { ok = true, action = 'UpgradeStorage', price = cost, level = draft.Data.UpgradeLevel,
                coinBefore = beforeCoin, coinAfter = draft.Data.FishCoin, levelBefore = beforeLevel }
        end, function(written, result, operation)
            if not written then self:Fail(player, nil, result) return end
            print('[MgrShop] 扩容落账', player.UserId, operation.id,
                'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter,
                'levelBefore=' .. result.levelBefore, 'levelAfter=' .. result.level)
            self.PlayerData:SendItemBar(player)
            self:Reply(player, result)
        end)
    end
    local ok, price = data:UpgradeStorage()
    if not ok then return self:Fail(player, nil, price) end
    print('[MgrShop] 扩容', player.UserId, 'level=' .. tostring(data.Data.UpgradeLevel), '-' .. tostring(price))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, action = 'UpgradeStorage', price = price,
        level = data.Data.UpgradeLevel })
    return true
end

-- 处理一次商店请求；持久模式返回是否接收，最终结果经 ShopResult 回包。
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or (payload.action ~= 'Buy' and payload.action ~= 'UpgradeStorage') then return false end
    local seq = payload.seq
    if (not self.Save or payload.operation == nil)
        and (type(seq) ~= 'number' or seq ~= math.floor(seq) or seq < 1 or seq > 2147483647) then return false end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    local operation
    if self.Save then
        local replayed
        operation, replayed = resolve(self, player, data, payload)
        if not operation then return replayed end
    end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return false end
    self.LastSeq[player.UserId] = seq
    if payload.action == 'UpgradeStorage' then return self:Upgrade(player, data, operation) end
    return self:Buy(player, data, payload.itemId, seq, operation)
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
