--属性规则包 - 属性单位方法集（双端共用）
--AttrUnit：无状态方法字典，操作属性单位

local Configs = require("common.packages.attr_rule.configs")
local Enums = require("common.packages.attr_rule.enums")
local utils = require("common.packages.attr_rule.utils")

local AttrComponentType = Enums.AttrComponentType
local ATTR_BUFFS_ATTRIBUTE = Configs.ATTR_BUFFS_ATTRIBUTE
local ATTR_BUFF_NEXT_ID_ATTRIBUTE = Configs.ATTR_BUFF_NEXT_ID_ATTRIBUTE

---把最终值写入目标单位 Controller 的某个字段
---@param controller any 目标单位的控制器
---@param field String 字段名
---@param value Float 设置值
local function setControllerField(controller, field, value)
	if controller == nil then
		return
	end
	controller[field] = value
end

---读取属性单位上的 Buff 记录表（Buff 句柄 → 变更列表）
---@param attrUnit Script 属性单位
---@return table? Buff 记录表
local function getAttrBuffRecord(attrUnit)
	if attrUnit == nil then
		return nil
	end
	return attrUnit:GetAttribute(ATTR_BUFFS_ATTRIBUTE)
end

---Buff 记录表
---@param attrUnit Script 属性单位
---@return table Buff 记录表
local function ensureAttrBuffRecord(attrUnit)
	local record = getAttrBuffRecord(attrUnit)
	if record == nil then
		record = {}
		attrUnit:SetAttribute(ATTR_BUFFS_ATTRIBUTE, record)
	end
	return record
end

---分配新的 Buff 句柄
---@param attrUnit Script 属性单位
---@return Int 新的 Buff 句柄
local function allocAttrBuffId(attrUnit)
	local attrBuffId = attrUnit:GetAttribute(ATTR_BUFF_NEXT_ID_ATTRIBUTE) or 0
	attrBuffId = attrBuffId + 1
	attrUnit:SetAttribute(ATTR_BUFF_NEXT_ID_ATTRIBUTE, attrBuffId)
	return attrBuffId
end

local AttrUnit = {}

---初始化属性单位：按全局配置写入各属性
---@param attrUnit Script 属性单位
---@param config table? 初始化配置：{ InitValues = AttrInitValue[] } 覆盖指定属性的基础值
---@return Bool success, String? err
function AttrUnit.InitAttrUnit(attrUnit, config)
	assert(attrUnit ~= nil, "AttrUnit.InitAttrUnit: attrUnit must not be nil")
	if AttrUnit.GetTargetUnit(attrUnit) == nil then
		return false, "[attr_rule] attr unit has no parent"
	end
	local initValues = type(config) == "table" and config.InitValues or nil
	if initValues == nil then
		initValues = attrUnit:GetAttribute(Configs.INIT_VALUES_ATTRIBUTE)
	end
	AttrUnit.InitAttributes(attrUnit)
	if initValues ~= nil then
		AttrUnit.ApplyInitValues(attrUnit, initValues)
	end
	return true, nil
end

---按全局属性配置表初始化属性单位的全部属性
---@param attrUnit Script 属性单位
function AttrUnit.InitAttributes(attrUnit)
	for attrKey, attrConfig in pairs(Configs.AllAttrConfigs) do
		AttrUnit.applyAttrConfig(attrUnit, attrKey, attrConfig)
	end
	for attrKey in pairs(Configs.ControllerAttrMap) do
		if Configs.AllAttrConfigs[attrKey] == nil then
			AttrUnit.applyControllerAttr(attrUnit, attrKey)
		end
	end
end

---按单条属性配置初始化属性：声明了目标类型的属性，只在目标单位是该类型（含子类）时才添加
---@param attrUnit Script 属性单位
---@param attrKey String 属性键
---@param attrConfig AttrConfig 属性配置
function AttrUnit.applyAttrConfig(attrUnit, attrKey, attrConfig)
	local targetType = attrConfig.TargetType
	if targetType ~= nil and targetType ~= "" then
		local targetUnit = AttrUnit.GetTargetUnit(attrUnit)
		if targetUnit == nil or not targetUnit:IsA(targetType) then
			return
		end
	end
	-- 只写基础值分量，其余分量缺省按 0 处理
	AttrUnit.SetAttrComponent(attrUnit, attrKey, AttrComponentType.Base, attrConfig.Default)
	AttrUnit.UpdateAttr(attrUnit, attrKey)
end

---按 Controller 当前值初始化属性：配置里没有该属性时，把 Controller 字段值作为基础值写入并回算
---@param attrUnit Script 属性单位
---@param attrKey String 属性键
function AttrUnit.applyControllerAttr(attrUnit, attrKey)
	local targetUnit = AttrUnit.GetTargetUnit(attrUnit)
	local controllerField = Configs.ControllerAttrMap[attrKey]
	local controller = targetUnit and targetUnit.Controller
	if controller == nil then
		return
	end
	local ok, value = pcall(function()
		return controller[controllerField]
	end)
	if ok and type(value) == "number" then
		AttrUnit.SetAttrComponent(attrUnit, attrKey, AttrComponentType.Base, value)
		AttrUnit.UpdateAttr(attrUnit, attrKey)
	end
end

---按初始值列表覆盖属性的基础值并回算属性值
---@param attrUnit Script 属性单位
---@param initValues AttrInitValue[] 初始值列表
function AttrUnit.ApplyInitValues(attrUnit, initValues)
	for _, initValue in ipairs(initValues) do
		local attrKey = initValue.AttrKey
		if type(attrKey) == "string" and attrKey ~= "" then
			AttrUnit.SetAttrComponent(attrUnit, attrKey, AttrComponentType.Base, initValue.Value or 0)
			AttrUnit.UpdateAttr(attrUnit, attrKey)
		end
	end
end

---在指定单位的子节点里查找属性单位
---@param unit Unit 目标单位
---@return Script? 属性单位
function AttrUnit.FindAttrUnitOf(unit)
	return utils.findChildScriptByPrefabType(unit, Configs.ATTR_UNIT_PREFAB_TYPE)
end

---获取目标单位，即属性单位的直接 Parent
---@param attrUnit Script 属性单位
---@return Unit? 目标单位
function AttrUnit.GetTargetUnit(attrUnit)
	if attrUnit == nil then
		return nil
	end
	return attrUnit.Parent
end

---获取属性值（各分量按公式叠加后的最终生效值），未设置过按 0 处理
---@param attrUnit Script 属性单位
---@param attrKey String 属性键
---@return Float 属性值
function AttrUnit.GetAttr(attrUnit, attrKey)
	if attrUnit == nil then
		return 0
	end
	return attrUnit:GetAttribute(attrKey) or 0
end

---获取属性某个分量的值，未设置过按 0 处理
---@param attrUnit Script 属性单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@return Float 分量值
function AttrUnit.GetAttrComponent(attrUnit, attrKey, attrComponentType)
	if attrUnit == nil then
		return 0
	end
	return attrUnit:GetAttribute(utils.getAttrComponentKey(attrKey, attrComponentType)) or 0
end

---设置属性某个分量的值
---@param attrUnit Script 属性单位
---@param attrKey String 属性键
---@param attrComponentType AttrComponentType 分量类型
---@param value Float 分量值
function AttrUnit.SetAttrComponent(attrUnit, attrKey, attrComponentType, value)
	if type(value) ~= "number" then
		return
	end
	attrUnit:SetAttribute(utils.getAttrComponentKey(attrKey, attrComponentType), value)
end

---按公式计算属性值并写回，同时同步到目标单位的 Controller
---@param attrUnit Script 属性单位
---@param attrKey String 属性键
function AttrUnit.UpdateAttr(attrUnit, attrKey)
	local attrConfig = Configs.AllAttrConfigs[attrKey]
	local finalValue = utils.computeFinalValue(
		AttrUnit.GetAttrComponent(attrUnit, attrKey, AttrComponentType.Base),
		AttrUnit.GetAttrComponent(attrUnit, attrKey, AttrComponentType.BaseExtra),
		AttrUnit.GetAttrComponent(attrUnit, attrKey, AttrComponentType.Ratio),
		AttrUnit.GetAttrComponent(attrUnit, attrKey, AttrComponentType.Bonus),
		attrConfig and attrConfig.Min,
		attrConfig and attrConfig.Max
	)
	local oldValue = AttrUnit.GetAttr(attrUnit, attrKey)
	if oldValue ~= finalValue then
		attrUnit:SetAttribute(attrKey, finalValue)
	end

	local controllerField = Configs.ControllerAttrMap[attrKey]
	if controllerField == nil then
		return
	end
	local targetUnit = AttrUnit.GetTargetUnit(attrUnit)
	local controller = targetUnit and targetUnit.Controller
	if controller == nil then
		return
	end
	-- 单位有 Controller 则应用到 Controller ，使用 pcall 保护，同步失败只打印日志，不影响属性值本身
	local ok, err = pcall(setControllerField, controller, controllerField, finalValue)
	if not ok then
		print(string.format(
			"[attr_rule] failed to set attr %q on Controller.%s: %s",
			attrKey,
			controllerField,
			tostring(err)
		))
	end
end

---给属性单位加一组属性 Buff，返回句柄用于移除
---@param attrUnit Script 属性单位
---@param attrBuffConfigs AttrBuffConfig[] Buff 配置列表
---@return Int? attrBuffId, String? err
function AttrUnit.AddAttrBuff(attrUnit, attrBuffConfigs)
	if attrUnit == nil or type(attrBuffConfigs) ~= "table" then
		return nil, "[attr_rule] attr buff configs must be a table"
	end
	local changes = {}
	for _, attrBuffConfig in ipairs(attrBuffConfigs) do
		local attrKey = attrBuffConfig.AttrKey
		if type(attrKey) ~= "string" or attrKey == "" then
			return nil, "[attr_rule] attr buff config has no valid AttrKey"
		end
		local attrComponentType = attrBuffConfig.AttrComponentType or AttrComponentType.Base
		if not Enums.IsValidAttrComponentType(attrComponentType) then
			return nil, "[attr_rule] attr buff config has an invalid AttrComponentType"
		end
		local delta = attrBuffConfig.Value or 0
		if type(delta) ~= "number" then
			return nil, "[attr_rule] attr buff config value must be a number"
		end
		if delta ~= 0 then
			table.insert(changes, {
				attrKey = attrKey,
				attrComponentType = attrComponentType,
				delta = delta,
			})
		end
	end

	local attrBuffId = allocAttrBuffId(attrUnit)
	-- 先登记再应用
	local record = ensureAttrBuffRecord(attrUnit)
	record[attrBuffId] = changes
	attrUnit:SetAttribute(ATTR_BUFFS_ATTRIBUTE, record)
	for _, change in ipairs(changes) do
		local currentValue = AttrUnit.GetAttrComponent(attrUnit, change.attrKey, change.attrComponentType)
		local nextValue = currentValue + change.delta
		AttrUnit.SetAttrComponent(attrUnit, change.attrKey, change.attrComponentType, nextValue)
		AttrUnit.UpdateAttr(attrUnit, change.attrKey)
	end
	return attrBuffId, nil
end

---移除指定 Buff，把当时加上的分量增量逐条减回
---@param attrUnit Script 属性单位
---@param attrBuffId Int AddAttrBuff 返回的句柄
---@return Bool success, String? err
function AttrUnit.RemoveAttrBuff(attrUnit, attrBuffId)
	local record = getAttrBuffRecord(attrUnit)
	local changes = record and record[attrBuffId]
	if changes == nil then
		return false, string.format("[attr_rule] attr buff %s not found", tostring(attrBuffId))
	end
	for _, change in ipairs(changes) do
		local currentValue = AttrUnit.GetAttrComponent(attrUnit, change.attrKey, change.attrComponentType)
		local restoredValue = currentValue - change.delta
		AttrUnit.SetAttrComponent(attrUnit, change.attrKey, change.attrComponentType, restoredValue)
		AttrUnit.UpdateAttr(attrUnit, change.attrKey)
	end
	record[attrBuffId] = nil
	attrUnit:SetAttribute(ATTR_BUFFS_ATTRIBUTE, record)
	return true, nil
end

return AttrUnit
