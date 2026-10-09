--胜利规则 - client端管理器
--CWinRuleManager：无状态方法集合，接收服务端结算事件并驱动本端结算/结束面板。

local Players = game:GetService("Players")

local Enums = require("common.packages.win_rule.enums")

local WinRuleResult = Enums.WinRuleResult

--胜利规则事件：接收服务端广播的结算结果与游戏结束
local winRuleEvent = RemoteEvent.New("win_rule_event")

--init 是否已执行，入口与单位脚本都会触发初始化，重复调用只生效一次
local isInited = false

---胜利规则管理器（客户端）：无状态方法集合
---@class CWinRuleManager
local CWinRuleManager = {}

---获取本地玩家的 ScreenGui，未就绪时返回 nil
---@return ScreenGui? 屏幕界面根节点
local function getScreenGui()
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil or localPlayer.PlayerGui == nil then
		return nil
	end
	return localPlayer.PlayerGui.ScreenGui
end

---处理服务端广播：结算结果展示胜负面板，"gameOver" 展示游戏结束面板
---@param result any WinRuleResult 成员或字符串 "gameOver"
local function onClientEvent(result)
	local screenGui = getScreenGui()
	if screenGui == nil then
		return
	end
	if result == WinRuleResult.Win then
		screenGui:ShowGameResult(true)
	elseif result == WinRuleResult.Lose then
		screenGui:ShowGameResult(false)
	elseif result == "gameOver" then
		screenGui:ShowGameOverPanel()
	end
end

---初始化：连接结算事件监听，重复调用只生效一次
function CWinRuleManager.init()
	if isInited then
		return
	end
	isInited = true
	winRuleEvent.OnClientEvent:Connect(onClientEvent)
end

return CWinRuleManager
