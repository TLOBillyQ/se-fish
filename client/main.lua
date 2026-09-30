local LocalMgrUtil = require("client.LocalMgrUtil")
LocalMgrUtil:Start()

local Task = game:GetService("Task")

-- 原生「举起」按钮在客户端发起的抓举无效、举着时再按有甩鱼风险，举鱼一律由服务端发起（#41）
_G.MgrGameUI:HideLiftButton()
-- 原生血条关掉，血量看 ScreenMain 的自绘血球（#53）
_G.MgrGameUI:HideNativeHealth()

local LocalMotorUnitCtrl = require("client.LocalMotorUnitCtrl")
local LocalReelIn = require("client.LocalReelIn")
local LocalLoot = require("client.LocalLoot")
local LocalInteract = require("client.LocalInteract")
local LocalGM = require("client.LocalGM")
local LocalShop = require("client.LocalShop")
local LocalLottery = require("client.LocalLottery")
local ScreenLottery = require("client.ScreenHandlers.ScreenLottery")
local ScreenFerry = require("client.ScreenHandlers.ScreenFerry")
local ScreenSurvival = require("client.ScreenHandlers.ScreenSurvival")
-- #137 烧烤文字泡与烤炉进度面板（运行时自绘，不经 MgrGameUI）
local ScreenGrill = require("client.ScreenHandlers.ScreenGrill")
-- #147 T26 盲盒与平台购买（肾上腺素报价、测试支付驱动、金币页入口）界面
local ScreenBlindbox = require("client.ScreenHandlers.ScreenBlindbox")
local ScreenPlatform = require("client.ScreenHandlers.ScreenPlatform")
-- #134 鳄雀鳝头部攻击贴地预警
local LocalGarBite = require("client.LocalGarBite")

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
    LocalLoot:Start()
    LocalGM:Start()
    _G.MgrGameUI:StartGM()
end)
-- 等钓鱼佬单位要轮询，单独起协程免得拖住上面的启动
Task:Spawn(function() LocalGarBite:Start() end)
Task:Spawn(function() LocalInteract:Start() end)
Task:Spawn(function() LocalShop:Start() end)
-- #138 T17 抽奖机：界面节点运行时创建（ScreenGM 模式），入口气泡等 Z*_Lottery 锚点要轮询，单独起协程
Task:Spawn(function() ScreenLottery:Start() end)
Task:Spawn(function() LocalLottery:Start() end)
Task:Spawn(function() ScreenFerry:Start() end)
Task:Spawn(function() ScreenSurvival:Start() end)
Task:Spawn(function() ScreenGrill:Start() end)
Task:Spawn(function() ScreenBlindbox:Start() end)
Task:Spawn(function() ScreenPlatform:Start() end)
Task:Delay(1, function() 
    _G.MgrGameUI:OpenScreen("ScreenMsg")
end)





