-- #53 官方指令只作用于真实受击体；轨迹交接先取消模式，再归还本体写入权。
local AiAPI = require('server.AiAPI')
local Mgr = { AiAPI = AiAPI, States = {} }

function Mgr:State(fish)
    local state = self.States[fish]
    if not state then state = {}; self.States[fish] = state end
    return state
end

function Mgr:Custom(fish)
    local state = self:State(fish)
    local carrier = fish.Carrier
    if state.Mode or not state.Initialized then
        local ok, err = pcall(function()
            self.AiAPI.StopAI(carrier.Receiver)
            self.AiAPI.StopMove(carrier.Receiver, 0)
            local p, offset = carrier.Body.Position, carrier.ReceiverOffset
            carrier.Receiver.Position = Vector3.New(p.x + (offset and offset.x or 0),
                p.y + (offset and offset.y or 0), p.z + (offset and offset.z or 0))
        end)
        state.Initialized = true
        state.Mode, state.Target, state.Direction = nil, nil, nil
        carrier.AiOwnsMovement = false
        if not ok then print('[MgrAi] 停止指令失败', fish.Id, tostring(err)); state.Failed = true; return false end
    end
    carrier.AiOwnsMovement = false
    return true
end

function Mgr:Pause(fish, paused)
    local state = self:State(fish)
    if paused then self:Custom(fish) end
    state.Paused = paused == true
end

function Mgr:Command(fish, mode, target, direction, speed, distance, range)
    local state = self:State(fish)
    if self.Stopped or state.Paused or state.Failed then return false end
    local carrier = fish.Carrier
    local unit = carrier and carrier.Receiver
    if not unit or not unit.Controller then
        print('[MgrAi] 受击体缺少Controller', fish.Id)
        state.Failed = true
        return false
    end
    if state.Mode == mode and state.Target == target and state.Direction == direction and state.Speed == speed then return true end
    if not self:Custom(fish) then return false end
    local ok, err = pcall(function()
        local p, offset = carrier.Body.Position, carrier.ReceiverOffset
        unit.Position = Vector3.New(p.x + (offset and offset.x or 0),
            p.y + (offset and offset.y or 0), p.z + (offset and offset.z or 0))
        unit.Controller.WalkSpeed = speed
        self.AiAPI.StartAI(unit)
        self.AiAPI.StopMove(unit, 0)
        if mode == 'direction' then self.AiAPI.MoveDirection(unit, direction, 0, 0)
        else self.AiAPI.ChaseTarget(unit, target, range or 0, distance or 0.1, 0, nil, 0, 1) end
    end)
    if not ok then
        print('[MgrAi] 指令启动失败', fish.Id, mode, tostring(err))
        state.Mode = mode
        self:Custom(fish)
        state.Failed = true
        return false
    end
    state.Mode, state.Target, state.Direction, state.Speed = mode, target, direction, speed
    carrier.AiOwnsMovement = true
    return true
end

function Mgr:MoveDirection(fish, direction, speed)
    return self:Command(fish, 'direction', nil, direction, speed)
end

function Mgr:Chase(fish, target, speed, distance, range)
    return self:Command(fish, 'chase', target, nil, speed, distance, range)
end

function Mgr:Sync(fish)
    if self:State(fish).Failed then return false end
    local carrier = fish.Carrier
    if not carrier.AiOwnsMovement then return true end
    local ok, err = pcall(function()
        local p = carrier.Receiver.Position
        for _, key in ipairs({ 'x', 'y', 'z' }) do
            local value = p and p[key]
            assert(type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge,
                '受击体坐标异常：' .. key)
        end
        local offset = carrier.ReceiverOffset or Vector3.New(0, 0, 0)
        carrier.Body.Position = Vector3.New(p.x - offset.x, p.y - offset.y, p.z - offset.z)
        carrier.Body.LinearVelocity = Vector3.New(0, 0, 0)
    end)
    if not ok then
        print('[MgrAi] 官方位移镜像失败', fish.Id, tostring(err))
        self:Custom(fish)
        self:State(fish).Failed = true
    end
    return ok
end

function Mgr:Remove(fish)
    self:Custom(fish)
    self.States[fish] = nil
end

function Mgr:Start()
    self.Stopped = false
    for _, state in pairs(self.States) do state.Paused = false end
end

function Mgr:Stop()
    self.Stopped = true
    for fish in pairs(self.States) do self:Pause(fish, true) end
end

return Mgr
