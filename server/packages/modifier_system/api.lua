--效果系统包 - server端api
--面向业务代码的效果操作入口，服务端为权威端，查询与修改均直接生效。
--读取约定：查询返回效果实体，即效果实例，字段直接从实体读取。
--  效果配置：Name / ModifierDesc / Icon / UgcModifierType / MaxStackCount
--  运行时状态：IsActive / CurrCount / CharMtg / IsPaused / EndTime / ModifierKey
--  实体自身：UnitId

local config = require("common.packages.modifier_system.config")
local modifierSystem = require("server.packages.modifier_system.modifier_system")

local Enums = {
	CreateResult = config.CreateResult,
}

-- 添加 / 移除

---给拥有者单位添加效果
---@param ownerUnit Unit 拥有者单位
---@param assetId string 效果预设 Asset
---@param addConfig table? 可选配置，支持 duration/stackable/maxStackCount/叠加策略等字段
---@return string 创建结果，取值见 Enums.CreateResult；效果实例经 GetUnitModifiers 获取
local function AddModifier(ownerUnit, assetId, addConfig)
	return modifierSystem:addModifierToUnit(ownerUnit, assetId, addConfig)
end

---移除指定效果实例
---@param modifierUnit Unit 效果实体单位
---@return boolean 是否移除成功
local function RemoveModifier(modifierUnit)
	return modifierSystem:removeModifierEntity(modifierUnit)
end

---移除拥有者身上指定 Key 的所有效果；Key 为空时清除全部
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string? 效果 Key，为空清除全部
---@return number 移除数量
local function ClearUnitModifiers(ownerUnit, modifierKey)
	if modifierKey and modifierKey ~= "" then
		return modifierSystem:removeModifierByKey(ownerUnit, modifierKey)
	end
	return modifierSystem:clearAllModifiers(ownerUnit)
end

-- 查询

---获取拥有者身上的效果实例列表；Key 非空时按预设过滤
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string? 效果 Key，为空返回全部
---@return Unit[] 效果实体单位列表
local function GetUnitModifiers(ownerUnit, modifierKey)
	if modifierKey and modifierKey ~= "" then
		return modifierSystem:getModifierUnitsByKey(ownerUnit, modifierKey)
	end
	return modifierSystem:getModifierUnits(ownerUnit)
end

---拥有者是否拥有指定 Key 的效果，Key 为空时返回是否存在任一效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return boolean 是否存在
local function IsInModifier(ownerUnit, modifierKey)
	return modifierSystem:hasModifier(ownerUnit, modifierKey)
end

-- 修改接口

---设置效果实例的层数，归零触发带失活的移除
---@param modifierUnit Unit 效果实体单位
---@param count number 目标层数
---@return boolean 是否执行成功
local function SetModifierStackCount(modifierUnit, count)
	return modifierSystem:setStackCountOfEntity(modifierUnit, count)
end

---增减效果实例的层数，delta 可为负数
---@param modifierUnit Unit 效果实体单位
---@param delta number 层数增量
---@return number 新层数
local function AddModifierStackCount(modifierUnit, delta)
	return modifierSystem:addStackCountOfEntity(modifierUnit, delta)
end

---延长效果实例的持续时间，extra 可为负数表示缩短
---@param modifierUnit Unit 效果实体单位
---@param extra number 延长时间，单位秒
---@return boolean 是否执行成功
local function AddModifierDurationByInstance(modifierUnit, extra)
	return modifierSystem:addDurationOfEntity(modifierUnit, extra)
end

---设置效果实例的剩余时间，单位秒
---@param modifierUnit Unit 效果实体单位
---@param remaining number 剩余时间
---@return boolean 是否执行成功
local function SetModifierRemainTime(modifierUnit, remaining)
	return modifierSystem:setRemainTimeOfEntity(modifierUnit, remaining)
end

---获取效果实例的拥有者
---@param modifierUnit Unit 效果实体单位
---@return Unit? 拥有者单位
local function GetModifierOwner(modifierUnit)
	return modifierSystem:getModifierOwnerOfEntity(modifierUnit)
end

-- 扩展接口

---暂停指定 Key 效果，冻结倒计时与叠加计时器
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
local function Pause(ownerUnit, modifierKey, unitId)
	return modifierSystem:pause(ownerUnit, modifierKey, unitId)
end

---恢复指定 Key 效果，补偿暂停时长并重建倒计时
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
local function Resume(ownerUnit, modifierKey, unitId)
	return modifierSystem:resume(ownerUnit, modifierKey, unitId)
end

---阻止当前触发中的效果获得，仅在"即将获得效果"事件中调用有效
---@return boolean 恒返回 true
local function SetInterruptModifierObtain()
	return modifierSystem:setInterruptModifierObtain()
end

---获取指定 Key 效果的剩余时间，永久效果返回 -1
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 剩余时间
local function GetRemainingTimeByKey(ownerUnit, modifierKey)
	return modifierSystem:getRemainingTimeByKey(ownerUnit, modifierKey)
end

---获取指定 Key 效果的来源单位，未指定来源时返回 nil
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return Unit? 来源单位
local function GetSourceByKey(ownerUnit, modifierKey)
	return modifierSystem:getSourceByKey(ownerUnit, modifierKey)
end

return {
	Enums = Enums,
	AddModifier = AddModifier,
	RemoveModifier = RemoveModifier,
	ClearUnitModifiers = ClearUnitModifiers,
	GetUnitModifiers = GetUnitModifiers,
	IsInModifier = IsInModifier,
	SetModifierStackCount = SetModifierStackCount,
	AddModifierStackCount = AddModifierStackCount,
	AddModifierDurationByInstance = AddModifierDurationByInstance,
	SetModifierRemainTime = SetModifierRemainTime,
	GetModifierOwner = GetModifierOwner,
	-- 扩展接口
	Pause = Pause,
	Resume = Resume,
	SetInterruptModifierObtain = SetInterruptModifierObtain,
	GetRemainingTimeByKey = GetRemainingTimeByKey,
	GetSourceByKey = GetSourceByKey,
}
