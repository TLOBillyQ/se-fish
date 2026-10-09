--胜利规则 - server端api
--面向地图脚本（服务端入口、单位脚本）的胜负结算入口。

local Enums = require("common.packages.win_rule.enums")
local winRule = require("server.packages.win_rule.win_rule")

local WinRuleResult = Enums.WinRuleResult

---初始化胜利规则：连接玩家进出事件清理结算记录，须在服务端入口调用一次，重复调用安全
local function Init()
	winRule.init()
end

---判定玩家胜利并广播结算，已结算过的玩家重复调用无效
---@param player Player 目标玩家
local function SetPlayerWin(player)
	winRule.settlePlayer(player, WinRuleResult.Win)
end

---判定玩家失败并广播结算，已结算过的玩家重复调用无效
---@param player Player 目标玩家
local function SetPlayerLose(player)
	winRule.settlePlayer(player, WinRuleResult.Lose)
end

---获取已结算胜利的玩家数
---@return Int 胜利玩家数
local function GetWinPlayerCount()
	return winRule.getWinPlayerCount()
end

---获取已结算失败的玩家数
---@return Int 失败玩家数
local function GetLosePlayerCount()
	return winRule.getLosePlayerCount()
end

return {
	Funcs = {
		Init = Init,
		SetPlayerWin = SetPlayerWin,
		SetPlayerLose = SetPlayerLose,
		GetWinPlayerCount = GetWinPlayerCount,
		GetLosePlayerCount = GetLosePlayerCount,
	},
}
