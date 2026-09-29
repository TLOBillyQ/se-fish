-- 喂食按 floor(基础售价 × mult) 入账，信物优先走 1:1 兑换；先复验身份、目标、距离与选中态。
-- 注入 Save 后只改隔离 draft，持久成功才回包、推库存、报任务与播动画（#123）。
-- 同会话 seq 重放或携带响应中的完整 operation 重试只回原结果；旧身份淘汰后拒绝。
-- 未注入 Save 的独立纯逻辑模式保留同步结算；「对话」是纯客户端台词。
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')

local Mgr = { LastSeq = {}, Anchors = {} }

-- 同通道相同 seq 重放原结果；完整 operation 可跨重连重试，身份校验归 Save。
local function resolve(mgr, player, data, payload)
    local requestId = payload.operation
    if requestId ~= nil and type(requestId) ~= 'table' then return nil, false end
    if requestId == nil then requestId = payload.seq end
    local operation, mode = mgr.Save:ResolveRequest(player, data, 'interact:fisherman', requestId)
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

local Points = {
    fisherman = { Cfg = function() return GameCfg.Interact.Fisherman end, Actions = { Feed = 'Feed' } },
}

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('InteractResult'):FireClient(player, payload)
end

function Mgr:FindAnchor(name)
    local cached = self.Anchors[name]
    if cached then return cached end
    local world = game:GetService('World')
    local ok, unit = pcall(world.FindFirstChild, world, name)
    if ok and unit then self.Anchors[name] = unit end
    return ok and unit or nil
end

local function flatDistance(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- 选中的可喂物：选中格是鱼获优先，其次是选中的鱼饵；返回 金币数, 扣除函数, 日志描述, 物品 id
local function feedable(data, point)
    local items = data.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    local slot = data.Data.SelectedSlot
    local entry = slot and items[slot]
    local species = entry and entry.count > 0 and GameCfg.Fish[entry.itemId]
    if species then
        return FishCatch.Price(species, entry.mult), function() items[slot] = nil end,
            entry.itemId .. ' x' .. tostring(entry.mult or 1) .. ' slot=' .. tostring(slot), entry.itemId, 'fish'
    end
    local baitId = data.Data.SelectedBait
    local price = baitId and point.BaitPrice[baitId]
    local count = baitId and data.Data.Bait[baitId]
    if price and type(count) == 'number' and count >= 1 then
        return price, function(d) d.Bait[baitId] = d.Bait[baitId] - 1 end, baitId, baitId, 'bait'
    end
end

-- 角色是否在交互点 point 的水平范围内（只看 x/z）；在就返回命中的锚点单位。
-- point 带 AnchorName（单锚点，商店/摆渡复用同一套复验）或 AnchorNames（多锚点，#90 钓鱼佬一区 + 虾池）
function Mgr:InRange(player, point)
    local character = player and player.Character
    local pos = character and character.Position
    if not pos then return nil end
    local names = point.AnchorNames or { point.AnchorName }
    for _, name in ipairs(names) do
        local anchor = self:FindAnchor(name)
        local center = anchor and anchor.Position
        if center and flatDistance(pos, center) <= point.Radius + point.Slack then return anchor end
    end
    return nil
end

function Mgr:PlayEat(anchor, point)
    -- 模型无动画时 EatAnimation 留空，直接跳过（吃动作改由客户端缩放脉冲表现）
    if not point.EatAnimation then return end
    -- 引擎单位读不存在的成员可能直接报错，所以连读取也包进 pcall
    local okRead, play = pcall(function() return anchor.PlayAnimation end)
    if not okRead or not play then
        print('[MgrInteract] 钓鱼佬没有可播放的动画，跳过吃动作')
        return
    end
    local ok, err = pcall(play, anchor, point.EatAnimation)
    if not ok then print('[MgrInteract] 吃动作播放失败', tostring(err)) end
end

-- 选中的信物（#87，GameSpec §8.1）：选中格是 Exchange 表里的信物时返回 { slot, tokenId, product }
local function exchangeable(data, point)
    local slot = data.Data.SelectedSlot
    local entry = slot and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][slot]
    local product = entry and entry.count > 0 and point.Exchange and point.Exchange[entry.itemId]
    if not product then return end
    return { slot = slot, tokenId = entry.itemId, product = product }
end

-- 信物兑换：扣除与发放由 PlayerData:ExchangeSlot 一次落地；满格拒绝且不消耗信物，
-- 不给金币、不报任务事实。'bad' 只会是配置错误（产物 id 不在物品表），记错误日志
function Mgr:Exchange(player, data, anchor, point, exchange, operation)
    if self.Save and self.Save:IsPaused(player.UserId) then
        self:Reply(player, { ok = false, reason = '临时本局暂停信物兑换，请先保存到存档' })
        return false
    end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            local entry = draft.Data.Containers[GameCfg.Items.ContainerId.ItemBar][exchange.slot]
            if not entry or entry.itemId ~= exchange.tokenId then return nil, 'nothing' end
            local beforeToken, beforeProduct = itemCount(draft, exchange.tokenId), itemCount(draft, exchange.product)
            local changed, failure = draft:ExchangeSlot(exchange.slot, exchange.product)
            if not changed then return nil, failure end
            return { ok = true, action = 'Feed', exchange = { from = exchange.tokenId, to = exchange.product },
                coinBefore = draft.Data.FishCoin, coinAfter = draft.Data.FishCoin,
                tokenBefore = beforeToken, tokenAfter = itemCount(draft, exchange.tokenId),
                itemBefore = beforeProduct, itemAfter = itemCount(draft, exchange.product) }
        end, function(written, result, operation)
            if not written then self:Reply(player, { ok = false, reason = result }) return end
            print('[MgrInteract] 兑换落账', player.UserId, operation.id, exchange.tokenId, exchange.product,
                'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter,
                'tokenBefore=' .. result.tokenBefore, 'tokenAfter=' .. result.tokenAfter,
                'itemBefore=' .. result.itemBefore, 'itemAfter=' .. result.itemAfter)
            self.PlayerData:SendItemBar(player)
            self:Reply(player, result)
            self:PlayEat(anchor, point)
        end)
    end
    local ok, reason = data:ExchangeSlot(exchange.slot, exchange.product)
    if not ok then
        if reason ~= 'full' then
            print('[MgrInteract] 兑换配置错误', player.UserId, exchange.tokenId, exchange.product, reason)
        end
        self:Reply(player, { ok = false, reason = reason })
        return false
    end
    print('[MgrInteract] 信物兑换', player.UserId, exchange.tokenId, '->', exchange.product)
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, action = 'Feed',
        exchange = { from = exchange.tokenId, to = exchange.product } })
    self:PlayEat(anchor, point)
    return true
end

function Mgr:Feed(player, data, anchor, point, seq, operation)
    local exchange = exchangeable(data, point)
    if exchange then return self:Exchange(player, data, anchor, point, exchange, operation) end
    local coins, spend, what, itemId, category = feedable(data, point)
    if not coins then
        self:Reply(player, { ok = false, reason = 'nothing' })
        return false
    end
    if self.Save then
        local selectedSlot, selectedBait = data.Data.SelectedSlot, data.Data.SelectedBait
        return execute(self, player, data, operation, function(draft)
            draft.Data.SelectedSlot, draft.Data.SelectedBait = selectedSlot, selectedBait
            local earned, consume, _, id, kind = feedable(draft, point)
            if not earned then return nil, 'nothing' end
            local beforeCoin, beforeItem = draft.Data.FishCoin, itemCount(draft, id)
            if not draft:AddCoin(earned, consume, 'feed') then return nil, 'nothing' end
            return { ok = true, action = 'Feed', coins = earned, itemId = id, category = kind,
                coinBefore = beforeCoin, coinAfter = draft.Data.FishCoin,
                itemBefore = beforeItem, itemAfter = itemCount(draft, id) }
        end, function(written, result, operation)
            if not written then self:Reply(player, { ok = false, reason = result }) return end
            print('[MgrInteract] 喂食落账', player.UserId, operation.id, result.itemId,
                'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter,
                'itemBefore=' .. result.itemBefore, 'itemAfter=' .. result.itemAfter)
            self.PlayerData:SendItemBar(player)
            self:Reply(player, result)
            self:PlayEat(anchor, point)
            if self.Quest then self.Quest:Notify('Feed', player, { itemId = result.itemId,
                category = result.category, eventId = operation.id }) end
        end)
    end
    if not data:AddCoin(coins, spend, 'feed') then return false end
    print('[MgrInteract] 喂食', player.UserId, what, '+' .. tostring(coins), 'FishCoin=' .. tostring(data.Data.FishCoin))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, action = 'Feed', coins = coins })
    self:PlayEat(anchor, point)
    -- 新手任务事实（#51 / #52）：序号每人严格递增、只结算一次，玩家 + 序号即这次喂食的唯一 eventId；
    -- category 区分鱼获（fish，只能来自本人拾取进道具栏）与鱼饵（bait）
    if self.Quest then
        self.Quest:Notify('Feed', player, { itemId = itemId, category = category,
            eventId = 'feed:' .. tostring(player.UserId) .. ':' .. tostring(seq) })
    end
    return true
end

-- 处理一次交互请求；持久模式返回是否接收，最终结果经 InteractResult 回包。
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' then return false end
    local entry = Points[payload.target]
    local method = entry and entry.Actions[payload.action]
    local seq = payload.seq
    if not method then return false end
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
    local point = entry.Cfg()
    local anchor = self:InRange(player, point)
    if not anchor then return false end
    self.LastSeq[player.UserId] = seq
    return self[method](self, player, data, anchor, point, seq, operation)
end

function Mgr:Start()
    _G.REUtil:GetRE('InteractAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'InteractAction', GameCfg.Items.ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
end

function Mgr:OnPlayerRemoving(player)
    self.LastSeq[player.UserId] = nil
end

return Mgr
