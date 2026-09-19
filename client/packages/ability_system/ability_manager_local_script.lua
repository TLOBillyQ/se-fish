--技能系统 - client技能管理器绑定
-- 由 client/main.lua 在找到 AbilityManager 后 attach(manager) 驱动，
-- 负责：客户端 abilities 镜像 + RemoteEvent 通知分发 + 子节点监听（绑定/解绑 UI）。

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityEventDefs = require("common.packages.ability_system.event_defs")
local AbilityRegistry = require("common.packages.ability_system.registry")
local AbilityUIHooks = require("common.packages.ability_system.ui_hooks")

local M = {}

-- 幂等标记：防止重复 attach
local _attachedManager = nil

-- attach：把客户端监听挂到 manager 上
---@param manager ScriptUnit AbilityManager（character 的子节点）
function M.attach(manager)
	if not manager then
		return false
	end
	if _attachedManager == manager then
		return true
	end

	local RunService = game:GetService("RunService")
	if not RunService:IsClient() then
		return false
	end

	-- UI 绑定链路就绪保障：确保 UIManager 单例与 hooks 注入（幂等），防止钩子停留在占位实现。
	local UIManager = require("client.packages.ability_system.ui.UIManager")
	if not UIManager.GetInstance() then
		UIManager.new(manager)
	end

	-- manager 切换（重生/换角色）：清掉上一个 manager 的旧 UI 绑定，
	-- 否则旧 controllers 占着槽位，新技能无法重新绑定。
	if _attachedManager then
		local um = UIManager.GetInstance()
		if um then
			um:ResetBindings()
		end
	end

	_attachedManager = manager

	-- 客户端 abilities 镜像（按槽位索引缓存）
	local abilities = {}

	-- 单一 RemoteEvent 通道（与 server 共享）
	local remoteEvent = AbilityEventDefs.getRemote()

	-- 标记 manager（客户端识别用）
	AbilityRegistry.addTag(manager, AbilityConstants.Tag.AbilityManager)

	-- ability_local_script：技能实例 reactive 绑定模块
	local ItemLocalScript = require("client.packages.ability_system.ability_local_script")

	-- 判断 child 是否为技能 ScriptUnit（tag 优先，Index attribute 兜底）
	local function isAbilityChild(child)
		if not child then
			return false
		end
		if AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityUnit) then
			return true
		end
		local ok, idx = pcall(function()
			return child:GetAttribute("Index")
		end)
		return ok and idx ~= nil and idx >= AbilityConstants.SLOT_BASE
	end

	-- 绑定单个技能：镜像缓存 + 通知 UI + 挂 item reactive 绑定（幂等）
	local function bindAbility(child, slotIndex)
		if not child or not slotIndex then
			return
		end
		if abilities[slotIndex] == child then
			return
		end
		abilities[slotIndex] = child
		ItemLocalScript.attach(child)
		AbilityUIHooks.onAbilityAdded(manager, child, slotIndex)
	end

	-- 槽位禁用/置灰（ForbidSlot 广播）：
	-- 广播含所有玩家，按角色 UnitId 过滤本地角色后调 AbilitySlot.SetForbidden
	local function _handleForbidSlot(unitId, slotIndex, isForbid, grayout)
		local owner = manager.Parent
		if not owner then
			return
		end
		local ok, ownerUnitId = pcall(function()
			return owner.UnitId
		end)
		if not ok or ownerUnitId ~= unitId then
			return
		end

		local um = UIManager.GetInstance()
		if not um or not um.controllers then
			return
		end
		local controller = um.controllers[slotIndex]
		if controller and controller._node then
			local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
			AbilitySlot.SetForbidden(
				controller._node,
				isForbid and true or false,
				grayout and true or false
			)
		end
	end

	-- OnClientEvent 分发（s→c 通知）
	-- 载荷：{ action = ..., args = {...} }（单参数契约）

	remoteEvent.OnClientEvent:Connect(function(payload)
		local action
		local args = {}
		if type(payload) == "table" and payload.action then
			action = payload.action
			args = payload.args or {}
		else
			action = payload
		end

		if action == AbilityEventDefs.ServerAction.OnSwitchNext then
			-- args = { ownerUnitId, parentSlotIndex, newActiveIndex }
			-- （FireAllClients 广播，按归属过滤）
			local ownerUnitId, parentSlotIndex, newActiveIndex = args[1], args[2], args[3]
			local owner = manager.Parent
			if not owner then
				return
			end
			local ok, selfUnitId = pcall(function()
				return owner.UnitId
			end)
			if not ok or selfUnitId ~= ownerUnitId then
				return
			end
			AbilityUIHooks.onSwitchNext(manager, parentSlotIndex, newActiveIndex)
		elseif action == AbilityEventDefs.ServerAction.ForbidSlot then
			-- 槽位禁用/启用广播：args = { unitId, slotIndex, isForbid, grayout }
			_handleForbidSlot(args[1], args[2], args[3], args[4])
		elseif action == AbilityEventDefs.ServerAction.FullSnapshot then
			local playerId, abilityStates = args[1], args[2]
			_handleFullSnapshot(playerId, abilityStates)
		elseif action == "AbilityAdded" then
			-- server 通知新 ability 入场（ChildAdded 之外的兜底通道）
			local abilityUnitId, slotIndex = args[1], args[2]
			if abilities[slotIndex] then
				return
			end
			for _, child in ipairs(manager:GetChildren()) do
				if
					child.UnitId == abilityUnitId
					or (
						AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityUnit)
						and child:GetAttribute("Index") == slotIndex
					)
				then
					bindAbility(child, slotIndex)
					break
				end
			end
		elseif action == "AbilityRemoved" then
			local slotIndex = args[1]
			if abilities[slotIndex] then
				AbilityUIHooks.onAbilityRemoved(manager, slotIndex)
				abilities[slotIndex] = nil
			end
		elseif action == "AbilityMoved" then
			local fromIndex, toIndex = args[1], args[2]
			if abilities[fromIndex] then
				local abilityScript = abilities[fromIndex]
				abilities[fromIndex] = nil
				abilities[toIndex] = abilityScript
			end
		end
		-- 其余 action（OnCastStart/OnCastEnd/OnCharge 等）由 ability_local_script
		-- 的 reactive 属性绑定驱动 UI，无需在此处理
	end)

	-- FastCatch 全量快照

	function _handleFullSnapshot(playerId, abilityStates)
		for i = 1, #abilities do
			abilities[i] = nil
		end
		for _, state in ipairs(abilityStates or {}) do
			for _, child in ipairs(manager:GetChildren()) do
				if
					child.UnitId == state.unitId
					or AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityUnit)
				then
					bindAbility(child, state.slotIndex)
					break
				end
			end
		end
	end

	-- 子节点监听
	-- ChildAdded 触发时 Index attribute 可能未同步，等 Index 就绪后再绑

	manager.ChildAdded:Connect(function(child)
		local function tryBind()
			local slotIndex = child:GetAttribute("Index")
			-- Index<SLOT_BASE（-1 未入槽哨兵）是初始化中间态，
			-- 等待同步到真实槽位再绑
			if not slotIndex or slotIndex < AbilityConstants.SLOT_BASE then
				return false
			end
			bindAbility(child, slotIndex)
			return true
		end

		if tryBind() then
			return
		end

		-- Index 未就绪：监听 Index 属性变化
		local conn = nil
		if child.GetAttributeChangedSignal then
			local sig = child:GetAttributeChangedSignal("Index")
			if sig and sig.Connect then
				conn = sig:Connect(function()
					if tryBind() and conn and conn.Disconnect then
						conn:Disconnect()
					end
				end)
			end
		end

		-- 兜底：等 Posted（Index 通常已同步）
		if child.Posted then
			child.Posted:Connect(function()
				if not tryBind() then
					game:GetService("Task"):Wait(0.1)
					tryBind()
				end
			end)
		end
	end)

	manager.ChildRemoved:Connect(function(child)
		if not isAbilityChild(child) then
			return
		end
		for slotIndex, abilityScript in pairs(abilities) do
			if abilityScript == child then
				AbilityUIHooks.onAbilityRemoved(manager, slotIndex)
				abilities[slotIndex] = nil
				break
			end
		end
	end)

	-- 已有子节点补绑（attach 前已存在的技能子节点）

	local function scanExistingChildren()
		local ok, children = pcall(function()
			return manager:GetChildren()
		end)
		if ok and children then
			for _, child in ipairs(children) do
				if isAbilityChild(child) then
					local slotIndex = child:GetAttribute("Index")
					if
						slotIndex
						and slotIndex >= AbilityConstants.SLOT_BASE
						and not abilities[slotIndex]
					then
						bindAbility(child, slotIndex)
					end
				end
			end
		end
	end

	scanExistingChildren()

	return true
end

-- 兼容路径：若脚本被作为 LocalScript 挂载（挂在 manager 下），自动 attach
if script and script.Parent then
	M.attach(script.Parent)
	-- 启动客户端生命周期（LocalPlayer 等待 / CharacterAdded 重生重挂，幂等）
	require("client.packages.ability_system.api").StartClientLifecycle()
end

return M
