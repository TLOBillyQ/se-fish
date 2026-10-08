--效果系统包 - client端api
--面向业务代码的效果操作入口：查询读本地镜像；修改为请求发往服务端执行，结果以服务端回推为准。
--客户端不提供添加接口，添加为服务端权威。
--读取约定：查询返回效果实体，即效果实例，字段直接从实体读取。
--  效果配置：Name / ModifierDesc / Icon / UgcModifierType / MaxStackCount
--  运行时状态：IsActive / CurrCount / CharMtg / IsPaused / EndTime / ModifierKey
--  实体自身：UnitId

local World = game:GetService("World")

local modifierSystem = require("client.packages.modifier_system.modifier_system")

---判断单位是否为有效拥有者，非 World 且 UnitId 有效；复制竞态下 Parent 可能暂为 World
---@param unit Unit? 待判定的单位
---@return boolean 是否有效
local function isValidOwner(unit)
	if not unit then
		return false
	end
	local okIsA, isNotWorld = pcall(function()
		return not unit:IsA("World")
	end)
	if not okIsA or not isNotWorld then
		return false
	end
	local ok, unitId = pcall(function()
		return unit.UnitId
	end)
	return ok and unitId ~= nil and unitId ~= 0
end

---解析效果实体的请求路由：返回 拥有者单位、效果 Key、实体 UnitId；无法解析时返回 nil
---客户端复制单位可能拿不到 Parent，经 OwnerUnitId 属性反查拥有者
local function resolveEntityRoute(modifierUnit)
	if not modifierUnit then
		return nil
	end
	local okUnitId, unitId = pcall(function()
		return modifierUnit.UnitId
	end)
	if not okUnitId or not unitId then
		return nil
	end
	local owner = nil
	local okParent, parent = pcall(function()
		return modifierUnit.Parent
	end)
	if okParent and isValidOwner(parent) then
		owner = parent
	end
	if not owner then
		local okOwnerId, ownerId = pcall(function()
			return modifierUnit:GetAttribute("OwnerUnitId")
		end)
		ownerId = okOwnerId and tonumber(ownerId) or nil
		if ownerId then
			local okLookup, unit = pcall(function()
				return World:GetUnitByID(ownerId)
			end)
			if okLookup and isValidOwner(unit) then
				owner = unit
			end
		end
	end
	if not owner then
		return nil
	end
	local okKey, key = pcall(function()
		return modifierUnit:GetAttribute("ModifierKey")
	end)
	return owner, (okKey and key) or "", unitId
end

-- 请求：发往服务端执行，返回值为"请求是否已发出"

---请求移除指定效果实例
---@param modifierUnit Unit 效果实体单位
---@return boolean 请求是否已发出
local function RemoveModifier(modifierUnit)
	local owner, key, unitId = resolveEntityRoute(modifierUnit)
	if not owner then
		return false
	end
	return modifierSystem:removeModifier(owner, key, unitId)
end

---请求移除拥有者身上指定 Key 的所有效果；Key 为空时清除全部
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string? 效果 Key，为空清除全部
---@return number 恒返回 0，结果以服务端回推为准
local function ClearUnitModifiers(ownerUnit, modifierKey)
	if modifierKey and modifierKey ~= "" then
		return modifierSystem:removeModifierByKey(ownerUnit, modifierKey)
	end
	return modifierSystem:clearAllModifiers(ownerUnit)
end

---请求设置效果实例的层数
---@param modifierUnit Unit 效果实体单位
---@param count number 目标层数
---@return boolean 请求是否已发出
local function SetModifierStackCount(modifierUnit, count)
	local owner, key, unitId = resolveEntityRoute(modifierUnit)
	if not owner then
		return false
	end
	return modifierSystem:setStackCount(owner, key, count, unitId)
end

---请求增减效果实例的层数
---@param modifierUnit Unit 效果实体单位
---@param delta number 层数增量
---@return number 恒返回 0，结果以服务端回推为准
local function AddModifierStackCount(modifierUnit, delta)
	local owner, key, unitId = resolveEntityRoute(modifierUnit)
	if not owner then
		return 0
	end
	return modifierSystem:addStackCount(owner, key, delta, unitId)
end

---请求延长效果实例的持续时间
---@param modifierUnit Unit 效果实体单位
---@param extra number 延长时间，单位秒
---@return boolean 请求是否已发出
local function AddModifierDurationByInstance(modifierUnit, extra)
	local owner, key, unitId = resolveEntityRoute(modifierUnit)
	if not owner then
		return false
	end
	return modifierSystem:addDuration(owner, key, extra, unitId)
end

---请求设置效果实例的剩余时间
---@param modifierUnit Unit 效果实体单位
---@param remaining number 剩余时间
---@return boolean 请求是否已发出
local function SetModifierRemainTime(modifierUnit, remaining)
	local owner, key, unitId = resolveEntityRoute(modifierUnit)
	if not owner then
		return false
	end
	return modifierSystem:setRemainTime(owner, key, remaining, unitId)
end

---请求暂停指定 Key 效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
local function Pause(ownerUnit, modifierKey, unitId)
	return modifierSystem:pause(ownerUnit, modifierKey, unitId)
end

---请求恢复指定 Key 效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
local function Resume(ownerUnit, modifierKey, unitId)
	return modifierSystem:resume(ownerUnit, modifierKey, unitId)
end

-- 查询：读本地镜像；返回效果实体，字段读实体属性，见文件头"读取约定"

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

---拥有者是否拥有指定 Key 的效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return boolean 是否存在
local function IsInModifier(ownerUnit, modifierKey)
	return modifierSystem:hasModifier(ownerUnit, modifierKey)
end

---获取指定 Key 效果的剩余时间，按状态 EndTime 换算，永久效果返回 -1
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 剩余时间
local function GetRemainingTimeByKey(ownerUnit, modifierKey)
	return modifierSystem:getRemainingTimeByKey(ownerUnit, modifierKey)
end

return {
	-- 请求
	RemoveModifier = RemoveModifier,
	ClearUnitModifiers = ClearUnitModifiers,
	SetModifierStackCount = SetModifierStackCount,
	AddModifierStackCount = AddModifierStackCount,
	AddModifierDurationByInstance = AddModifierDurationByInstance,
	SetModifierRemainTime = SetModifierRemainTime,
	Pause = Pause,
	Resume = Resume,
	-- 查询
	GetUnitModifiers = GetUnitModifiers,
	IsInModifier = IsInModifier,
	GetRemainingTimeByKey = GetRemainingTimeByKey,
}
