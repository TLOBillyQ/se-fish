--效果系统包 - 事件定义与事件单位工厂
--定义跨端消息动作、载荷打包与本地BindableEvent 事件单位的创建与触发。

local config = require("common.packages.modifier_system.config")

local eventDefs = {}

-- 客户端可发送的请求动作集合：客户端发往服务端
eventDefs.ClientAction = {
	Remove = "Remove",
	RemoveByKey = "RemoveByKey",
	ClearAll = "ClearAll",
	SetStack = "SetStack",
	AddStack = "AddStack",
	AddDuration = "AddDuration",
	SetRemain = "SetRemain",
	Pause = "Pause",
	Resume = "Resume",
}

-- 服务端可推送的通知动作集合：服务端发往客户端
eventDefs.ServerAction = {
	OnModifierAdded = "OnModifierAdded",
	OnModifierRemoved = "OnModifierRemoved",
	OnObtain = "OnObtain",
	OnLoss = "OnLoss",
	OnReobtain = "OnReobtain",
	OnRefresh = "OnRefresh",
	OnStackChange = "OnStackChange",
	OnPause = "OnPause",
	OnResume = "OnResume",
}

---打包服务端广播载荷：args[1] 恒为 ownerUnitId，客户端据此过滤
---@param action string 服务端动作名
---@param ... any 业务参数
---@return table 载荷
function eventDefs.packServerPayload(action, ...)
	return {
		action = action,
		args = { ... },
	}
end

---打包客户端请求载荷：args[1] 恒为 ownerUnitId，args[2] 为 modifierKey，余下为业务参数
---@param action string 客户端动作名
---@param ownerUnitId number 拥有者单位 UnitId
---@param ... any 业务参数
---@return table 载荷
function eventDefs.packClientPayload(action, ownerUnitId, ...)
	return {
		action = action,
		args = { ownerUnitId, ... },
	}
end

---获取或创建挂载在指定单位下的同名 BindableEvent 事件单位
---先查后建：同名单位已存在时直接复用，避免脚本重载/重放场景重复创建
---@param ownerUnit Unit 挂载目标单位
---@param name string 事件单位名
---@return Unit 事件单位
function eventDefs.getOrCreateEventUnit(ownerUnit, name)
	-- FindFirstChild 为可选的沙箱接口，探测失败时按不存在处理，照常创建
	local ok, existing = pcall(function()
		return ownerUnit:FindFirstChild(name)
	end)
	if ok and existing then
		return existing
	end
	local unit = game:CreateUnit("BindableEvent", { Name = name })
	unit.Parent = ownerUnit
	return unit
end

---创建效果级事件单位集合，挂效果单位下，供子脚本监听
---@param modifierUnit Unit 效果单位
---@return table<string, Unit> 事件名 → 事件单位
function eventDefs.createModifierSignals(modifierUnit)
	local signals = {}
	for _, name in pairs(config.EventType) do
		signals[name] = eventDefs.getOrCreateEventUnit(modifierUnit, name)
	end
	return signals
end

---创建拥有者级事件单位集合，挂拥有者单位下，供作者监听
---@param ownerUnit Unit 拥有者单位
---@return table<string, Unit> 事件名 → 事件单位
function eventDefs.createManagerSignals(ownerUnit)
	local signals = {}
	for _, name in pairs(config.ManagerEvent) do
		signals[name] = eventDefs.getOrCreateEventUnit(ownerUnit, name)
	end
	return signals
end

---销毁一组事件单位，持有者销毁时显式调用，不依赖父子级联销毁
---@param signals table<string, Unit> 事件单位集合
function eventDefs.destroySignals(signals)
	for name, unit in pairs(signals) do
		signals[name] = nil
		-- 单位可能已随父级联销毁，单个销毁失败不阻断其余清理
		pcall(function()
			unit:Destroy()
		end)
	end
end

---触发指定名称的事件单位
---@param signals table<string, Unit> 事件单位集合
---@param name string 事件名
---@param ... any 事件参数
function eventDefs.fireEvent(signals, name, ...)
	local signal = signals[name]
	if signal then
		signal:Fire(...)
	end
end

return eventDefs
