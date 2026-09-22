--技能系统 - client技能请求api
--仅由根 AbilityAPI.lua 在客户端加载。

local AbilityEventDefs = require("common.packages.ability_system.event_defs")
local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityRegistry = require("common.packages.ability_system.registry")

local AbilityClientAPI = {}

local function getOwnerId(manager)
	return manager:GetAttribute("OwnerId") or ""
end

local function getManagerForUnit(unit)
	if not unit then
		return nil
	end
	if AbilityRegistry.hasTag(unit, AbilityConstants.Tag.AbilityManager) then
		return unit
	end
	for _, child in ipairs(unit:GetChildren()) do
		if AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityManager) then
			return child
		end
	end
	return nil
end

-- 导出：UI 层需要从角色反查 AbilityManager
---获取单位身上的技能管理器（按 AbilityManager 标签反查自身或子节点）
---@param unit Unit 目标单位
---@return Script? 技能管理器脚本单位，未找到返回 nil
function AbilityClientAPI.GetManagerForUnit(unit)
	return getManagerForUnit(unit)
end

---获取指定槽位上的技能脚本单位
---@param unit Unit 目标单位
---@param abilityIndex integer 槽位索引（0 基）
---@return Script? 技能脚本单位，未找到返回 nil
function AbilityClientAPI.GetAbility(unit, abilityIndex)
	local manager = getManagerForUnit(unit)
	if not manager or not abilityIndex then
		return nil
	end
	for _, child in ipairs(manager:GetChildren()) do
		if
			AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityUnit)
			and child:GetAttribute("Index") == abilityIndex
		then
			return child
		end
	end
	return nil
end

---请求施放指定槽位的技能（client → server）
---@param manager Script 技能管理器脚本单位
---@param abilityIndex integer 槽位索引（0 基）
---@param releasePoint Vector3? 释放点
---@param releaseDir Vector3? 释放方向
---@param releaseTarget integer? 释放目标
---@return boolean 是否已发送请求
function AbilityClientAPI.RequestCast(
	manager,
	abilityIndex,
	releasePoint,
	releaseDir,
	releaseTarget
)
	if not manager or not abilityIndex then
		return false, "[ability_system] RequestCast: manager or abilityIndex is invalid"
	end
	-- RemoteEvent 单参数契约：载荷用 table 打包
	AbilityEventDefs.getRemote():FireServer({
		action = AbilityEventDefs.ClientAction.Cast,
		ownerId = getOwnerId(manager),
		index = abilityIndex,
		args = { releasePoint, releaseDir, releaseTarget },
	})
	return true
end

---请求停止施放指定槽位的技能
---@param manager Script 技能管理器脚本单位
---@param abilityIndex integer 槽位索引（0 基）
---@return boolean 是否已发送请求
function AbilityClientAPI.RequestStop(manager, abilityIndex)
	if not manager or not abilityIndex then
		return false, "[ability_system] RequestStop: manager or abilityIndex is invalid"
	end
	AbilityEventDefs.getRemote():FireServer({
		action = AbilityEventDefs.ClientAction.BreakCast,
		ownerId = getOwnerId(manager),
		index = abilityIndex,
	})
	return true
end

---请求切换子技能组到下一个成员
---@param manager Script 技能管理器脚本单位
---@param parentSlotIndex integer 父技能槽位索引（0 基）
---@return boolean 是否已发送请求
function AbilityClientAPI.RequestSwitchNext(manager, parentSlotIndex)
	if not manager or not parentSlotIndex then
		return false, "[ability_system] RequestSwitchNext: manager or parentSlotIndex is invalid"
	end
	AbilityEventDefs.getRemote():FireServer({
		action = AbilityEventDefs.ClientAction.SwitchNext,
		ownerId = getOwnerId(manager),
		index = parentSlotIndex,
	})
	return true
end

-- 蓄力：请求进入蓄力（服务端 Accumulate action 已处理 startAccumulate）
---请求进入蓄力（服务端 Accumulate action 处理 startAccumulate）
---@param manager Script 技能管理器脚本单位
---@param abilityIndex integer 槽位索引（0 基）
---@return boolean 是否已发送请求
function AbilityClientAPI.RequestAccumulate(manager, abilityIndex)
	if not manager or not abilityIndex then
		return false, "[ability_system] RequestAccumulate: manager or abilityIndex is invalid"
	end
	AbilityEventDefs.getRemote():FireServer({
		action = AbilityEventDefs.ClientAction.Accumulate,
		ownerId = getOwnerId(manager),
		index = abilityIndex,
	})
	return true
end

-- UI 辅助（技能栏 UI 需要）

-- 全局 UI 管理器（懒初始化；由 ui/UIManager.lua 提供）
local _uiManager = nil

---获取客户端技能栏 UI 管理器单例（懒初始化）
---@return table 技能栏 UI 管理器
function AbilityClientAPI.GetUIManager()
	if _uiManager == nil then
		local UIManager = require("client.packages.ability_system.ui.UIManager")
		local character = nil
		local player = game:GetService("Players").LocalPlayer
		if player then
			character = player.Character
		end
		_uiManager = UIManager.new(character)
	end
	return _uiManager
end

-- 开放注册（Pointer/Strategy domain 注册入口，转发到 common registry）
---注册释放策略 / 施法指示器类（转发到 common registry 的 domain 注册）
---@param domain string 注册域（"ReleaseStrategy" / "PointerType"）
---@param key integer 枚举键
---@param value table 类
function AbilityClientAPI.Register(domain, key, value)
	AbilityRegistry.register(domain, key, value)
end

-- 客户端生命周期（系统内部，勿在 main 展开）
-- 监听本地玩家 Character 生命周期（含重生），自动查找并挂接 AbilityManager。
-- 入口仅 client/main.lua 调用一次（幂等）。

local _lifecycleStarted = false

---启动客户端生命周期（等待 LocalPlayer、监听重生、自动挂接技能管理器，幂等）
function AbilityClientAPI.StartClientLifecycle()
	local RunService = game:GetService("RunService")
	if not RunService:IsClient() then
		return
	end
	if _lifecycleStarted then
		return
	end
	_lifecycleStarted = true

	local Players = game:GetService("Players")
	local Task = game:GetService("Task")
	local ManagerClient = require("client.packages.ability_system.ability_manager_local_script")

	-- 角色就绪后有界等待 manager 复制到客户端再挂接
	local function attachManagerWhenReady(character)
		if not character then
			return
		end
		Task:Spawn(function()
			local retried = 0
			while retried < 100 do
				-- 角色已销毁则退出
				local alive = pcall(function()
					return character:GetChildren()
				end)
				if not alive then
					return
				end
				local manager = getManagerForUnit(character)
				if manager then
					ManagerClient.attach(manager)
					return
				end
				Task:Wait(0.1)
				retried = retried + 1
			end
		end)
	end

	local function bindPlayer(player)
		if not player then
			return
		end
		-- 重生 → 新 Character → 重新挂接新 manager
		player.CharacterAdded:Connect(function(character)
			attachManagerWhenReady(character)
		end)
		-- 已有 Character（重连/进入时已就绪）
		if player.Character then
			attachManagerWhenReady(player.Character)
		end
	end

	-- LocalPlayer 可能未就绪，有界等待（10s）
	Task:Spawn(function()
		local waited = 0
		while not Players.LocalPlayer and waited < 100 do
			Task:Wait(0.1)
			waited = waited + 1
		end
		bindPlayer(Players.LocalPlayer)
	end)
end

return AbilityClientAPI
