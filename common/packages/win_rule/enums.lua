--胜利规则 - 枚举

local Enums = {}

---游戏结束条件：满足何种条件时整局游戏结束
---@export_enum
---@name 胜利规则游戏结束条件
---@inherit Int
---@default 1
Enums.WinRuleGameOverCondition = {
	---@enumValue 所有玩家都结算时结束
	EverySettlement = 1,
	---@enumValue 任意玩家胜利时结束
	AnyWin = 2,
	---@enumValue 任意玩家失败时结束
	AnyLose = 3,
}

---结算结果：玩家在一场对局中的胜负判定
---@export_enum
---@name 胜利规则结算结果
---@inherit Int
---@default 1
Enums.WinRuleResult = {
	---@enumValue 胜利
	Win = 1,
	---@enumValue 失败
	Lose = 2,
}

---校验某个值是否是 WinRuleGameOverCondition 的合法成员
---@param condition any 待校验的值
---@return Bool 是否合法
local function isValidWinRuleGameOverCondition(condition)
	for _, member in pairs(Enums.WinRuleGameOverCondition) do
		if condition == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 WinRuleResult 的合法成员
---@param result any 待校验的值
---@return Bool 是否合法
local function isValidWinRuleResult(result)
	for _, member in pairs(Enums.WinRuleResult) do
		if result == member then
			return true
		end
	end
	return false
end

Enums.IsValidWinRuleGameOverCondition = isValidWinRuleGameOverCondition
Enums.IsValidWinRuleResult = isValidWinRuleResult

return Enums
