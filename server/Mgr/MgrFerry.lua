-- #127 T06 六条航线摆渡：请求必须带航线 id，锚点、目的地、船票与票价全部由这条航线给出；
-- 伪造 / 未登记的 id 直接拒收，越界与缺票缺币各自拒绝且不动账。
-- 每条航线有自己的航班状态（Flights[routeId]）与自己的交票写入（BoardPending[routeId]），
-- 不同航线互不占用倒计时；同一条航线倒计时中再交票拒绝且不扣。
-- 去程一人交 1 张票、倒计时（5 秒）后带走 BoatRange 内的所有人（搭便船合法、未赶上不退票）；
-- 返程按人付 10 × 3^(到达区序 − 2) 金币、立即传送。
-- #123：交票与返程扣款先经 Save.Execute 持久，再发布倒计时或传送。传送和存储不能原子提交：
-- 收费同时保存恢复记录，完成或补偿用独立幂等操作落账；未确认的跨会话记录只退款，不重放传送。
-- 扣费、搭载、到达（Extra.travel.arrived）与恢复结果都落进存档，重进后仍可验证。
-- FerryAction{action='Board'|'Return', routeId, seq, requestId?}；跨会话 requestId 为 FerryResult.operation。
-- 锚点缺失取消航班退票；交票人在倒计时中掉线同样取消该航线航班。
local GameCfg = require('common.GameCfg')

local Mgr = { LastSeq = {}, Recoveries = {}, ReturnPending = {}, Flights = {}, BoardPending = {} }

local function flatDistance(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- 到达记录（#127）：每区一份到达计数，跟落点一起写进 draft.Extra.travel.arrived；
-- 重放只回原结果不再执行，所以同一趟不会重复计数。
local function markArrival(draft, zone)
    local arrived = draft.Extra.travel.arrived
    arrived[zone] = (arrived[zone] or 0) + 1
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('FerryResult'):FireClient(player, payload)
end

function Mgr:Broadcast(payload)
    _G.REUtil:GetRE('FerryState'):FireAllClients(payload)
end

function Mgr:Fail(player, action, reason)
    print('[MgrFerry] 请求拒绝', player.UserId, action, tostring(reason))
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
    if not character then
        print('[MgrFerry] 传送失败', player and player.UserId, '角色缺失')
        return false
    end
    local ok, err = pcall(function()
        local pos = Vector3.New(dest.x, dest.y, dest.z)
        if character.SetPosition then
            character:SetPosition(pos)
        else
            character.Position = pos
        end
    end)
    if not ok then print('[MgrFerry] 传送失败', player.UserId, tostring(err)) end
    return ok
end

-- 所有财产变更只写 Save 的隔离 draft；同步拒绝仍返回 false，异步接纳返回 true。
function Mgr:Settle(player, data, kind, transform, done, operation)
    operation = operation or self.Save:NextOperation(player, kind)
    if not operation then return false, 'save' end
    local outcome
    local accepted, reason = self.Save:Execute(player, data, operation, transform, function(ok, result)
        outcome = ok
        if not ok then print('[MgrFerry] 结算失败', player.UserId, operation.id, kind, tostring(result)) end
        done(ok, result)
    end)
    if not accepted then print('[MgrFerry] 结算未接纳', player.UserId, operation.id, kind, tostring(reason)) end
    return accepted and outcome ~= false, reason
end

-- 这条航线上是否有一位玩家正在交票落账（返回航班对象，没有就 nil）
function Mgr:PendingFlight(routeId)
    return self.BoardPending[routeId] or self.Flights[routeId]
end

function Mgr:Board(player, data, route, operation)
    local point = route.Outbound
    if self:PendingFlight(route.Id) then return self:Fail(player, 'Board', 'sailing') end
    if not self.Interact:InRange(player, point) then return self:Fail(player, 'Board', 'range') end
    local flight = { player = player, operation = operation.id, routeId = route.Id }
    self.BoardPending[route.Id] = flight
    local accepted, reason = self:Settle(player, data, 'ferry:board', function(draft)
        if not draft:ConsumeItem(point.Ticket) then return nil, 'ticket' end
        draft.Extra.recovery.ferry = { operation = operation.id, identity = operation, action = 'Board',
            routeId = route.Id, ticket = point.Ticket, zone = point.Zone, state = 'pending' }
        return { ok = true, action = 'Board', routeId = route.Id, seconds = point.CountdownSec,
            operation = operation }
    end, function(ok, result)
        if self.BoardPending[route.Id] ~= flight then return end
        self.BoardPending[route.Id] = nil
        if not ok then self:Fail(player, 'Board', result) return end
        self.Flights[route.Id] = { player = player, operation = operation.id, routeId = route.Id,
            DepartAt = self.World:GetServerTime() + point.CountdownSec }
        print('[MgrFerry] 船票落账，开船倒计时', player.UserId, route.Id, operation.id)
        self:Broadcast({ phase = 'countdown', routeId = route.Id, seconds = point.CountdownSec })
        self:Reply(player, result)
    end, operation)
    if not accepted and self.BoardPending[route.Id] == flight then
        self.BoardPending[route.Id] = nil
        return self:Fail(player, 'Board', reason or 'save')
    end
    return accepted
end

-- 外部传送结果与补偿各自落账，退款只能改 draft，记录清除与退款是同一次写入。
function Mgr:FinishTravel(player, data, record, delivered, reason, done)
    return self:Settle(player, data, delivered and 'ferry:confirm' or 'ferry:refund', function(draft)
        local pending = draft.Extra.recovery.ferry
        if not pending or pending.operation ~= record.operation then return nil, 'recovery' end
        if delivered then
            if record.zone then
                draft:SetZone(record.zone)
                markArrival(draft, record.zone)
            end
        elseif record.action == 'Board' then
            if not draft:AddItem(record.ticket) then return nil, 'full' end
        elseif not draft:AddCoin(record.price, nil, 'ferry:return:refund') then return nil, 'coin' end
        draft.Extra.recovery.ferry = nil
        local result = { ok = delivered, action = record.action, routeId = record.routeId,
            price = record.price, operation = record.identity, reason = not delivered and reason or nil }
        local finals = {}
        for _, prior in ipairs(draft.SaveMeta.operations) do
            local kept = draft.Extra.recovery.ferryFinal and draft.Extra.recovery.ferryFinal[prior.id]
            if kept then finals[prior.id] = kept end
        end
        finals[record.operation] = result
        draft.Extra.recovery.ferryFinal = finals
        return result
    end, done)
end

function Mgr:ReturnBack(player, data, route, operation)
    local point = route.Return
    if not self.Interact:InRange(player, point) then return self:Fail(player, 'Return', 'range') end
    local record = { operation = operation.id, identity = operation, action = 'Return', routeId = route.Id,
        price = point.Price, state = 'pending', zone = point.Zone }
    self.ReturnPending[player.UserId] = record
    local outcome
    local accepted, reason = self:Settle(player, data, 'ferry:return', function(draft)
        if not draft:SpendCoin(point.Price, nil, 'ferry:return') then return nil, 'coin' end
        draft.Extra.recovery.ferry = record
        return { ok = true, action = 'Return', routeId = route.Id, price = point.Price, operation = operation }
    end, function(ok, result)
        if self.ReturnPending[player.UserId] ~= record then return end
        if not ok then
            self.ReturnPending[player.UserId] = nil
            outcome = false self:Fail(player, 'Return', result) return
        end
        local delivered = self:Teleport(player, point.Destination)
        outcome = delivered
        self:FinishTravel(player, data, record, delivered, 'teleport', function(written, final)
            if self.ReturnPending[player.UserId] ~= record then return end
            self.ReturnPending[player.UserId] = nil
            if written then self:Reply(player, final) else self:Fail(player, 'Return', final) end
        end)
    end, operation)
    if not accepted and outcome == nil then
        self.ReturnPending[player.UserId] = nil
        return self:Fail(player, 'Return', reason or 'save')
    end
    return accepted and outcome ~= false
end

local Actions = { Board = 'Board', Return = 'ReturnBack' }

-- 序号契约与 MgrInteract 一致：每人严格递增，重放与旧序号不结算。
-- 航线 id 在取存档之前先校验：查不到这条航线，后面的一切（NPC、目的地、船票）都无从谈起。
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' then return false end
    local method = Actions[payload.action]
    local seq = payload.seq
    if not method or type(seq) ~= 'number' or seq ~= math.floor(seq) then return false end
    local route = GameCfg.Ferry.Route(payload.routeId)
    if not route then return self:Fail(player, payload.action, 'route') end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    if not self.Save or not data.Inited or self.Save:IsPaused(player.UserId) then
        return self:Fail(player, payload.action, 'save')
    end
    local kind = payload.action == 'Board' and 'ferry:board' or 'ferry:return'
    local operation, status = self.Save:ResolveRequest(player, data, kind, payload.requestId or seq)
    if not operation then return self:Fail(player, payload.action, status) end
    if status == 'replay' then
        -- 旧客户端的 seq 重放仍拒绝；显式 requestId 只回历史包，不重新启动外部权益。
        if payload.requestId == nil then return false end
        local flight = self:PendingFlight(route.Id)
        local active = flight and flight.player == player and flight.operation == operation.id
        if data.Extra.recovery.ferry and not active then
            self:Recover(player, data)
            local final = data.Extra.recovery.ferryFinal and data.Extra.recovery.ferryFinal[operation.id]
            if final then self:Reply(player, final) return true end
            return self:Fail(player, payload.action, 'pending')
        end
        return self:Settle(player, data, kind, function() return nil, 'replay' end, function(ok, result)
            if ok then
                local final = data.Extra.recovery.ferryFinal and data.Extra.recovery.ferryFinal[operation.id]
                self:Reply(player, final or result)
            else self:Fail(player, payload.action, result) end
        end, operation)
    end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return false end
    self.LastSeq[player.UserId] = seq
    if data.Extra.recovery.ferry then
        self:Recover(player, data)
        return self:Fail(player, payload.action, 'pending')
    end
    return self[method](self, player, data, route, operation)
end

-- 倒计时到点：带走船上所有人（搭便船）；没赶上船的留在原地，船票不退。
-- 锚点缺失属场景配置事故：这条航线取消并把船票退给交票人
function Mgr:Depart(route, flight)
    local point = route.Outbound
    local anchor = self.Interact:FindAnchor(point.AnchorName)
    local center = anchor and anchor.Position
    if not center then
        print('[MgrFerry] 找不到摆渡锚点，本次航班取消并退票', route.Id, point.AnchorName)
        for _, player in ipairs(self:OnlinePlayers()) do
            if player.UserId == flight.player.UserId then
                local data = self.PlayerData:GetDataInst(player)
                local record = data and data.Extra.recovery.ferry
                if record then
                    self:FinishTravel(player, data, record, false, 'anchor', function(ok, result)
                        if ok then self:Reply(player, result) end
                    end)
                end
            end
        end
        self:Broadcast({ phase = 'cancelled', routeId = route.Id })
        return
    end
    local payer = flight.player
    for _, player in ipairs(self:OnlinePlayers()) do
        local data = self.PlayerData:GetDataInst(player)
        local pos = player.Character and player.Character.Position
        local aboard = pos and flatDistance(pos, center) <= point.BoatRange
        if data and data.Inited and not self.Save:IsPaused(player.UserId) then
            local delivered = aboard and self:Teleport(player, point.Destination)
            if player == payer and data.Extra.recovery.ferry then
                local record = data.Extra.recovery.ferry
                if delivered then record.zone = point.Zone end
                -- 未赶上船照常消费；角色在船上但传送失败才补偿。
                self:FinishTravel(player, data, record, not aboard or delivered, 'teleport', function() end)
            elseif delivered then
                self:Settle(player, data, 'ferry:ride', function(draft)
                    draft:SetZone(point.Zone)
                    markArrival(draft, point.Zone)
                    return { ok = true, action = 'Board', routeId = route.Id }
                end, function() end)
            end
            if delivered then print('[MgrFerry] 送达', player.UserId, route.Id, point.Zone) end
        end
    end
    self:Broadcast({ phase = 'departed', routeId = route.Id })
end

-- 收起未完成记录（掉线、待确认）：交票人退款、返程退款，一次写入清记录。
function Mgr:Recover(player, data)
    local record = data.Extra.recovery.ferry
    if not record then return false end
    local flight = record.routeId and self:PendingFlight(record.routeId)
    if flight and flight.player == player and flight.operation == record.operation then return true end
    if self.Recoveries[player.UserId] then return true end
    self.Recoveries[player.UserId] = player
    local accepted = self:FinishTravel(player, data, record, false, 'interrupted', function(ok, result)
        if self.Recoveries[player.UserId] == player then self.Recoveries[player.UserId] = nil end
        if ok then self:Reply(player, result) end
    end)
    if not accepted then self.Recoveries[player.UserId] = nil end
    return true
end

function Mgr:Update()
    if self.Save then
        for _, player in ipairs(self:OnlinePlayers()) do
            local data = self.PlayerData:GetDataInst(player)
            if data and data.Inited and not self.Save:IsPaused(player.UserId) then self:Recover(player, data) end
        end
    end
    local now = self.World:GetServerTime()
    for _, route in ipairs(GameCfg.Ferry.Routes) do
        local flight = self.Flights[route.Id]
        if flight and now >= flight.DepartAt then
            self.Flights[route.Id] = nil
            self:Depart(route, flight)
        end
    end
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
    self.Recoveries[player.UserId] = nil
    self.ReturnPending[player.UserId] = nil
    for routeId, flight in pairs(self.BoardPending) do
        if flight.player == player then self.BoardPending[routeId] = nil end
    end
    for routeId, flight in pairs(self.Flights) do
        if flight.player == player then
            self.Flights[routeId] = nil
            self:Broadcast({ phase = 'cancelled', routeId = routeId })
        end
    end
end

return Mgr
