--技能系统 - client释放策略基类
--定义 OnTouchBegin/Move/End 输入契约（默认空实现）。
-- 策略实例由 Controller._createStrategy 构造：setmetatable({ctrl = controller}, cls)，
-- 不走 BaseStrategy.new；实例共享字段 self.ctrl（Controller）。

---释放策略抽象基类：定义 OnTouchBegin / Move / End 输入契约（默认空实现）。
---@class BaseStrategy
---@field ctrl Controller 技能槽位 UI 控制器
local BaseStrategy = {}
BaseStrategy.__index = BaseStrategy

function BaseStrategy.new(controller)
	local self = setmetatable({}, BaseStrategy)
	self.ctrl = controller
	return self
end

function BaseStrategy:OnTouchBegin(eventData) end
function BaseStrategy:OnTouchMove(eventData) end
function BaseStrategy:OnTouchEnd(eventData) end
function BaseStrategy:Destroy() end

return BaseStrategy
