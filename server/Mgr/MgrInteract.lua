-- 交互点管理器（#44，#27 规格）：登记场景既有单位为交互目标，当前只有钓鱼佬与「喂食」（M3 复用于钓场老板）。
-- 客户端发 InteractAction{target, action, seq}；服务端复验身份、目标、距离（只看 x/z）与选中态，
-- 序号必须递增，重放与旧序号不结算。喂食即出售：选中格是鱼获就扣该格按 floor(基础售价 × mult) 入账，
-- 否则扣 1 只选中的鱼饵按 BaitPrice 入账；扣除与入账走 PlayerData:AddCoin 一次落地。
-- 吃动作是表现层，失败只记日志、不影响裁决。「对话」是纯客户端台词，不经服务端。
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')

local Mgr = { LastSeq = {}, Anchors = {} }

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
            entry.itemId .. ' x' .. tostring(entry.mult or 1) .. ' slot=' .. tostring(slot), entry.itemId
    end
    local baitId = data.Data.SelectedBait
    local price = baitId and point.BaitPrice[baitId]
    local count = baitId and data.Data.Bait[baitId]
    if price and type(count) == 'number' and count >= 1 then
        return price, function(d) d.Bait[baitId] = d.Bait[baitId] - 1 end, baitId, baitId
    end
end

-- 角色是否在交互点 point（带 AnchorName / Radius / Slack）的水平范围内；在就返回锚点单位。
-- 商店（#48）复用同一套复验
function Mgr:InRange(player, point)
    local character = player and player.Character
    local pos = character and character.Position
    local anchor = pos and self:FindAnchor(point.AnchorName)
    local center = anchor and anchor.Position
    if not center or flatDistance(pos, center) > point.Radius + point.Slack then return nil end
    return anchor
end

function Mgr:PlayEat(anchor, point)
    -- 引擎单位读不存在的成员可能直接报错，所以连读取也包进 pcall
    local okRead, play = pcall(function() return anchor.PlayAnimation end)
    if not okRead or not play then
        print('[MgrInteract] 钓鱼佬没有可播放的动画，跳过吃动作')
        return
    end
    local ok, err = pcall(play, anchor, point.EatAnimation)
    if not ok then print('[MgrInteract] 吃动作播放失败', tostring(err)) end
end

function Mgr:Feed(player, data, anchor, point, seq)
    local coins, spend, what, itemId = feedable(data, point)
    if not coins then
        self:Reply(player, { ok = false, reason = 'nothing' })
        return false
    end
    if not data:AddCoin(coins, spend, 'feed') then return false end
    print('[MgrInteract] 喂食', player.UserId, what, '+' .. tostring(coins), 'FishCoin=' .. tostring(data.Data.FishCoin))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, action = 'Feed', coins = coins })
    self:PlayEat(anchor, point)
    -- 新手任务事实（#51）：序号每人严格递增、只结算一次，玩家 + 序号即这次喂食的唯一 eventId
    if self.Quest then
        self.Quest:Notify('Feed', player, { itemId = itemId, eventId = 'feed:' .. tostring(player.UserId) .. ':' .. tostring(seq) })
    end
    return true
end

-- 处理一次交互请求；结算成功返回 true
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' then return false end
    local entry = Points[payload.target]
    local method = entry and entry.Actions[payload.action]
    local seq = payload.seq
    if not method or type(seq) ~= 'number' or seq ~= math.floor(seq) then return false end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return false end
    local point = entry.Cfg()
    local anchor = self:InRange(player, point)
    if not anchor then return false end
    self.LastSeq[player.UserId] = seq
    return self[method](self, player, data, anchor, point, seq)
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
