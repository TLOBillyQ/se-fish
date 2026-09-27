-- #87 试玩验收探针（server 端）：信物兑换三条验收
-- 1. 喂电鳗头 → 鸭子 x1、电鳗头消失、金币不变
-- 2. 喂鳄雀鳝鱼头 → 船票 x1
-- 3. 道具栏+背包全满 → 拒绝、信物不消耗（回包 reason='full'）
local GameCfg = require('common.GameCfg')
local MgrInteract = require('server.Mgr.MgrInteract')
local MgrPlayerData = _G.MgrPlayerData

local player = game:GetService('Players'):GetPlayers()[1]
local data = MgrPlayerData:GetDataInst(player)
local world = game:GetService('World')
local anchor = world:FindFirstChild('TGUnitFish')
-- 把角色挪到钓鱼佬旁（只看 x/z）
local c = anchor.Position
player.Character.Position = Vector3.New(c.x + 1, c.y, c.z)

-- 拦回包取证
local replies = {}
local origReply = MgrInteract.Reply
MgrInteract.Reply = function(self, p, payload)
    replies[#replies + 1] = payload
    origReply(self, p, payload)
end

local function countItem(itemId)
    local total = 0
    for _, container in pairs(data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId then total = total + entry.count end
        end
    end
    return total
end

local function slotOf(itemId)
    local bar = data.Data.Containers.itemBar
    for i = 1, data:ItemBarCapacity() do
        if bar[i] and bar[i].itemId == itemId then return i end
    end
end

local seq = 1000
local function feed()
    seq = seq + 1
    return MgrInteract:Handle(player, { target = 'fisherman', action = 'Feed', seq = seq })
end

-- 场景 1：喂电鳗头换鸭子
data:GrantItem('eelHead', 1)
data:SelectSlot(slotOf('eelHead'))
local coinBefore = data.Data.FishCoin
local ok1 = feed()
print('PROBE87 s1 ok=' .. tostring(ok1)
    .. ' eelHead=' .. countItem('eelHead') .. ' duck=' .. countItem('duck')
    .. ' coin=' .. data.Data.FishCoin .. '(before=' .. coinBefore .. ')')

-- 场景 2：喂鳄雀鳝鱼头换船票（道具栏已满，先丢掉 s1 的鸭子腾格，让鱼头进道具栏）
local duckSlot = slotOf('duck')
if duckSlot then data:DiscardSlot(duckSlot) end
data:GrantItem('garHead', 1)
data:SelectSlot(slotOf('garHead'))
local ok2 = feed()
print('PROBE87 s2 ok=' .. tostring(ok2)
    .. ' garHead=' .. countItem('garHead') .. ' ticket=' .. countItem('shrimpTicket')
    .. ' coin=' .. data.Data.FishCoin)

-- 场景 3：填满道具栏+背包后喂信物被拒绝且不消耗
local ticketSlot = slotOf('shrimpTicket')
if ticketSlot then data:DiscardSlot(ticketSlot) end -- 腾格让信物先进道具栏，再填满
data:GrantItem('eelHead', 1)
while data:GrantItem('tilapia', 1) do end
data:SelectSlot(slotOf('eelHead'))
local ok3 = feed()
local r3 = replies[#replies]
print('PROBE87 s3 ok=' .. tostring(ok3)
    .. ' eelHead=' .. countItem('eelHead') .. ' duck=' .. countItem('duck')
    .. ' reason=' .. tostring(r3 and r3.reason))

-- 回包流水
for i, r in ipairs(replies) do
    print('PROBE87 reply' .. i .. ' ok=' .. tostring(r.ok)
        .. ' coins=' .. tostring(r.coins) .. ' reason=' .. tostring(r.reason)
        .. ' exchange=' .. tostring(r.exchange and (r.exchange.from .. '->' .. r.exchange.to)))
end
print('PROBE87 DONE')
