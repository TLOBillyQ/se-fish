--技能系统 - client按下瞬发施法策略（NoTarget）

local BaseStrategy = require("client.packages.ability_system.strategy.BaseStrategy")

local PressStrategy = setmetatable({}, BaseStrategy)
PressStrategy.__index = PressStrategy

function PressStrategy:OnTouchBegin(eventData)
	-- 按下瞬间直接施法，NoTarget 类型：point/dir/target 均为 nil
	local ctrl = self.ctrl
	ctrl:_requestCast(nil, nil, nil)
end

function PressStrategy:OnTouchMove(eventData)
	-- 无操作
end

function PressStrategy:OnTouchEnd(eventData)
	-- 无操作
end

function PressStrategy:Destroy()
	-- 无需清理
end

return PressStrategy
