--效果系统包 - server端状态管理
--SModifierSystemManager：服务端效果管理器，负责容器与实例注册、生命周期流转、
--跨端消息分发与查询；效果实体由预设壳自动注册并直挂生物单位下。

local RunService = game:GetService("RunService")
local World = game:GetService("World")

local config = require("common.packages.modifier_system.config")
local eventDefs = require("common.packages.modifier_system.event_defs")
local eventBridge = require("server.packages.modifier_system.event_bridge")
local ModifierHandler = require("server.packages.modifier_system.ModifierHandler")

-- 动态添加时可覆盖的配置字段：Unit 属性名 → API 小写别名，大写属性名优先
local DYNAMIC_CONFIG_FIELDS = {
	{ "Duration", "duration" },
	{ "Stackable", "stackable" },
	{ "StackCountStep", "stackCountStep" },
	{ "MaxStackCount", "maxStackCount" },
	{ "StackDurationMode", "stackDurationMode" },
	{ "StackCountMode", "stackCountMode" },
	{ "UgcModifierType", "modifierType" },
	{ "Name", "name" },
	{ "Icon", "icon" },
	{ "ModifierDesc", "desc" },
	{ "StatusDisplay", "statusDisplay" },
	{ "RemoveMode", "removeMode" },
	{ "SameSourceStack", "sameSourceStack" },
	{ "AttrConfigs", "attrConfigs" },
	{ "ObtainPerformanceList", "obtainPerformanceList" },
	{ "LostPerformanceList", "lostPerformanceList" },
}

---获取单位标记组件，可选能力，组件不存在时返回 nil
---@param unit Unit 目标单位
---@return table? 标记组件
local function getTagsComponent(unit)
	local ok, component = pcall(function()
		return unit:GetComponent("UnitComponentTags")
	end)
	if ok and component then
		return component
	end
	return nil
end

---服务端效果管理器，单例
---@class SModifierSystemManager
---@field private _containers table<number, table> 拥有者 UnitId → 容器
---@field private _modifiers table<number, ModifierHandler> 效果实体 UnitId → 处理器
---@field private _pendingSourceOverrides table<number, table> 动态创建待注入的来源，注册时消费一次
---@field private _luaTags table<number, string[]> Lua 层单位标记，引擎标记组件不可用时的回退
---@field private _attachedResults table 已注册实体的结果缓存，幂等重入保护
---@field private _remoteEvent RemoteEvent 跨端事件通道，服务端实例
local SModifierSystemManager = {}
SModifierSystemManager.__index = SModifierSystemManager

---创建管理器实例并接入客户端请求通道
---@return SModifierSystemManager
function SModifierSystemManager.new()
	local self = setmetatable({}, SModifierSystemManager)
	self._containers = {}
	self._modifiers = {}
	self._pendingSourceOverrides = {}
	self._luaTags = {}
	self._attachedResults = setmetatable({}, { __mode = "k" })
	self._remoteEvent = RemoteEvent.New(config.CHANNEL_NAME)
	self:_bindClientRequests()
	return self
end

---订阅客户端请求：按拥有者容器分发，含基础鉴权与 unitId 优先路由
function SModifierSystemManager:_bindClientRequests()
	self._remoteEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or not payload.action then
			return
		end
		local args = payload.args or {}
		local ownerUnitId = args[1]
		local container = ownerUnitId and self._containers[ownerUnitId]
		if not container then
			return
		end
		-- 基础鉴权：请求者必须是拥有者对应的玩家
		local character = player and player.Character
		local owner = container.owner
		if character and owner and character ~= owner then
			return
		end

		local ClientAction = eventDefs.ClientAction
		local action = payload.action
		if action == ClientAction.RemoveByKey then
			self:_clearAll(container, args[2])
			return
		end
		if action == ClientAction.ClearAll then
			self:_clearAll(container)
			return
		end

		local modifierKey = args[2]
		local unitId = args[3]
		local handler = self:_findHandler(container, modifierKey, unitId)
		if not handler then
			return
		end

		if action == ClientAction.Remove then
			self:removeModifierWithLoss(container, handler:getUnit())
		elseif action == ClientAction.SetStack then
			handler:setStackCount(args[4])
		elseif action == ClientAction.AddStack then
			handler:addStackCount(args[4])
		elseif action == ClientAction.AddDuration then
			handler:extendDuration(args[4])
		elseif action == ClientAction.SetRemain then
			handler:setRemainingTime(args[4])
		elseif action == ClientAction.Pause then
			handler:pause()
		elseif action == ClientAction.Resume then
			handler:resume()
		end
	end)
end

-- 容器管理

---按拥有者反查容器
---@param ownerUnit Unit 拥有者单位
---@return table? 容器
function SModifierSystemManager:getContainer(ownerUnit)
	if not ownerUnit then
		return nil
	end
	return self._containers[ownerUnit.UnitId]
end

---获取或创建拥有者容器，创建时绑定销毁清理
---@param ownerUnit Unit 拥有者单位
---@return table? 容器
function SModifierSystemManager:getOrCreateContainer(ownerUnit)
	if not ownerUnit then
		return nil
	end
	local existing = self._containers[ownerUnit.UnitId]
	if existing then
		return existing
	end
	local container = {
		owner = ownerUnit,
		modifiers = {},
		count = 0,
		order = {},
	}
	self._containers[ownerUnit.UnitId] = container
	ownerUnit.Destroying:Connect(function()
		-- 拥有者销毁时清理容器，效果子节点随父子级联销毁
		self._containers[ownerUnit.UnitId] = nil
	end)
	return container
end

---容器内注册实例，唯一写入口；调用方保证不重复注册同一 unitId
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@param handler ModifierHandler 效果处理器
function SModifierSystemManager:_addInstance(container, unitId, handler)
	container.modifiers[unitId] = handler
	container.count = container.count + 1
	table.insert(container.order, unitId)
end

---容器内注销实例，唯一写入口；未注册返回 false
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@return boolean 是否注销成功
function SModifierSystemManager:_removeInstance(container, unitId)
	if not container.modifiers[unitId] then
		return false
	end
	container.modifiers[unitId] = nil
	container.count = container.count - 1
	for i, id in ipairs(container.order) do
		if id == unitId then
			table.remove(container.order, i)
			break
		end
	end
	return true
end

-- 注册与创建

---注册效果实体，由预设壳或动态创建调用；幂等，返回创建结果状态
---@param modifierUnit Unit 效果实体单位
---@return string 创建结果，取值见 config.CreateResult
function SModifierSystemManager:registerModifier(modifierUnit)
	if not RunService:IsServer() then
		return config.CreateResult.Failed
	end
	-- 已处理过：返回既有结果
	if self._attachedResults[modifierUnit] ~= nil then
		return self._attachedResults[modifierUnit]
	end
	local owner = modifierUnit.Parent
	if not owner then
		return config.CreateResult.Failed
	end
	-- 拒绝非生物挂载，动态创建中转态或异常复制下 Parent 可能暂为 World
	local okIsA, isNotWorld = pcall(function()
		return not owner:IsA("World")
	end)
	if not okIsA or not isNotWorld then
		return config.CreateResult.Rejected
	end

	local handler = ModifierHandler.new(modifierUnit, self)
	local container = self:getOrCreateContainer(owner)
	self:_ensureContainerEvents(container)
	local result = self:_registerModifierChild(container, modifierUnit, handler)
	-- 新增/叠加视为已处理；拒绝/失败不缓存，允许后续重挂时再次注册
	if result == config.CreateResult.Added or result == config.CreateResult.Reobtained then
		self._attachedResults[modifierUnit] = result
	end
	return result
end

---向拥有者添加效果：创建资产 → 写入配置 → 挂载注册
---@param ownerUnit Unit 拥有者单位
---@param assetId string 效果预设 Asset
---@param addConfig table? 可选配置，支持大写属性名或小写别名，另支持 sourceUnit
---@return string 创建结果，取值见 config.CreateResult
function SModifierSystemManager:_createModifier(ownerUnit, assetId, addConfig)
	if not ownerUnit or not assetId then
		return config.CreateResult.Failed
	end
	local container = self:getOrCreateContainer(ownerUnit)
	if not container then
		return config.CreateResult.Failed
	end

	local assets = World:CreateAsset(assetId)
	local modifierUnit = assets and assets[1]
	if not modifierUnit then
		return config.CreateResult.Failed
	end

	if addConfig then
		-- 预设即 Key：动态添加的效果 Key 恒等于 assetId，作者零配置
		modifierUnit:SetAttribute("ModifierKey", assetId)
		for _, fieldNames in ipairs(DYNAMIC_CONFIG_FIELDS) do
			local attributeName = fieldNames[1]
			local aliasName = fieldNames[2]
			local value = addConfig[attributeName]
			if value == nil then
				value = addConfig[aliasName]
			end
			if value ~= nil then
				modifierUnit:SetAttribute(attributeName, value)
			end
		end
		-- 来源为 Unit 引用，无法经属性通道承载，暂存到管理器供注册时注入
		if addConfig.source then
			self._pendingSourceOverrides[modifierUnit.UnitId] = { Source = addConfig.source }
		end
	end

	-- 挂到拥有者下触发效果注册，注册幂等，结果状态由注册路径唯一决定
	modifierUnit.Parent = ownerUnit
	local ok, result = pcall(function()
		return self:registerModifier(modifierUnit)
	end)
	if not ok then
		-- 注册涉及引擎调用，单次失败仅记录并返回失败状态
		print(
			"[modifier_system] failed to register modifier, asset:",
			tostring(assetId),
			"error:",
			tostring(result)
		)
		return config.CreateResult.Failed
	end
	return result or config.CreateResult.Failed
end

---添加效果：ownerUnit / assetId 必填，其余字段可选
---@param ownerUnit Unit 拥有者单位
---@param assetId string 效果预设 Asset
---@param addConfig table? 可选配置，支持 duration/stackable/叠加策略/source 等字段
---@return string 创建结果，取值见 config.CreateResult
function SModifierSystemManager:addModifierToUnit(ownerUnit, assetId, addConfig)
	assert(assetId ~= nil and assetId ~= "", "AddModifier: assetId must not be empty")
	assert(ownerUnit ~= nil, "AddModifier: owner must not be nil")
	local mergedConfig = {}
	for key, value in pairs(addConfig or {}) do
		mergedConfig[key] = value
	end
	mergedConfig.owner = ownerUnit
	mergedConfig.assetId = assetId
	-- 兼容 sourceUnit 写法
	if mergedConfig.source == nil and mergedConfig.sourceUnit ~= nil then
		mergedConfig.source = mergedConfig.sourceUnit
	end
	return self:_createModifier(ownerUnit, assetId, mergedConfig)
end

---效果实体的注册主流程：来源注入 → 上限检查 → 叠加路由 → 追加实例 → 激活
---@param container table 容器
---@param modifierUnit Unit 效果实体单位
---@param modifierHandler ModifierHandler 效果处理器
---@return string 创建结果，取值见 config.CreateResult
function SModifierSystemManager:_registerModifierChild(container, modifierUnit, modifierHandler)
	if not container or not modifierUnit or not modifierHandler then
		return config.CreateResult.Failed
	end
	self:_ensureContainerEvents(container)

	-- 客户端拥有者解析兜底：状态同步复制场景下客户端 unit.Parent 可能未就绪，
	-- 客户端经该属性 + World:GetUnitByID 反查拥有者
	modifierUnit:SetAttribute("OwnerUnitId", container.owner.UnitId)

	-- 消费动态创建的来源注入，注册必然发生在创建之后，无时序竞争
	local pendingSource = self._pendingSourceOverrides[modifierUnit.UnitId]
	if pendingSource then
		self._pendingSourceOverrides[modifierUnit.UnitId] = nil
		modifierHandler:setSource(pendingSource.Source)
	end

	-- 实例总数上限检查
	if container.count >= config.DEFAULT_MAX_MODIFIER_COUNT then
		pcall(function()
			modifierUnit:Destroy()
		end)
		return config.CreateResult.Rejected
	end

	-- 叠加路由：同 Key 已存在则尝试叠加
	local modifierKey = modifierHandler:getModifierKey()
	if modifierKey and modifierKey ~= "" then
		local existingHandler = self:getModifierHandlerByKey(container, modifierKey)
		if existingHandler and existingHandler ~= modifierHandler then
			if existingHandler:canReobtain(modifierHandler:getSource()) then
				local _, newCount = existingHandler:whenReobtain()
				local existingUnit = existingHandler:getUnit()
				eventDefs.fireEvent(container.events, config.ManagerEvent.ModifierRefresh, existingUnit)
				-- 载荷末参为绝对 EndTime：叠加可能更新倒计时，客户端据此同步
				self:notifyClients(
					container.owner.UnitId,
					eventDefs.ServerAction.OnReobtain,
					existingUnit.UnitId,
					newCount or 0,
					existingHandler:getEndTime()
				)
				pcall(function()
					modifierUnit:Destroy()
				end)
				return config.CreateResult.Reobtained
			elseif existingHandler:enableReobtain() then
				-- 仅同源叠加但来源不同：不叠加，作为独立实例继续注册
			else
				pcall(function()
					modifierUnit:Destroy()
				end)
				return config.CreateResult.Rejected
			end
		end
	end

	-- 追加实例
	self:_addInstance(container, modifierUnit.UnitId, modifierHandler)
	eventDefs.fireEvent(container.events, config.ManagerEvent.ModifierAdded, modifierUnit)
	self:notifyClients(
		container.owner.UnitId,
		eventDefs.ServerAction.OnModifierAdded,
		modifierUnit.UnitId,
		modifierHandler:getModifierKey() or "",
		modifierHandler:getName() or "",
		modifierHandler:getDesc() or "",
		modifierHandler:getIcon() or "",
		modifierHandler:getModifierType() or "",
		modifierHandler:getMaxStackCount() or 0
	)

	-- 立刻触发激活，被"阻止效果获得"拦截时回滚注册并销毁
	if not modifierHandler:onObtain() then
		self:_removeInstance(container, modifierUnit.UnitId)
		eventDefs.fireEvent(container.events, config.ManagerEvent.ModifierRemoved, modifierUnit)
		self:notifyClients(
			container.owner.UnitId,
			eventDefs.ServerAction.OnModifierRemoved,
			modifierUnit.UnitId
		)
		pcall(function()
			modifierUnit:Destroy()
		end)
		return config.CreateResult.Rejected
	end
	return config.CreateResult.Added
end

---按拥有者创建容器事件单位集合，挂在拥有者下，作者可 FindFirstChild 监听
---@param container table 容器
---@return table<string, Unit> 事件单位集合
function SModifierSystemManager:_ensureContainerEvents(container)
	if container.events then
		return container.events
	end
	container.events = eventDefs.createManagerSignals(container.owner)
	return container.events
end

-- 移除与修改

---广播消息给所有客户端
---@param ownerUnitId number 拥有者单位 UnitId
---@param action string 服务端动作名
---@param ... any 业务参数
function SModifierSystemManager:notifyClients(ownerUnitId, action, ...)
	self._remoteEvent:FireAllClients(eventDefs.packServerPayload(action, ownerUnitId, ...))
end

---移除指定 Key 的所有效果，带失活处理，返回移除数量
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 移除数量
function SModifierSystemManager:removeModifierByKey(ownerUnit, modifierKey)
	local container = self:getContainer(ownerUnit)
	if not container or not modifierKey then
		return 0
	end
	return self:_clearAll(container, modifierKey)
end

---清除拥有者的所有效果，带失活处理，返回移除数量
---@param ownerUnit Unit 拥有者单位
---@return number 移除数量
function SModifierSystemManager:clearAllModifiers(ownerUnit)
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	return self:_clearAll(container)
end

---清除容器内指定 Key 的效果，Key 为空时清除全部，带失活处理
---@param container table 容器
---@param modifierKey string? 效果 Key
---@return number 移除数量
function SModifierSystemManager:_clearAll(container, modifierKey)
	local toRemove = {}
	for _, handler in ipairs(self:getModifierHandlers(container)) do
		if not modifierKey or handler:getModifierKey() == modifierKey then
			table.insert(toRemove, handler:getUnit())
		end
	end
	for _, unit in ipairs(toRemove) do
		self:removeModifierWithLoss(container, unit)
	end
	return #toRemove
end

---移除指定效果实体，即事件回调中拿到的效果实体
---@param modifierUnit Unit 效果实体单位
---@return boolean 是否移除成功
function SModifierSystemManager:removeModifierEntity(modifierUnit)
	if not modifierUnit then
		return false
	end
	local owner = modifierUnit.Parent
	local container = owner and self:getContainer(owner)
	if not container then
		return false
	end
	return self:removeModifierWithLoss(container, modifierUnit)
end

---先触发 onLoss 再移除，外部移除入口
---@param container table 容器
---@param modifierUnit Unit 效果实体单位
---@return boolean 是否移除成功
function SModifierSystemManager:removeModifierWithLoss(container, modifierUnit)
	if not container or not modifierUnit then
		return false
	end
	local handler = self:getModifierHandler(modifierUnit)
	if handler and handler.onLoss then
		handler:onLoss()
	end
	return self:removeModifierUnit(container, modifierUnit)
end

---从容器移除并销毁，不触发 onLoss
---@param container table 容器
---@param modifierUnit Unit 效果实体单位
---@return boolean 是否移除成功
function SModifierSystemManager:removeModifierUnit(container, modifierUnit)
	if not container or not modifierUnit then
		return false
	end
	if not self:_removeInstance(container, modifierUnit.UnitId) then
		return false
	end
	self:_ensureContainerEvents(container)
	eventDefs.fireEvent(container.events, config.ManagerEvent.ModifierRemoved, modifierUnit)
	self:notifyClients(
		container.owner.UnitId,
		eventDefs.ServerAction.OnModifierRemoved,
		modifierUnit.UnitId
	)
	-- 实体可能已被级联销毁，销毁失败不阻断收尾
	pcall(function()
		modifierUnit:Destroy()
	end)
	return true
end

---设置指定 Key 效果的层数，归零触发带失活的移除
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param count number 目标层数
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
function SModifierSystemManager:setStackCount(ownerUnit, modifierKey, count, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:_findHandler(container, modifierKey, unitId)
	if not handler then
		return false
	end
	return (handler.setStackCount and handler:setStackCount(count or 0)) or false
end

---增减指定 Key 效果的层数，delta 可为负数，返回新层数
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param delta number 层数增量
---@param unitId number? 效果实体 UnitId
---@return number 新层数
function SModifierSystemManager:addStackCount(ownerUnit, modifierKey, delta, unitId)
	if not modifierKey then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local handler = self:_findHandler(container, modifierKey, unitId)
	if not handler then
		return 0
	end
	if handler.addStackCount then
		handler:addStackCount(delta or 0)
	end
	return (handler.getStackCount and handler:getStackCount()) or 0
end

---延长指定 Key 效果的持续时间，extra 可为负数表示缩短
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param extra number 延长时间，单位秒
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
function SModifierSystemManager:addDuration(ownerUnit, modifierKey, extra, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:_findHandler(container, modifierKey, unitId)
	if not handler then
		return false
	end
	if handler.extendDuration then
		handler:extendDuration(extra or 0)
	end
	return true
end

---设置指定 Key 效果的剩余时间，单位秒
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param remaining number 剩余时间
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
function SModifierSystemManager:setRemainTime(ownerUnit, modifierKey, remaining, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:_findHandler(container, modifierKey, unitId)
	if not handler then
		return false
	end
	if handler.setRemainingTime then
		handler:setRemainingTime(remaining or 0)
	end
	return true
end

---暂停指定 Key 效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
function SModifierSystemManager:pause(ownerUnit, modifierKey, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:_findHandler(container, modifierKey, unitId)
	if not handler then
		return false
	end
	if handler.pause then
		handler:pause()
	end
	return true
end

---恢复指定 Key 效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 是否执行成功
function SModifierSystemManager:resume(ownerUnit, modifierKey, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:_findHandler(container, modifierKey, unitId)
	if not handler then
		return false
	end
	if handler.resume then
		handler:resume()
	end
	return true
end

-- 查询

---按 Key 取第一个匹配的处理器，按注册序命中最早注册实例
---@param container table 容器
---@param modifierKey string 效果 Key
---@return ModifierHandler? 效果处理器
function SModifierSystemManager:getModifierHandlerByKey(container, modifierKey)
	if not container or not modifierKey or modifierKey == "" then
		return nil
	end
	for _, unitId in ipairs(container.order) do
		local handler = container.modifiers[unitId]
		if handler and handler:getModifierKey() == modifierKey then
			return handler
		end
	end
	return nil
end

---按 Key 取所有匹配的处理器，按注册序返回
---@param container table 容器
---@param modifierKey string 效果 Key
---@return ModifierHandler[] 效果处理器列表
function SModifierSystemManager:getModifierHandlersByKey(container, modifierKey)
	local result = {}
	if not container or not modifierKey or modifierKey == "" then
		return result
	end
	for _, unitId in ipairs(container.order) do
		local handler = container.modifiers[unitId]
		if handler and handler:getModifierKey() == modifierKey then
			table.insert(result, handler)
		end
	end
	return result
end

---按 UnitId 取处理器，实例级寻址
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@return ModifierHandler? 效果处理器
function SModifierSystemManager:getModifierHandlerByUnitId(container, unitId)
	if not container or not unitId then
		return nil
	end
	return container.modifiers[unitId]
end

---取容器内全部处理器，按注册序返回
---@param container table 容器
---@return ModifierHandler[] 效果处理器列表
function SModifierSystemManager:getModifierHandlers(container)
	if not container then
		return {}
	end
	local result = {}
	for _, unitId in ipairs(container.order) do
		local handler = container.modifiers[unitId]
		if handler then
			table.insert(result, handler)
		end
	end
	return result
end

---按 Key 定位处理器，可传 UnitId 精确定位
---@param container table 容器
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return ModifierHandler? 效果处理器
function SModifierSystemManager:_findHandler(container, modifierKey, unitId)
	if unitId then
		local byId = self:getModifierHandlerByUnitId(container, unitId)
		if byId then
			return byId
		end
	end
	return self:getModifierHandlerByKey(container, modifierKey)
end

---获取拥有者下所有效果，返回效果实体单位列表
---@param ownerUnit Unit 拥有者单位
---@return Unit[] 效果实体单位列表
function SModifierSystemManager:getModifierUnits(ownerUnit)
	local container = self:getContainer(ownerUnit)
	if not container then
		return {}
	end
	local result = {}
	for _, handler in ipairs(self:getModifierHandlers(container)) do
		table.insert(result, handler:getUnit())
	end
	return result
end

---按 Key 获取第一个匹配的效果实体
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return Unit? 效果实体单位
function SModifierSystemManager:getModifierByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return nil
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return nil
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler:getUnit()) or nil
end

---按 Key 获取所有匹配的效果实体列表
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return Unit[] 效果实体单位列表
function SModifierSystemManager:getModifierUnitsByKey(ownerUnit, modifierKey)
	local result = {}
	if not modifierKey or modifierKey == "" then
		return result
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return result
	end
	for _, handler in ipairs(self:getModifierHandlersByKey(container, modifierKey)) do
		table.insert(result, handler:getUnit())
	end
	return result
end

---按效果类型获取所有匹配的效果实体列表，类型为空时返回全部
---@param ownerUnit Unit 拥有者单位
---@param modifierType number? 效果类型
---@return Unit[] 效果实体单位列表
function SModifierSystemManager:getModifierUnitsByType(ownerUnit, modifierType)
	local result = {}
	local container = self:getContainer(ownerUnit)
	if not container then
		return result
	end
	for _, handler in ipairs(self:getModifierHandlers(container)) do
		local handlerType = handler:getModifierType() or ""
		if not modifierType or modifierType == "" or handlerType == modifierType then
			table.insert(result, handler:getUnit())
		end
	end
	return result
end

---检查拥有者是否拥有指定 Key 的效果，Key 为空时返回是否存在任一效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return boolean 是否存在
function SModifierSystemManager:hasModifier(ownerUnit, modifierKey)
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	if not modifierKey or modifierKey == "" then
		return container.count > 0
	end
	return self:getModifierByKey(ownerUnit, modifierKey) ~= nil
end

---获取拥有者的最大效果数，全局默认
---@param ownerUnit Unit 拥有者单位
---@return number 最大效果数
function SModifierSystemManager:getMaxModifierCount(ownerUnit)
	return config.DEFAULT_MAX_MODIFIER_COUNT
end

---检查指定 Key 效果是否激活
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return boolean 是否激活
function SModifierSystemManager:isActiveByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.isActive and handler:isActive()) or false
end

---获取指定 Key 效果的当前层数
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 当前层数
function SModifierSystemManager:getStackCountByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getStackCount and handler:getStackCount()) or 0
end

---获取指定 Key 效果的当前材质 ID，0 表示无材质
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 材质 ID
function SModifierSystemManager:getCharMtgByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getCharMtg and handler:getCharMtg()) or 0
end

---检查指定 Key 效果是否暂停
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return boolean 是否暂停
function SModifierSystemManager:isPausedByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.isPaused and handler:isPaused()) or false
end

---获取指定 Key 效果的剩余时间，单位秒，永久效果返回 -1
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 剩余时间
function SModifierSystemManager:getRemainingTimeByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getRemainingTime and handler:getRemainingTime()) or 0
end

---获取指定 Key 效果的最大层数
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 最大层数
function SModifierSystemManager:getMaxStackCountByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getMaxStackCount and handler:getMaxStackCount()) or 0
end

---获取指定 Key 效果的来源单位，未指定来源时返回 nil
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return Unit? 来源单位
function SModifierSystemManager:getSourceByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return nil
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return nil
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getSource and handler:getSource()) or nil
end

---获取指定 Key 效果的效果实体 UnitId
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 效果实体 UnitId，未命中返回 0
function SModifierSystemManager:getModifierIdByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	local unit = handler and handler.getUnit and handler:getUnit()
	return (unit and unit.UnitId) or 0
end

---获取指定 Key 效果的类型
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number|string 效果类型，未命中返回空串
function SModifierSystemManager:getModifierTypeByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return ""
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return ""
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getModifierType and handler:getModifierType()) or ""
end

---获取指定 Key 效果的名称
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return string 名称
function SModifierSystemManager:getModifierNameByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return ""
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return ""
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getName and handler:getName()) or ""
end

---获取指定 Key 效果的描述
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return string 描述
function SModifierSystemManager:getModifierDescByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return ""
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return ""
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getDesc and handler:getDesc()) or ""
end

---获取指定 Key 效果的图标资源路径
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return string 图标路径
function SModifierSystemManager:getModifierIconByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return ""
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return ""
	end
	local handler = self:getModifierHandlerByKey(container, modifierKey)
	return (handler and handler.getIcon and handler:getIcon()) or ""
end

-- 实体级操作，供事件回调按效果实体操作

---设置效果实体的层数，归零触发带失活的移除
---@param modifierUnit Unit 效果实体单位
---@param count number 目标层数
---@return boolean 是否执行成功
function SModifierSystemManager:setStackCountOfEntity(modifierUnit, count)
	local handler = self:getModifierHandler(modifierUnit)
	if not handler or not handler.setStackCount then
		return false
	end
	return handler:setStackCount(count or 0) or false
end

---增减效果实体的层数，delta 可为负数，返回新层数
---@param modifierUnit Unit 效果实体单位
---@param delta number 层数增量
---@return number 新层数
function SModifierSystemManager:addStackCountOfEntity(modifierUnit, delta)
	local handler = self:getModifierHandler(modifierUnit)
	if not handler then
		return 0
	end
	if handler.addStackCount then
		handler:addStackCount(delta or 0)
	end
	return (handler.getStackCount and handler:getStackCount()) or 0
end

---延长效果实体的剩余持续时间，extra 可为负数表示缩短
---@param modifierUnit Unit 效果实体单位
---@param extra number 延长时间，单位秒
---@return boolean 是否执行成功
function SModifierSystemManager:addDurationOfEntity(modifierUnit, extra)
	local handler = self:getModifierHandler(modifierUnit)
	if not handler or not handler.extendDuration then
		return false
	end
	handler:extendDuration(extra or 0)
	return true
end

---设置效果实体的剩余持续时间
---@param modifierUnit Unit 效果实体单位
---@param remaining number 剩余时间
---@return boolean 是否执行成功
function SModifierSystemManager:setRemainTimeOfEntity(modifierUnit, remaining)
	local handler = self:getModifierHandler(modifierUnit)
	if not handler or not handler.setRemainingTime then
		return false
	end
	handler:setRemainingTime(remaining or 0)
	return true
end

---获取效果实体的拥有者单位
---@param modifierUnit Unit 效果实体单位
---@return Unit? 拥有者单位
function SModifierSystemManager:getModifierOwnerOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getOwner and handler:getOwner()) or nil
end

---获取效果实体的当前层数
---@param modifierUnit Unit 效果实体单位
---@return number 当前层数
function SModifierSystemManager:getStackCountOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getStackCount and handler:getStackCount()) or 0
end

---获取效果实体的最大层数
---@param modifierUnit Unit 效果实体单位
---@return number 最大层数
function SModifierSystemManager:getMaxStackCountOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getMaxStackCount and handler:getMaxStackCount()) or 0
end

---获取效果实体的剩余时间，永久效果返回 -1
---@param modifierUnit Unit 效果实体单位
---@return number 剩余时间
function SModifierSystemManager:getRemainTimeOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getRemainingTime and handler:getRemainingTime()) or 0
end

---获取效果实体的来源单位，未指定来源时返回 nil
---@param modifierUnit Unit 效果实体单位
---@return Unit? 来源单位
function SModifierSystemManager:getSourceOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getSource and handler:getSource()) or nil
end

---获取效果实体的类型，默认中立
---@param modifierUnit Unit 效果实体单位
---@return number 效果类型
function SModifierSystemManager:getModifierTypeOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	if handler and handler.getModifierType then
		return handler:getModifierType()
	end
	return config.ModifierType.Neutral
end

---获取效果实体的名称
---@param modifierUnit Unit 效果实体单位
---@return string 名称
function SModifierSystemManager:getNameOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getName and handler:getName()) or ""
end

---获取效果实体的描述
---@param modifierUnit Unit 效果实体单位
---@return string 描述
function SModifierSystemManager:getDescOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getDesc and handler:getDesc()) or ""
end

---获取效果实体的图标资源路径
---@param modifierUnit Unit 效果实体单位
---@return string 图标路径
function SModifierSystemManager:getIconOfEntity(modifierUnit)
	local handler = self:getModifierHandler(modifierUnit)
	return (handler and handler.getIcon and handler:getIcon()) or ""
end

---获取效果实体的 Key，处理器不可用时回退读实体属性
---@param modifierUnit Unit 效果实体单位
---@return string 效果 Key
function SModifierSystemManager:getModifierKeyOfEntity(modifierUnit)
	if not modifierUnit then
		return ""
	end
	local handler = self:getModifierHandler(modifierUnit)
	if handler and handler.getModifierKey then
		return handler:getModifierKey() or ""
	end
	local ok, key = pcall(function()
		return modifierUnit:GetAttribute("ModifierKey")
	end)
	if ok and key ~= nil then
		return key
	end
	return ""
end

---获取效果实体的 UnitId
---@param modifierUnit Unit 效果实体单位
---@return number 效果实体 UnitId，无效实体返回 0
function SModifierSystemManager:getModifierIdOfEntity(modifierUnit)
	if not modifierUnit then
		return 0
	end
	return modifierUnit.UnitId or 0
end

-- 处理器字典与标记

---按效果实体反查处理器
---@param modifierUnit Unit 效果实体单位
---@return ModifierHandler? 效果处理器
function SModifierSystemManager:getModifierHandler(modifierUnit)
	if not modifierUnit then
		return nil
	end
	return self._modifiers[modifierUnit.UnitId]
end

---注册效果处理器
---@param modifierUnit Unit 效果实体单位
---@param handler ModifierHandler 效果处理器
function SModifierSystemManager:registerModifierHandler(modifierUnit, handler)
	self._modifiers[modifierUnit.UnitId] = handler
end

---反注册效果处理器
---@param modifierUnit Unit 效果实体单位
function SModifierSystemManager:unregisterModifierHandler(modifierUnit)
	self._modifiers[modifierUnit.UnitId] = nil
end

---清除尚未消费的动态来源注入，用于效果销毁时兜底
---@param modifierUnit Unit 效果实体单位
function SModifierSystemManager:clearPendingSourceOverride(modifierUnit)
	self._pendingSourceOverrides[modifierUnit.UnitId] = nil
end

---为 Unit 添加标记，优先写引擎组件，同时记录 Lua 层回退
---@param unit Unit 目标单位
---@param tag string 标记
function SModifierSystemManager:addTag(unit, tag)
	local key = unit.UnitId
	if not self._luaTags[key] then
		self._luaTags[key] = {}
	end
	for _, existingTag in ipairs(self._luaTags[key]) do
		if existingTag == tag then
			return
		end
	end
	table.insert(self._luaTags[key], tag)
	local component = getTagsComponent(unit)
	if component then
		-- 引擎组件为可选能力，写入失败时保留 Lua 层回退记录
		pcall(function()
			component:AddTag(tag)
		end)
	end
end

---检查 Unit 是否拥有指定标记，先查引擎组件，再查 Lua 层回退
---@param unit Unit 目标单位
---@param tag string 标记
---@return boolean 是否拥有
function SModifierSystemManager:hasTag(unit, tag)
	if not unit then
		return false
	end
	local component = getTagsComponent(unit)
	if component then
		local ok, has = pcall(function()
			return component:HasTag(tag)
		end)
		if ok and has then
			return true
		end
	end
	local tags = self._luaTags[unit.UnitId]
	if not tags then
		return false
	end
	for _, existingTag in ipairs(tags) do
		if existingTag == tag then
			return true
		end
	end
	return false
end

---清除 Unit 的全部 Lua 层标记记录，Unit 销毁时调用
---@param unit Unit 目标单位
function SModifierSystemManager:clearTags(unit)
	self._luaTags[unit.UnitId] = nil
end

-- 获得拦截

---阻止当前触发中的效果获得，仅在"即将获得效果"事件中有效
---@return boolean 恒返回 true
function SModifierSystemManager:setInterruptModifierObtain()
	eventBridge.setIntercept()
	return true
end

return SModifierSystemManager.new()
