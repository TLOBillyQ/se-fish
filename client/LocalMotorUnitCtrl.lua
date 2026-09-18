local World = game:GetService("World")
local ctrl = {}
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Task = game:GetService("Task")

function ctrl:DoLocalMotor(unit)
    local RotateSpd = unit:GetAttribute("RegRotate")
    if RotateSpd then
        self:TweenRotate(unit)
    end

    local TweenPosition = unit:GetAttribute("LocalTweenPosition")
    if TweenPosition then
        self:TweenPosition(unit)
    end

    if unit.Name == "LocalMotorUnit" and unit:IsA("BaseMotorUnit") then
        print("DoLocalMotor", unit.Parent.Name)
        unit.IsActive = true
        unit:Start()
    end
end

function ctrl:TweenRotate(unit)
    local RotateSpd = unit:GetAttribute("RegRotate")
    if not RotateSpd then return end
    --local DelayTime = unit:GetAttribute("DelayTime")
    local connection = nil

    local rv = unit.Rotation:GetVectorV()
    local orginV = Vector3(math.deg(rv.x), math.deg(rv.y), math.deg(rv.z))
    
    connection = RunService.Heartbeat:Connect(function(dt)
        if (not unit or not unit.Parent) and connection then
            connection:Disconnect()
            connection = nil
            return
        end
        orginV = orginV + RotateSpd* dt
        unit.Rotation = Quaternion.FromEulerAngles(math.rad(orginV.x), math.rad(orginV.y), math.rad(orginV.z))
    end)
end

function ctrl:TweenPosition(unit)
    local offsetPos = unit:GetAttribute("LocalTweenPosition")
    if not offsetPos then return end

    local Time = unit:GetAttribute("Time") or 2
    local DelayTime = unit:GetAttribute("DelayTime") or 0
    local IsReverse = unit:GetAttribute("IsReverse")
    local Loop = unit:GetAttribute("Loop") or -1
    
    local tweenInfo = TweenInfo.New(Time, EasingStyle.Linear, EasingDirection.InOut, Loop, IsReverse, DelayTime)
    local goal = { Position = unit.Position + offsetPos}
    -- 创建 Tween 对象
    local tween = TweenService:Create(unit, tweenInfo, goal)
    -- 播放 Tween
    if tween then
        tween:Play()
    end
end

function ctrl:Start()
    if ctrl.Inited then return end
    
    ctrl.Inited = true
    local allUnit = World:GetDescendants()
    for k,v in pairs(allUnit) do
        ctrl:DoLocalMotor(v)
    end

    World.DescendantAdded:Connect(function(unit) 
        ctrl:DoLocalMotor(unit)
    end)
end

return ctrl