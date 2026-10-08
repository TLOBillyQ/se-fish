--属性规则包 - server端api
--面向业务代码的属性操作入口。
--方法按功能域分组：配置查询 → 属性单位（查找/读/写/Buff/初始化/懒创建）→ 属性加成单位。

local Enums = require("common.packages.attr_rule.enums")
local AttrUnit = require("common.packages.attr_rule.AttrUnit")
local AttrBuffUnit = require("common.packages.attr_rule.AttrBuffUnit")
local attrRule = require("server.packages.attr_rule.attr_rule")

-- 配置查询

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

-- 属性单位

---取目标单位下的属性单位，没有则返回 nil
---@param targetUnit Unit 目标单位
---@return Script? 属性单位
local function GetAttrUnit(targetUnit)
	return attrRule.getAttrUnit(targetUnit)
end

---获取属性值，单位没有属性单位时按 0 处理
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@return Float 属性值
local function GetAttr(targetUnit, attrKey)
	return attrRule.getAttr(targetUnit, attrKey)
end

---获取属性某个分量的值，单位没有属性单位时按 0 处理
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@return Float 分量值
local function GetAttrComponent(targetUnit, attrKey, attrComponentType)
	return attrRule.getAttrComponent(targetUnit, attrKey, attrComponentType)
end

---设置属性某个分量的值并重算最终值
---@param targetUnit Unit 目标单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@param value Float 分量值
---@return Bool success, String? err
local function SetAttrComponent(targetUnit, attrKey, attrComponentType, value)
	return attrRule.setAttrComponent(targetUnit, attrKey, attrComponentType, value)
end

---给目标单位加一组属性 Buff，返回 Buff 句柄用于移除
---@param targetUnit Unit 目标单位
---@param attrBuffConfigs AttrBuffConfig[] Buff 配置列表：{ AttrKey, AttrComponentType, Value }
---@return Int? attrBuffId, String? err
local function AddAttrBuff(targetUnit, attrBuffConfigs)
	return attrRule.addAttrBuff(targetUnit, attrBuffConfigs)
end

---移除指定 Buff，把当时加上的分量增量逐条减回
---@param targetUnit Unit 目标单位
---@param attrBuffId Int AddAttrBuff 返回的句柄
---@return Bool success, String? err
local function RemoveAttrBuff(targetUnit, attrBuffId)
	return attrRule.removeAttrBuff(targetUnit, attrBuffId)
end

---初始化属性单位：按全局配置写入各属性；配置不传时读单位自身携带的面板配置
---@param attrUnit Script 属性单位
---@param config table? 初始化配置：{ InitValues = AttrInitValue[] } 覆盖指定属性的基础值
---@return Bool success, String? err
local function InitAttrUnit(attrUnit, config)
	return AttrUnit.InitAttrUnit(attrUnit, config)
end

---取目标单位下的属性单位，没有就按预设创建一个
---@param targetUnit Unit 目标单位
---@return Script? attrUnit, String? err
local function EnsureAttrUnit(targetUnit)
	return attrRule.ensureAttrUnit(targetUnit)
end

-- 属性加成单位

---取指定单位下挂载的属性加成单位，没有则返回 nil
---@param unit Unit 加成单位挂载的单位
---@return Script? 属性加成单位
local function GetAttrBuffUnit(unit)
	return AttrBuffUnit.FindAttrBuffUnitOf(unit)
end

---获取属性加成单位当前的目标单位
---@param buffUnit Script 属性加成单位
---@return Unit? 目标单位
local function GetAttrBuffTargetUnit(buffUnit)
	return AttrBuffUnit.GetTargetUnit(buffUnit)
end

---设置属性加成单位的目标单位，传 nil 表示解除
---@param buffUnit Script 属性加成单位
---@param targetUnit Unit? 新的目标单位
---@return Bool success, String? err
local function SetAttrBuffTargetUnit(buffUnit, targetUnit)
	return AttrBuffUnit.SetTargetUnit(buffUnit, targetUnit)
end

---初始化属性加成单位：加成配置写到加成单位自身；配置不传时读单位自身携带的面板配置
---@param buffUnit Script 属性加成单位
---@param config table? 初始化配置：{ AttrBuffConfigs = AttrBuffConfig[] } 加成配置列表
---@return Bool success, String? err
local function InitAttrBuffUnit(buffUnit, config)
	return AttrBuffUnit.InitAttrBuffUnit(buffUnit, config)
end

return {
	Enums = Enums,
	Prefabs = {
		AttrUnit = AttrUnit,
		AttrBuffUnit = AttrBuffUnit,
	},
	Funcs = {
		-- 配置查询
		GetAttrConfig = GetAttrConfig,
		GetAllAttrConfigs = GetAllAttrConfigs,
		GetAttrIcon = GetAttrIcon,
		-- 属性单位
		GetAttrUnit = GetAttrUnit,
		GetAttr = GetAttr,
		GetAttrComponent = GetAttrComponent,
		SetAttrComponent = SetAttrComponent,
		AddAttrBuff = AddAttrBuff,
		RemoveAttrBuff = RemoveAttrBuff,
		InitAttrUnit = InitAttrUnit,
		EnsureAttrUnit = EnsureAttrUnit,
		-- 属性加成单位
		GetAttrBuffUnit = GetAttrBuffUnit,
		GetAttrBuffTargetUnit = GetAttrBuffTargetUnit,
		SetAttrBuffTargetUnit = SetAttrBuffTargetUnit,
		InitAttrBuffUnit = InitAttrBuffUnit,
	},
}
