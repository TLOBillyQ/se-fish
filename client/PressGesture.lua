-- #129 按压手势状态机（纯 Lua，无引擎依赖，便于 headless 测试）：
-- 区分「点按」（短按松手）与「长按」（达到阈值即触发选点模式），滑出容差则取消。
-- 武器按钮：点按=普通攻击/直接投掷，长按=换弹/瞄准选点。
local Gesture = {}
Gesture.__index = Gesture

local DEFAULTS = {
    LongPressSec = 0.35,   -- 与 GameCfg.Ability.Throw.LongPressSec 同票面（暂取值）
    MoveTolerancePx = 12,  -- 滑动容差：超过视为拖动取消（像素，按 1080p 手感暂取）
}

function Gesture.New(opts)
    opts = opts or {}
    local self = setmetatable({}, Gesture)
    self.LongPressSec = opts.LongPressSec or DEFAULTS.LongPressSec
    self.MoveTolerancePx = opts.MoveTolerancePx or DEFAULTS.MoveTolerancePx
    self.Active = false
    return self
end

local function movedFar(self, pos)
    if not pos or not self.StartPos then return false end
    local dx, dy = pos.x - self.StartPos.x, pos.y - self.StartPos.y
    return dx * dx + dy * dy > self.MoveTolerancePx * self.MoveTolerancePx
end

function Gesture:Begin(t, pos)
    self.Active = true
    self.StartT = t
    self.StartPos = pos and { x = pos.x, y = pos.y } or nil
    self.LongFired = false
    self.Canceled = false
    return true
end

-- 返回 true 表示本次 Update 触发了长按（只触发一次）
function Gesture:Update(t)
    if not self.Active then return false end
    if self.Canceled or self.LongFired then return false end
    if t - (self.StartT or t) >= self.LongPressSec then
        self.LongFired = true
        return true
    end
    return false
end

-- 返回 'tap' / 'long' / nil（取消）；nil 时调用方不应触发任何动作
function Gesture:End(t, pos)
    if not self.Active then return nil end
    self.Active = false
    if self.LongFired then return 'long' end
    if self.Canceled or movedFar(self, pos) then return nil end
    if t - (self.StartT or t) >= self.LongPressSec then return 'long' end
    return 'tap'
end

-- 滑动更新（按下期间移动）：长按未触发前滑出容差即取消
function Gesture:Move(pos)
    if not self.Active or self.LongFired then return end
    if movedFar(self, pos) then self.Canceled = true end
end

return Gesture
