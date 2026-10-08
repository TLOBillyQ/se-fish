-- official_ai_feature（生物 AI 包）根聚合入口的共有拼装，机制复用 AbilityAPIBase.build。
-- 名单即接缝契约：与包内 api.lua 的 Funcs 导出同名同序，单测拿包内源码校对；
-- 包整包 vendor 不改，升级改名/删名时立刻在这条接缝上暴露。
-- AI 包 client 侧无 api.lua，只有服务端名单。

local AbilityAPIBase = require("common.AbilityAPIBase")

local AiAPIBase = {}

-- 与 server/packages/official_ai_feature/api.lua 的 Funcs 导出同名同序。
AiAPIBase.SERVER_API = {
	"StartAI",
	"StopAI",
	"Roll",
	"Rush",
	"Jump",
	"Lift",
	"MoveDirection",
	"MoveToPos",
	"StopMove",
	"Follow",
	"Alert",
	"Imitate",
	"SearchEnemy",
	"ChaseTarget",
	"Nav",
	"BasicCommand",
	"CastAbility",
	"CastAbilityByKey",
	"ExecuteCareerSkill",
	"AddAbilityToSlot",
	"SetSearchEnemyPriorityMode",
	"SetSearchEnemyPriorityValue",
	"SetSearchEnemyFocusTarget",
	"SetMoveThreshold",
}

function AiAPIBase.build(impl, names)
	return AbilityAPIBase.build(impl, names, "[AiAPI] 生物AI包")
end

return AiAPIBase
