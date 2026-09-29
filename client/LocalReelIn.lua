local REUtil = require('common.REUtil')
local RateLimit = require('common.RateLimit')
local GameCfg = require('common.GameCfg')
local ReelDisplay = require('common.ReelDisplay')

local LocalReelIn = { SessionId = nil }
LocalReelIn.CHANNEL = 'ReelInRE'

function LocalReelIn:SetSession(id)
    if type(id) ~= 'string' or id == '' or self.ClosedSession == id then return false end
    if self.SessionId == id then return true end
    self.SessionId = id
    self.Aggregator = RateLimit.NewAggregator({ SessionId = id,
        AggregateSec = GameCfg.HighFreqInput.AggregateSec })
    self.Display = ReelDisplay.New(self.World:GetServerTime(), GameCfg.ReelIn)
    return true
end

function LocalReelIn:Send(payload)
    if not payload then return end
    if self.Display then self.Display:Sent(payload.q, payload.n, self.World:GetServerTime()) end
    self.RE:FireServer(payload)
end

function LocalReelIn:Flush()
    if not self.Aggregator then return end
    self:Send(self.Aggregator:Flush())
end

function LocalReelIn:Click()
    if not self.Aggregator then return end
    local now = self.World:GetServerTime()
    self.Aggregator:Click(now)
    if self.Display then self.Display:Click(now) end
end

-- 当前会话的显示进度（本地反馈 + 平滑追平）；没有会话返回 nil
function LocalReelIn:DisplayProgress()
    return self.Display and self.Display:Value(self.World:GetServerTime()) or nil
end

function LocalReelIn:Close(id)
    local session = id or self.SessionId
    if not session or (self.SessionId and self.SessionId ~= session)
        or self.ClosedSession == session then return end
    local payload = self.Aggregator and self.Aggregator:Flush()
    self.ClosedSession = session
    self.SessionId = nil
    self.Aggregator = nil
    self.Display = nil
    if payload then self.RE:FireServer(payload) end
    self.CloseRE:FireServer({ session = session })
end

-- #133 界面被遮挡只是表现：待发批次先送出去（C-10），会话、序号与本地进度原样保留。
-- 不主动收线——服务端照常按权威时钟衰减，到 0 由服务端判脱钩，重开界面接着显示同一个进度。
-- 这里不做本地暂停：留一个「暂停中」标志只会让人以为计时停了，实际权威进度仍在下降。
function LocalReelIn:Suspend()
    if self.Aggregator then self:Flush() end
end

function LocalReelIn:Clear(id)
    if not id or self.SessionId ~= id then return end
    self.ClosedSession = id
    self.SessionId = nil
    self.Aggregator = nil
    self.Display = nil
end

function LocalReelIn:Stop()
    self:Close()
    if self.Connection then self.Connection:Disconnect() end
    if self.UpdateConnection then self.UpdateConnection:Disconnect() end
    self.Connection = nil
    self.UpdateConnection = nil
    self.World = nil
    self.RE = nil
    self.CloseRE = nil
end

function LocalReelIn:Start()
    if self.Connection then return end
    self.World = game:GetService('World')
    self.RE = REUtil:GetRE(self.CHANNEL)
    self.CloseRE = REUtil:GetRE('CloseReelIn')
    self.Connection = self.RE.OnClientEvent:Connect(function(payload)
        if type(payload) ~= 'table' or type(payload.session) ~= 'string' then return end
        if payload.action == 'started' then
            if not self:SetSession(payload.session) then return end
        elseif self.SessionId ~= payload.session then return end
        self.LastResult = payload
        if self.Display and (payload.action == 'progress' or payload.action == 'started') then
            self.Display:Authority(self.World:GetServerTime(), payload.progress, payload.q)
        end
        if payload.action == 'landed' or payload.action == 'unhooked' then
            self:Clear(payload.session)
        end
    end)
    self.UpdateConnection = game:GetService('RunService').Heartbeat:Connect(function()
        if self.Aggregator then
            self:Send(self.Aggregator:Collect(self.World:GetServerTime()))
        end
    end)
end

return LocalReelIn
