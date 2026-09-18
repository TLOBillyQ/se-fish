local FXUtil = {}
local World = game:GetService("World")
local Task = game:GetService("Task")

--fxId = "official://preset/2030"
--cframe 还未实装，尝试用transform 或者 pos/rot
function FXUtil:PlayFX(fxId, pos, rot, scale, keepTime)
    local duration = keepTime or -1
    local fxRoot = World:FindFirstChild("FX")

   -- print("[FXUtil] PlayFX() CreateUnit start")
    local effectUnit = World:CreateUnit("EffectUnit", {EffectId = fxId, Duration = duration}) --Duration在创建时设置，若Duration>0 则播放完毕后触发自动回收
    --print("[FXUtil] PlayFX() CreateUnit end", effectUnit)
    --长期使用可以考虑挂统一的父节点
    effectUnit.Parent = fxRoot

    effectUnit:SetPosition(pos)
    if rot then
        effectUnit:SetRotation(rot)
    end
    if scale then
        effectUnit:SetScale(scale)
    end

    --effectUnit:SetDuration(duration) --若对已创建的特效设置duration，则不会触发自动回收
    --effectUnit:SetVisible(true) --默认true

    --验证特效播放完毕自动删除的规则
    --[[
    print("[FX] Check FX", effectUnit:GetAllProps())
    Task:Delay(duration + 0.01, function() 
        print("[FX] Check FX delay", effectUnit, fxRoot:GetChildren())
    end)
    --]]
    return effectUnit
end

_G.FXUtil = FXUtil
return FXUtil