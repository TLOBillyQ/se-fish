local LocalMgrUtil = require("client.LocalMgrUtil")
LocalMgrUtil:Start()

local Task = game:GetService("Task")

-- 原生「举起」按钮在客户端发起的抓举无效、举着时再按有甩鱼风险，举鱼一律由服务端发起（#41）
_G.MgrGameUI:HideLiftButton()

local LocalMotorUnitCtrl = require("client.LocalMotorUnitCtrl")
local LocalAttackButton = require("client.LocalAttackButton")
local LocalReelIn = require("client.LocalReelIn")
local LocalLoot = require("client.LocalLoot")
local LocalInteract = require("client.LocalInteract")

-- 运行时 require 失败只进日志并返回 nil，所以这里判一次再调
local AbilityAPI = require("client.AbilityAPI")
if AbilityAPI then
    AbilityAPI.StartClientLifecycle()
end

Task:Spawn(function() 
    LocalMotorUnitCtrl:Start()
    _G.LocalReelIn = LocalReelIn
    LocalReelIn:Start()
    _G.MgrGameUI:OpenScreen('ScreenMain')
    LocalAttackButton:Start()
    LocalLoot:Start()
end)
-- 等钓鱼佬单位要轮询，单独起协程免得拖住上面的启动
Task:Spawn(function() LocalInteract:Start() end)
Task:Delay(1, function() 
    _G.MgrGameUI:OpenScreen("ScreenMsg")
end)





