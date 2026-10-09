--属性规则包 - 属性规则管理器基类（双端共用）
--AttrRuleManager：双端共用的配置查询与属性读取；客户端/服务端管理器在此基类上扩展端特有方法。

local Configs = require("common.packages.attr_rule.configs")
local Enums = require("common.packages.attr_rule.enums")
local AttrUnit = require("common.packages.attr_rule.AttrUnit")
local AttrBuffUnit = require("common.packages.attr_rule.AttrBuffUnit")

---单位 → 属性单位的临时缓存表：纯加速用，与状态无关。
---命中时校验挂接关系（parent 不符即弃用重建），miss 时重新查找。
---@type table<Unit, Script>
local attrUnitCache = {}

---@class AttrRuleManager
local AttrRuleManager = {}

---获取属性配置，未配置时返回 nil
---@param attrKey String 属性键
---@return AttrConfig? 属性配置
function AttrRuleManager.getAttrConfig(attrKey)
	return Configs.AllAttrConfigs[attrKey]
end

---获取全部属性配置：属性键 → 配置
---@return table<String, AttrConfig> 全部属性配置
function AttrRuleManager.getAllAttrConfigs()
	return Configs.AllAttrConfigs
end

---获取属性图标，未配置图标时返回 nil
---@param attrKey String 属性键
---@return String? 图标资源 URI
function AttrRuleManager.getAttrIcon(attrKey)
	local attrConfig = Configs.AllAttrConfigs[attrKey]
	if attrConfig == nil or attrConfig.Icon == "" then
		return nil
	end
	return attrConfig.Icon
end

---取目标单位下的属性单位，没有则返回 nil
---@param targetUnit Unit 目标单位
---@return Script? 属性单位
function AttrRuleManager.getAttrUnit(targetUnit)
	if targetUnit == nil then
		return nil
	end
	local cached = attrUnitCache[targetUnit]
	if cached ~= nil then
		-- 属性单位可能已销毁或被挪走：parent 校验不通过即弃用缓存，重新查找
		if cached.Parent == targetUnit then
			return cached
		end
		attrUnitCache[targetUnit] = nil
	end
	local attrUnit = AttrUnit.FindAttrUnitOf(targetUnit)
	if attrUnit ~= nil then
		attrUnitCache[targetUnit] = attrUnit
	end
	return attrUnit
end

---获取指定单位下挂载的属性加成单位，没有则返回 nil
---@param unit Unit 加成单位挂载的单位
---@return Script? 属性加成单位
function AttrRuleManager.getAttrBuffUnit(unit)
	return AttrBuffUnit.FindAttrBuffUnitOf(unit)
end

---获取属性值，单位没有属性单位或属性未配置时按 0 处理
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@return Float 属性值
function AttrRuleManager.getAttr(targetUnit, attrKey)
	local attrUnit = AttrRuleManager.getAttrUnit(targetUnit)
	if attrUnit == nil then
		return 0
	end
	return AttrUnit.GetAttr(attrUnit, attrKey)
end

---获取属性某个分量的值，单位没有属性单位或属性未配置时按 0 处理
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@return Float 分量值
function AttrRuleManager.getAttrComponent(targetUnit, attrKey, attrComponentType)
	assert(
		Enums.IsValidAttrComponentType(attrComponentType),
		"GetAttrComponent: attrComponentType must be an AttrComponentType member"
	)
	local attrUnit = AttrRuleManager.getAttrUnit(targetUnit)
	if attrUnit == nil then
		return 0
	end
	return AttrUnit.GetAttrComponent(attrUnit, attrKey, attrComponentType)
end

return AttrRuleManager
