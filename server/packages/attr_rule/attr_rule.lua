--属性规则包 - server端状态管理
--SAttrRuleManager：属性系统的服务端管理器，继承 AttrRuleManager 的读取能力，扩展权威写入、Buff 增删与单位创建。

local World = game:GetService("World")

local Configs = require("common.packages.attr_rule.configs")
local Enums = require("common.packages.attr_rule.enums")
local AttrUnit = require("common.packages.attr_rule.AttrUnit")
local AttrRuleManager = require("common.packages.attr_rule.AttrRuleManager")

local DEFAULT_ATTR_UNIT_KEY = Configs.DEFAULT_ATTR_UNIT_KEY

---属性规则管理器（服务端）
---@class SAttrRuleManager : AttrRuleManager
local SAttrRuleManager = setmetatable({}, { __index = AttrRuleManager })

---设置属性某个分量的值并重算最终值
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@param value Float 分量值
---@return Bool success, String? err
function SAttrRuleManager.setAttrComponent(targetUnit, attrKey, attrComponentType, value)
	assert(type(attrKey) == "string", "SetAttrComponent: attrKey must be a string")
	assert(Enums.IsValidAttrComponentType(attrComponentType), "SetAttrComponent: attrComponentType must be an AttrComponentType member")
	assert(type(value) == "number", "SetAttrComponent: value must be a number")

	local attrUnit, err = SAttrRuleManager.ensureAttrUnit(targetUnit)
	if attrUnit == nil then
		return false, err
	end
	AttrUnit.SetAttrComponent(attrUnit, attrKey, attrComponentType, value)
	AttrUnit.UpdateAttr(attrUnit, attrKey)
	return true, nil
end

---给目标单位加一组属性 Buff，返回句柄用于移除
---@param targetUnit Unit 目标单位
---@param attrBuffConfigs AttrBuffConfig[] Buff 配置列表
---@return Int? attrBuffId, String? err
function SAttrRuleManager.addAttrBuff(targetUnit, attrBuffConfigs)
	assert(type(attrBuffConfigs) == "table", "AddAttrBuff: attrBuffConfigs must be a table")
	local attrUnit, err = SAttrRuleManager.ensureAttrUnit(targetUnit)
	if attrUnit == nil then
		return nil, err
	end
	return AttrUnit.AddAttrBuff(attrUnit, attrBuffConfigs)
end

---移除指定 Buff，把当时加上的分量增量逐条减回
---@param targetUnit Unit 目标单位
---@param attrBuffId Int AddAttrBuff 返回的句柄
---@return Bool success, String? err
function SAttrRuleManager.removeAttrBuff(targetUnit, attrBuffId)
	local attrUnit = SAttrRuleManager.getAttrUnit(targetUnit)
	if attrUnit == nil then
		return false, "[attr_rule] no attr unit found under the target unit"
	end
	return AttrUnit.RemoveAttrBuff(attrUnit, attrBuffId)
end

---取目标单位下的属性单位，没有就按预设创建一个
---@param targetUnit Unit 目标单位
---@return Script? attrUnit, String? err
function SAttrRuleManager.ensureAttrUnit(targetUnit)
	if targetUnit == nil then
		return nil, "[attr_rule] target unit must not be nil"
	end
	local attrUnit = SAttrRuleManager.getAttrUnit(targetUnit)
	if attrUnit ~= nil then
		return attrUnit, nil
	end
	local units = World:CreateAsset(DEFAULT_ATTR_UNIT_KEY)
	local attrUnit = units and units[1]
	if attrUnit == nil then
		return nil, "[attr_rule] failed to create attr unit by preset " .. DEFAULT_ATTR_UNIT_KEY
	end
	attrUnit.Parent = targetUnit
	local ok, initErr = AttrUnit.InitAttrUnit(attrUnit)
	if not ok then
		attrUnit:Destroy()
		return nil, initErr
	end
	return attrUnit, nil
end

return SAttrRuleManager
