-- modifier_system（效果包）双端根聚合入口的共有拼装，机制复用 AbilityAPIBase.build。
-- 名单即接缝契约：与包内 api.lua 的导出同名同序，单测拿包内源码校对；
-- 包整包 vendor 不改，升级改名/删名时立刻在这条接缝上暴露。

local AbilityAPIBase = require("common.AbilityAPIBase")

local ModifierAPIBase = {}

-- 与 server/packages/modifier_system/api.lua 的导出同名同序。
ModifierAPIBase.SERVER_API = {
	"AddModifier",
	"RemoveModifier",
	"ClearUnitModifiers",
	"GetUnitModifiers",
	"IsInModifier",
	"SetModifierStackCount",
	"AddModifierStackCount",
	"AddModifierDurationByInstance",
	"SetModifierRemainTime",
	"GetModifierOwner",
	"Pause",
	"Resume",
	"SetInterruptModifierObtain",
	"GetRemainingTimeByKey",
	"GetSourceByKey",
}

-- 与 client/packages/modifier_system/api.lua 的导出同名同序。
ModifierAPIBase.CLIENT_API = {
	"RemoveModifier",
	"ClearUnitModifiers",
	"SetModifierStackCount",
	"AddModifierStackCount",
	"AddModifierDurationByInstance",
	"SetModifierRemainTime",
	"Pause",
	"Resume",
	"GetUnitModifiers",
	"IsInModifier",
	"GetRemainingTimeByKey",
}

function ModifierAPIBase.build(impl, names)
	return AbilityAPIBase.build(impl, names, "[ModifierAPI] 效果包")
end

return ModifierAPIBase
