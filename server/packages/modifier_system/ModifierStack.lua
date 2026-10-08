--效果系统包 - server端叠加组件
--ModifierStack：层数/时间叠加策略与独立计时；层数权威同步回效果处理器并广播。

local TimerService = game:GetService("TimerService")

local config = require("common.packages.modifier_system.config")
local util = require("common.packages.modifier_system.util")

---叠加组件：承载层数与倒计时叠加策略
---@class ModifierStack
---@field modifierHandler ModifierHandler 所属效果处理器
---@field enableStack boolean 是否允许叠加
---@field maxStackCount number 最大层数
---@field stackDurationMode number 叠加时间策略，取值见 config.StackDurationMode
---@field stackCountMode number 叠加层数策略，取值见 config.StackCountMode
---@field obtainCount number 单次获得增加的层数
---@field sameSourceOnly boolean 是否仅同源叠加
---@field duration number 单次获得的持续时间，单位秒，0 表示永久
---@field stackCount number 当前层数
---@field private _layers table[] 独立计时层记录列表，独立模式权威
---@field private _layerId number 层记录单调递增 id
local ModifierStack = {}
ModifierStack.__index = ModifierStack

---创建叠加组件实例，并按模式完成首层初始化
---@param modifierHandler ModifierHandler 所属效果处理器
---@param stackConfig table 叠加配置，由 ModifierHandler._buildStackConfig 提供
---@return ModifierStack
function ModifierStack.new(modifierHandler, stackConfig)
	local self = setmetatable({}, ModifierStack)
	self.modifierHandler = modifierHandler
	self.enableStack = stackConfig.enableStack or false
	self.maxStackCount = math.max(1, stackConfig.maxStackCount or config.DEFAULT_MAX_STACK_COUNT)
	self.stackDurationMode = stackConfig.stackDurationMode or 0
	self.stackCountMode = stackConfig.stackCountMode or 0
	self.obtainCount = math.max(1, stackConfig.obtainCount or config.DEFAULT_STACK_COUNT_STEP)
	self.sameSourceOnly = stackConfig.sameSourceOnly or false
	self.duration = stackConfig.duration or 0
	self.stackCount = 0
	self._layers = {}
	self._layerId = 0
	if self.stackDurationMode == config.StackDurationMode.StandAlone and self.duration > 0 then
		-- 独立计时模式：层数增加方式固定为 Add，与逐层回收配合
		self.stackCountMode = config.StackCountMode.Add
		self:_addLayer()
	else
		-- 普通模式：首层直接计入层数，倒计时由主 EndTime 承担
		self.stackCount = math.min(self.obtainCount, self.maxStackCount)
	end
	-- 首层经模型语义归一，入口 clamp / 派生后，层数权威同步回效果处理器
	if self.modifierHandler and self.modifierHandler._onStackCountChanged then
		self.modifierHandler:_onStackCountChanged(self.stackCount)
	end
	return self
end

---重新获得时的叠加处理，由 ModifierHandler.whenReobtain 调用
---@return number 旧层数
---@return number 新层数
function ModifierStack:whenReobtain()
	local oldCount = self.stackCount
	self:_applyCountStrategy()
	self:_applyTimeStrategy()
	local newCount = self.stackCount
	if self.modifierHandler then
		self.modifierHandler:_onStackCountChanged(newCount)
	end
	return oldCount, newCount
end

---获取当前层数
---@return number 当前层数
function ModifierStack:getStackCount()
	return self.stackCount
end

---设置层数，归零时第二个返回值返回 nil，由调用方触发移除
---仅普通模式对外开放，独立模式层数由层记录派生，外部直设会破坏一致性
---@param count number 目标层数
---@return number 旧层数
---@return number? 新层数，归零时为 nil
function ModifierStack:setStackCount(count)
	local oldCount = self.stackCount
	self.stackCount = math.min(math.max(0, count), self.maxStackCount)
	if self.modifierHandler then
		self.modifierHandler:_onStackCountChanged(self.stackCount)
	end
	if self.stackCount == 0 then
		return oldCount, nil
	end
	return oldCount, self.stackCount
end

---减少层数，即 setStackCount 的便捷写法
---@param count number 减少量
---@return number 旧层数
---@return number? 新层数，归零时为 nil
function ModifierStack:reduceStackCount(count)
	return self:setStackCount(self.stackCount - count)
end

---暂停所有层计时器，效果暂停时调用：记录剩余时间并取消计时器句柄
function ModifierStack:pauseTimers()
	local now = util.getServerTime()
	for _, entry in ipairs(self._layers) do
		if entry.timer then
			-- 计时器可能已触发回收，取消失败不阻断其余层的处理
			pcall(function()
				entry.timer:Cancel()
			end)
			entry.timer = nil
		end
		entry.remaining = entry.endTime - now
	end
end

---恢复所有层计时器，效果恢复时调用：按剩余时间重建，暂停期间已到期的立即回收
function ModifierStack:resumeTimers()
	local now = util.getServerTime()
	local expired = {}
	for _, entry in ipairs(self._layers) do
		local remaining = entry.remaining or 0
		if remaining > 0 then
			entry.endTime = now + remaining
			entry.remaining = nil
			local id = entry.id
			entry.timer = TimerService:CreateTimer(1, remaining, false, function()
				self:_onLayerExpire(id)
			end)
		else
			table.insert(expired, entry.id)
		end
	end
	for _, id in ipairs(expired) do
		self:_onLayerExpire(id)
	end
end

---销毁所有层计时器，效果移除时调用
function ModifierStack:destroy()
	for _, entry in ipairs(self._layers) do
		if entry.timer then
			-- 计时器可能已触发回收，取消失败不阻断其余层的清理
			pcall(function()
				entry.timer:Cancel()
			end)
		end
	end
	self._layers = {}
end

---应用层数叠加策略，独立计时模式下层数由 _addLayer 管理，此处跳过
function ModifierStack:_applyCountStrategy()
	if self.stackDurationMode == config.StackDurationMode.StandAlone then
		return
	end
	if self.stackCountMode == config.StackCountMode.Override then
		self.stackCount = math.min(self.obtainCount, self.maxStackCount)
	elseif self.stackCountMode == config.StackCountMode.Add then
		self.stackCount = math.min(self.stackCount + self.obtainCount, self.maxStackCount)
	end
end

---应用时间叠加策略：Override 重置倒计时 / Add 在当前剩余时间上累加 / StandAlone 添加独立层
function ModifierStack:_applyTimeStrategy()
	local handler = self.modifierHandler
	if self.stackDurationMode == config.StackDurationMode.Override then
		handler:_setupMaxDuration()
	elseif self.stackDurationMode == config.StackDurationMode.Add then
		if self.duration > 0 then
			handler:extendDuration(self.duration)
		end
	elseif self.stackDurationMode == config.StackDurationMode.StandAlone then
		self:_addLayer()
	end
end

---独立计时：添加层，首次获得与重复获得共用同一入口
---不变量，由本函数与 _onLayerExpire/setStackCount 共同维护：
---  I1: sum(_layers[i].count) == self.stackCount，禁止零 count 层
---  I2: self.stackCount <= self.maxStackCount
---  I3: _layers 按 endTime 升序，[1] 最早到期
---满层策略：回收最早到期的层整体腾位，新获得顶替最旧层，总层数仍受 maxStackCount 约束
function ModifierStack:_addLayer()
	local duration = self.duration
	if duration <= 0 then
		return
	end

	-- 入口 clamp：单次获得实际加入层数不超过 maxStackCount；
	-- 否则 obtainCount > maxStackCount 时顶替-补层循环会做无谓整层回收与计时器创建/取消
	local remaining = math.min(self.obtainCount, self.maxStackCount)
	while remaining > 0 do
		local capacity = self.maxStackCount - self.stackCount
		if capacity > 0 then
			-- 有空余容量：加一层，单次最多补满剩余容量
			local add = math.min(remaining, capacity)
			self._layerId = self._layerId + 1
			local id = self._layerId
			local now = util.getServerTime()
			local timer = TimerService:CreateTimer(1, duration, false, function()
				self:_onLayerExpire(id)
			end)
			table.insert(self._layers, {
				id = id,
				endTime = now + duration,
				timer = timer,
				count = add,
			})
			self.stackCount = self.stackCount + add
			remaining = remaining - add
		elseif #self._layers > 0 then
			-- 满层：整体回收最早到期层腾位，stackCount 同步扣减，I1/I2 恒成立
			local earliest = table.remove(self._layers, 1)
			if earliest.timer then
				-- 计时器可能已触发回收，取消失败不阻断腾位
				pcall(function()
					earliest.timer:Cancel()
				end)
			end
			self.stackCount = self.stackCount - earliest.count
		else
			break
		end
	end

	if #self._layers > 0 then
		-- 按到期时间排序，确保 [1] 是最早到期的，即 I3
		table.sort(self._layers, function(a, b)
			return a.endTime < b.endTime
		end)
		-- 主 EndTime 必须覆盖最晚到期的层，否则主计时器先到期会整体移除
		local handler = self.modifierHandler
		if handler and handler._ensureEndTimeCovers then
			handler:_ensureEndTimeCovers(self._layers[#self._layers].endTime)
		end
	end
end

---独立层到期回调：按层 count 回收层数，归零时触发带失活的移除
---@param id number 层记录 id
function ModifierStack:_onLayerExpire(id)
	local expireCount
	for i, entry in ipairs(self._layers) do
		if entry.id == id then
			expireCount = entry.count
			if entry.timer then
				-- 计时器已自然到期，取消仅作句柄清理
				pcall(function()
					entry.timer:Cancel()
				end)
			end
			table.remove(self._layers, i)
			break
		end
	end
	if not expireCount then
		return
	end
	self:reduceStackCount(expireCount)
	if self.stackCount == 0 and self.modifierHandler then
		local handler = self.modifierHandler
		local manager = handler.manager
		local owner = handler:getUnit().Parent
		local container = owner and manager:getContainer(owner)
		if container then
			manager:removeModifierWithLoss(container, handler:getUnit())
		end
	end
end

return ModifierStack
