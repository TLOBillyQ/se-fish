--属性规则包 - 工具方法
--无状态工具集：纯计算 + 只读查询，不修改任何对象。

local Configs = require("common.packages.attr_rule.configs")
local Enums = require("common.packages.attr_rule.enums")

local utils = {}

---拼接某个分量在自定义属性（Attribute）上的键名；分量类型非法时退化为属性键本身
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@return String 分量键名
function utils.getAttrComponentKey(attrKey, attrComponentType)
	local suffix = Enums.AttrComponentTypeSuffix[attrComponentType]
	if suffix == nil then
		return attrKey
	end
	return attrKey .. suffix
end

---属性最终值公式：最终值 = (基础值 + 额外基础值) * (1 + 加成比例) + 额外加成
---下限优先于上限：同时越界时先按下限钳制
---@param base Float 基础值
---@param baseExtra Float 额外基础值
---@param ratio Float 加成比例
---@param bonus Float 额外加成
---@param minValue Float? 最终值下限，nil 表示不限
---@param maxValue Float? 最终值上限，nil 表示不限
---@return Float 最终值
function utils.computeFinalValue(base, baseExtra, ratio, bonus, minValue, maxValue)
	local value = (base + baseExtra) * (1 + ratio) + bonus
	if minValue ~= nil and value < minValue then
		value = minValue
	elseif maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return value
end

---在父单位的子节点里按预设类型查找脚本单位
---@param parentUnit Unit 父单位
---@param prefabTypeName String 预设类型名
---@return Script? 匹配的脚本单位
function utils.findChildScriptByPrefabType(parentUnit, prefabTypeName)
	if parentUnit == nil then
		return nil
	end
	for _, childUnit in ipairs(parentUnit:GetChildren()) do
		if childUnit:IsA("Script") then
			local presetLink = childUnit:FindFirstChildOfClass("PresetLink")
			local prefabType = presetLink and presetLink:GetAttribute(Configs.PREFAB_TYPE_ATTRIBUTE)
			if prefabType == prefabTypeName then
				return childUnit
			end
		end
	end
	return nil
end

return utils
