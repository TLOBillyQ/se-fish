local REUtil = {}

local World = game:GetService("World")
local RunService = game:GetService("RunService")

REUtil.REMap = {}


local RECDCheckMap = {}

function REUtil:GetRE(eventName)
    local targetRE = REUtil.REMap[eventName]
    if not targetRE then 
        targetRE = game:CreateRemoteEvent(eventName)
        REUtil.REMap[eventName] = targetRE
        print("[REUtil] CreateRemoteEvent", eventName)
    end
    
    return targetRE
end

--CD拦截成功Return true 
function REUtil:CheckRECD(player, reName, duration)
    if not duration then duration = 1 end

    local pMap = RECDCheckMap[player.UserId]
    if not pMap then
        pMap = {}
        RECDCheckMap[player.UserId] = pMap
    end

    local workTime = pMap[reName]
    local nowTime = World:GetServerTime()
    if not workTime or workTime < nowTime then
        pMap[reName] = nowTime + duration
        return
    end

    return true
end

if RunService:IsServer() then
    local Players = game:GetService("Players")
    Players.PlayerRemoving:Connect(function(player)
        RECDCheckMap[player.UserId] = nil        
    end)
end

_G.REUtil = REUtil
return REUtil