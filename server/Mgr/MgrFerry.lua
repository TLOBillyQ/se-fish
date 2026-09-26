-- 摆渡（#89，GameSpec §8.3 已确认细则）：客户端发 FerryAction{action='Board'|'Return', seq}。
-- 去程 Board：复验序号/距离后扣 1 张船票开始倒计时（时长在 GameCfg.Ferry.Outbound.CountdownSec），
-- 倒计时结束把船锚点 BoatRange 米内（只看 x/z）的所有在线玩家传送到虾池落点——搭便船合法，
-- 所以只收先交票那一个人的票；倒计时中其他人再交票拒绝（'sailing'）且不扣。
-- 返程 Return：虾池侧锚点按人收金币、立即传送回第一钓鱼区；传送失败（角色缺失等）退款。
-- 到点后区域写入 PlayerData:SetZone（#92 存档用）。范围复验复用 MgrInteract:InRange（AnchorName/Radius/Slack）。
local GameCfg = require('common.GameCfg')

local Mgr = { LastSeq = {} }

local function flatDistance(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('FerryResult'):FireClient(player, payload)
end

function Mgr:Broadcast(payload)
    _G.REUtil:GetRE('FerryState'):FireAllClients(payload)
end

function Mgr:Fail(player, action, reason)
    self:Reply(player, { ok = false, action = action, reason = reason })
    return false
end

-- 在线玩家枚举是测试替身的注入点（试玩里就是 Players:GetPlayers()）
function Mgr:OnlinePlayers()
    return game:GetService('Players'):GetPlayers()
end

-- 传送单个玩家到配置落点；角色缺失或引擎拒绝都不算成功
function Mgr:Teleport(player, dest)
    local character = player and player.Character
    if not character then return false end
    local ok = pcall(function()
        local pos = Vector3.New(dest.x, dest.y, dest.z)
        if character.SetPosition then
            character:SetPosition(pos)
        else
            character.Position = pos
        end
    end)
    if not ok then print('[MgrFerry] 传送失败', player.UserId) end
    return ok
end

function Mgr:Board(player, data)
    local point = GameCfg.Ferry.Outbound
    if self.DepartAt then return self:Fail(player, 'Board', 'sailing') end
    if not self.Interact:InRange(player, point) then return self:Fail(player, 'Board', 'range') end
    if not data:ConsumeItem(point.Ticket) then return self:Fail(player, 'Board', 'ticket') end
    self.DepartAt = self.World:GetServerTime() + point.CountdownSec
    self.Payer = player.UserId
    print('[MgrFerry] 收船票开船倒计时', player.UserId, point.CountdownSec .. 's')
    self.PlayerData:SendItemBar(player)
    self:Broadcast({ phase = 'countdown', seconds = point.CountdownSec })
    self:Reply(player, { ok = true, action = 'Board', seconds = point.CountdownSec })
    return true
end

function Mgr:ReturnBack(player, data)
    local point = GameCfg.Ferry.Return
    if not self.Interact:InRange(player, point) then return self:Fail(player, 'Return', 'range') end
    if not data:SpendCoin(point.Price, nil, 'ferry:return') then
        return self:Fail(player, 'Return', 'coin')
    end
    if not self:Teleport(player, point.Destination) then
        data:AddCoin(point.Price, nil, 'ferry:return:refund')
        return self:Fail(player, 'Return', 'teleport')
    end
    data:SetZone(point.Zone)
    print('[MgrFerry] 返程', player.UserId, '-' .. tostring(point.Price),
        'FishCoin=' .. tostring(data.Data.FishCoin))
    self:Reply(player, { ok = true, action = 'Return', price = point.Price })
    return true
end

local Actions = { Board = 'Board', Return = 'ReturnBack' }

-- 序号契约与 MgrInteract 一致：每人严格递增，重放与旧序号不结算
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' then return false end
    local method = Actions[payload.action]
    local seq = payload.seq
    if not method or type(seq) ~= 'number' or seq ~= math.floor(seq) then return false end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return false end
    self.LastSeq[player.UserId] = seq
    return self[method](self, player, data)
end

-- 倒计时到点：带走船上所有人（搭便船）；没赶上船的留在原地，船票不退。
-- 锚点缺失属场景配置事故：航班取消并把船票退给交票人
function Mgr:Update()
    if not self.DepartAt then return end
    if self.World:GetServerTime() < self.DepartAt then return end
    self.DepartAt = nil
    local point = GameCfg.Ferry.Outbound
    local anchor = self.Interact:FindAnchor(point.AnchorName)
    local center = anchor and anchor.Position
    if not center then
        print('[MgrFerry] 找不到摆渡锚点，本次航班取消并退票', point.AnchorName)
        for _, player in ipairs(self:OnlinePlayers()) do
            if player.UserId == self.Payer then
                local data = self.PlayerData:GetDataInst(player)
                if data then data:AddItem(point.Ticket) end
            end
        end
        self.Payer = nil
        self:Broadcast({ phase = 'cancelled' })
        return
    end
    self.Payer = nil
    for _, player in ipairs(self:OnlinePlayers()) do
        local pos = player.Character and player.Character.Position
        if pos and flatDistance(pos, center) <= point.BoatRange
            and self:Teleport(player, point.Destination) then
            local data = self.PlayerData:GetDataInst(player)
            if data then data:SetZone(point.Zone) end
            print('[MgrFerry] 送达', player.UserId, point.Zone)
        end
    end
    self:Broadcast({ phase = 'departed' })
end

function Mgr:Start()
    self.World = self.World or game:GetService('World')
    _G.REUtil:GetRE('FerryAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'FerryAction', GameCfg.Items.ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
end

function Mgr:OnPlayerRemoving(player)
    self.LastSeq[player.UserId] = nil
end

return Mgr
