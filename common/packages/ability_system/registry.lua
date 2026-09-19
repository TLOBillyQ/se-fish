--技能系统 - common注册表
-- Ability/Manager/Group 字典 + 多态 domain Registry。
-- 键规范：优先单位 UnitId；不可读时回退 tostring(script)。

local AbilityConstants = require("common.packages.ability_system.constants")

local AbilityRegistry = {}

-- 键推导：优先 UnitId，异常/缺失时回退 tostring(script)
local function _unitKey(script_unit)
	local ok, unit_id = pcall(function()
		return script_unit.UnitId
	end)
	if ok and unit_id ~= nil and unit_id ~= 0 then
		return unit_id
	end
	return tostring(script_unit)
end

-- 键推导：优先 UnitId，异常/缺失时回退 tostring(script)
-- 供外部消费方（如 sub_ability 的 _childHandlersKeys）与 registry 内部保持同键规范
function AbilityRegistry.unitKeyOf(scriptUnit)
	return _unitKey(scriptUnit)
end

-- Ability / Manager / Group 全局反查字典
-- key = _unitKey(scriptUnit)；value = handler table 或 entry

AbilityRegistry._abilities = {} -- [UnitId] = handler
AbilityRegistry._managers = {} -- [UnitId] = { handler=, owner= }
AbilityRegistry._groups = {} -- [UnitId(父技能)] = group table

-- Ability 注册 / 反注册

function AbilityRegistry.registerAbility(abilityScript, handler)
	AbilityRegistry._abilities[_unitKey(abilityScript)] = handler
end

function AbilityRegistry.unregisterAbility(abilityScript)
	AbilityRegistry._abilities[_unitKey(abilityScript)] = nil
end

function AbilityRegistry.getAbilityHandler(abilityScript)
	return AbilityRegistry._abilities[_unitKey(abilityScript)]
end

-- Manager 注册 / 反注册 / 反查

function AbilityRegistry.registerManager(managerScript, handler, owner)
	AbilityRegistry._managers[_unitKey(managerScript)] = { handler = handler, owner = owner }
end

function AbilityRegistry.unregisterManager(managerScript)
	AbilityRegistry._managers[_unitKey(managerScript)] = nil
end

function AbilityRegistry.getManagerHandler(managerScript)
	local entry = AbilityRegistry._managers[_unitKey(managerScript)]
	return entry and entry.handler or nil
end

function AbilityRegistry.findManagerForPlayer(player)
	local key = _unitKey(player)
	for _, entry in pairs(AbilityRegistry._managers) do
		if entry.owner and _unitKey(entry.owner) == key then
			return entry.handler
		end
	end
	return nil
end

-- Group 注册 / 反查

function AbilityRegistry.registerGroup(parentAbilityScript, group)
	AbilityRegistry._groups[_unitKey(parentAbilityScript)] = group
end

function AbilityRegistry.unregisterGroup(parentAbilityScript)
	AbilityRegistry._groups[_unitKey(parentAbilityScript)] = nil
end

function AbilityRegistry.findGroup(parentAbilityScript)
	return AbilityRegistry._groups[_unitKey(parentAbilityScript)]
end

-- 按子 ability 找其所属 group：遍历 _groups
function AbilityRegistry.findGroupByChild(childAbilityScript)
	local child_key = _unitKey(childAbilityScript)
	for _, group in pairs(AbilityRegistry._groups) do
		if group._childHandlersKeys and group._childHandlersKeys[child_key] then
			return group
		end
		if group._childrenKeys and group._childrenKeys[child_key] then
			return group
		end
	end
	return nil
end

-- 多态 domain Registry（Pointer / Strategy 等开放注册）

AbilityRegistry._domains = {}

function AbilityRegistry.register(domain, key, value)
	if not AbilityRegistry._domains[domain] then
		AbilityRegistry._domains[domain] = {}
	end
	AbilityRegistry._domains[domain][key] = value
end

function AbilityRegistry.get(domain, key)
	local d = AbilityRegistry._domains[domain]
	if not d then
		return nil
	end
	return d[key]
end

function AbilityRegistry.list(domain)
	local d = AbilityRegistry._domains[domain]
	if not d then
		return {}
	end
	local result = {}
	for k, _ in pairs(d) do
		table.insert(result, k)
	end
	return result
end

-- 系统级：存放作者用 AbilityAPI.defineAbility 注册的配置
-- key = config.name；value = config table

AbilityRegistry._definitions = {}

function AbilityRegistry.registerDefinition(name, config)
	AbilityRegistry._definitions[name] = config
end

function AbilityRegistry.getDefinition(name)
	return AbilityRegistry._definitions[name]
end

-- Tag 兼容封装
-- 优先调用引擎 UnitComponentTags 组件；失败 fallback 到 Lua-level tag set
-- 这样 ScriptUnit 即使不绑 UnitComponentTags 也能正常工作

AbilityRegistry._luaTags = {} -- [UnitId] = { tag1, tag2, ... }

local function _getTagsComp(scriptUnit)
	local ok, comp = pcall(function()
		return scriptUnit:GetComponent("UnitComponentTags")
	end)
	if ok and comp then
		return comp
	end
	return nil
end

function AbilityRegistry.addTag(scriptUnit, tag)
	-- fallback Lua table
	local key = _unitKey(scriptUnit)
	if not AbilityRegistry._luaTags[key] then
		AbilityRegistry._luaTags[key] = {}
	end
	-- 去重
	for _, t in ipairs(AbilityRegistry._luaTags[key]) do
		if t == tag then
			return
		end
	end
	table.insert(AbilityRegistry._luaTags[key], tag)
	-- 优先尝试引擎级 AddTag
	local comp = _getTagsComp(scriptUnit)
	if comp then
		local ok = pcall(function()
			comp:AddTag(tag)
		end)
		-- 引擎级失败也不报错，Lua-level 已经记录
	end
end

function AbilityRegistry.hasTag(scriptUnit, tag)
	-- 先尝试引擎级 HasTag
	local comp = _getTagsComp(scriptUnit)
	if comp then
		local ok, has = pcall(function()
			return comp:HasTag(tag)
		end)
		if ok and has then
			return true
		end
	end
	-- fallback Lua level
	local key = _unitKey(scriptUnit)
	local tags = AbilityRegistry._luaTags[key]
	if not tags then
		return false
	end
	for _, t in ipairs(tags) do
		if t == tag then
			return true
		end
	end
	return false
end

function AbilityRegistry.removeTag(scriptUnit, tag)
	local comp = _getTagsComp(scriptUnit)
	if comp then
		pcall(function()
			comp:RemoveTag(tag)
		end)
	end
	local key = _unitKey(scriptUnit)
	local tags = AbilityRegistry._luaTags[key]
	if not tags then
		return
	end
	for i = #tags, 1, -1 do
		if tags[i] == tag then
			table.remove(tags, i)
		end
	end
end

-- 清理 Unit 销毁时的所有 lua tag 注册（避免内存泄漏）
function AbilityRegistry.clearTags(scriptUnit)
	local key = _unitKey(scriptUnit)
	AbilityRegistry._luaTags[key] = nil
end

return AbilityRegistry
