--胜利规则 - server端管理器
--SWinRuleManager：无状态方法集合，负责玩家结算、游戏结束判定与广播。

local Players = game:GetService("Players")
local Task = game:GetService("Task")

local Enums = require("common.packages.win_rule.enums")

local WinRuleResult = Enums.WinRuleResult
local WinRuleGameOverCondition = Enums.WinRuleGameOverCondition

---游戏结束条件
---@export_data
---@type Int 胜利模式
---@style enum
---@enum [[1, "EVERY_SETTLEMENT", "所有玩家都结算时结束"], [2, "ANY_WIN", "任意玩家胜利时结束"], [3, "ANY_LOSE", "任意玩家失败时结束"]]
---@title 游戏结束条件
local GameOverContdition = 1

--胜利规则事件：服务端向客户端广播结算结果与游戏结束
local winRuleEvent = RemoteEvent.New("win_rule_event")

--游戏结束广播后延迟踢人的时长（秒）：给客户端留出接收 "gameOver" 并展示结算面板的时间，
--避免事件发送过程中连接被销毁导致报错
local GAME_OVER_KICK_DELAY_SEC = 4

--对局进度是会话级记录而非单位数据：World 服务没有自定义属性接口，结算信息也不随单位持久，
--玩家掉线即退出本局、无需断线重连恢复，故由模块级表持有，仅服务端本进程有效
--玩家 UserId → 结算结果（WinRuleResult）；玩家掉线即清出，对局结束即作废
local settlementMap = {}
--本局是否已触发游戏结束，触发后不再判定
local isGameOver = false
--init 是否已执行，重复调用只生效一次
local isInited = false

---胜利规则管理器（服务端）：无状态方法集合，对局进度见文件头说明
---@class SWinRuleManager
local SWinRuleManager = {}

---让玩家角色进入失控状态，结算后禁止继续操作
---@param player Player 目标玩家
local function loseControl(player)
	local character = player.Character
	if character == nil or character.Controller == nil then
		return
	end
	character.Controller:ChangeState(Enums.ControllerStateType.LostControl)
end

---游戏结束后踢出一名玩家；期间玩家可能已自行离开，Kick 加保护避免报错
---@param player Player 目标玩家
local function kickPlayer(player)
	local ok, err = pcall(function()
		player:Kick()
	end)
	if not ok then
		print(string.format(
			"[win_rule] failed to kick player %s: %s",
			tostring(player.UserId),
			tostring(err)
		))
	end
end

---广播游戏结束并延迟踢出所有在线玩家
---@param players Player[] 当前在线玩家列表
local function fireGameOver(players)
	isGameOver = true
	winRuleEvent:FireAllClients("gameOver")
	Task:Delay(GAME_OVER_KICK_DELAY_SEC, function()
		for _, player in ipairs(players) do
			kickPlayer(player)
		end
	end)
end

---判定是否满足游戏结束条件，满足则广播结束
local function checkIsGameOver()
	if isGameOver then
		return
	end
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	--提前结束模式：任意玩家胜利/失败即结束
	if GameOverContdition == WinRuleGameOverCondition.AnyWin
		or GameOverContdition == WinRuleGameOverCondition.AnyLose then
		for _, player in ipairs(players) do
			local state = settlementMap[player.UserId]
			local isTargetState = false
			if GameOverContdition == WinRuleGameOverCondition.AnyWin then
				isTargetState = state == WinRuleResult.Win
			elseif GameOverContdition == WinRuleGameOverCondition.AnyLose then
				isTargetState = state == WinRuleResult.Lose
			end
			if isTargetState then
				fireGameOver(players)
				return
			end
		end
		return
	end

	--默认模式：全员在线玩家均已结算 → 触发游戏结束
	for _, player in ipairs(players) do
		if settlementMap[player.UserId] == nil then
			return
		end
	end
	fireGameOver(players)
end

---结算玩家：记录结果、锁定操作、向该玩家客户端广播结算，并触发结束判定
---@param player Player 目标玩家
---@param result Int 结算结果（WinRuleResult 成员）
function SWinRuleManager.settlePlayer(player, result)
	if player == nil then
		return
	end
	if settlementMap[player.UserId] ~= nil then
		return
	end
	settlementMap[player.UserId] = result
	loseControl(player)
	winRuleEvent:FireClient(player, result)
	checkIsGameOver()
end

---获取已结算胜利的玩家数
---@return Int 胜利玩家数
function SWinRuleManager.getWinPlayerCount()
	local count = 0
	for _, state in pairs(settlementMap) do
		if state == WinRuleResult.Win then
			count = count + 1
		end
	end
	return count
end

---获取已结算失败的玩家数
---@return Int 失败玩家数
function SWinRuleManager.getLosePlayerCount()
	local count = 0
	for _, state in pairs(settlementMap) do
		if state == WinRuleResult.Lose then
			count = count + 1
		end
	end
	return count
end

---初始化：连接玩家进出事件清理结算记录，重复调用只生效一次
function SWinRuleManager.init()
	if isInited then
		return
	end
	isInited = true
	Players.PlayerAdded:Connect(function(player)
		settlementMap[player.UserId] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		settlementMap[player.UserId] = nil
	end)
end

return SWinRuleManager
