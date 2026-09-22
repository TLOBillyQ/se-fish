local LocalMgrUtil = require("client.LocalMgrUtil")
LocalMgrUtil:Start()

local Task = game:GetService("Task")

local LocalMotorUnitCtrl = require("client.LocalMotorUnitCtrl")
local LocalFishEnter = require("client.LocalFishEnter")
local LocalAttackButton = require("client.LocalAttackButton")
local LocalReelIn = require("client.LocalReelIn")

-- 运行时 require 失败只进日志并返回 nil，所以这里判一次再调
local AbilityAPI = require("client.AbilityAPI")
if AbilityAPI then
    AbilityAPI.StartClientLifecycle()
end

Task:Spawn(function() 
    LocalMotorUnitCtrl:Start()
    LocalFishEnter:Start()
    LocalAttackButton:Start()
    LocalReelIn:Start()
end)
Task:Delay(1, function() 
    _G.MgrGameUI:OpenScreen("ScreenMsg")
end)







