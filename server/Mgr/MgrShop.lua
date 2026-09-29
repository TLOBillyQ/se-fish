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

-- #130：按货架行编号查上架商品（升级行无 itemKey，编号是稳定购买键）；编号非法或等级不够返回 nil
function Mgr:FindGoodsByNumber(number, level)
    if type(number) ~= 'number' or number ~= math.floor(number) or number < 1 then return nil end
    for _, goods in ipairs(GameCfg.Shop.Goods) do
        if goods.Number == number and goods.MinShopLevel <= level then return goods end
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

function Mgr:Fail(player, itemId, reason, number)
    print('[MgrShop] 购买失败', player.UserId, tostring(itemId), tostring(number), reason)
    self:Reply(player, { ok = false, itemId = itemId, number = number, reason = reason })
    return false
end

-- 结算一次购买（live/draft 通用，#130）：限购复验、扣款、发货或强化、购买计数一次落地。
-- 价格一律取货架行（服务端定价，客户端传价忽略）；返回 result 或 nil, reason。
local function settlePurchase(draft, goods)
    if (goods.PurchaseLimit or 0) > 0 and draft:PurchaseCount(goods.Number) >= goods.PurchaseLimit then
        return nil, 'limit'
    end
    if goods.Upgrade then
        local allowed, failure = draft:CanShopUpgrade(goods.Upgrade)
        if not allowed then return nil, failure end
        local beforeCoin = draft.Data.FishCoin
        if not draft:SpendCoin(goods.Price, function() draft:ApplyShopUpgrade(goods.Upgrade) end,
            'shop:' .. goods.Number) then
            return nil, 'coin'
        end
        draft:NotePurchase(goods.Number)
        return { ok = true, action = 'Upgrade', number = goods.Number, name = goods.Name, price = goods.Price,
            kind = goods.Upgrade.kind, level = goods.Upgrade.level,
            coinBefore = beforeCoin, coinAfter = draft.Data.FishCoin }
    end
    local itemId = goods.ItemId
    local allowed, failure = draft:CanGrant(itemId, 1)
    if not allowed then return nil, failure == 'full' and 'full' or 'item' end
    local beforeCoin, beforeItem = draft.Data.FishCoin, itemCount(draft, itemId)
    if not draft:SpendCoin(goods.Price, function() draft:GrantItem(itemId, 1) end, 'shop:' .. itemId) then
        return nil, 'coin'
    end
    draft:NotePurchase(goods.Number)
    return { ok = true, itemId = itemId, number = goods.Number, name = goods.Name, price = goods.Price,
        coinBefore = beforeCoin, coinAfter = draft.Data.FishCoin,
        itemBefore = beforeItem, itemAfter = itemCount(draft, itemId) }
end

function Mgr:Buy(player, data, itemId, number, seq, operation)
    local stand = self:StandFor(player)
    if not stand then return self:Fail(player, itemId, 'range', number) end
    local goods
    if number ~= nil then goods = self:FindGoodsByNumber(number, stand.Level)
    else goods = self:FindGoods(itemId, stand.Level) end
    if not goods then return self:Fail(player, itemId, 'item', number) end
    -- 快速预检（live 状态）；持久模式仍在隔离 draft 上复验，结果以 draft 结算为准
    if (goods.PurchaseLimit or 0) > 0 and data:PurchaseCount(goods.Number) >= goods.PurchaseLimit then
        return self:Fail(player, itemId, 'limit', number)
    end
    if goods.Upgrade then
        local allowed, failure = data:CanShopUpgrade(goods.Upgrade)
        if not allowed then return self:Fail(player, itemId, failure, number) end
    else
        local ok, reason = data:CanGrant(goods.ItemId, 1)
        if not ok then return self:Fail(player, itemId, reason == 'full' and 'full' or 'item', number) end
    end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            local result, failure = settlePurchase(draft, goods)
            if not result then return nil, failure end
            return result
        end, function(written, result, operation)
            if not written then self:Fail(player, itemId, result, number) return end
            print('[MgrShop] 购买落账', player.UserId, operation.id,
                tostring(result.itemId or result.number),
                'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter)
            self.PlayerData:SendItemBar(player)
            self:Reply(player, result)
            if self.Quest then self.Quest:Notify('Buy', player,
                { itemId = result.itemId, number = result.number, eventId = operation.id }) end
        end)
    end
    local result, failure = settlePurchase(data, goods)
    if not result then return self:Fail(player, itemId, failure, number) end
    print('[MgrShop] 购买', player.UserId, tostring(result.itemId or result.number),
        '-' .. tostring(goods.Price), 'FishCoin=' .. tostring(data.Data.FishCoin))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, result)
    -- 新手任务事实（#51）：玩家 + 严格递增的请求序号即这次购买的唯一 eventId
    if self.Quest then
        self.Quest:Notify('Buy', player, { itemId = result.itemId, number = result.number,
            eventId = 'shop:' .. tostring(player.UserId) .. ':' .. tostring(seq) })
    end
    return true
end

-- 旧扩容通道的货架行（#130 code-review）：与新升级行同口径——逐级一次、摊位最低等级、限购计数，
-- 避免旧 action='UpgradeStorage' 绕过新货架等级/限购。返回行或 nil, reason。
local function backpackRow(data, standLevel)
    local spec = GameCfg.Shop.UpgradeKinds.backpack
    local nextLevel = data:ShopUpgradeLevel('backpack') + 1
    if not spec or nextLevel > spec.MaxLevel then return nil, 'max' end
    local row
    for _, goods in ipairs(GameCfg.Shop.Goods) do
        if goods.Upgrade and goods.Upgrade.kind == 'backpack' and goods.Upgrade.level == nextLevel
            and goods.MinShopLevel <= standLevel then
            row = goods
            break
        end
    end
    if not row then return nil, 'level' end
    if (row.PurchaseLimit or 0) > 0 and data:PurchaseCount(row.Number) >= row.PurchaseLimit then
        return nil, 'limit'
    end
    return row
end

function Mgr:Upgrade(player, data, operation)
    local stand = self:StandFor(player)
    if not stand then return self:Fail(player, nil, 'range') end
    local row, reason = backpackRow(data, stand.Level)
    if not row then return self:Fail(player, nil, reason) end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            local draftRow, failure = backpackRow(draft, stand.Level)
            if not draftRow then return nil, failure end
            local beforeCoin, beforeLevel = draft.Data.FishCoin, draft.Data.UpgradeLevel
            local upgraded, cost = draft:UpgradeStorage()
            if not upgraded then return nil, cost end
            draft:NotePurchase(draftRow.Number)
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
    data:NotePurchase(row.Number)
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
    -- #130：购买键支持 itemId（旧路径）或货架行编号 number（升级行唯一键）；两者取 number
    local itemId, number = payload.itemId, payload.number
    if number ~= nil then
        if type(number) ~= 'number' or number ~= math.floor(number) or number < 1
            or number > 2147483647 then return false end
    elseif type(itemId) ~= 'string' then return false end
    return self:Buy(player, data, itemId, number, seq, operation)
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
