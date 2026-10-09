--属性规则包 - client端api
--面向业务代码的属性操作入口。

local Enums = require("common.packages.attr_rule.enums")
local AttrUnit = require("common.packages.attr_rule.AttrUnit")
local attrRule = require("client.packages.attr_rule.attr_rule")

---获取属性配置（含默认值/上下限/图标/目标类型），属性未配置时返回 nil
---@param attrKey String 属性键
---@return AttrConfig? 属性配置
local function GetAttrConfig(attrKey)
	return attrRule.getAttrConfig(attrKey)
end

---获取全部属性配置：属性键 → 配置
---@return table<String, AttrConfig> 全部属性配置
local function GetAllAttrConfigs()
	return attrRule.getAllAttrConfigs()
end

---获取属性图标，属性未配置图标时返回 nil
---@param attrKey String 属性键
---@return String? 图标资源 URI
local function GetAttrIcon(attrKey)
	return attrRule.getAttrIcon(attrKey)
end

---取目标单位下的属性单位，没有则返回 nil
---@param targetUnit Unit 目标单位
---@return Script? 属性单位
local function GetAttrUnit(targetUnit)
	return attrRule.getAttrUnit(targetUnit)
end

---获取属性值，属性单位还没同步到本端时按 0 处理
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@return Float 属性值
local function GetAttr(targetUnit, attrKey)
	return attrRule.getAttr(targetUnit, attrKey)
end

---获取属性某个分量的值，属性单位还没同步到本端时按 0 处理
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@return Float 分量值
local function GetAttrComponent(targetUnit, attrKey, attrComponentType)
	return attrRule.getAttrComponent(targetUnit, attrKey, attrComponentType)
end

return {
	Enums = Enums,
	Prefabs = {
		AttrUnit = AttrUnit,
	},
	Funcs = {
		GetAttrUnit = GetAttrUnit,
		GetAttrConfig = GetAttrConfig,
		GetAllAttrConfigs = GetAllAttrConfigs,
		GetAttrIcon = GetAttrIcon,
		GetAttr = GetAttr,
		GetAttrComponent = GetAttrComponent,
	},
}
