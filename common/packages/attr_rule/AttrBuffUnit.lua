--属性规则包 - 属性加成单位方法集（双端共用）
--AttrBuffUnit：无状态方法字典，操作属性加成单位

local Configs = require("common.packages.attr_rule.configs")
local utils = require("common.packages.attr_rule.utils")
local AttrUnit = require("common.packages.attr_rule.AttrUnit")
-- 文件级别名：正文里反复用到的键名，避免到处写模块前缀
local ATTR_BUFF_CONFIGS_ATTRIBUTE = Configs.ATTR_BUFF_CONFIGS_ATTRIBUTE
local ATTR_BUFF_TARGET_UNIT_ATTRIBUTE = Configs.ATTR_BUFF_TARGET_UNIT_ATTRIBUTE
local ATTR_BUFF_ID_ATTRIBUTE = Configs.ATTR_BUFF_ID_ATTRIBUTE

---属性加成单位的状态记录
---@class AttrBuffUnitState
---@field configs AttrBuffConfig[] 加成配置列表
---@field targetUnit Unit? 当前目标单位
---@field attrBuffId Int? 生效中的 Buff 句柄

local AttrBuffUnit = {}

---监听加成单位销毁：自动撤回已应用的加成，避免加成残留在目标单位上。
---@param buffUnit Script 属性加成单位
local function bindDestroyingRevoke(buffUnit)
	if buffUnit and buffUnit.Destroying then
		buffUnit.Destroying:Connect(function()
			local ok, err = pcall(AttrBuffUnit.SetTargetUnit, buffUnit, nil)
			if not ok then
				print(string.format("[attr_rule] failed to revoke attr buff on destroying: %s", tostring(err)))
			end
		end)
	end
end

---在指定单位的子节点里查找属性加成单位
---@param unit Unit 加成单位挂载的单位
---@return Script? 属性加成单位
function AttrBuffUnit.FindAttrBuffUnitOf(unit)
	return utils.findChildScriptByPrefabType(unit, Configs.ATTR_BUFF_UNIT_PREFAB_TYPE)
end

---初始化属性加成单位：把加成配置写到加成单位自身
---@param buffUnit Script 属性加成单位
---@param config table? 初始化配置：{ AttrBuffConfigs = AttrBuffConfig[] } 加成配置列表
---@return Bool success, String? err
function AttrBuffUnit.InitAttrBuffUnit(buffUnit, config)
	assert(buffUnit ~= nil, "AttrBuffUnit.InitAttrBuffUnit: buffUnit must not be nil")
	if AttrBuffUnit.GetState(buffUnit) ~= nil then
		return true, nil
	end
	local attrBuffConfigs = type(config) == "table" and config.AttrBuffConfigs or nil
	if attrBuffConfigs == nil then
		attrBuffConfigs = buffUnit:GetAttribute(Configs.ATTR_BUFF_CONFIGS_ATTRIBUTE)
	end
	AttrBuffUnit.InitState(buffUnit, attrBuffConfigs or {})
	bindDestroyingRevoke(buffUnit)
	return true, nil
end

---初始化加成单位的状态，随单位同步到客户端
---@param buffUnit Script 属性加成单位
---@param configs AttrBuffConfig[] 加成配置列表
function AttrBuffUnit.InitState(buffUnit, configs)
	buffUnit:SetAttribute(ATTR_BUFF_CONFIGS_ATTRIBUTE, configs)
	buffUnit:SetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE, nil)
	buffUnit:SetAttribute(ATTR_BUFF_ID_ATTRIBUTE, nil)
end

---读取加成单位的状态，未初始化时返回 nil。
---@param buffUnit Script 属性加成单位
---@return AttrBuffUnitState? 状态快照
function AttrBuffUnit.GetState(buffUnit)
	if buffUnit == nil then
		return nil
	end
	local configs = buffUnit:GetAttribute(ATTR_BUFF_CONFIGS_ATTRIBUTE)
	if configs == nil then
		return nil
	end
	return {
		configs = configs,
		targetUnit = buffUnit:GetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE),
		attrBuffId = buffUnit:GetAttribute(ATTR_BUFF_ID_ATTRIBUTE),
	}
end

---获取当前的目标单位
---@param buffUnit Script 属性加成单位
---@return Unit? 目标单位
function AttrBuffUnit.GetTargetUnit(buffUnit)
	if buffUnit == nil then
		return nil
	end
	return buffUnit:GetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE)
end

---设置目标单位：先撤回旧目标上的加成，再应用到新目标，传 nil 表示纯解除
---@param buffUnit Script 属性加成单位
---@param targetUnit Unit? 新的目标单位
---@return Bool success, String? err
function AttrBuffUnit.SetTargetUnit(buffUnit, targetUnit)
	local state = AttrBuffUnit.GetState(buffUnit)
	if state == nil then
		return false, "[attr_rule] attr buff unit is not initialized"
	end

	-- 撤回旧目标：目标已销毁时加成随单位销毁自动消失，parent 判活跳过撤回
	if state.targetUnit ~= nil and state.attrBuffId ~= nil then
		local oldTargetUnit = state.targetUnit
		if oldTargetUnit.Parent ~= nil then
			local oldAttrUnit = AttrUnit.FindAttrUnitOf(oldTargetUnit)
			if oldAttrUnit ~= nil then
				local removed, removeErr = AttrUnit.RemoveAttrBuff(oldAttrUnit, state.attrBuffId)
				if not removed then
					print(string.format(
						"[attr_rule] failed to remove attr buff %s: %s",
						tostring(state.attrBuffId),
						tostring(removeErr)
					))
				end
			end
		end
	end
	buffUnit:SetAttribute(ATTR_BUFF_ID_ATTRIBUTE, nil)

	if targetUnit == nil then
		buffUnit:SetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE, nil)
		return true, nil
	end

	local attrUnit = AttrUnit.FindAttrUnitOf(targetUnit)
	if attrUnit == nil then
		buffUnit:SetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE, nil)
		return false, "[attr_rule] no attr unit found under the target unit"
	end
	local attrBuffId, err = AttrUnit.AddAttrBuff(attrUnit, state.configs)
	if attrBuffId == nil then
		buffUnit:SetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE, nil)
		return false, err
	end
	buffUnit:SetAttribute(ATTR_BUFF_TARGET_UNIT_ATTRIBUTE, targetUnit)
	buffUnit:SetAttribute(ATTR_BUFF_ID_ATTRIBUTE, attrBuffId)
	return true, nil
end

return AttrBuffUnit
