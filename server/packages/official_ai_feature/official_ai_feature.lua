--生物AI包 - server端行为管理
--SOfficialAiFeatureManager：AI 动作与自动行为模式的服务端方法集合，本身不存状态；
--运行态任务在 BehaviorRuntime，技能交互在 AbilityBridge，技能能力依赖技能包服务端门面。

local Task = game:GetService("Task")
local World = game:GetService("World")
local Players = game:GetService("Players")

local Configs = require("common.packages.official_ai_feature.configs")
local utils = require("common.packages.official_ai_feature.utils")

local AbilityBridge = require("server.packages.official_ai_feature.ability_bridge")
local BehaviorRuntime = require("server.packages.official_ai_feature.behavior_runtime")

---生物AI管理器（服务端）：无状态方法集合，方法用点号定义、点号调用
---@class SOfficialAiFeatureManager
local SOfficialAiFeatureManager = {}

---激活单位的AI，恢复执行后续指令
---@param unit EggyUnitInstance 角色
function SOfficialAiFeatureManager.startAI(unit)
	if not utils.isValidUnit(unit) then
		return
	end
	local state = BehaviorRuntime.getState(unit)
	if state ~= nil then
		state.disabled = nil
	end
end

---禁用单位的AI；禁用前等待执行的指令会被记忆，重新激活后继续
---@param unit EggyUnitInstance 角色
function SOfficialAiFeatureManager.stopAI(unit)
	if not utils.isValidUnit(unit) then
		return
	end
	BehaviorRuntime.stopMode(unit)
	local state = BehaviorRuntime.getState(unit)
	if state ~= nil then
		state.disabled = true
	end
end

---让单位立即滚动一次
---@param unit EggyUnitInstance 角色
function SOfficialAiFeatureManager.roll(unit)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	-- 预期错误：单位处于不能滚动的状态时无效
	pcall(function()
		unit.Controller:Fling()
	end)
end

---让单位立即向前飞扑一次
---@param unit EggyUnitInstance 角色
function SOfficialAiFeatureManager.rush(unit)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	-- 预期错误：单位处于不能飞扑的状态时无效
	pcall(function()
		unit.Controller:Rush()
	end)
end

---让单位立即跳跃一次
---@param unit EggyUnitInstance 角色
function SOfficialAiFeatureManager.jump(unit)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	unit.Controller:Jump()
end

---让单位执行一次抓举/放下/投掷
---@param unit EggyUnitInstance 角色
function SOfficialAiFeatureManager.lift(unit)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	-- 预期错误：单位处于不能抓举的状态时无效
	pcall(function()
		unit.Controller:Lift()
	end)
end

---让单位朝指定方向持续移动
---@param unit EggyUnitInstance 角色
---@param params table 移动参数：direction / hateTime / autoObstacle
function SOfficialAiFeatureManager.moveDirection(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local direction = params.direction
	local hateTime = params.hateTime
	-- 无视障碍（0）时按直线移动处理；避障（非 0）在移动循环里响应碰撞跳跃
	local jumpOnCollision = params.autoObstacle ~= 0

	BehaviorRuntime.startMode(unit, "move_dir", function()
		local startTime = World:GetServerTime()
		local collConn = nil
		if jumpOnCollision and unit.Controller.OnCollisionEnter ~= nil then
			local lastJump = -math.huge
			collConn = unit.Controller.OnCollisionEnter:Connect(function()
				local now = World:GetServerTime()
				if now - lastJump < Configs.COLLISION_JUMP_COOLDOWN then
					return
				end
				lastJump = now
				if utils.isValidUnit(unit) and unit.Controller ~= nil then
					unit.Controller:Jump()
				end
			end)
		end
		while utils.isValidUnit(unit) do
			if BehaviorRuntime.isMoveBlocked(unit) then
				unit.Controller:Move(math.Vector3(0, 0, 0))
			else
				unit.Controller:Move(direction)
			end
			-- 厌恶时间：不大于 0 表示不限时
			local elapsed = World:GetServerTime() - startTime
			if hateTime ~= nil and hateTime > 0 and elapsed >= hateTime then
				break
			end
			Task:Wait(Configs.MOVE_TICK)
		end
		if collConn ~= nil then
			collConn:Disconnect()
		end
		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位移动到指定位置
---@param unit EggyUnitInstance 角色
---@param params table 移动参数：targetPos / hateTime / toleranceDis / autoObstacle
function SOfficialAiFeatureManager.moveToPos(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local targetPos = params.targetPos
	local hateTime = params.hateTime
	local threshold = Configs.DEFAULT_MOVE_TOLERANCE
	if params.toleranceDis ~= nil and params.toleranceDis > 0 then
		threshold = params.toleranceDis
	end
	-- autoObstacle 为积木保留参数，当前不影响移动

	BehaviorRuntime.startMode(unit, "move_pos", function()
		local startTime = World:GetServerTime()
		while utils.isValidUnit(unit) do
			local offset = targetPos - unit:GetPosition()
			local moving = BehaviorRuntime.moveTowards(unit, offset, threshold)
			if not moving then
				break
			end
			local elapsed = World:GetServerTime() - startTime
			if hateTime ~= nil and hateTime > 0 and elapsed >= hateTime then
				break
			end
			Task:Wait(Configs.MOVE_TICK)
		end
		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位停止移动；带时长时禁足一段时间，期间所有移动指令无效
---@param unit EggyUnitInstance 角色
---@param duration Float? 禁足时长（秒）；不大于 0 表示立即恢复移动
function SOfficialAiFeatureManager.stopMove(unit, duration)
	if not utils.isValidUnit(unit) then
		return
	end
	BehaviorRuntime.stopMode(unit)
	local state = BehaviorRuntime.ensureState(unit)
	if duration ~= nil and duration > 0 then
		state.stopMoveUntil = World:GetServerTime() + duration
	else
		state.stopMoveUntil = nil
	end
end

---让单位跟随目标：不断缩短与目标的距离，超出容忍距离则放弃
---@param unit EggyUnitInstance 角色
---@param params table 跟随参数：continuousSec / followTarget / followDis / tolerateDis
function SOfficialAiFeatureManager.follow(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local continuousSec = params.continuousSec
	local followTarget = params.followTarget
	local followDis = params.followDis
	local tolerateDis = params.tolerateDis

	BehaviorRuntime.startMode(unit, "follow", function()
		local startTime = World:GetServerTime()
		while utils.isValidUnit(unit) and utils.isValidUnit(followTarget) do
			local elapsed = World:GetServerTime() - startTime
			if continuousSec ~= nil and continuousSec > 0 and elapsed >= continuousSec then
				break
			end
			local offset = followTarget:GetPosition() - unit:GetPosition()
			local dis = offset:Length()
			if dis <= followDis then
				unit.Controller:Move(math.Vector3(0, 0, 0))
			else
				local moving = BehaviorRuntime.moveTowards(unit, offset, followDis)
				if not moving then
					break
				end
			end
			-- 超出容忍距离：放弃跟随
			if tolerateDis ~= nil and tolerateDis > 0 and dis > tolerateDis then
				break
			end
			Task:Wait(Configs.MOVE_TICK)
		end
		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位警戒指定位置：偏离后延迟一段时间返回，超过容忍距离则脱离警戒
---@param unit EggyUnitInstance 角色
---@param params table 警戒参数：continuousSec / keepPos / keepPosRotation / delayTime /
---tolerateDis
function SOfficialAiFeatureManager.alert(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local continuousSec = params.continuousSec
	local keepPos = params.keepPos
	local keepPosRotation = params.keepPosRotation
	local delayTime = params.delayTime
	local tolerateDis = params.tolerateDis

	BehaviorRuntime.startMode(unit, "alert", function()
		local startTime = World:GetServerTime()
		local delay = delayTime
		if delay == nil then
			delay = Configs.DEFAULT_ALERT_DELAY
		end
		local tolerate = tolerateDis
		if tolerate == nil then
			tolerate = Configs.DEFAULT_ALERT_TOLERANCE
		end
		while utils.isValidUnit(unit) do
			local elapsed = World:GetServerTime() - startTime
			if continuousSec ~= nil and continuousSec > 0 and elapsed >= continuousSec then
				break
			end
			local offset = keepPos - unit:GetPosition()
			local dis = offset:Length()
			if dis <= Configs.DEFAULT_STOP_DISTANCE then
				unit.Controller:Move(math.Vector3(0, 0, 0))
				-- 回到警戒点后恢复朝向
				if keepPosRotation ~= nil and dis <= Configs.DEFAULT_ALERT_ROTATE_DISTANCE then
					-- 预期错误：个别单位不支持直接设置朝向，失败时忽略
					pcall(function()
						unit:SetRotation(keepPosRotation)
					end)
				end
			elseif dis > tolerate then
				-- 超过容忍距离：视为离开警戒范围，直接返回
				unit.Controller:Move(math.Vector3(0, 0, 0))
				break
			else
				-- 先等待延迟时间再返回
				Task:Wait(delay)
				while utils.isValidUnit(unit) do
					local currentOffset = keepPos - unit:GetPosition()
					local moving = BehaviorRuntime.moveTowards(unit, currentOffset, Configs.DEFAULT_STOP_DISTANCE)
					if not moving then
						break
					end
					Task:Wait(Configs.MOVE_TICK)
				end
				unit.Controller:Move(math.Vector3(0, 0, 0))
				if keepPosRotation ~= nil then
					-- 预期错误：个别单位不支持直接设置朝向，失败时忽略
					pcall(function()
						unit:SetRotation(keepPosRotation)
					end)
				end
			end
			Task:Wait(Configs.MOVE_TICK)
		end
		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位模仿目标的动作与移动
---@param unit EggyUnitInstance 角色
---@param imitateTarget EggyUnitInstance 模仿目标
---@param continuousSec Float? 持续时长（秒）；不大于 0 或为空时持续到目标销毁
function SOfficialAiFeatureManager.imitate(unit, imitateTarget, continuousSec)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	if not utils.isValidUnit(imitateTarget) or imitateTarget.Controller == nil then
		return
	end

	local targetController = imitateTarget.Controller
	local connections = {}

	local function unbind()
		for key, connection in pairs(connections) do
			if key == "move_task" then
				Task:Cancel(connection)
			elseif connection ~= nil and connection.Disconnect ~= nil then
				connection:Disconnect()
			end
		end
		connections = {}
	end

	-- 动作模仿：目标做出动作后，延迟半秒跟着做一次
	if targetController.OnJump ~= nil then
		connections["jump"] = targetController.OnJump:Connect(function()
			if utils.isValidUnit(unit) and unit.Controller ~= nil then
				Task:Spawn(function()
					Task:Wait(Configs.IMITATE_ACTION_DELAY)
					if utils.isValidUnit(unit) and unit.Controller ~= nil then
						unit.Controller:Jump()
					end
				end)
			end
		end)
	end
	if targetController.OnLiftBegin ~= nil then
		connections["lift"] = targetController.OnLiftBegin:Connect(function()
			if utils.isValidUnit(unit) and unit.Controller ~= nil then
				Task:Spawn(function()
					Task:Wait(Configs.IMITATE_ACTION_DELAY)
					if utils.isValidUnit(unit) and unit.Controller ~= nil then
						-- 预期错误：单位处于不能抓举的状态时无效
						pcall(function()
							unit.Controller:Lift()
						end)
					end
				end)
			end
		end)
	end
	if targetController.OnRush ~= nil then
		connections["rush"] = targetController.OnRush:Connect(function()
			if utils.isValidUnit(unit) and unit.Controller ~= nil then
				Task:Spawn(function()
					Task:Wait(Configs.IMITATE_ACTION_DELAY)
					if utils.isValidUnit(unit) and unit.Controller ~= nil then
						-- 预期错误：单位处于不能飞扑的状态时无效
						pcall(function()
							unit.Controller:Rush()
						end)
					end
				end)
			end
		end)
	end
	if targetController.OnRollBegin ~= nil then
		connections["fling"] = targetController.OnRollBegin:Connect(function()
			if utils.isValidUnit(unit) and unit.Controller ~= nil then
				Task:Spawn(function()
					Task:Wait(Configs.IMITATE_ACTION_DELAY)
					if utils.isValidUnit(unit) and unit.Controller ~= nil then
						-- 预期错误：单位处于不能滚动的状态时无效
						pcall(function()
							unit.Controller:Fling()
						end)
					end
				end)
			end
		end)
	end

	-- 移动模仿：目标进入移动状态时，沿其移动方向跟随一段
	if targetController.StateChanged ~= nil and targetController.GetState ~= nil then
		local moveTask = nil
		local function stopMoveTask()
			if moveTask ~= nil then
				Task:Cancel(moveTask)
				moveTask = nil
				connections["move_task"] = nil
				if utils.isValidUnit(unit) and unit.Controller ~= nil then
					unit.Controller:Move(math.Vector3(0, 0, 0))
				end
			end
		end
		local function startMoveTask()
			if moveTask ~= nil then
				return
			end
			moveTask = Task:Spawn(function()
				local lastPos = imitateTarget:GetPosition()
				while utils.isValidUnit(unit) and utils.isValidUnit(imitateTarget) do
					Task:Wait(Configs.IMITATE_SAMPLE_TICK)
					if not utils.isValidUnit(imitateTarget) or imitateTarget.Controller == nil then
						break
					end
					if imitateTarget.Controller:GetState() ~= Enums.ControllerStateType.Moving then
						break
					end
					local currentPos = imitateTarget:GetPosition()
					local delta = currentPos - lastPos
					lastPos = currentPos
					local horizontalDelta = math.Vector3(delta.x, 0, delta.z)
					local distance = horizontalDelta:Length()
					if distance > 0.05 then
						local moveDirection = math.Vector3(
							horizontalDelta.x / distance,
							0,
							horizontalDelta.z / distance
						)
						local endTime = World:GetServerTime() + distance / Configs.IMITATE_MOVE_SPEED
						while World:GetServerTime() < endTime and utils.isValidUnit(unit) do
							if not utils.isValidUnit(imitateTarget) or imitateTarget.Controller == nil then
								break
							end
							if imitateTarget.Controller:GetState() ~= Enums.ControllerStateType.Moving then
								break
							end
							if BehaviorRuntime.isMoveBlocked(unit) then
								unit.Controller:Move(math.Vector3(0, 0, 0))
							else
								unit.Controller:Move(moveDirection)
							end
							Task:Wait(Configs.IMITATE_MOVE_TICK)
						end
						if utils.isValidUnit(unit) and unit.Controller ~= nil then
							unit.Controller:Move(math.Vector3(0, 0, 0))
						end
					end
				end
				if utils.isValidUnit(unit) and unit.Controller ~= nil then
					unit.Controller:Move(math.Vector3(0, 0, 0))
				end
				moveTask = nil
				connections["move_task"] = nil
			end)
			connections["move_task"] = moveTask
		end
		local function onStateChanged(_, newState)
			if newState == Enums.ControllerStateType.Moving then
				startMoveTask()
			else
				stopMoveTask()
			end
		end
		connections["state_change"] = targetController.StateChanged:Connect(onStateChanged)
		if targetController:GetState() == Enums.ControllerStateType.Moving then
			startMoveTask()
		end
	end

	-- 目标销毁时解除模仿
	if imitateTarget.Destroying ~= nil then
		connections["destroying"] = imitateTarget.Destroying:Connect(function()
			unbind()
		end)
	end

	BehaviorRuntime.startMode(unit, "imitate", function()
		if continuousSec ~= nil and continuousSec > 0 then
			Task:Wait(continuousSec)
		else
			while utils.isValidUnit(unit) and utils.isValidUnit(imitateTarget) do
				Task:Wait(Configs.IMITATE_IDLE_TICK)
			end
		end
		unbind()
	end)
end

---让单位自动搜索范围内符合条件的敌人并追击
---@param unit EggyUnitInstance 角色
---@param params table 搜敌参数：searchRadius / filterCamp / tags / ignoreTags /
---reactionDis / reactBehavior / reactArg / tolerateDis / hateTime
function SOfficialAiFeatureManager.searchEnemy(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local searchRadius = params.searchRadius
	local filterCamp = params.filterCamp
	local tags = params.tags
	local ignoreTags = params.ignoreTags
	local reactionDis = params.reactionDis
	local reactBehavior = params.reactBehavior
	local reactArg = params.reactArg
	local tolerateDis = params.tolerateDis
	local hateTime = params.hateTime

	BehaviorRuntime.startMode(unit, "search_enemy", function()
		local currentTarget = nil
		local engageTime = 0

		while utils.isValidUnit(unit) do
			Task:Wait(Configs.REACT_TICK)

			if currentTarget == nil then
				-- 搜索最近的敌人：距离最近且在搜索半径内
				local ownerPos = unit:GetPosition()
				local ownerId = unit.UnitId
				local closest = nil
				local closestDis = nil
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					if character ~= nil and character.UnitId ~= ownerId then
						local dis = (character:GetPosition() - ownerPos):Length()
						if dis <= (searchRadius or Configs.DEFAULT_SEARCH_RADIUS) then
							-- 阵营过滤：0=未知 1=敌人 2=友军
							local ok = true
							if filterCamp ~= nil and filterCamp ~= Configs.CAMP_UNKNOWN then
								local relation = 0
								if World.GetUnitRelationShip ~= nil then
									relation = World:GetUnitRelationShip(unit, character) or 0
								end
								if relation ~= filterCamp then
									ok = false
								end
							end
							-- 标签过滤
							if ok and ignoreTags ~= nil and #ignoreTags > 0 and character.HasAnyTags ~= nil then
								if character:HasAnyTags(ignoreTags) then
									ok = false
								end
							end
							if ok and tags ~= nil and #tags > 0 and character.HasAllTags ~= nil then
								if not character:HasAllTags(tags) then
									ok = false
								end
							end
							if ok and (closestDis == nil or dis < closestDis) then
								closest = character
								closestDis = dis
							end
						end
					end
				end
				if closest ~= nil then
					currentTarget = closest
					engageTime = World:GetServerTime()
				end
			else
				-- 追击目标
				if not utils.isValidUnit(currentTarget) then
					currentTarget = nil
				else
					local dis = (currentTarget:GetPosition() - unit:GetPosition()):Length()
					-- 厌恶距离 / 厌恶时间脱战
					local rejectDis = tolerateDis or searchRadius or Configs.DEFAULT_SEARCH_RADIUS
					if searchRadius ~= nil and searchRadius > rejectDis then
						rejectDis = searchRadius
					end
					local elapsed = World:GetServerTime() - engageTime
					if dis > rejectDis then
						currentTarget = nil
					elseif hateTime ~= nil and hateTime > 0 and elapsed > hateTime then
						currentTarget = nil
					elseif dis <= (reactionDis or Configs.DEFAULT_REACTION_DISTANCE) then
						-- 到达反应距离：执行反应行为
						AbilityBridge.doReact(unit, reactBehavior, reactArg)
						unit.Controller:Move(math.Vector3(0, 0, 0))
						Task:Wait(Configs.REACT_COOLDOWN)
					else
						-- 朝目标水平方向移动
						local direction = utils.horizontalDirection(unit:GetPosition(), currentTarget:GetPosition())
						if direction ~= nil and not BehaviorRuntime.isMoveBlocked(unit) then
							unit.Controller:Move(direction)
						else
							unit.Controller:Move(math.Vector3(0, 0, 0))
						end
					end
				end
			end
		end

		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位追击指定目标，超出范围/次数或时间到即结束
---@param unit EggyUnitInstance 角色
---@param params table 追击参数：target / chaseRange / actionDistance / rejectTime /
---reactBehavior / actionCount
function SOfficialAiFeatureManager.chaseTarget(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local target = params.target
	if not utils.isValidUnit(target) then
		return
	end
	local chaseRange = params.chaseRange
	local actionDistance = params.actionDistance
	local rejectTime = params.rejectTime
	local reactBehavior = params.reactBehavior
	local maxCount = params.actionCount or Configs.DEFAULT_ACTION_COUNT
	-- moveType 为积木保留参数，当前不影响追击行为

	BehaviorRuntime.startMode(unit, "chase_target", function()
		local engageTime = World:GetServerTime()
		local count = 0

		while utils.isValidUnit(unit) and utils.isValidUnit(target) do
			local elapsed = World:GetServerTime() - engageTime
			if rejectTime ~= nil and rejectTime > 0 and elapsed > rejectTime then
				break
			end
			local dis = (target:GetPosition() - unit:GetPosition()):Length()
			if chaseRange ~= nil and chaseRange > 0 and dis > chaseRange then
				break
			end
			if dis <= (actionDistance or Configs.DEFAULT_REACTION_DISTANCE) then
				unit.Controller:Move(math.Vector3(0, 0, 0))
				AbilityBridge.doReact(unit, reactBehavior, nil)
				count = count + 1
				if count >= maxCount then
					break
				end
				Task:Wait(Configs.REACT_COOLDOWN)
			else
				local direction = utils.horizontalDirection(unit:GetPosition(), target:GetPosition())
				if direction ~= nil and not BehaviorRuntime.isMoveBlocked(unit) then
					unit.Controller:Move(direction)
				else
					unit.Controller:Move(math.Vector3(0, 0, 0))
				end
			end
			Task:Wait(Configs.MOVE_TICK)
		end

		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位沿寻路路径移动
---@param unit EggyUnitInstance 角色
---@param params table 寻路参数：path / navMode / navThreshold
function SOfficialAiFeatureManager.nav(unit, params)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	local path = params.path
	local navMode = params.navMode
	local navThreshold = params.navThreshold
	-- autoObstacle 为积木保留参数，当前不影响寻路行为

	BehaviorRuntime.startMode(unit, "nav", function()
		-- 取路径点
		local waypoints = {}
		if path ~= nil and path.GetWaypoints ~= nil then
			local points = path:GetWaypoints()
			if points ~= nil then
				for _, waypoint in ipairs(points) do
					waypoints[#waypoints + 1] = waypoint.Position
				end
			end
		end
		if #waypoints == 0 then
			return
		end

		local threshold = navThreshold
		if threshold == nil then
			threshold = Configs.DEFAULT_NAV_THRESHOLD
		end
		local mode = navMode
		if mode == nil then
			mode = 1
		end
		local count = #waypoints
		local index = 1
		local step = 1

		while utils.isValidUnit(unit) do
			local target = waypoints[index]
			local offset = target - unit:GetPosition()
			local moving = BehaviorRuntime.moveTowards(unit, offset, threshold)
			if not moving then
				unit.Controller:Move(math.Vector3(0, 0, 0))
				-- 导航模式：1=单程 2=循环 3=往返
				if mode == 1 then
					if index >= count then
						break
					end
					index = index + 1
				elseif mode == 2 then
					index = (index % count) + 1
				elseif mode == 3 then
					index = index + step
					if index > count then
						index = count - 1
						step = -1
					elseif index < 1 then
						index = 2
						step = 1
					end
				else
					index = (index % count) + 1
				end
				Task:Wait(Configs.MOVE_TICK)
			else
				Task:Wait(Configs.MOVE_TICK)
			end
		end

		if utils.isValidUnit(unit) and unit.Controller ~= nil then
			unit.Controller:Move(math.Vector3(0, 0, 0))
		end
	end)
end

---让单位执行基础行为：跳跃/滚动/飞扑/抓举/施放技能
---@param unit EggyUnitInstance 角色
---@param command AIBasicCommand 行为类型（Configs.CMD_*）
---@param slot AbilityIndex? 技能槽位（施放技能时使用）
function SOfficialAiFeatureManager.basicCommand(unit, command, slot)
	if not utils.isValidUnit(unit) or unit.Controller == nil then
		return
	end
	if command == Configs.CMD_JUMP then
		unit.Controller:Jump()
	elseif command == Configs.CMD_FLING then
		-- 预期错误：单位处于不能滚动的状态时无效
		pcall(function()
			unit.Controller:Fling()
		end)
	elseif command == Configs.CMD_RUSH then
		-- 预期错误：单位处于不能飞扑的状态时无效
		pcall(function()
			unit.Controller:Rush()
		end)
	elseif command == Configs.CMD_LIFT then
		-- 预期错误：单位处于不能抓举的状态时无效
		pcall(function()
			unit.Controller:Lift()
		end)
	elseif command == Configs.CMD_ABILITY then
		-- 使用槽位释放技能
		AbilityBridge.doReact(unit, Configs.CMD_ABILITY, slot)
	end
end

---让单位向指定方向释放技能
---@param unit EggyUnitInstance 角色
---@param params table 技能参数：direction / slot / chargeTime
function SOfficialAiFeatureManager.castAbility(unit, params)
	if not utils.isValidUnit(unit) then
		return
	end
	-- 对外释放无目标参数，按槽位与方向释放
	AbilityBridge.castAtSlot(unit, params.slot, nil, params.direction, params.chargeTime)
end

---让单位施放指定预设的技能；没有该技能时先添加再施放
---@param unit EggyUnitInstance 角色
---@param params table 技能参数：abilityKey / chargeTime / target
function SOfficialAiFeatureManager.castAbilityByKey(unit, params)
	if not utils.isValidUnit(unit) then
		return
	end
	AbilityBridge.castByKey(unit, params.abilityKey, params.chargeTime, params.target)
end

---让单位施放战技
---@param unit EggyUnitInstance 角色
---@param target EggyUnitInstance? 施放目标
---@param chargeTime Float? 蓄力时间（秒）
function SOfficialAiFeatureManager.executeCareerSkill(unit, target, chargeTime)
	if not utils.isValidUnit(unit) then
		return
	end
	-- 战技固定使用战技槽位
	AbilityBridge.castAtSlot(unit, Configs.CAREER_SKILL_SLOT, target, nil, chargeTime)
end

---给单位添加技能并放到指定槽位
---@param unit EggyUnitInstance 角色
---@param abilityIndex AbilityIndex 槽位号
---@param abilityId AbilityPrefab 技能预设 Key
function SOfficialAiFeatureManager.addAbilityToSlot(unit, abilityIndex, abilityId)
	if not utils.isValidUnit(unit) then
		return
	end
	-- 直接传目标槽位一步到位：与技能包内部添加技能后的入槽方式一致；
	-- 不走"先加到空闲槽再移动"：技能刚创建时可能尚未完成初始化。
	-- 语义：目标槽位被其他预设占用时添加失败（不覆盖、不互换）。
	AbilityBridge.addAbilityToSlot(unit, abilityIndex, abilityId)
end

---设置搜敌优先级类型（预留：当前搜敌按距离最近选目标）
---@param unit EggyUnitInstance 角色
---@param priorityMode Int 优先级类型
function SOfficialAiFeatureManager.setSearchEnemyPriorityMode(unit, priorityMode)
	if not utils.isValidUnit(unit) then
		return
	end
	local state = BehaviorRuntime.ensureState(unit)
	state.priorityMode = priorityMode
end

---设置搜敌时对指定目标的优先级权重（预留：当前不生效）
---@param unit EggyUnitInstance 角色
---@param target EggyUnitInstance 目标
---@param priorityValue Float 优先级权重
function SOfficialAiFeatureManager.setSearchEnemyPriorityValue(unit, target, priorityValue)
	-- 预留：暂未生效；当前搜敌默认按距离最近选目标
end

---设置搜敌的最优先目标（预留：当前不生效）
---@param unit EggyUnitInstance 角色
---@param target EggyUnitInstance 最优先目标
function SOfficialAiFeatureManager.setSearchEnemyFocusTarget(unit, target)
	if not utils.isValidUnit(unit) then
		return
	end
	local state = BehaviorRuntime.ensureState(unit)
	state.focusTarget = target
end

---设置寻路到达阈值（预留：当前不生效）
---@param unit EggyUnitInstance 角色
---@param threshold Float 到达阈值
function SOfficialAiFeatureManager.setMoveThreshold(unit, threshold)
	if not utils.isValidUnit(unit) then
		return
	end
	local state = BehaviorRuntime.ensureState(unit)
	state.moveThreshold = threshold
end

return SOfficialAiFeatureManager
