local ReelProgress = {}
ReelProgress.__index = ReelProgress

function ReelProgress.New(now, cfg)
    return setmetatable({ Progress = cfg.Initial, Time = now, ZeroAt = nil,
        Result = nil, Config = cfg }, ReelProgress)
end

function ReelProgress:Advance(now, count, span)
    if self.Result then return self.Result end
    now = math.max(now, self.Time)
    local cfg = self.Config
    local function step(at)
        if self.Result then return end
        local elapsed = at - self.Time
        if elapsed > 0 then
            local before = self.Progress
            self.Progress = math.max(0, before - cfg.DecayPerSec * elapsed)
            if before > 0 and self.Progress == 0 then
                self.ZeroAt = self.Time + before / cfg.DecayPerSec
            end
            self.Time = at
        end
        if self.ZeroAt and at > self.ZeroAt + cfg.GraceSec then
            self.Result = 'unhooked'
        end
    end
    count = count or 0
    local first = math.max(self.Time, now - (span or 0))
    for i = 1, count do
        step(first + (now - first) * i / count)
        if self.Result then return self.Result end
        self.Progress = math.min(100, self.Progress + cfg.ClickGain)
        if self.Progress > 0 then self.ZeroAt = nil end
        if self.Progress == 100 then self.Result = 'landed' end
    end
    step(now)
    return self.Result
end

return ReelProgress
