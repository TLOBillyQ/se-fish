--效果系统包 - server端获得拦截桥
--「阻止效果获得」拦截标记：即将获得事件中置位，作用于当前触发中的效果，获得流程消费一次。
--"生物即将获得效果" ECA 事件由拥有者单位下的 BindableEvent 事件单位承载，
--单位事件按 unit.<事件名> 绑定，事件名见 config.ManagerEvent.ObtainBefore。

local config = require("common.packages.modifier_system.config")
local eventDefs = require("common.packages.modifier_system.event_defs")

local eventBridge = {}

-- 拦截标记与触发栈：触发栈记录正在触发"即将获得"的效果单位，
-- 拦截标记按效果单位 UnitId 关联，避免多个效果同时获得时串位
local _obtainStack = {}
local _interceptFlags = {}

---触发"即将获得效果"事件，事件处理器同步执行期间可调用置位拦截
---@param modifierUnit Unit 效果单位
---@param ownerUnit Unit 拥有者单位
function eventBridge.fireObtainBefore(modifierUnit, ownerUnit)
	table.insert(_obtainStack, modifierUnit)
	local ok, err = pcall(function()
		local signal = ownerUnit
			and eventDefs.getOrCreateEventUnit(ownerUnit, config.ManagerEvent.ObtainBefore)
		if signal then
			signal:Fire(modifierUnit, ownerUnit)
		end
	end)
	table.remove(_obtainStack)
	if not ok then
		-- 事件回调异常时仍回退触发栈，避免残留栈顶让后续置位拦截错位
		print("[modifier_system] fireObtainBefore failed:", tostring(err))
	end
end

---置位拦截标记，由"阻止本次效果获得"动作调用，作用于当前触发中的效果
function eventBridge.setIntercept()
	local modifierUnit = _obtainStack[#_obtainStack]
	if modifierUnit then
		_interceptFlags[modifierUnit.UnitId] = true
	end
end

---消费指定效果的拦截标记：命中返回 true 并清除
---@param modifierUnit Unit 效果单位
---@return boolean 是否命中拦截
function eventBridge.consumeIntercept(modifierUnit)
	local key = modifierUnit.UnitId
	local hit = _interceptFlags[key] == true
	_interceptFlags[key] = nil
	return hit
end

return eventBridge
