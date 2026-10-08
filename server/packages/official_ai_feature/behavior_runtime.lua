--生物AI包 - server端行为运行态引擎（包内模块）
--BehaviorRuntime：每个单位的 AI 模式任务与移动控制；运行态瞬时存在，任务结束或单位销毁即释放。

local Task = game:GetService("Task")
local World = game:GetService("World")

local BehaviorRuntime = {}

-- 每个单位的运行态：{ modeName, modeTask, stopMoveUntil, disabled,
-- priorityMode, focusTarget, moveThreshold }
-- 模式类行为（移动/跟随/警戒/模仿/搜敌/追击/寻路）互斥：新启动会停止旧模式。
local states = {}

---创建运行态并挂接单位销毁清理，避免状态残留
---@param unit Unit 目标单位
---@return table 运行态
local function createState(unit)
	local state = {}
	states[unit.UnitId] = state
	-- 单位销毁即取消模式任务并释放运行态（UnitId 可能被后续单位复用）
	if unit.Destroying ~= nil then
		unit.Destroying:Connect(function()
			local current = states[unit.UnitId]
			if current ~= nil and current.modeTask ~= nil then
				Task:Cancel(current.modeTask)
			end
			states[unit.UnitId] = nil
		end)
	end
	return state
end

---读取单位运行态，未初始化返回 nil
---@param unit Unit 目标单位
---@return table? 运行态
function BehaviorRuntime.getState(unit)
	return states[unit.UnitId]
end

---读取单位运行态，未初始化则创建
---@param unit Unit 目标单位
---@return table 运行态
function BehaviorRuntime.ensureState(unit)
	local state = states[unit.UnitId]
	if state == nil then
		state = createState(unit)
	end
	return state
end

---停止当前模式：取消模式任务并停下移动
---@param unit Unit 目标单位
function BehaviorRuntime.stopMode(unit)
	local state = states[unit.UnitId]
	if state ~= nil then
		if state.modeTask ~= nil then
			Task:Cancel(state.modeTask)
		end
		state.modeTask = nil
		state.modeName = nil
	end
	if unit.Controller ~= nil then
		unit.Controller:Move(math.Vector3(0, 0, 0))
	end
end

---启动模式行为任务：先停旧模式，再记录新任务
---@param unit Unit 目标单位
---@param modeName String 模式名（用于排查问题）
---@param taskFn fun() 模式主循环
function BehaviorRuntime.startMode(unit, modeName, taskFn)
	BehaviorRuntime.stopMode(unit)
	local state = BehaviorRuntime.ensureState(unit)
	state.modeName = modeName
	state.modeTask = Task:Spawn(function()
		taskFn()
		local current = states[unit.UnitId]
		if current ~= nil and current.modeTask ~= nil then
			current.modeTask = nil
			current.modeName = nil
		end
	end)
end

---检查停止移动指令是否仍在生效（StopMove 的时长内禁止移动）
---@param unit Unit 目标单位
---@return Bool 是否被禁足
function BehaviorRuntime.isMoveBlocked(unit)
	local state = states[unit.UnitId]
	if state == nil or state.stopMoveUntil == nil then
		return false
	end
	if World:GetServerTime() < state.stopMoveUntil then
		return true
	end
	state.stopMoveUntil = nil
	return false
end

---朝目标方向移动一帧，返回是否还在移动
---@param unit Unit 目标单位
---@param offset Vector3 目标相对当前位置的偏移
---@param threshold Float 到达阈值
---@return Bool 是否还在移动
function BehaviorRuntime.moveTowards(unit, offset, threshold)
	if BehaviorRuntime.isMoveBlocked(unit) then
		unit.Controller:Move(math.Vector3(0, 0, 0))
		return true
	end
	local dis = offset:Length()
	if dis <= threshold then
		unit.Controller:Move(math.Vector3(0, 0, 0))
		return false
	end
	local hdir = math.Vector3(offset.x, 0, offset.z)
	local hlen = hdir:Length()
	if hlen > 0.01 then
		unit.Controller:Move(math.Vector3(hdir.x / hlen, 0, hdir.z / hlen))
	end
	return true
end

return BehaviorRuntime
