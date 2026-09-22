--技能系统 - server技能管理器逻辑
-- 技能管理器服务端共享逻辑：槽位管理 / 客户端通知 / 生命周期。
-- 由管理器预设壳（ability_manager_script.lua）在服务端 require 并调用 Attach(script)。

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityEventDefs = require("common.packages.ability_system.event_defs")
local AbilityRegistry = require("common.packages.ability_system.registry")
local AbilityUtils = require("common.packages.ability_system.util")

local AbilityManagerLogic = {}

local _attached = setmetatable({}, { __mode = "k" })

function AbilityManagerLogic.Attach(manager)
	local RunService = game:GetService("RunService")

	if not RunService:IsServer() then
		return
	end

	-- 重复挂载保护
	if _attached[manager] then
		return
	end
	_attached[manager] = true

	local World = game:GetService("World")
	local Players = game:GetService("Players")

	-- 初始化运行时状态（不暴露编辑器）
	manager:SetAttribute("OwnerId", "")
	manager:SetAttribute("PlayerId", 0)
	manager:SetAttribute("ManagerReady", false)

	-- 槽位数组（本地 Lua cache，存 AbilityItem ScriptUnit 引用）
	-- 槽位编号 0 基、无上限：键=槽位索引，值=技能 ScriptUnit（稀疏表）
	local abilities = {} -- [slotIndex] -> abilityScript or nil

	-- 创建管理器级 signals（BindableEvent 事件单位挂在 manager 下）
	local signals = AbilityEventDefs.createManagerSignals(manager)

	-- 单一 RemoteEvent 通道（与客户端共享）
	local remoteEvent = AbilityEventDefs.getRemote()

	-- 标记自己为 AbilityManager ScriptUnit
	AbilityRegistry.addTag(manager, AbilityConstants.Tag.AbilityManager)

	-- 内部辅助函数

	local function getUnitId()
		-- 引擎 Unit.UnitId 字段；如果不可读 fallback 0
		local ok, val = pcall(function()
			return manager.UnitId
		end)
		return ok and val or 0
	end

	local function notifyClients(action, ...)
		-- RemoteEvent 契约：FireAllClients 单参数 table 打包
		remoteEvent:FireAllClients(AbilityEventDefs.packServerPayload(action, ...))
	end

	-- handler 方法（暴露给 AbilityAPI、AbilityRegistry 反查）

	local handler = {}

	function handler.getManager()
		return manager
	end

	function handler.getOwner()
		return manager.Parent
	end

	function handler.getOwnerId()
		return manager:GetAttribute("OwnerId")
	end

	function handler.getAbilities()
		return AbilityUtils.sortByIndex(abilities)
	end

	-- 第一个空槽（无上限：从 SLOT_BASE 起找第一个未占用索引）
	function handler.getFirstAvailableSlot()
		return AbilityUtils.getFirstAvailableSlot(abilities, AbilityConstants.SLOT_BASE)
	end

	function handler.getAbility(slotIndex)
		if not AbilityUtils.isSlotValid(nil, slotIndex) then
			return nil
		end
		local abilityScript = abilities[slotIndex]
		if not abilityScript then
			return nil
		end
		return AbilityRegistry.getAbilityHandler(abilityScript)
	end

	function handler.addAbility(abilityScript, slotIndex)
		if not AbilityUtils.isSlotValid(nil, slotIndex) then
			return false
		end
		if not AbilityUtils.isSlotEmpty(abilities, slotIndex) then
			return false
		end
		-- 设置层级关系（引擎自动同步父子结构到客户端）
		abilityScript.Parent = manager
		-- 写入 Index attribute，让客户端可按 Index 反查
		abilityScript:SetAttribute("Index", slotIndex)
		-- 技能继承管理器归属（客户端归属检查用；"" 表示归属尚未解析，客户端放行）
		abilityScript:SetAttribute("OwnerId", manager:GetAttribute("OwnerId") or "")
		abilities[slotIndex] = abilityScript

		local abilityHandler = AbilityRegistry.getAbilityHandler(abilityScript)
		signals.AbilityAdded:Fire(abilityScript, slotIndex)
		notifyClients("AbilityAdded", abilityScript.UnitId, slotIndex)
		return true
	end

	function handler.removeAbility(slotIndex)
		local abilityScript = abilities[slotIndex]
		if not abilityScript then
			return nil
		end
		abilities[slotIndex] = nil
		signals.AbilityRemoved:Fire(abilityScript, slotIndex)
		notifyClients("AbilityRemoved", slotIndex)
		return abilityScript
	end

	function handler.stopAbility(slotIndex)
		local abilityHandler = AbilityRegistry.getAbilityHandler(abilities[slotIndex])
		if abilityHandler and abilityHandler.breakCast then
			abilityHandler.breakCast()
			return true
		end
		return false
	end

	function handler.forbidSlot(slotIndex, isForbid, grayout)
		-- 槽位禁用/启用：广播所有客户端，unitId = 角色单位
		local ownerUnit = manager.Parent
		notifyClients(
			AbilityEventDefs.ServerAction.ForbidSlot,
			ownerUnit and ownerUnit.UnitId or getUnitId(),
			slotIndex,
			isForbid and true or false,
			grayout and true or false
		)
		return true
	end

	function handler.moveAbility(fromIndex, toIndex)
		local fromItem = abilities[fromIndex]
		local toItem = abilities[toIndex]
		if not fromItem then
			return false
		end
		abilities[fromIndex] = toItem
		abilities[toIndex] = fromItem
		if toItem then
			toItem:SetAttribute("Index", fromIndex)
		end
		fromItem:SetAttribute("Index", toIndex)
		notifyClients("AbilityMoved", fromIndex, toIndex)
		return true
	end

	-- 子技能组切换专用：整体替换槽位成员（旧成员转休眠由调用方负责其 Index 置 -1）
	-- 与 addAbility/removeAbility 的差异：不做 Parent 挂载与空槽校验，
	-- 单次调用完成"旧成员移出槽位 + 新成员上位"的缓存更新 / 信号 / 客户端通知三件事。
	-- 先发 Removed 再发 Added：客户端 abilities[slotIndex] 先清后绑（manager_local :115-126 依赖此顺序）。
	function handler.setSlotAbility(slotIndex, abilityScript)
		if not AbilityUtils.isSlotValid(nil, slotIndex) then
			return false
		end
		local old = abilities[slotIndex]
		if old == abilityScript then
			return true
		end
		abilities[slotIndex] = abilityScript
		if old then
			signals.AbilityRemoved:Fire(old, slotIndex)
			notifyClients("AbilityRemoved", slotIndex)
		end
		if abilityScript then
			abilityScript:SetAttribute("Index", slotIndex)
			abilityScript:SetAttribute("OwnerId", manager:GetAttribute("OwnerId") or "")
			signals.AbilityAdded:Fire(abilityScript, slotIndex)
			notifyClients("AbilityAdded", abilityScript.UnitId, slotIndex)
		end
		return true
	end

	-- 子技能组切换通知（s→c OnSwitchNext）：作者级钩子 + 上层感知；
	-- UI 槽位跟随不走此通道（由 setSlotAbility 的 Removed/Added 通知驱动）。
	-- args = { ownerUnitId, slotIndex, newActiveIndex }，客户端按 ownerUnitId 过滤（对齐 ForbidSlot 先例）。
	function handler.notifySwitchNext(slotIndex, newActiveIndex)
		local ownerUnit = manager.Parent
		notifyClients(
			AbilityEventDefs.ServerAction.OnSwitchNext,
			ownerUnit and ownerUnit.UnitId or getUnitId(),
			slotIndex,
			newActiveIndex
		)
	end

	function handler.getAbilitiesInSlotRange(startIndex, endIndex)
		local result = {}
		for i = startIndex, endIndex do
			if abilities[i] then
				table.insert(result, abilities[i])
			end
		end
		return result
	end

	-- 注册 self 到 AbilityRegistry（让外部可通过 player 找到）
	AbilityRegistry.registerManager(manager, handler, manager.Parent)

	-- 初始技能配置（InitAbilities）
	-- 作者在编辑器配置的初始技能列表：{ AssetId = 技能预设URI, Index = 槽位 }。
	-- 角色生成后自动把这些技能装备到对应槽位；
	-- AddAbility 对空 AssetId 与已占用槽位均安全（幂等，不覆盖既有技能）。
	local function tryInitAbilities()
		local initAbilities = nil
		local ok, val = pcall(function()
			return manager:GetAttribute("InitAbilities")
		end)
		if ok and val and type(val) == "table" then
			initAbilities = val
		end
		if not initAbilities then
			ok, val = pcall(function()
				return manager.InitAbilities
			end)
			if ok and val and type(val) == "table" then
				initAbilities = val
			end
		end
		if not initAbilities or #initAbilities == 0 then
			return
		end

		local AbilityServerAPI = require("server.packages.ability_system.api")
		local ownerUnit = manager.Parent
		if not ownerUnit then
			return
		end
		for _, entry in ipairs(initAbilities) do
			if entry and entry.AssetId and entry.AssetId ~= "" then
				AbilityServerAPI.AddAbility(ownerUnit, entry.AssetId, entry.Index)
			end
		end
	end

	-- Owner 归属写入（OwnerId = 玩家名，PlayerId = UserId）
	-- 客户端归属检查与 c→s 载荷的 ownerId 均读此字段；
	-- 解析依赖 manager.Parent（角色）就绪后走 Players 反查。
	local Task = game:GetService("Task")

	local function resolveOwner()
		local ownerUnit = manager.Parent
		if not ownerUnit then
			return false
		end
		local player = Players:GetPlayerFromCharacter(ownerUnit)
		if not player then
			return false
		end
		local ok, name, userId = pcall(function()
			return player:GetName(), player.UserId
		end)
		if not ok or not name or name == "" then
			return false
		end
		if manager:GetAttribute("OwnerId") ~= name then
			manager:SetAttribute("OwnerId", name)
		end
		if userId and manager:GetAttribute("PlayerId") ~= userId then
			manager:SetAttribute("PlayerId", userId)
		end
		return true
	end

	-- Attach 时同步尝试；Parent 尚未挂好时有界重试（1s）
	if not resolveOwner() then
		local _resolveRetried = 0
		local function retryResolve()
			if resolveOwner() then
				return
			end
			_resolveRetried = _resolveRetried + 1
			if _resolveRetried < 10 then
				Task:Delay(0.1, retryResolve)
			end
		end
		Task:Delay(0.1, retryResolve)
	end

	tryInitAbilities()

	-- 注：客户端施法请求（Cast/BreakCast 等 c→s 监听）由 api.lua 的
	-- RegisterEvents() 统一分发（模块加载时自动注册），本模块不再重复监听。

	-- 销毁清理

	manager.Destroying:Connect(function()
		-- 反注册 manager
		AbilityRegistry.unregisterManager(manager)
		AbilityRegistry.clearTags(manager)
		-- 清理所有子 ability ScriptUnit
		for slotIndex, abilityScript in pairs(abilities) do
			pcall(function()
				abilityScript:Destroy()
			end)
			abilities[slotIndex] = nil
		end
		-- 销毁事件单位（不依赖父子级联销毁）
		AbilityEventDefs.destroySignals(signals)
	end)

	-- 在 Posted 之后写入 ManagerReady，避免客户端错过首次 Posted 同步
	manager:SetAttribute("ManagerReady", true)

	-- 自动归位：场景里手动摆放的 AbilityItem ScriptUnit 自动加进 slot
	for _, child in ipairs(manager:GetChildren()) do
		if AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityUnit) then
			-- 拿 child 的 Index attribute（如果作者在场景里设了）
			local childIndex = child:GetAttribute("Index")
			if childIndex and not abilities[childIndex] then
				abilities[childIndex] = child
				signals.AbilityAdded:Fire(child, childIndex)
				notifyClients("AbilityAdded", child.UnitId, childIndex)
			elseif not childIndex then
				-- 没设 Index，自动找空槽
				local freeSlot = AbilityUtils.getFirstAvailableSlot(
					abilities,
					AbilityConstants.SLOT_BASE
				)
				if freeSlot then
					child:SetAttribute("Index", freeSlot)
					abilities[freeSlot] = child
					signals.AbilityAdded:Fire(child, freeSlot)
					notifyClients("AbilityAdded", child.UnitId, freeSlot)
				end
			end
		end
	end
end

return AbilityManagerLogic
