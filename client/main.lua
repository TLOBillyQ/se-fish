local LocalMgrUtil = require("client.LocalMgrUtil")
LocalMgrUtil:Start()

local Task = game:GetService("Task")

local LocalMotorUnitCtrl = require("client.LocalMotorUnitCtrl")
local LocalFishEnter = require("client.LocalFishEnter")

Task:Spawn(function() 
    LocalMotorUnitCtrl:Start()
    LocalFishEnter:Start()
end)
Task:Delay(1, function() 
    _G.MgrGameUI:OpenScreen("ScreenMsg")
end)







