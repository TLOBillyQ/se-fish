--技能系统 - common事件信号与通道定义
-- 双端共享。

local AbilityConstants = require("common.packages.ability_system.constants")

local AbilityEventDefs = {}

-- 单一 RemoteEvent 通道
-- RemoteEvent 契约：FireServer(args) 单参数 / OnServerEvent(player, args) / OnClientEvent(args)
-- 载荷统一为单参数 table：{ action = <action>, ...业务字段 }

local _abilityRemote = nil

function AbilityEventDefs.getRemote()
	if not _abilityRemote then
		_abilityRemote = RemoteEvent.New(AbilityConstants.CHANNEL_NAME)
	end
	return _abilityRemote
end

-- 打包 s→c 载荷（服务端广播给客户端）
function AbilityEventDefs.packServerPayload(action, ...)
	return {
		action = action,
		args = { ... },
	}
end

-- Action 字符串集合
-- c→s 客户端可发的 action
AbilityEventDefs.ClientAction = {
	Cast = "Cast",
	BreakCast = "BreakCast",
	Accumulate = "Accumulate",
	Upgrade = "Upgrade",
	SwitchNext = "SwitchNext",
}

-- s→c 服务端可推的 action
-- OnSwitchNext 契约：args = { ownerUnitId, slotIndex, newActiveIndex }（子技能组切换广播，客户端按归属过滤）
AbilityEventDefs.ServerAction = {
	OnCastStart = "OnCastStart",
	OnCastEnd = "OnCastEnd",
	OnCastBreak = "OnCastBreak",
	OnCDEnd = "OnCDEnd",
	OnCharge = "OnCharge",
	OnSwitchNext = "OnSwitchNext",
	FullSnapshot = "FullSnapshot",
	ForbidSlot = "ForbidSlot",
}

-- 本地事件工厂（BindableEvent 单位方式）
-- 事件单位 = 引擎原生 BindableEvent（本地事件，纯逻辑容器，提供 Connect/Once/Wait/Fire）。
-- 事件单位挂在所有者单位下：作者可用 ownerUnit:FindFirstChild(eventName) 直接拿到事件单位注册监听。
-- 生命周期不依赖父子级联销毁：所有者销毁时须显式调用 destroySignals(signals) 清理。

-- 创建单个事件单位并挂到所有者单位下。
-- 已存在同名事件单位时直接复用：重复 Attach / 重复实例化时不得再造第二份，
-- 否则 FindFirstChild 与内部 signals 引用会指向不同单位，监听方全部收不到 Fire。
function AbilityEventDefs.createEventUnit(ownerUnit, name)
	local existing = ownerUnit:FindFirstChild(name)
	if existing then
		return existing
	end
	local unit = game:CreateUnit("BindableEvent", { Name = name })
	unit.Parent = ownerUnit
	return unit
end

-- 技能级 signals（挂在 abilityScript 下）
function AbilityEventDefs.createAbilitySignals(ownerUnit)
	local signals = {}
	for _, name in pairs(AbilityConstants.EventType) do
		signals[name] = AbilityEventDefs.createEventUnit(ownerUnit, name)
	end
	return signals
end

-- 锚点级 signals（挂在锚点子单位下）
-- 主体是锚点自身：每个锚点自带一套四事件，监听方无需 groupId 过滤
function AbilityEventDefs.createAnchorSignals(ownerUnit)
	local signals = {}
	for _, name in pairs(AbilityConstants.AnchorEvent) do
		signals[name] = AbilityEventDefs.createEventUnit(ownerUnit, name)
	end
	return signals
end

-- 管理器级 signals（挂在 manager 下）
function AbilityEventDefs.createManagerSignals(ownerUnit)
	local signals = {}
	for _, name in pairs(AbilityConstants.ManagerEvent) do
		signals[name] = AbilityEventDefs.createEventUnit(ownerUnit, name)
	end
	return signals
end

-- 销毁一组事件单位（所有者单位销毁时显式调用，不依赖父子级联销毁）
function AbilityEventDefs.destroySignals(signals)
	for name, unit in pairs(signals) do
		signals[name] = nil
		pcall(function()
			unit:Destroy()
		end)
	end
end

-- Signal 触发 helper

function AbilityEventDefs.fireEvent(signals, name, ...)
	local sig = signals[name]
	if sig then
		sig:Fire(...)
	end
end

-- 可拦截事件钩子
function AbilityEventDefs.fireBefore(signals, name, ...)
	local sig = signals[name]
	if not sig then
		return false
	end
	sig:Fire(...)
	return false
end

return AbilityEventDefs
