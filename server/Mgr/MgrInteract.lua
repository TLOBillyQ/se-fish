-- 喂食即回收（#127）：选中格是本区**未烤**信物时优先走本区链 1:1 兑换；其余选中物品按物品表
-- 基础价 × 实例倍率结金币（烤过的按烤熟价 ×1.5），选中的鱼饵按 Fishing.BaitPrice 每只结。
-- 先复验身份、目标、距离与选中态；背包里的东西不能借喂食绕过转入规则。
-- 注入 Save 后只改隔离 draft，持久成功才回包、推库存、报任务与播动画（#123）。
-- 同会话 seq 重放或携带响应中的完整 operation 重试只回原结果；旧身份淘汰后拒绝。
-- 未注入 Save 的独立纯逻辑模式保留同步结算；「对话」是纯客户端台词。
local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')

local Mgr = { LastSeq = {}, Anchors = {} }

local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar

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

-- 七区钓鱼佬（#127）：共享表现参数（Radius/Slack/BubbleHeight/DialogText/BaitPrice/ModelName）
-- 与本区锚点、本区兑换链合成一个完整交互点。每次请求现取共享表，配置热改与测试替身都即时生效。
local function fishermanPoint(shared, npc)
    local point = {}
    for key, value in pairs(shared) do point[key] = value end
    point.ZoneId, point.AnchorNames, point.Exchange, point.Chain = npc.ZoneId, npc.AnchorNames, npc.Exchange, npc.Chain
    return point
end

-- 选中并实际可用的道具栏格（#127）：兑换与回收都只看选中的这一格，不看背包
local function selectedEntry(data)
    local items = data.Data.Containers[ITEM_BAR]
    local slot = data.Data.SelectedSlot
    local entry = slot and items[slot]
    if entry and entry.count > 0 then return slot, entry end
end

-- 烤制标记（#127 / #137）：旧布尔写在存档格位的 saved.cooked 上；烧烤取出的数值倍率在
-- entry.cooked / saved.k（GameCfg.Items.CookRate 统一读取）。烤过的信物只售卖，不再走兑换
local function isCooked(entry)
    return GameCfg.Items.CookRate(entry) ~= nil
end

local Points = {
    fisherman = { Cfg = function() return GameCfg.Interact.Fisherman end, Actions = { Feed = 'Feed' },
        -- 按区分派（#127）：范围内命中哪个区的钓鱼佬就用哪个区的锚点与兑换链
        Resolve = function(mgr, player)
            local shared = GameCfg.Interact.Fisherman
            for _, npc in ipairs(GameCfg.Interact.Fishermen) do
                local probe = { AnchorNames = npc.AnchorNames, Radius = shared.Radius, Slack = shared.Slack }
                local anchor = mgr:InRange(player, probe)
                if anchor then return fishermanPoint(shared, npc), anchor end
            end
        end },
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

-- 选中的可喂物（#127）：先看选中格的物品——鱼获按个体倍率、普通物品按物品表基础价，烤过的按烤熟价；
-- 选中格空或表里没有时才退回选中的鱼饵（计数库存，每只 BaitPrice）。
-- 返回 金币数, 扣除回调, 日志描述, 物品 id, 类别（fish 鱼获 / item 普通物品 / bait 鱼饵）
local function saleable(data, point)
    local slot, entry = selectedEntry(data)
    if entry then
        local rate = GameCfg.Items.CookRate(entry)
        local price = GameCfg.Items.SalePrice(entry.itemId, entry.mult, rate)
        if price then
            return price, function(d) d.Containers[ITEM_BAR][slot] = nil end,
                entry.itemId .. (rate and '(烤)' or '') .. ' x' .. tostring(entry.mult or 1) .. ' slot=' .. tostring(slot),
                entry.itemId, GameCfg.Fish[entry.itemId] and 'fish' or 'item'
        end
    end
    local baitId = data.Data.SelectedBait
    local price = baitId and point.BaitPrice[baitId]
    local count = baitId and data.Data.Bait[baitId]
    if price and type(count) == 'number' and count >= 1 then
        return price, function(d) d.Bait[baitId] = d.Bait[baitId] - 1 end, baitId, baitId, 'bait'
    end
end

-- 角色是否在交互点 point 的水平范围内（只看 x/z）；在就返回命中的锚点单位。
-- point 带 AnchorName（单锚点，商店/摆渡复用同一套复验）或 AnchorNames（多锚点，#90 起）
function Mgr:InRange(player, point)
    local character = player and player.Character
    local pos = character and character.Position
    if not pos then return nil end
    local names = point.AnchorNames or { point.AnchorName }
    for _, name in ipairs(names) do
        local anchor = self:FindAnchor(name)
        local center = anchor and anchor.Position
        if center and flatDistance(pos, center) <= BodyScale.InteractionRadius(character, point.Radius) + point.Slack then return anchor end
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

-- 兑换产物的两种形态（#127，GameSpec §8.1）：'achievement.<id>' 落到 Extra.achievements（不占格），
-- 其余字符串是物品表 id。前缀口径与 common/ContentValidation.lua 的 'achievement.final' 特例一致。
local function productOf(product)
    if type(product) ~= 'string' then return nil end
    local achievement = product:match('^achievement%.(.+)$')
    if achievement then return { achievement = achievement } end
    return { itemId = product }
end

-- 选中的本区信物（#87 / #127）：选中格是本区未烤信物时返回 { slot, tokenId, product }
local function exchangeable(data, point)
    local slot, entry = selectedEntry(data)
    local product = entry and not isCooked(entry) and point.Exchange and point.Exchange[entry.itemId]
    if not product then return end
    return { slot = slot, tokenId = entry.itemId, product = product }
end

-- 兑换交付（#127）：先扣掉选中信物（释放这一格），再按**交付后的容量**校验并发放；
-- 最终容量不足时回退且不扣物品——使用本次交付释放的格位是合法的（1:1 兑换总能落回这一格）。
-- 目标既可以是真 PlayerData，也可以是 #123 的隔离 draft（draft 失败时整份草案被丢弃，这里的回退是防御）。
local function deliver(target, exchange, product)
    local items = target.Data.Containers[ITEM_BAR]
    local kept = items[exchange.slot]
    if not kept or kept.count <= 0 or kept.itemId ~= exchange.tokenId then return false, 'nothing' end
    items[exchange.slot] = nil
    if product.achievement then
        target.Extra.achievements = target.Extra.achievements or {}
        target.Extra.achievements[product.achievement] = true
    elseif not target:CanGrant(product.itemId, 1) or not target:GrantItem(product.itemId, 1) then
        items[exchange.slot] = kept
        return false, 'full'
    end
    if target.Data.SelectedSlot == exchange.slot then target.Data.SelectedSlot = nil end
    return true
end

-- 信物兑换（#87 / #127）：扣除与发放一次落地，不给金币、不报任务事实。
-- 同步模式补一次 UpdateData 让选中态归位、属性与库存同步；operation 重放只回原结果（#123）
function Mgr:Exchange(player, data, anchor, point, exchange, operation)
    if self.Save and self.Save:IsPaused(player.UserId) then
        self:Reply(player, { ok = false, reason = '临时本局暂停信物兑换，请先保存到存档' })
        return false
    end
    local product = productOf(exchange.product)
    if not product then
        print('[MgrInteract] 兑换产物无法解析', player.UserId, tostring(exchange.product))
        return false
    end
    local function replyOf(result, written)
        if not written then
            self:Reply(player, { ok = false, reason = result })
            return
        end
        self.PlayerData:SendItemBar(player)
        self:Reply(player, result)
        self:PlayEat(anchor, point)
    end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            local entry = draft.Data.Containers[ITEM_BAR][exchange.slot]
            if not entry or entry.itemId ~= exchange.tokenId then return nil, 'nothing' end
            local beforeToken, beforeProduct = itemCount(draft, exchange.tokenId), itemCount(draft, exchange.product)
            local changed, failure = deliver(draft, exchange, product)
            if not changed then return nil, failure end
            local result = { ok = true, action = 'Feed', exchange = { from = exchange.tokenId, to = exchange.product },
                coinBefore = draft.Data.FishCoin, coinAfter = draft.Data.FishCoin,
                tokenBefore = beforeToken, tokenAfter = itemCount(draft, exchange.tokenId),
                itemBefore = beforeProduct, itemAfter = itemCount(draft, exchange.product) }
            if product.achievement then result.achievement = product.achievement end
            return result
        end, function(written, result, operation)
            if written then
                print('[MgrInteract] 兑换落账', player.UserId, operation.id, exchange.tokenId, exchange.product,
                    'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter,
                    'tokenBefore=' .. result.tokenBefore, 'tokenAfter=' .. result.tokenAfter,
                    'itemBefore=' .. result.itemBefore, 'itemAfter=' .. result.itemAfter)
            end
            replyOf(result, written)
        end)
    end
    local changed, reason = deliver(data, exchange, product)
    if not changed then
        if reason ~= 'full' then
            print('[MgrInteract] 兑换配置错误', player.UserId, exchange.tokenId, exchange.product, reason)
        end
        self:Reply(player, { ok = false, reason = reason })
        return false
    end
    data:UpdateData(function() end, true)
    print('[MgrInteract] 信物兑换', player.UserId, exchange.tokenId, '->', exchange.product)
    local result = { ok = true, action = 'Feed', exchange = { from = exchange.tokenId, to = exchange.product } }
    if product.achievement then result.achievement = product.achievement end
    replyOf(result, true)
    return true
end

function Mgr:Feed(player, data, anchor, point, seq, operation)
    local exchange = exchangeable(data, point)
    if exchange then return self:Exchange(player, data, anchor, point, exchange, operation) end
    local coins, spend, what, itemId, category = saleable(data, point)
    if not coins then
        self:Reply(player, { ok = false, reason = 'nothing' })
        return false
    end
    if self.Save then
        local selectedSlot, selectedBait = data.Data.SelectedSlot, data.Data.SelectedBait
        return execute(self, player, data, operation, function(draft)
            draft.Data.SelectedSlot, draft.Data.SelectedBait = selectedSlot, selectedBait
            local earned, consume, _, id, kind = saleable(draft, point)
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
    -- 回包字段与持久模式保持一致，便于同一套客户端与用例覆盖两种模式
    self:Reply(player, { ok = true, action = 'Feed', coins = coins, itemId = itemId, category = category })
    self:PlayEat(anchor, point)
    -- 新手任务事实（#51 / #52）：序号每人严格递增、只结算一次，玩家 + 序号即这次喂食的唯一 eventId；
    -- category 区分鱼获（fish，只能来自本人拾取进道具栏）与普通物品（item）/鱼饵（bait）
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
    local point, anchor
    if entry.Resolve then
        point, anchor = entry.Resolve(self, player)
    else
        point = entry.Cfg()
        anchor = self:InRange(player, point)
    end
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
