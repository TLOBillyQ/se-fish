--生物AI包 - server端api
--面向业务代码的 AI 行为入口；技能能力依赖技能包服务端门面 server.packages.ability_system.api。
--门面函数参数与蛋码积木参数一一对应（含保留参数），顺序即对外契约，不再合并。

local Configs = require("common.packages.official_ai_feature.configs")
local officialAiFeature = require("server.packages.official_ai_feature.official_ai_feature")

---激活单位的AI，恢复执行后续指令
---@param unit EggyUnitInstance 角色
local function StartAI(unit)
	return officialAiFeature.startAI(unit)
end

---禁用单位的AI；禁用前等待执行的指令会被记忆，重新激活后继续
---@param unit EggyUnitInstance 角色
local function StopAI(unit)
	return officialAiFeature.stopAI(unit)
end

---让单位立即滚动一次
---@param unit EggyUnitInstance 角色
local function Roll(unit)
	return officialAiFeature.roll(unit)
end

---让单位立即向前飞扑一次
---@param unit EggyUnitInstance 角色
local function Rush(unit)
	return officialAiFeature.rush(unit)
end

---让单位立即跳跃一次
---@param unit EggyUnitInstance 角色
local function Jump(unit)
	return officialAiFeature.jump(unit)
end

---让单位执行一次抓举/放下/投掷
---@param unit EggyUnitInstance 角色
local function Lift(unit)
	return officialAiFeature.lift(unit)
end

---让单位朝指定方向持续移动
---@param unit EggyUnitInstance 角色
---@param direction Vector3 方向
---@param hateTime Float 厌恶时间（秒）；不大于 0 表示不限时
---@param autoObstacle AIMoveMode 移动模式（0=无视障碍，非 0=避障）
local function MoveDirection(unit, direction, hateTime, autoObstacle)
	return officialAiFeature.moveDirection(unit, {
		direction = direction,
		hateTime = hateTime,
		autoObstacle = autoObstacle,
	})
end

---让单位移动到指定位置
---@param unit EggyUnitInstance 角色
---@param targetPos Vector3 目标位置
---@param hateTime Float 厌恶时间（秒）；不大于 0 表示不限时
---@param toleranceDis Float 容错距离；不大于 0 时按默认值处理
---@param autoObstacle AIMoveMode 移动模式（保留参数）
local function MoveToPos(unit, targetPos, hateTime, toleranceDis, autoObstacle)
	return officialAiFeature.moveToPos(unit, {
		targetPos = targetPos,
		hateTime = hateTime,
		toleranceDis = toleranceDis,
		autoObstacle = autoObstacle,
	})
end

---让单位停止移动；带时长时禁足一段时间，期间其他行为模式也会被暂停
---@param unit EggyUnitInstance 角色
---@param duration Float 禁足时长（秒）；不大于 0 表示立即恢复移动
local function StopMove(unit, duration)
	return officialAiFeature.stopMove(unit, duration)
end

---让单位跟随目标：不断缩短与目标的距离，超出容忍距离则放弃
---@param unit EggyUnitInstance 角色
---@param continuousSec Float 持续时长（秒）；不大于 0 或为空时持续到目标销毁
---@param followTarget EggyUnitInstance 跟随目标
---@param followDis Float 反应距离：超过该距离开始移动
---@param tolerateDis Float 容忍距离：超过该距离放弃跟随；不大于 0 表示不限制
local function Follow(unit, continuousSec, followTarget, followDis, tolerateDis)
	return officialAiFeature.follow(unit, {
		continuousSec = continuousSec,
		followTarget = followTarget,
		followDis = followDis,
		tolerateDis = tolerateDis,
	})
end

---让单位警戒指定位置：偏离后延迟一段时间返回，超过容忍距离则脱离警戒
---@param unit EggyUnitInstance 角色
---@param continuousSec Float 持续时长（秒）；不大于 0 表示不限时
---@param keepPos Vector3 保持位置（警戒点）
---@param keepPosRotation Quaternion? 回到警戒点后的朝向
---@param delayTime Float? 离开警戒点后开始返回的延迟时间（秒）；为空时按默认值处理
---@param tolerateDis Float? 容忍距离：超过该距离脱离警戒；为空时按默认值处理
local function Alert(unit, continuousSec, keepPos, keepPosRotation, delayTime, tolerateDis)
	return officialAiFeature.alert(unit, {
		continuousSec = continuousSec,
		keepPos = keepPos,
		keepPosRotation = keepPosRotation,
		delayTime = delayTime,
		tolerateDis = tolerateDis,
	})
end

---让单位模仿目标的动作与移动
---@param unit EggyUnitInstance 角色
---@param imitateTarget EggyUnitInstance 模仿目标
---@param continuousSec Float 持续时长（秒）；不大于 0 或为空时持续到目标销毁
local function Imitate(unit, imitateTarget, continuousSec)
	return officialAiFeature.imitate(unit, imitateTarget, continuousSec)
end

---让单位自动搜索范围内符合条件的敌人并追击
---@param unit EggyUnitInstance 角色
---@param searchRadius Float 搜索半径
---@param filterCamp Camp 敌意阵营（0=不限）
---@param tags String[] 必选标签（全部满足）
---@param ignoreTags String[] 忽略标签（命中任一即跳过）
---@param reactionDis Float 反应距离
---@param reactBehavior AIBasicCommand 反应行为
---@param reactArg AbilityIndex 反应参数（施放技能时为技能槽位）
---@param tolerateDis Float 厌恶距离
---@param hateTime Float 厌恶时间（秒）
local function SearchEnemy(
	unit,
	searchRadius,
	filterCamp,
	tags,
	ignoreTags,
	reactionDis,
	reactBehavior,
	reactArg,
	tolerateDis,
	hateTime
)
	return officialAiFeature.searchEnemy(unit, {
		searchRadius = searchRadius,
		filterCamp = filterCamp,
		tags = tags,
		ignoreTags = ignoreTags,
		reactionDis = reactionDis,
		reactBehavior = reactBehavior,
		reactArg = reactArg,
		tolerateDis = tolerateDis,
		hateTime = hateTime,
	})
end

---让单位追击指定目标：超出最大范围、达到追击次数或厌恶时间到时结束
---@param unit EggyUnitInstance 角色
---@param chaseTarget EggyUnitInstance 追击目标
---@param chaseRange Float 最大范围
---@param actionDistance Float 反应距离
---@param rejectTime Float 厌恶时间（秒）
---@param reactBehavior AIBasicCommand 反应行为
---@param moveType Int 移动方式（保留参数）
---@param actionCount Int 追击次数
local function ChaseTarget(
	unit,
	chaseTarget,
	chaseRange,
	actionDistance,
	rejectTime,
	reactBehavior,
	moveType,
	actionCount
)
	return officialAiFeature.chaseTarget(unit, {
		target = chaseTarget,
		chaseRange = chaseRange,
		actionDistance = actionDistance,
		rejectTime = rejectTime,
		reactBehavior = reactBehavior,
		actionCount = actionCount,
	})
end

---让单位沿指定路径寻路移动
---@param unit EggyUnitInstance 角色
---@param path FindingPathUnit 路径
---@param navMode NavMode 导航模式
---@param navThreshold Float 到达阈值
---@param autoObstacle AIMoveMode 移动模式（保留参数）
local function Nav(unit, path, navMode, navThreshold, autoObstacle)
	return officialAiFeature.nav(unit, {
		path = path,
		navMode = navMode,
		navThreshold = navThreshold,
	})
end

---让单位执行基础行为：跳跃/滚动/飞扑/抓举/施放技能
---@param unit EggyUnitInstance 角色
---@param command AIBasicCommand 基础命令
---@param slot AbilityIndex 技能槽位（施放技能时使用）
local function BasicCommand(unit, command, slot)
	return officialAiFeature.basicCommand(unit, command, slot)
end

---让单位向指定方向释放技能
---@param unit EggyUnitInstance 角色
---@param direction Vector3 释放方向
---@param slot AbilityIndex 技能槽位
---@param chargeTime Float 蓄力时间（秒）
local function CastAbility(unit, direction, slot, chargeTime)
	return officialAiFeature.castAbility(unit, {
		direction = direction,
		slot = slot,
		chargeTime = chargeTime,
	})
end

---让单位施放指定预设的技能；没有该技能时先添加再施放
---@param unit EggyUnitInstance 角色
---@param abilityKey String 技能预设 Key
---@param chargeTime Float 蓄力时间（秒）
---@param target EggyUnitInstance 施放目标
local function CastAbilityByKey(unit, abilityKey, chargeTime, target)
	return officialAiFeature.castAbilityByKey(unit, {
		abilityKey = abilityKey,
		chargeTime = chargeTime,
		target = target,
	})
end

---让单位施放战技
---@param unit EggyUnitInstance 角色
---@param target EggyUnitInstance 施放目标
---@param chargeTime Float 蓄力时间（秒）
local function ExecuteCareerSkill(unit, target, chargeTime)
	return officialAiFeature.executeCareerSkill(unit, target, chargeTime)
end

---给单位的指定槽位添加技能；目标槽位被其他预设占用时不覆盖
---@param unit EggyUnitInstance 角色
---@param abilityIndex AbilityIndex 槽位号
---@param abilityId AbilityPrefab 技能预设
local function AddAbilityToSlot(unit, abilityIndex, abilityId)
	return officialAiFeature.addAbilityToSlot(unit, abilityIndex, abilityId)
end

---设置搜敌优先级类型（预留：当前搜敌按距离最近选目标）
---@param unit EggyUnitInstance 角色
---@param priorityMode Int 优先级类型
local function SetSearchEnemyPriorityMode(unit, priorityMode)
	return officialAiFeature.setSearchEnemyPriorityMode(unit, priorityMode)
end

---设置搜敌时对指定目标的优先级权重（预留：当前不生效）
---@param unit EggyUnitInstance 角色
---@param target EggyUnitInstance 目标
---@param priorityValue Float 优先级权重
local function SetSearchEnemyPriorityValue(unit, target, priorityValue)
	return officialAiFeature.setSearchEnemyPriorityValue(unit, target, priorityValue)
end

---设置搜敌的最优先目标（预留：当前不生效）
---@param unit EggyUnitInstance 角色
---@param target EggyUnitInstance 最优先目标
local function SetSearchEnemyFocusTarget(unit, target)
	return officialAiFeature.setSearchEnemyFocusTarget(unit, target)
end

---设置寻路到达阈值（预留：当前不生效）
---@param unit EggyUnitInstance 角色
---@param threshold Float 寻路阈值
local function SetMoveThreshold(unit, threshold)
	return officialAiFeature.setMoveThreshold(unit, threshold)
end

return {
	Configs = Configs,
	Funcs = {
		StartAI = StartAI,
		StopAI = StopAI,
		Roll = Roll,
		Rush = Rush,
		Jump = Jump,
		Lift = Lift,
		MoveDirection = MoveDirection,
		MoveToPos = MoveToPos,
		StopMove = StopMove,
		Follow = Follow,
		Alert = Alert,
		Imitate = Imitate,
		SearchEnemy = SearchEnemy,
		ChaseTarget = ChaseTarget,
		Nav = Nav,
		BasicCommand = BasicCommand,
		CastAbility = CastAbility,
		CastAbilityByKey = CastAbilityByKey,
		ExecuteCareerSkill = ExecuteCareerSkill,
		AddAbilityToSlot = AddAbilityToSlot,
		SetSearchEnemyPriorityMode = SetSearchEnemyPriorityMode,
		SetSearchEnemyPriorityValue = SetSearchEnemyPriorityValue,
		SetSearchEnemyFocusTarget = SetSearchEnemyFocusTarget,
		SetMoveThreshold = SetMoveThreshold,
	},
}
