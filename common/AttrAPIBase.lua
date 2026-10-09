-- attr_rule（属性规则包）双端根聚合入口的共有拼装，机制复用 AbilityAPIBase.build。
-- 名单即接缝契约：与包内 api.lua 的 Funcs 导出同名同序，单测拿包内源码校对；
-- 包整包 vendor 不改，升级改名/删名时立刻在这条接缝上暴露。

local AbilityAPIBase = require("common.AbilityAPIBase")

local AttrAPIBase = {}

-- 与 server/packages/attr_rule/api.lua 的 Funcs 导出同名同序。
AttrAPIBase.SERVER_API = {
	"GetAttrConfig",
	"GetAllAttrConfigs",
	"GetAttrIcon",
	"GetAttrUnit",
	"GetAttr",
	"GetAttrComponent",
	"SetAttrComponent",
	"AddAttrBuff",
	"RemoveAttrBuff",
	"InitAttrUnit",
	"EnsureAttrUnit",
	"GetAttrBuffUnit",
	"GetAttrBuffTargetUnit",
	"SetAttrBuffTargetUnit",
	"InitAttrBuffUnit",
}

-- 与 client/packages/attr_rule/api.lua 的 Funcs 导出同名同序。
AttrAPIBase.CLIENT_API = {
	"GetAttrUnit",
	"GetAttrConfig",
	"GetAllAttrConfigs",
	"GetAttrIcon",
	"GetAttr",
	"GetAttrComponent",
}

function AttrAPIBase.build(impl, names)
	return AbilityAPIBase.build(impl, names, "[AttrAPI] 属性规则包")
end

return AttrAPIBase
