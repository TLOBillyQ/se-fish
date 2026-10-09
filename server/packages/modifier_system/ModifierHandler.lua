--效果系统包 - server端效果处理器
--ModifierHandler：单个效果实例的服务端权威状态与生命周期，处理激活/失活/叠加/暂停。
--配置动态读取：每次从效果单位属性取值，保证拿到覆盖后的最新配置。

local TimerService = game:GetService("TimerService")

local config = require("common.packages.modifier_system.config")
local eventDefs = require("common.packages.modifier_system.event_defs")
local util = require("common.packages.modifier_system.util")
local eventBridge = require("server.packages.modifier_system.event_bridge")
local ModifierStack = require("server.packages.modifier_system.ModifierStack")

-- attr_rule 为可选依赖：延迟探测，未部署时静默跳过属性修改；门面结构不符时输出一次性诊断。
local attrRuleAPICache = false
local attrRuleFacadeWarned = false
local function getAttrRuleAPI()
	if attrRuleAPICache == false then
		local ok, api = pcall(function()
			return require("server.packages.attr_rule.api")
		end)
		attrRuleAPICache = (ok and api) or nil
	end
	return attrRuleAPICache
end

local function getAttrRuleFunc(methodName)
	local attrRuleAPI = getAttrRuleAPI()
	if not attrRuleAPI then
		return nil
	end
	local attrFuncs = type(attrRuleAPI) == "table" and attrRuleAPI.Funcs or nil
	local func = type(attrFuncs) == "table" and attrFuncs[methodName] or nil
	if type(func) ~= "function" then
		if not attrRuleFacadeWarned then
			attrRuleFacadeWarned = true
			print("[modifier_system] attr_rule facade mismatch, AttrConfigs changes are skipped")
		end
		return nil
	end
	return func
end

---效果处理器：单个效果实例的服务端状态与行为
---@class ModifierHandler
---@field unit Unit 效果实体单位，脚本直接运行在效果单位上
---@field manager SModifierSystemManager 服务端效果管理器
---@field private _source Unit? 效果来源单位，动态创建时注入，可空
---@field private _destroyHandled boolean 销毁收尾是否已执行，幂等保护
---@field signals table<string, Unit> 效果级事件单位集合
---@field state table 权威状态，含激活/层数/倒计时/材质/暂停/Buff句柄/叠加组件
local ModifierHandler = {}
ModifierHandler.__index = ModifierHandler

---创建效果处理器并完成注册
---@param modifierUnit Unit 效果实体单位
---@param manager SModifierSystemManager 服务端效果管理器
---@return ModifierHandler
function ModifierHandler.new(modifierUnit, manager)
	local self = setmetatable({}, ModifierHandler)
	self.unit = modifierUnit
	self.manager = manager
	self._source = nil
	self._destroyHandled = false
	self.signals = eventDefs.createModifierSignals(modifierUnit)
	self.state = {
		isActive = false,
		endTime = 0,
		obtainTime = 0,
		currCount = 0,
		charMtg = 0,
		isPaused = false,
		pauseTime = 0,
		removeTimer = nil,
		attrBuffId = nil,
		attrAppliedCount = nil, -- 属性结算时对应的层数
		stack = nil,
	}
	-- 初始运行时属性同步到客户端，供子脚本 GetAttributeChangedSignal 监听
	local Attr = config.Attr
	modifierUnit:SetAttribute(Attr.IsActive, false)
	modifierUnit:SetAttribute(Attr.CurrCount, 0)
	modifierUnit:SetAttribute(Attr.CharMtg, 0)
	modifierUnit:SetAttribute(Attr.IsPaused, false)
	modifierUnit:SetAttribute(Attr.EndTime, 0)
	manager:addTag(modifierUnit, config.Tag.ModifierUnit)
	manager:registerModifierHandler(modifierUnit, self)
	modifierUnit.Destroying:Connect(function()
		self:_onDestroying()
	end)
	return self
end

---读取标量配置，空值回退默认值
---@param name string 属性名
---@param fallback any 默认值
---@return any 配置值
function ModifierHandler:_getScalarConf(name, fallback)
	local value = self.unit:GetAttribute(name)
	if value ~= nil and value ~= "" then
		return value
	end
	return fallback
end

---读取列表配置，空表回退空表
---@param name string 属性名
---@return table 配置列表
function ModifierHandler:_getListConf(name)
	local value = self.unit:GetAttribute(name)
	if value and type(value) == "table" and next(value) ~= nil then
		return value
	end
	return {}
end

---设置效果来源单位，动态创建时由管理器注入
---@param source Unit 来源单位
function ModifierHandler:setSource(source)
	self._source = source
end

---是否允许叠加，需 Stackable=true 且已初始化叠加组件
---@return boolean 是否允许叠加
function ModifierHandler:isStackable()
	return self:_getScalarConf("Stackable", false) == true
end

---获取效果拥有者，效果直挂生物下，unit.Parent 即拥有者
---@return Unit? 拥有者单位
function ModifierHandler:getOwner()
	return self.unit.Parent
end

---获取效果实体单位
---@return Unit 效果实体单位
function ModifierHandler:getUnit()
	return self.unit
end

---获取效果 Key
---@return string 效果 Key
function ModifierHandler:getModifierKey()
	local value = self.unit:GetAttribute("ModifierKey")
	if value ~= nil and value ~= "" then
		return value
	end
	return ""
end

---是否处于激活状态
---@return boolean 是否激活
function ModifierHandler:isActive()
	return self.state.isActive
end

---获取当前层数
---@return number 当前层数
function ModifierHandler:getStackCount()
	return self.state.currCount
end

---获取当前材质 ID，0 表示无材质
---@return number 材质 ID
function ModifierHandler:getCharMtg()
	return self.state.charMtg
end

---是否处于暂停状态
---@return boolean 是否暂停
function ModifierHandler:isPaused()
	return self.state.isPaused
end

---获取最大层数
---@return number 最大层数
function ModifierHandler:getMaxStackCount()
	local raw = self:_getScalarConf("MaxStackCount", config.DEFAULT_MAX_STACK_COUNT)
	return tonumber(raw) or config.DEFAULT_MAX_STACK_COUNT
end

---获取效果来源单位
---@return Unit? 来源单位
function ModifierHandler:getSource()
	return self._source
end

---获取效果类型，取值 0 有益 / 1 有害 / 2 中立
---@return number 效果类型
function ModifierHandler:getModifierType()
	return self:_getScalarConf("UgcModifierType", config.ModifierType.Neutral)
end

---获取效果描述
---@return string 描述
function ModifierHandler:getDesc()
	return self:_getScalarConf("ModifierDesc", "")
end

---获取效果图标资源路径
---@return string 图标路径
function ModifierHandler:getIcon()
	return self:_getScalarConf("Icon", "")
end

---获取效果名称
---@return string 名称
function ModifierHandler:getName()
	return self:_getScalarConf("Name", "")
end

---通知所有客户端，附带 ownerUnitId 供客户端过滤；消息体以 unitId 定位实例
---@param action string 服务端动作名
---@param ... any 业务参数
function ModifierHandler:_notify(action, ...)
	local ownerUnitId = self.unit.Parent and self.unit.Parent.UnitId or 0
	self.manager:notifyClients(ownerUnitId, action, ...)
end

---激活效果：设激活态、按当前层数应用属性修改、计算材质、启动倒计时、初始化叠加组件
---被管理器注册流程触发；返回 false 表示本次获得被"阻止效果获得"拦截
---@return boolean 是否成功激活
function ModifierHandler:onObtain()
	if self.state.isActive then
		return true
	end
	-- 触发"即将获得"事件，可在其中调用"阻止本次效果获得"
	eventDefs.fireEvent(self.signals, config.EventType.BeforeObtain, self.unit)
	eventBridge.fireObtainBefore(self.unit, self:getOwner())
	if eventBridge.consumeIntercept(self.unit) then
		-- 本次获得被拦截，不激活
		return false
	end

	self.state.isActive = true
	local stepCount = self:_getScalarConf("StackCountStep", config.DEFAULT_STACK_COUNT_STEP)
	self.state.currCount = tonumber(stepCount) or config.DEFAULT_STACK_COUNT_STEP
	self.state.obtainTime = util.getServerTime()

	self:_applyAttrChanges()
	self:_computeCharMtg()
	self:_setupMaxDuration()

	-- 可叠加时初始化叠加组件，内部按模式完成首层初始化
	if self:isStackable() then
		self.state.stack = ModifierStack.new(self, self:_buildStackConfig())
	end

	-- 同步运行时属性到客户端，EndTime 已由 _setupMaxDuration 经 _setEndTime 同步
	local Attr = config.Attr
	self.unit:SetAttribute(Attr.IsActive, true)
	self.unit:SetAttribute(Attr.CurrCount, self.state.currCount)
	self.unit:SetAttribute(Attr.CharMtg, self.state.charMtg)

	eventDefs.fireEvent(self.signals, config.EventType.Obtain, self.unit, self:getOwner())

	self:_notify(
		eventDefs.ServerAction.OnObtain,
		self.unit.UnitId,
		self.state.endTime,
		self.state.currCount,
		self.state.charMtg
	)
	return true
end

---失活效果：设失活态、回滚属性修改、清材质、取消倒计时、销毁叠加组件
---被 _onDurationFinish / removeModifierWithLoss 触发
function ModifierHandler:onLoss()
	if not self.state.isActive then
		return
	end
	self.state.isActive = false
	self:_rollbackAttrChanges()
	local oldMaterialId = self.state.charMtg
	self.state.charMtg = 0
	self:_cancelRemoveTimer()

	if self.state.stack then
		self.state.stack:destroy()
		self.state.stack = nil
	end

	-- 同步运行时属性到客户端
	local Attr = config.Attr
	self.unit:SetAttribute(Attr.IsActive, false)
	self.unit:SetAttribute(Attr.CharMtg, 0)

	eventDefs.fireEvent(self.signals, config.EventType.Loss, self.unit, self:getOwner())

	self:_notify(
		eventDefs.ServerAction.OnLoss,
		self.unit.UnitId,
		oldMaterialId
	)
end

---计算获得表现里的材质，取最后一个材质替换条目，存到 state.charMtg
---属性面板配置字段为 Fixed 定点数，比较/赋值前先 tonumber() 归一化
function ModifierHandler:_computeCharMtg()
	local performanceList = self:_getListConf("ObtainPerformanceList")
	if #performanceList == 0 then
		return
	end
	local lastMaterialConfig = nil
	for _, performanceConfig in ipairs(performanceList) do
		local performanceType = tonumber(performanceConfig.PerformanceType)
		if performanceType == config.PerformanceType.SkinMaterial then
			lastMaterialConfig = performanceConfig
		end
	end
	if lastMaterialConfig and tonumber(lastMaterialConfig.Mtg or 0) > 0 then
		self.state.charMtg = tonumber(lastMaterialConfig.Mtg)
	end
end

---设置最大持续时间并启动倒计时，Duration=0 表示永久
function ModifierHandler:_setupMaxDuration()
	local duration = tonumber(self:_getScalarConf("Duration", config.DEFAULT_DURATION)) or 0
	if duration > 0 then
		self:_setEndTime(util.getServerTime() + duration)
		self:_cancelRemoveTimer()
		self.state.removeTimer = TimerService:CreateTimer(1, duration, false, function()
			self:_onDurationFinish()
		end)
	else
		self:_setEndTime(-1)
	end
end

---倒计时到期处理：先 onLoss 失活，再从容器移除
function ModifierHandler:_onDurationFinish()
	eventDefs.fireEvent(self.signals, config.EventType.DurationFinish, self.unit)
	self:onLoss()
	local owner = self.unit.Parent
	local container = owner and self.manager:getContainer(owner)
	if container then
		-- 这里只做移除，onLoss 已执行过
		self.manager:removeModifierUnit(container, self.unit)
	end
end

---取消当前倒计时计时器
function ModifierHandler:_cancelRemoveTimer()
	if self.state.removeTimer then
		-- 计时器可能已触发回收，取消失败不影响状态清理
		pcall(function()
			self.state.removeTimer:Cancel()
		end)
		self.state.removeTimer = nil
	end
end

---确保 EndTime 覆盖指定时刻，供独立计时模式叠加层使用
---@param targetEndTime number 目标结束时间戳
function ModifierHandler:_ensureEndTimeCovers(targetEndTime)
	if self.state.endTime < 0 then
		-- 永久效果不处理
		return
	end
	if self.state.endTime < targetEndTime then
		self:_setEndTime(targetEndTime)
		self:_rebuildTimerFromEndTime()
	end
end

---按 state.endTime 重建倒计时，时间叠加修改后
function ModifierHandler:_rebuildTimerFromEndTime()
	self:_cancelRemoveTimer()
	if self.state.endTime <= 0 then
		return
	end
	if self.state.isPaused then
		return
	end
	local left = self.state.endTime - util.getServerTime()
	if left <= 0 then
		self:_onDurationFinish()
		return
	end
	self.state.removeTimer = TimerService:CreateTimer(1, left, false, function()
		self:_onDurationFinish()
	end)
end

---获取剩余时间，单位秒，永久效果返回 -1；其余按绝对 EndTime 换算
---@return number 剩余时间
function ModifierHandler:getRemainingTime()
	if self.state.endTime < 0 then
		return -1
	end
	if self.state.endTime == 0 then
		return 0
	end
	if self.state.isPaused then
		return self.state.endTime - self.state.pauseTime
	end
	return math.max(0, self.state.endTime - util.getServerTime())
end

---获取绝对结束时间戳，0 表示未激活，-1 表示永久
---@return number 结束时间戳
function ModifierHandler:getEndTime()
	return self.state.endTime
end

---EndTime 单一写入口：更新权威状态并同步实体属性，引擎复制到客户端状态
---@param value number 结束时间戳
function ModifierHandler:_setEndTime(value)
	self.state.endTime = value
	self.unit:SetAttribute(config.Attr.EndTime, value)
end

---暂停效果：记暂停起始时刻、取消倒计时、暂停叠加计时器
function ModifierHandler:pause()
	if self.state.isPaused then
		return
	end
	self.state.isPaused = true
	self.state.pauseTime = util.getServerTime()
	self:_cancelRemoveTimer()
	if self.state.stack then
		self.state.stack:pauseTimers()
	end
	self.unit:SetAttribute(config.Attr.IsPaused, true)
	eventDefs.fireEvent(self.signals, config.EventType.Pause, self.unit)
	self:_notify(eventDefs.ServerAction.OnPause, self.unit.UnitId)
end

---恢复效果：补偿暂停期间的时长、重建倒计时、恢复叠加计时器
function ModifierHandler:resume()
	if not self.state.isPaused then
		return
	end
	local paused = util.getServerTime() - self.state.pauseTime
	self.state.isPaused = false
	if self.state.endTime > 0 then
		self:_setEndTime(self.state.endTime + paused)
		self:_rebuildTimerFromEndTime()
	end
	if self.state.stack then
		self.state.stack:resumeTimers()
	end
	self.unit:SetAttribute(config.Attr.IsPaused, false)
	eventDefs.fireEvent(self.signals, config.EventType.Resume, self.unit)
	self:_notify(
		eventDefs.ServerAction.OnResume,
		self.unit.UnitId,
		self:getRemainingTime(),
		self.state.endTime
	)
end

---延长持续时间，extra 可为负数表示缩短
---@param extra number 延长时间，单位秒
function ModifierHandler:extendDuration(extra)
	if self.state.endTime <= 0 then
		return
	end
	self:_setEndTime(self.state.endTime + (tonumber(extra) or 0))
	if not self.state.isPaused then
		self:_rebuildTimerFromEndTime()
	end
	self:_notifyRefresh()
end

---设置剩余时间，单位秒
---@param remaining number 剩余时间
function ModifierHandler:setRemainingTime(remaining)
	if self.state.endTime <= 0 then
		return
	end
	remaining = math.max(0, tonumber(remaining) or 0)
	if self.state.isPaused then
		self:_setEndTime(self.state.pauseTime + remaining)
	else
		self:_setEndTime(util.getServerTime() + remaining)
		self:_rebuildTimerFromEndTime()
	end
	self:_notifyRefresh()
end

---通知客户端刷新倒计时/层数显示，携带权威 endTime 供客户端状态换算
function ModifierHandler:_notifyRefresh()
	self:_notify(
		eventDefs.ServerAction.OnRefresh,
		self.unit.UnitId,
		self:getRemainingTime(),
		self.state.currCount,
		self.state.endTime
	)
end

---由叠加组件回调，更新 currCount、重结算属性并广播
---@param newCount number 新层数
function ModifierHandler:_onStackCountChanged(newCount)
	self.state.currCount = newCount
	self.unit:SetAttribute(config.Attr.CurrCount, newCount)
	self:_syncAttrChangesToCount(newCount)
	self:_notify(
		eventDefs.ServerAction.OnStackChange,
		self.unit.UnitId,
		newCount
	)
end

---层数变化后按新层数重结算属性修改：先减回已施加的 buff，再重新施加
---层数未变化时跳过；未激活时不动属性
---@param newCount number 新层数
function ModifierHandler:_syncAttrChangesToCount(newCount)
	if not self.state.isActive then
		return
	end
	newCount = tonumber(newCount) or 0
	if self.state.attrAppliedCount == newCount then
		return
	end
	self:_rollbackAttrChanges()
	self:_applyAttrChanges(newCount)
end

---应用属性修改，对接 attr_rule：把 AttrConfigs 转成 Buff 施加到拥有者，
---Buff 句柄存 state.attrBuffId，onLoss 时经 RemoveAttrBuff 按记录回滚
---施加值 = 配置值 × 当前层数；施加失败不记账，待下次层数变化重试
---@param scale number? 缺省按叠加状态推导（叠加取层数、非叠加恒 1）
function ModifierHandler:_applyAttrChanges(scale)
	if scale == nil then
		if self:isStackable() then
			-- 叠加效果按当前层数缩放，与建栈层数归一规则一致（避免首层瞬时超发）
			local count = math.max(1, tonumber(self.state.currCount) or 1)
			local maxCount = math.max(1, self:getMaxStackCount())
			scale = math.min(count, maxCount)
		else
			-- 非叠加效果恒按 1 层施加
			scale = 1
		end
	end
	scale = tonumber(scale) or 1
	if scale < 0 then
		scale = 0
	end
	if scale == 0 then
		-- 层数归零：保持回滚态，不再施加
		self.state.attrAppliedCount = 0
		return
	end
	local attrConfigs = self:_getListConf("AttrConfigs")
	if #attrConfigs == 0 then
		-- 未配置属性修改：记下当前层数，避免层数变化反复空转
		self.state.attrAppliedCount = scale
		return
	end
	local owner = self:getOwner()
	if not owner then
		return
	end
	-- 先构建有效条目，丢弃空 Key / 零值条目：未配置真实属性修改时不触发依赖探测
	-- 分量类型编号与 attr_rule 的 AttrComponentType 对齐：0=基础值 1=基础额外值 2=加成比例 3=额外加成
	local buffConfigs = {}
	for _, attrConfig in ipairs(attrConfigs) do
		local attrKey = attrConfig.AttrKey or attrConfig.attrKey
		local attrType = tonumber(attrConfig.AttrType or attrConfig.attrType) or 0
		if attrType < 0 or attrType > 3 then
			-- 非法分量类型按基础值处理，与 attr_rule 的 AttrComponentType 0-3 对齐
			attrType = 0
		end
		local value = (tonumber(attrConfig.Value or attrConfig.attrValue) or 0) * scale
		if attrKey and attrKey ~= "" and value ~= 0 then
			table.insert(buffConfigs, {
				AttrKey = attrKey,
				AttrComponentType = attrType,
				Value = value,
			})
		end
	end
	if #buffConfigs == 0 then
		self.state.attrAppliedCount = scale
		return
	end
	local addAttrBuff = getAttrRuleFunc("AddAttrBuff")
	if not addAttrBuff then
		return
	end
	local buffId = addAttrBuff(owner, buffConfigs)
	if buffId == nil then
		return
	end
	self.state.attrBuffId = buffId
	self.state.attrAppliedCount = scale
end

---回滚属性修改，onLoss / 层数重结算前调用：RemoveAttrBuff 按 attr_rule 内部记录的增量逐个减回
function ModifierHandler:_rollbackAttrChanges()
	local buffId = self.state.attrBuffId
	if buffId == nil then
		return
	end
	self.state.attrBuffId = nil
	local removeAttrBuff = getAttrRuleFunc("RemoveAttrBuff")
	if not removeAttrBuff then
		return
	end
	local owner = self:getOwner()
	if not owner then
		return
	end
	removeAttrBuff(owner, buffId)
end

---构建叠加配置，动态读取，供 ModifierStack 使用
---@return table 叠加配置
function ModifierHandler:_buildStackConfig()
	return {
		enableStack = self:isStackable(),
		maxStackCount = tonumber(self:_getScalarConf("MaxStackCount", config.DEFAULT_MAX_STACK_COUNT))
			or config.DEFAULT_MAX_STACK_COUNT,
		stackDurationMode = tonumber(self:_getScalarConf("StackDurationMode", 0)) or 0,
		stackCountMode = tonumber(self:_getScalarConf("StackCountMode", 0)) or 0,
		obtainCount = tonumber(self:_getScalarConf("StackCountStep", config.DEFAULT_STACK_COUNT_STEP))
			or config.DEFAULT_STACK_COUNT_STEP,
		sameSourceOnly = self:_getScalarConf("SameSourceStack", false) == true,
		duration = tonumber(self:_getScalarConf("Duration", 0)) or 0,
	}
end

---是否允许叠加，叠加组件已初始化且开启叠加
---@return boolean 是否允许叠加
function ModifierHandler:enableReobtain()
	return self.state.stack ~= nil and self.state.stack.enableStack
end

---是否仅同源叠加，SameSourceStack 配置，动态读取
---@return boolean 是否仅同源叠加
function ModifierHandler:isSameSourceOnly()
	return self:_getScalarConf("SameSourceStack", false) == true
end

---新实例到来时，本实例是否可与之叠加
---仅同源叠加时要求来源一致；来源未知为 nil 时不阻断
---@param sourceUnit Unit? 新实例来源单位
---@return boolean 是否可叠加
function ModifierHandler:canReobtain(sourceUnit)
	if not self:enableReobtain() then
		return false
	end
	if self:isSameSourceOnly() and self._source and sourceUnit then
		return self._source == sourceUnit
	end
	return true
end

---重新获得时的叠加处理，由管理器叠加路由调用
---@return number? 旧层数
---@return number? 新层数
function ModifierHandler:whenReobtain()
	if not self.state.stack then
		return nil, nil
	end
	local oldCount, newCount = self.state.stack:whenReobtain()
	if newCount then
		self.state.currCount = newCount
	elseif self.state.stack.stackCount == 0 then
		-- 层数归零触发移除，带失活处理
		local owner = self.unit.Parent
		local container = owner and self.manager:getContainer(owner)
		if container then
			self.manager:removeModifierWithLoss(container, self.unit)
		end
	end
	eventDefs.fireEvent(self.signals, config.EventType.StackChange, self.unit, oldCount, newCount)
	eventDefs.fireEvent(self.signals, config.EventType.Reobtain, self.unit, self:getOwner())
	return oldCount, newCount
end

---设置层数，归零触发带失活的移除
---@param count number 目标层数
---@return boolean 是否执行了设置
function ModifierHandler:setStackCount(count)
	if not self.state.stack then
		return false
	end
	if self.state.stack.stackDurationMode == config.StackDurationMode.StandAlone then
		return false
	end
	local _, newCount = self.state.stack:setStackCount(tonumber(count) or 0)
	if newCount then
		self.state.currCount = newCount
	elseif self.state.stack.stackCount == 0 then
		local owner = self.unit.Parent
		local container = owner and self.manager:getContainer(owner)
		if container then
			self.manager:removeModifierWithLoss(container, self.unit)
		end
	end
	self:_notify(
		eventDefs.ServerAction.OnStackChange,
		self.unit.UnitId,
		newCount or 0
	)
	return true
end

---增减层数，delta 可为负数
---@param delta number 层数增量
---@return boolean 是否执行了增减
function ModifierHandler:addStackCount(delta)
	if not self.state.stack then
		return false
	end
	if self.state.stack.stackDurationMode == config.StackDurationMode.StandAlone then
		return false
	end
	delta = tonumber(delta) or 0
	if delta == 0 then
		return true
	end
	local _, newCount = self.state.stack:setStackCount(self.state.stack.stackCount + delta)
	if newCount then
		self.state.currCount = newCount
	elseif self.state.stack.stackCount == 0 then
		local owner = self.unit.Parent
		local container = owner and self.manager:getContainer(owner)
		if container then
			self.manager:removeModifierWithLoss(container, self.unit)
		end
	end
	self:_notify(
		eventDefs.ServerAction.OnStackChange,
		self.unit.UnitId,
		newCount or 0
	)
	return true
end

---销毁清理，无论销毁来源：管理器移除 / 外部脚本直接销毁 / 拥有者级联销毁
---规范移除路径会先 onLoss 再销毁，此时本回调为幂等附加清理；
---外部直接销毁会绕过管理器——在此补偿失活与容器注销，保证收敛到一致终态
function ModifierHandler:_onDestroying()
	if self._destroyHandled then
		return
	end
	self._destroyHandled = true
	-- 防御：清理未消费的动态来源注入，正常路径已在注册时消费
	self.manager:clearPendingSourceOverride(self.unit)
	-- 补偿：激活态下被直接销毁 → 触发失活，回滚属性 / 事件 / 客户端通知
	if self.state.isActive then
		self:onLoss()
	end
	-- 补偿：从容器注销，未注册或规范移除路径已注销时为无害 no-op
	local owner = self.unit.Parent
	local container = owner and self.manager:getContainer(owner)
	if container then
		self.manager:removeModifierUnit(container, self.unit)
	end
	if self.state.removeTimer then
		-- 计时器可能已触发回收，取消失败不影响销毁收尾
		pcall(function()
			self.state.removeTimer:Cancel()
		end)
	end
	if self.state.stack then
		self.state.stack:destroy()
	end
	-- 销毁事件单位，不依赖父子级联销毁
	if self.signals then
		eventDefs.destroySignals(self.signals)
		self.signals = nil
	end
	self.manager:unregisterModifierHandler(self.unit)
	self.manager:clearTags(self.unit)
end

return ModifierHandler
