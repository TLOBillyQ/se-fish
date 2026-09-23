local REUtil = require('common.REUtil')
local RateLimit = require('common.RateLimit')
local GameCfg = require('common.GameCfg')

local LocalReelIn = { SessionId = nil }
LocalReelIn.CHANNEL = 'ReelInRE'

function LocalReelIn:SetSession(id)
    if type(id) ~= 'string' or id == '' or self.Suspended or self.ClosedSession == id then return false end
    if self.SessionId == id then return true end
    self.SessionId = id
    self.Aggregator = RateLimit.NewAggregator({ SessionId = id,
        AggregateSec = GameCfg.HighFreqInput.AggregateSec })
    return true
end

function LocalReelIn:Flush()
    if not self.Aggregator then return end
    local payload = self.Aggregator:Flush()
    if payload then self.RE:FireServer(payload) end
end

function LocalReelIn:Click()
    if not self.Aggregator then return end
    self.Aggregator:Click(self.World:GetServerTime())
end

function LocalReelIn:Close(id)
    local session = id or self.SessionId
    if not session or (self.SessionId and self.SessionId ~= session)
        or self.ClosedSession == session then return end
    local payload = self.Aggregator and self.Aggregator:Flush()
    self.ClosedSession = session
    self.SessionId = nil
    self.Aggregator = nil
    if payload then self.RE:FireServer(payload) end
    self.CloseRE:FireServer({ session = session })
end

function LocalReelIn:Suspend(id)
    self.Suspended = true
    self:Close(id)
end

function LocalReelIn:Resume()
    self.Suspended = false
end

function LocalReelIn:Clear(id)
    if not id or self.SessionId ~= id then return end
    self.ClosedSession = id
    self.SessionId = nil
    self.Aggregator = nil
end

function LocalReelIn:Start()
    self.World = game:GetService('World')
    self.RE = REUtil:GetRE(self.CHANNEL)
    self.CloseRE = REUtil:GetRE('CloseReelIn')
    self.Connection = self.RE.OnClientEvent:Connect(function(payload)
        if type(payload) ~= 'table' or type(payload.session) ~= 'string' then return end
        if payload.action == 'started' then
            if self.Suspended then self:Close(payload.session) end
            if not self:SetSession(payload.session) then return end
        elseif self.SessionId ~= payload.session then return end
        self.LastResult = payload
        if payload.action == 'landed' or payload.action == 'unhooked' then
            self:Clear(payload.session)
        end
    end)
    self.UpdateConnection = game:GetService('RunService').Heartbeat:Connect(function()
        if self.Aggregator then
            local payload = self.Aggregator:Collect(self.World:GetServerTime())
            if payload then self.RE:FireServer(payload) end
        end
    end)
end

return LocalReelIn
