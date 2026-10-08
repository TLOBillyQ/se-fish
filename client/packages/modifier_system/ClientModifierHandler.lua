--效果系统包 - 客户端效果处理器
--ClientModifierHandler：单个效果实例的客户端处理，监听属性同步驱动表现与材质栈。

local Task = game:GetService("Task")

local config = require("common.packages.modifier_system.config")
local util = require("common.packages.modifier_system.util")
local performance = require("client.packages.modifier_system.performance")

---判断单位是否为有效拥有者，非 World 且 UnitId 有效，避免复制竞态下表现绑到 World 原点
---@param owner Unit? 待判定的单位
---@return boolean 是否有效
local function isValidOwner(owner)
	if not owner then
		return false
	end
	local okIsA, isNotWorld = pcall(function()
		return not owner:IsA("World")
	end)
	if not okIsA or not isNotWorld then
		return false
	end
	local ok, unitId = pcall(function()
		return owner.UnitId
	end)
	return ok and unitId ~= nil and unitId ~= 0
end

---客户端效果处理器：一个效果实例对应一个处理器
---@class ClientModifierHandler
---@field unit Unit 效果实体单位
---@field manager CModifierSystemManager 客户端效果管理器
---@field state table 客户端状态，字段 isActive/endTime/currCount/charMtg/isPaused/modifierKey
---@field private _playingPerformance table? 跟随销毁的表现单位集合
---@field private _owner Unit? 已解析的表现拥有者缓存
local ClientModifierHandler = {}
ClientModifierHandler.__index = ClientModifierHandler

---创建客户端效果处理器并绑定属性监听
---@param modifierUnit Unit 效果实体单位
---@param manager CModifierSystemManager 客户端效果管理器
---@return ClientModifierHandler
function ClientModifierHandler.new(modifierUnit, manager)
	local self = setmetatable({}, ClientModifierHandler)
	self.unit = modifierUnit
	self.manager = manager
	self._playingPerformance = nil
	self._owner = nil
	self.state = {
		isActive = false,
		endTime = 0,
		currCount = 0,
		charMtg = 0,
		isPaused = false,
		modifierKey = modifierUnit:GetAttribute("ModifierKey") or "",
	}
	manager:addTag(modifierUnit, config.Tag.ModifierUnit)
	manager:registerModifierHandler(modifierUnit, self)

	local Attr = config.Attr
	-- IsActive 变化 → 状态 + 材质栈 + 表现播放/销毁，表现由属性驱动，无时序竞争
	modifierUnit:GetAttributeChangedSignal(Attr.IsActive):Connect(function(isActive)
		self:_onActiveChange(isActive)
	end)
	-- CharMtg 变化 → 更新材质栈
	modifierUnit:GetAttributeChangedSignal(Attr.CharMtg):Connect(function(materialId)
		local previousMaterialId = self.state.charMtg
		self.state.charMtg = tonumber(materialId) or 0
		if self.state.isActive then
			if previousMaterialId > 0 then
				self:_popMaterial()
			end
			if self.state.charMtg > 0 then
				self:_pushMaterial(self.state.charMtg)
			end
		end
	end)
	-- 监听其他标量属性
	modifierUnit:GetAttributeChangedSignal(Attr.CurrCount):Connect(function(count)
		self.state.currCount = count or 0
	end)
	modifierUnit:GetAttributeChangedSignal(Attr.IsPaused):Connect(function(paused)
		self.state.isPaused = paused or false
	end)
	modifierUnit:GetAttributeChangedSignal(Attr.EndTime):Connect(function(endTime)
		self.state.endTime = endTime or 0
	end)

	modifierUnit.Destroying:Connect(function()
		self._destroyed = true
		manager:unregisterModifierHandler(self.unit)
		manager:clearTags(self.unit)
	end)

	-- 读属性初始值，即引擎复制到客户端的即时快照：
	-- 覆盖首次动态创建 / 新玩家中途加入 / 重连时处理器晚挂的场景；
	-- GetAttributeChangedSignal 只监听变化不触发初始值，故此处显式读取一次。
	-- 注意：state.endTime 全程保存绝对时间戳，与状态条目一致，剩余时间一律按绝对时间换算
	self.state.currCount = tonumber(modifierUnit:GetAttribute(Attr.CurrCount)) or 0
	self.state.isPaused = modifierUnit:GetAttribute(Attr.IsPaused) == true
	self.state.endTime = tonumber(modifierUnit:GetAttribute(Attr.EndTime)) or 0
	local initialMaterialId = tonumber(modifierUnit:GetAttribute(Attr.CharMtg)) or 0
	self.state.charMtg = initialMaterialId
	local initialActive = modifierUnit:GetAttribute(Attr.IsActive)
	if initialActive then
		self:_onActiveChange(true)
	end
	return self
end

---激活/失活统一处理：材质栈 + 表现播放/销毁
---@param isActive boolean 是否激活
function ClientModifierHandler:_onActiveChange(isActive)
	local previousActive = self.state.isActive
	if isActive == previousActive then
		return
	end
	self.state.isActive = isActive
	if isActive then
		if self.state.charMtg > 0 then
			self:_pushMaterial(self.state.charMtg)
		end
		self:_playPerformanceList(self:_getPerformanceFromAttr("ObtainPerformanceList"), true)
	else
		if self.state.charMtg > 0 then
			self:_popMaterial()
		end
		-- 失去表现播完自行结束：不登记"跟随销毁"。失去表现结构无该字段，nil 会按缺省 true 被登记，
		-- 紧随的清理会把刚创建的表现单位一并销毁，导致失去表现无法播放
		self:_playPerformanceList(self:_getPerformanceFromAttr("LostPerformanceList"), false, false)
		-- 销毁获得时标记"跟随效果销毁"的特效/音效，循环特效随效果失去清理
		self:_destroyPlayingPerformance()
	end
end

---销毁跟随效果销毁的表现单位
function ClientModifierHandler:_destroyPlayingPerformance()
	if not self._playingPerformance then
		return
	end
	for _, effectUnit in ipairs(self._playingPerformance.effects or {}) do
		-- 单位可能已自行销毁，单个销毁失败不阻断其余清理
		pcall(function()
			effectUnit:Destroy()
		end)
	end
	for _, soundUnit in ipairs(self._playingPerformance.sounds or {}) do
		-- 单位可能已自行销毁，单个销毁失败不阻断其余清理
		pcall(function()
			soundUnit:Destroy()
		end)
	end
	self._playingPerformance = nil
end

---读取表现配置，优先实体属性；实体可能已销毁，读取失败按无表现处理
---@param attributeName string 属性名
---@return table? 表现配置列表
function ClientModifierHandler:_getPerformanceFromAttr(attributeName)
	local ok, value = pcall(function()
		return self.unit:GetAttribute(attributeName)
	end)
	if ok and value and type(value) == "table" and #value > 0 then
		return value
	end
	return nil
end

-- 消息状态更新，仅更新状态，不播表现
-- 通道契约：state.endTime 全程保存绝对时间戳，剩余时间一律按绝对时间换算

---应用刷新消息，同步层数与绝对 EndTime
---@param currCount number? 当前层数
---@param endTime number? 结束时间戳
function ClientModifierHandler:onRefreshClient(currCount, endTime)
	if currCount then
		self.state.currCount = currCount
	end
	if endTime then
		self.state.endTime = endTime
	end
end

---应用层数变化消息
---@param newCount number 新层数
function ClientModifierHandler:onStackChangeClient(newCount)
	self.state.currCount = newCount or 0
end

---应用叠加消息，同步层数与绝对 EndTime，叠加策略可能更新倒计时
---@param newCount number 新层数
---@param endTime number? 结束时间戳
function ClientModifierHandler:onReobtainClient(newCount, endTime)
	self.state.currCount = newCount or 0
	if endTime then
		self.state.endTime = endTime
	end
end

---应用暂停消息
function ClientModifierHandler:onPauseClient()
	self.state.isPaused = true
end

---应用恢复消息
---@param endTime number? 结束时间戳
function ClientModifierHandler:onResumeClient(endTime)
	self.state.isPaused = false
	if endTime then
		self.state.endTime = endTime
	end
end

-- 客户端语义查询接口

---获取效果 Key
---@return string 效果 Key
function ClientModifierHandler:getModifierKey()
	return self.state.modifierKey or self.unit:GetAttribute("ModifierKey") or ""
end

---获取效果实体单位
---@return Unit 效果实体单位
function ClientModifierHandler:getUnit()
	return self.unit
end

---是否处于激活状态
---@return boolean 是否激活
function ClientModifierHandler:isActive()
	return self.state.isActive == true
end

---获取当前层数
---@return number 当前层数
function ClientModifierHandler:getStackCount()
	return self.state.currCount or 0
end

---获取当前材质 ID，0 表示无材质
---@return number 材质 ID
function ClientModifierHandler:getCharMtg()
	return self.state.charMtg or 0
end

---是否处于暂停状态
---@return boolean 是否暂停
function ClientModifierHandler:isPaused()
	return self.state.isPaused == true
end

---获取剩余时间，单位秒，永久效果返回 -1；按状态 EndTime 时间戳换算
---@return number 剩余时间
function ClientModifierHandler:getRemainingTime()
	local endTime = self.state.endTime or 0
	if endTime < 0 then
		return -1
	end
	if endTime <= 0 then
		return 0
	end
	-- 时间源异常时返回 0，不阻断查询
	local ok, now = pcall(util.getServerTime)
	if not ok or not now then
		return 0
	end
	return math.max(0, endTime - now)
end

---取客户端状态条目，展示字段以消息透传为准
---@return table? 状态条目
function ClientModifierHandler:_getSlotMirror()
	local owner = self:_resolveOwner()
	local container = owner and self.manager:getContainer(owner)
	if container and container.slots then
		return container.slots[self.unit.UnitId] or nil
	end
	return nil
end

---获取效果描述
---@return string 描述
function ClientModifierHandler:getDesc()
	local mirror = self:_getSlotMirror()
	return (mirror and mirror.desc) or ""
end

---获取效果类型
---@return number|string 效果类型
function ClientModifierHandler:getModifierType()
	local mirror = self:_getSlotMirror()
	return (mirror and mirror.modifierType) or self.unit:GetAttribute("UgcModifierType") or ""
end

---获取最大层数
---@return number 最大层数
function ClientModifierHandler:getMaxStackCount()
	local mirror = self:_getSlotMirror()
	return (mirror and mirror.maxStackCount) or config.DEFAULT_MAX_STACK_COUNT
end

-- 拥有者解析与等待

local OWNER_WAIT_INTERVAL = 0.2
local OWNER_WAIT_LIMIT = 25

---解析拥有者：当前 Parent → 已缓存 owner → OwnerUnitId 属性反查
---客户端复制单位可能拿不到 Parent，host-local 复制路径不挂 Parent，属性通道可靠，故以此兜底
---@return Unit? 有效拥有者
function ClientModifierHandler:_resolveOwner()
	local okParent, parent = pcall(function()
		return self.unit.Parent
	end)
	if okParent and isValidOwner(parent) then
		self._owner = parent
		return parent
	end
	if isValidOwner(self._owner) then
		return self._owner
	end
	local okAttr, ownerId = pcall(function()
		return self.unit:GetAttribute("OwnerUnitId")
	end)
	ownerId = okAttr and tonumber(ownerId) or nil
	if ownerId then
		local World = game:GetService("World")
		local okUnit, ownerUnit = pcall(function()
			return World:GetUnitByID(ownerId)
		end)
		if okUnit and isValidOwner(ownerUnit) then
			self._owner = ownerUnit
			return ownerUnit
		end
	end
	return nil
end

---等待拥有者就绪后执行 fn，单位销毁或超时即停；fn 内需按当前状态自行守卫
---@param fn function fn(owner: Unit)
function ClientModifierHandler:_awaitOwner(fn)
	if self._destroyed then
		return
	end
	local owner = self:_resolveOwner()
	if owner then
		fn(owner)
		return
	end
	local tries = (self._ownerWaitTries or 0) + 1
	self._ownerWaitTries = tries
	if tries > OWNER_WAIT_LIMIT then
		return
	end
	Task:Delay(OWNER_WAIT_INTERVAL, function()
		self:_awaitOwner(fn)
	end)
end

-- 材质栈接入

---材质入栈，拥有者就绪后执行；状态变化后不再补入
---@param materialId number 材质 ID
function ClientModifierHandler:_pushMaterial(materialId)
	self:_awaitOwner(function(owner)
		if not self.state.isActive or self.state.charMtg ~= materialId then
			return
		end
		local container = self.manager:getContainer(owner)
		if not container then
			return
		end
		self.manager:pushMaterial(container, self.unit.UnitId, materialId)
	end)
end

---材质出栈，拥有者就绪后执行；已重新激活带材质时跳过
function ClientModifierHandler:_popMaterial()
	self:_awaitOwner(function(owner)
		if self.state.isActive and self.state.charMtg > 0 then
			return
		end
		local container = self.manager:getContainer(owner)
		if not container then
			return
		end
		self.manager:popMaterial(container, self.unit.UnitId)
	end)
end

-- 表现播放

---播放表现列表，拥有者就绪后执行；获得表现补播需仍处于激活态
---@param performanceList table? 表现配置列表
---@param requireActive boolean 补播前是否要求仍处于激活态，获得表现传 true
---@param followDestroy boolean? 是否登记"跟随销毁"单位，缺省 true；失去表现传 false，播完自行结束
function ClientModifierHandler:_playPerformanceList(performanceList, requireActive, followDestroy)
	if not performanceList then
		return
	end
	self:_awaitOwner(function(owner)
		if requireActive and not self.state.isActive then
			return
		end
		local result = performance.play(performanceList, owner)
		if followDestroy ~= false then
			self:_collectPlayingPerformance(result)
		end
	end)
end

---累计跟随销毁的表现单位，失活时统一销毁
---@param result table? performance.play 返回值
function ClientModifierHandler:_collectPlayingPerformance(result)
	if not result then
		return
	end
	if not self._playingPerformance then
		self._playingPerformance = { effects = {}, sounds = {} }
	end
	for _, unit in ipairs(result.effects or {}) do
		table.insert(self._playingPerformance.effects, unit)
	end
	for _, unit in ipairs(result.sounds or {}) do
		table.insert(self._playingPerformance.sounds, unit)
	end
end

return ClientModifierHandler
