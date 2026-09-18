local Util = {}
local Task = game:GetService("Task")
local RunService = game:GetService("RunService")
local World = game:GetService("World")
local REUtil = require("common.REUtil")
--local NotificationService = game:GetService("NotificationService")

function Util:WaitForChild(rootObj, childName, waitTime)
	if not rootObj then
		return 
	end
	if not waitTime then waitTime = 10 end
	local costTime = 0
	while rootObj and costTime < waitTime do
		local childObj = rootObj:FindFirstChild(childName)
		if childObj then 
			--print("[ShaoTest] WaitForChild break", childObj, costTime)
			return childObj
		 end
		Task:Wait(0.033) 
		costTime = costTime + 0.033
	end

	print("[Util] WaitForChild time end", childName, waitTime)
	return
end	

function Util:MsgNotice(player, msg, duration, textColor)
	--NotificationService:ShowTips(msg, player, duration)
	if RunService:IsServer() then
		REUtil:GetRE("MsgNoticeRE"):FireClient(player, msg, duration, textColor)
		return
	end

	if not _G.LocalMsgNotice then 
		print("_G.LocalMsgNotice 未初始化")
		return 
	end

	_G.LocalMsgNotice(msg, duration, textColor)
end

function Util:GlobalMsgNotice(msg, duration, textColor)
	--work in server
	if RunService:IsClient() then
		print("GlobalMsgNotice 只在服务端调用")
		return
	end

	REUtil:GetRE("MsgNoticeRE"):FireAllClients(msg, duration, textColor)
end

if RunService:IsClient() then
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	REUtil:GetRE("MsgNoticeRE").OnClientEvent:Connect(function(msg, duration, textColor) 
		Util:MsgNotice(LocalPlayer, msg, duration, textColor)
	end)
end

--[[
function Util:MsgMarquee(player, msg)
	NotificationService:ShowMarquee(msg, player)
end

function Util:GlobalMarquee(msg)
	--work in server
	if RunService:IsClient() then
		REUtil:GetRE("GlobalMarquee"):FireServer(msg)
		return
	end
	NotificationService:ShowMarquee(msg)
end
--]]

if RunService:IsServer() then
	REUtil:GetRE("GlobalMarquee").OnServerEvent:Connect(function(p, msg) 
		Util:GlobalMarquee(msg)
	end)
end

function Util:PopNoticeConfirm(msg, callBack)
	if RunService:IsServer() then
		print("[Util] PopConfirmYesNo Client only!")
		return
	end

	_G.MgrGameUI:OpenScreen("DialogNoticeConfirm", {Msg = msg, CallBack = callBack},true)
end

function Util:SplitString(inputstr, sep) 
	if sep == nil then
        sep = "%s"
    end

    local t = {}
    local i = 1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        t[i] = str
        i = i + 1
    end
	--print("[Util] SplitString rst = ", t)
	return t
end

function Util:WeldTo(unit, toUnit)
	local connectDict = {}
	connectDict[unit.UnitId] = true
	connectDict[toUnit.UnitId] = true
	-- 创建焊接约束，RootUnitId 指定根单位
	local weld = World:CreateUnit("WeldConstraint", {
		ConnectUnitIdDict = connectDict,
		RootUnitId = toUnit.UnitId,
		Parent = unit
	})
	return weld
end

function Util:MarkPointPart(position, color, keepTime)
	if not color then color = tonumber("ff0000", 16) end
	local part = World:CreateUnit("WorldUnit", {
		Position = position,
		ModelColor1 = color,
		Scale = Vector3(0.5, 0.5, 0.5),
		PhysicsActive = false,
		BodyType = Enums.BodyType.Kinematic,
	})

	if keepTime then
		Task:Delay(keepTime, function() 
			part:Destroy()
		end)
	end

	return part
end

function Util:RandomDirection(detailRange, ignoreY)
	if not detailRange then
		detailRange = 10
	end
	if ignoreY == nil then
		ignoreY = true
	end
	local x = math.random(-detailRange, detailRange)
	local y = ignoreY and 0 or math.random(-detailRange, detailRange)
	local z = math.random(-detailRange, detailRange)
	return Vector3(x, y, z).Unit
end

local NumWithStrMap = {
	{
		Str = "K",
		Value = 1000,		--千
	},
	{
		Str = "M",
		Value = 1000000,	--百万
	},
	{
		Str = "B",
		Value = 1000000000,	--十亿
	},
}

--简化大数字
function Util:DesignNumber(value, keepNum)
	if value < 0 then return tostring(value) end --简单排除负数

	local curNumInfo = nil
	for i, info in ipairs(NumWithStrMap) do
		if value > info.Value then
			curNumInfo = info
		else
			break
		end	
	end

	if not curNumInfo then return tostring(value) end

	if not keepNum then keepNum = 2 end

	local formatKey = "%." .. keepNum ..  "f" ..curNumInfo.Str
	return string.format(formatKey, value/curNumInfo.Value)
end

_G.Util = Util
return Util
