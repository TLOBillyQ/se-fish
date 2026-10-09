--效果系统包 - client端状态管理
--CModifierSystemManager：客户端效果管理器，维护客户端状态、材质栈与跨端请求通道；
--效果实体由客户端预设壳自动注册并直挂生物单位下。

local RunService = game:GetService("RunService")

local config = require("common.packages.modifier_system.config")
local eventDefs = require("common.packages.modifier_system.event_defs")
local util = require("common.packages.modifier_system.util")
local ClientModifierHandler = require("client.packages.modifier_system.ClientModifierHandler")

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

---客户端效果管理器，单例
---@class CModifierSystemManager
---@field private _containers table<number, table> 拥有者 UnitId → 客户端容器
---@field private _modifiers table<number, ClientModifierHandler> 效果实体 UnitId → 处理器
---@field private _luaTags table<number, string[]> Lua 层单位标记，引擎标记组件不可用时的回退
---@field private _attachedModifiers table 已注册实体，幂等重入保护
---@field private _remoteEvent RemoteEvent 跨端事件通道，客户端实例
local CModifierSystemManager = {}
CModifierSystemManager.__index = CModifierSystemManager

---创建管理器实例并接入服务端推送通道
---@return CModifierSystemManager
function CModifierSystemManager.new()
	local self = setmetatable({}, CModifierSystemManager)
	self._containers = {}
	self._modifiers = {}
	self._luaTags = {}
	self._attachedModifiers = setmetatable({}, { __mode = "k" })
	self._remoteEvent = RemoteEvent.New(config.CHANNEL_NAME)
	self:_bindRemoteEvent()
	return self
end

---订阅服务端推送：按拥有者 UnitId 分发到各容器
function CModifierSystemManager:_bindRemoteEvent()
	self._remoteEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or not payload.action then
			return
		end
		local args = payload.args or {}
		local ownerUnitId = args[1]
		local container = self._containers[ownerUnitId]
		if not container then
			return
		end
		self:_onServerPush(container, payload.action, table.unpack(args, 2))
	end)
end

-- 容器与条目绑定

---按拥有者获取容器，不存在时创建并绑定实体监听
---@param ownerUnit Unit 拥有者单位
---@return table? 容器
function CModifierSystemManager:getContainer(ownerUnit)
	if not ownerUnit then
		return nil
	end
	-- 拒绝非生物拥有者，复制竞态下 Parent 可能暂为 World
	local okIsA, isNotWorld = pcall(function()
		return not ownerUnit:IsA("World")
	end)
	if not okIsA or not isNotWorld then
		return nil
	end
	local container = self._containers[ownerUnit.UnitId]
	if container then
		return container
	end
	container = {
		owner = ownerUnit,
		slots = {},
		order = {},
		materialStack = {},
	}
	self._containers[ownerUnit.UnitId] = container
	self:_bindOwnerChildren(container)
	ownerUnit.Destroying:Connect(function()
		-- 拥有者销毁时清理容器
		self._containers[ownerUnit.UnitId] = nil
	end)
	return container
end

---绑定拥有者的子节点增删监听，并补绑已有子节点
---@param container table 容器
function CModifierSystemManager:_bindOwnerChildren(container)
	local ownerUnit = container.owner
	ownerUnit.ChildAdded:Connect(function(child)
		if not self:_isModifierChild(child) then
			return
		end
		self:_bindModifier(container, child)
	end)
	ownerUnit.ChildRemoved:Connect(function(child)
		if not self:_isModifierChild(child) then
			return
		end
		-- ChildRemoved 不作为清理依据：引擎在部分场景会对拥有者子树派发摘除事件而效果实体仍然存活；
		-- 清理以实体销毁信号与移除消息为准，此处仅重新应用当前材质
		self:applyTopMaterial(container)
	end)
	-- 已有子节点补绑，覆盖拥有者复制先于管理器创建的场景
	for _, child in ipairs(ownerUnit:GetChildren()) do
		if self:_isModifierChild(child) then
			self:_bindModifier(container, child)
		end
	end
end

---判断子节点是否为效果实体
---@param child Unit? 子节点
---@return boolean 是否为效果实体
function CModifierSystemManager:_isModifierChild(child)
	if not child then
		return false
	end
	if self:hasTag(child, config.Tag.ModifierUnit) then
		return true
	end
	-- 判定信号 1：ModifierKey 属性存在，动态创建的效果必写
	local okKey, key = pcall(function()
		return child:GetAttribute("ModifierKey")
	end)
	if okKey and key ~= nil and key ~= "" then
		return true
	end
	-- 判定信号 2：运行时属性存在，创建时必写并随实体复制；
	-- 该信号覆盖 ModifierKey 为空的预放置预设，也排除无属性的场景子节点
	local okActive, isActive = pcall(function()
		return child:GetAttribute("IsActive")
	end)
	return okActive and isActive ~= nil
end

---容器内绑定条目，唯一写入口；已存在时返回现有条目
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@param initial table? 已有条目，复用其展示字段
---@return table 状态条目
function CModifierSystemManager:_bindSlot(container, unitId, initial)
	local slot = container.slots[unitId]
	if not slot then
		slot = initial or {}
		slot.unitId = unitId
		container.slots[unitId] = slot
		table.insert(container.order, unitId)
	end
	return slot
end

---容器内解绑条目，唯一写入口；未绑定返回 false
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@return boolean 是否解绑成功
function CModifierSystemManager:_unbindSlot(container, unitId)
	if not container.slots[unitId] then
		return false
	end
	container.slots[unitId] = nil
	for i, id in ipairs(container.order) do
		if id == unitId then
			table.remove(container.order, i)
			break
		end
	end
	return true
end

---按 UnitId 建立/刷新状态条目，读属性初始值，覆盖新玩家与重连场景
---@param container table 容器
---@param child Unit 效果实体单位
function CModifierSystemManager:_bindModifier(container, child)
	if not child then
		return
	end
	local unitId = child.UnitId
	local existing = container.slots[unitId]
	if existing and existing.unit == child then
		return
	end
	local okKey, key = pcall(function()
		return child:GetAttribute("ModifierKey")
	end)
	local function readAttribute(name, fallback)
		local ok, value = pcall(function()
			return child:GetAttribute(name)
		end)
		if ok and value ~= nil then
			return value
		end
		return fallback
	end
	local slot = self:_bindSlot(container, unitId, existing)
	slot.unit = child
	slot.modifierKey = (okKey and key) or slot.modifierKey or ""
	slot.isActive = readAttribute("IsActive", false) == true
	slot.currCount = readAttribute("CurrCount", 0)
	slot.charMtg = readAttribute("CharMtg", 0)
	slot.isPaused = readAttribute("IsPaused", false) == true
	slot.endTime = readAttribute("EndTime", 0)
	if not slot.modifierType then
		slot.modifierType = readAttribute("UgcModifierType", "")
	end
	if not slot.maxStackCount then
		slot.maxStackCount = readAttribute("MaxStackCount", config.DEFAULT_MAX_STACK_COUNT)
	end
	if not slot.desc then
		slot.desc = readAttribute("ModifierDesc", "")
	end
	-- 真销毁清理通道 1：引擎销毁复制触发 Destroying，与 OnModifierRemoved 消息通道互为兜底，
	-- 解绑幂等，双通道都触发时第二次为 no-op；ChildRemoved 不作为清理依据
	if not slot._destroyBound then
		slot._destroyBound = true
		child.Destroying:Connect(function()
			if self:_unbindSlot(container, child.UnitId) then
				self:removeMaterial(container, child.UnitId)
				self:applyTopMaterial(container)
			end
		end)
	end
	-- 已激活且带材质：补材质栈，用于新加入客户端恢复材质表现
	if slot.isActive then
		local materialId = tonumber(slot.charMtg) or 0
		if materialId > 0 then
			self:pushMaterial(container, unitId, materialId)
		end
	end
end

-- 注册与消息分发

---注册效果实体，由客户端预设壳调用；幂等
---@param modifierUnit Unit 效果实体单位
function CModifierSystemManager:registerModifier(modifierUnit)
	if RunService:IsServer() then
		return
	end
	if self._attachedModifiers[modifierUnit] then
		return
	end
	self._attachedModifiers[modifierUnit] = true
	ClientModifierHandler.new(modifierUnit, self)
end

---按 unitId 从拥有者子节点反查客户端处理器
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@return ClientModifierHandler? 客户端处理器
function CModifierSystemManager:_findClientHandler(container, unitId)
	if not unitId then
		return nil
	end
	for _, child in ipairs(container.owner:GetChildren()) do
		if child.UnitId == unitId then
			return self:getModifierHandler(child)
		end
	end
	return nil
end

---服务端事件分发，args[1] 已在订阅处过滤为 ownerUnitId
---@param container table 容器
---@param action string 服务端动作名
---@param ... any 业务参数
function CModifierSystemManager:_onServerPush(container, action, ...)
	local ServerAction = eventDefs.ServerAction
	local slots = container.slots

	if action == ServerAction.OnModifierAdded then
		local unitId, modifierKey, name, desc, icon, modifierType, maxStackCount = ...
		local slot = self:_bindSlot(container, unitId)
		slot.modifierKey = modifierKey
		slot.name = name
		slot.desc = desc
		slot.icon = icon
		slot.modifierType = modifierType
		slot.maxStackCount = maxStackCount

	elseif action == ServerAction.OnObtain then
		local unitId, endTime, currCount, charMtg = ...
		local slot = self:_bindSlot(container, unitId)
		slot.endTime = endTime
		slot.currCount = currCount
		slot.charMtg = charMtg
		slot.isActive = true
		if charMtg and charMtg > 0 then
			self:pushMaterial(container, unitId, charMtg)
		end

	elseif action == ServerAction.OnLoss then
		local unitId, oldMaterialId = ...
		if slots[unitId] then
			slots[unitId].isActive = false
			slots[unitId].charMtg = 0
		end
		if oldMaterialId and oldMaterialId > 0 then
			self:popMaterial(container, unitId)
		end

	elseif action == ServerAction.OnRefresh then
		local unitId, _, currCount, endTime = ...
		if slots[unitId] then
			slots[unitId].currCount = currCount
			if endTime then
				slots[unitId].endTime = endTime
			end
		end
		local handler = self:_findClientHandler(container, unitId)
		if handler then
			handler:onRefreshClient(currCount, endTime)
		end

	elseif action == ServerAction.OnReobtain then
		local unitId, newCount, endTime = ...
		local slot = slots[unitId]
		if slot then
			slot.currCount = newCount
			-- 叠加可能更新倒计时，同步绝对 EndTime
			if endTime then
				slot.endTime = endTime
			end
		end
		local handler = self:_findClientHandler(container, unitId)
		if handler then
			handler:onReobtainClient(newCount, endTime)
		end

	elseif action == ServerAction.OnStackChange then
		local unitId, newCount = ...
		if slots[unitId] then
			slots[unitId].currCount = newCount
		end
		local handler = self:_findClientHandler(container, unitId)
		if handler then
			handler:onStackChangeClient(newCount)
		end

	elseif action == ServerAction.OnPause then
		local unitId = ...
		if slots[unitId] then
			slots[unitId].isPaused = true
		end
		local handler = self:_findClientHandler(container, unitId)
		if handler then
			handler:onPauseClient()
		end

	elseif action == ServerAction.OnResume then
		local unitId, _, endTime = ...
		if slots[unitId] then
			slots[unitId].isPaused = false
			if endTime then
				slots[unitId].endTime = endTime
			end
		end
		local handler = self:_findClientHandler(container, unitId)
		if handler then
			handler:onResumeClient(endTime)
		end

	elseif action == ServerAction.OnModifierRemoved then
		local unitId = ...
		if self:_unbindSlot(container, unitId) then
			self:removeMaterial(container, unitId)
			self:applyTopMaterial(container)
		end
	end
end

---发送客户端请求到服务端
---@param ownerUnit Unit 拥有者单位
---@param action string 客户端动作名
---@param modifierKey string? 效果 Key
---@param unitId number? 效果实体 UnitId
---@param ... any 业务参数
function CModifierSystemManager:_fireServer(ownerUnit, action, modifierKey, unitId, ...)
	local ownerUnitId = ownerUnit and ownerUnit.UnitId or 0
	local payload = eventDefs.packClientPayload(action, ownerUnitId, modifierKey, unitId, ...)
	self._remoteEvent:FireServer(payload)
end

-- 材质栈管理

---材质入栈并应用栈顶，同效果重复入栈时先移除旧条目
---@param container table 容器
---@param unitId number 效果实体 UnitId
---@param materialId number 材质 ID
function CModifierSystemManager:pushMaterial(container, unitId, materialId)
	self:removeMaterial(container, unitId)
	table.insert(container.materialStack, { unitId = unitId, materialId = materialId })
	self:applyTopMaterial(container)
end

---材质出栈并应用栈顶
---@param container table 容器
---@param unitId number 效果实体 UnitId
function CModifierSystemManager:popMaterial(container, unitId)
	self:removeMaterial(container, unitId)
	self:applyTopMaterial(container)
end

---移除指定效果的材质条目
---@param container table 容器
---@param unitId number 效果实体 UnitId
function CModifierSystemManager:removeMaterial(container, unitId)
	for i = #container.materialStack, 1, -1 do
		if container.materialStack[i].unitId == unitId then
			table.remove(container.materialStack, i)
		end
	end
end

---应用材质栈顶：有材质则设置，无材质则还原
---@param container table 容器
function CModifierSystemManager:applyTopMaterial(container)
	local owner = container.owner
	if not owner then
		return
	end
	local topEntry = container.materialStack[#container.materialStack]
	if topEntry and topEntry.materialId > 0 then
		-- 材质设置为可选表现接口，失败仅跳过本次表现
		pcall(function()
			if owner.SetCharMtg then
				owner:SetCharMtg(topEntry.materialId)
			end
		end)
	else
		-- 材质还原为可选表现接口，失败仅跳过本次表现
		pcall(function()
			if owner.RestoreCharMtg then
				owner:RestoreCharMtg()
			end
		end)
	end
end

-- 修改请求：客户端发往服务端

---请求移除拥有者身上指定 Key 的所有效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 恒返回 0，结果以服务端回推为准
function CModifierSystemManager:removeModifierByKey(ownerUnit, modifierKey)
	local container = self:getContainer(ownerUnit)
	if not container or not modifierKey then
		return 0
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.RemoveByKey, modifierKey)
	return 0
end

---请求清除拥有者身上所有效果
---@param ownerUnit Unit 拥有者单位
---@return number 恒返回 0，结果以服务端回推为准
function CModifierSystemManager:clearAllModifiers(ownerUnit)
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.ClearAll)
	return 0
end

---请求移除指定效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
function CModifierSystemManager:removeModifier(ownerUnit, modifierKey, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.Remove, modifierKey, unitId)
	return true
end

---请求设置指定 Key 效果的层数
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param count number 目标层数
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
function CModifierSystemManager:setStackCount(ownerUnit, modifierKey, count, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.SetStack, modifierKey, unitId, count)
	return true
end

---请求增减指定 Key 效果的层数
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param delta number 层数增量
---@param unitId number? 效果实体 UnitId
---@return number 恒返回 0，结果以服务端回推为准
function CModifierSystemManager:addStackCount(ownerUnit, modifierKey, delta, unitId)
	if not modifierKey then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.AddStack, modifierKey, unitId, delta)
	return 0
end

---请求延长指定 Key 效果的持续时间
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param extra number 延长时间，单位秒
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
function CModifierSystemManager:addDuration(ownerUnit, modifierKey, extra, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.AddDuration, modifierKey, unitId, extra)
	return true
end

---请求设置指定 Key 效果的剩余时间
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param remaining number 剩余时间
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
function CModifierSystemManager:setRemainTime(ownerUnit, modifierKey, remaining, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.SetRemain, modifierKey, unitId, remaining)
	return true
end

---请求暂停指定 Key 效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
function CModifierSystemManager:pause(ownerUnit, modifierKey, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.Pause, modifierKey, unitId)
	return true
end

---请求恢复指定 Key 效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@param unitId number? 效果实体 UnitId
---@return boolean 请求是否已发出
function CModifierSystemManager:resume(ownerUnit, modifierKey, unitId)
	if not modifierKey then
		return false
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	self:_fireServer(ownerUnit, eventDefs.ClientAction.Resume, modifierKey, unitId)
	return true
end

-- 查询，读客户端镜像状态

---检查拥有者是否拥有指定 Key 的效果，Key 为空时返回是否存在任一效果
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return boolean 是否存在
function CModifierSystemManager:hasModifier(ownerUnit, modifierKey)
	local container = self:getContainer(ownerUnit)
	if not container then
		return false
	end
	if not modifierKey or modifierKey == "" then
		return next(container.slots) ~= nil
	end
	for _, slot in pairs(container.slots) do
		if slot.modifierKey == modifierKey then
			return true
		end
	end
	return false
end

---获取拥有者身上所有效果实体
---@param ownerUnit Unit 拥有者单位
---@return Unit[] 效果实体单位列表
function CModifierSystemManager:getModifierUnits(ownerUnit)
	local container = self:getContainer(ownerUnit)
	if not container then
		return {}
	end
	local result = {}
	for _, unitId in ipairs(container.order) do
		local slot = container.slots[unitId]
		if slot and slot.unit then
			table.insert(result, slot.unit)
		end
	end
	return result
end

---按 Key 在客户端状态中定位，返回 unitId 与状态条目；未匹配时均返回 nil
---@param container table 容器
---@param modifierKey string 效果 Key
---@return number? 效果实体 UnitId
---@return table? 状态条目
function CModifierSystemManager:_findSlotByKey(container, modifierKey)
	if not modifierKey or modifierKey == "" then
		return nil, nil
	end
	for _, unitId in ipairs(container.order) do
		local slot = container.slots[unitId]
		if slot and slot.modifierKey == modifierKey then
			return unitId, slot
		end
	end
	return nil, nil
end

---按 Key 获取所有匹配的效果实体列表
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return Unit[] 效果实体单位列表
function CModifierSystemManager:getModifierUnitsByKey(ownerUnit, modifierKey)
	local result = {}
	if not modifierKey or modifierKey == "" then
		return result
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return result
	end
	for _, unitId in ipairs(container.order) do
		local slot = container.slots[unitId]
		if slot and slot.modifierKey == modifierKey and slot.unit then
			table.insert(result, slot.unit)
		end
	end
	return result
end

---获取指定 Key 效果的剩余时间，单位秒，永久效果返回 -1；按状态 EndTime 换算
---@param ownerUnit Unit 拥有者单位
---@param modifierKey string 效果 Key
---@return number 剩余时间
function CModifierSystemManager:getRemainingTimeByKey(ownerUnit, modifierKey)
	if not modifierKey or modifierKey == "" then
		return 0
	end
	local container = self:getContainer(ownerUnit)
	if not container then
		return 0
	end
	local _, slot = self:_findSlotByKey(container, modifierKey)
	if not slot or not slot.endTime then
		return 0
	end
	if slot.endTime < 0 then
		-- 永久效果
		return -1
	end
	-- 时间源异常时返回 0，不阻断查询
	local ok, now = pcall(util.getServerTime)
	if not ok or not now then
		return 0
	end
	return math.max(0, slot.endTime - now)
end

-- 处理器字典与标记

---按效果实体反查处理器
---@param modifierUnit Unit 效果实体单位
---@return ClientModifierHandler? 客户端处理器
function CModifierSystemManager:getModifierHandler(modifierUnit)
	if not modifierUnit then
		return nil
	end
	return self._modifiers[modifierUnit.UnitId]
end

---注册客户端处理器
---@param modifierUnit Unit 效果实体单位
---@param handler ClientModifierHandler 客户端处理器
function CModifierSystemManager:registerModifierHandler(modifierUnit, handler)
	self._modifiers[modifierUnit.UnitId] = handler
end

---反注册客户端处理器
---@param modifierUnit Unit 效果实体单位
function CModifierSystemManager:unregisterModifierHandler(modifierUnit)
	self._modifiers[modifierUnit.UnitId] = nil
end

---为 Unit 添加标记，优先写引擎组件，同时记录 Lua 层回退
---@param unit Unit 目标单位
---@param tag string 标记
function CModifierSystemManager:addTag(unit, tag)
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
function CModifierSystemManager:hasTag(unit, tag)
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
function CModifierSystemManager:clearTags(unit)
	self._luaTags[unit.UnitId] = nil
end

return CModifierSystemManager.new()
