--技能系统 - clientAbilitySlot 技能栏槽位节点行为
--
-- 使用方式：UIManager 拿到节点后调用 AbilitySlot.Attach(node) 初始化字段与
-- 子节点绑定（按子节点 name 通过 FindFirstChild 绑定），之后以
-- AbilitySlot.xxx(node, ...) 形式调用；解绑/销毁时调用 AbilitySlot.Cleanup(node)。
--
-- 注意：EUI 节点是引擎 userdata，禁止挂自定义字段，全部状态存 Lua 侧 _nodeState[node]。

local EuiAdapter = require("client.packages.ability_system.ui.eui_adapter")

local AbilitySlot = {}
AbilitySlot.__index = AbilitySlot

local Task = game:GetService("Task")
local World = game:GetService("World")

-- Lua 侧节点状态缓存（EUI userdata 不能挂字段）

local _nodeState = {} -- [node] = state table

local function getState(node)
	if not _nodeState[node] then
		_nodeState[node] = {
			attached = false,
			cd_timer = nil,
			cd_gen = 0,
			cd_start_time = 0,
			cd_total_time = 0,
			isChargeConsuming = false,
			chargeCount = 0,
			maxChargeCount = 1,
			chargeInterval = 1.0,
			chargeAmount = 1,
			chargeType = 0,
			charge_timer = nil,
			charge_start_time = 0,
			isForbidden = false,
			isForbiddenGrayout = false,
			touchRange = 0,
			ImageMoveRange = nil,
			ImageTouchPoint = nil,
			ProgressTimer = nil,
			CdText = nil,
			CdMask = nil,
			ChargeBackground = nil,
			ChargeProgressTimer = nil,
			ChargeCount = nil,
		}
	end
	return _nodeState[node]
end

-- Attach：把行为初始化挂到节点上（幂等）

function AbilitySlot.Attach(node)
	if not node then
		return nil
	end
	local st = getState(node)
	if st.attached then
		return node
	end
	st.attached = true

	-- 解析子节点字段：按子节点 name 通过 FindFirstChild 绑定
	AbilitySlot.BindChildren(node)

	-- 初始化字段
	st.cd_timer = nil
	st.cd_gen = 0
	st.cd_start_time = 0
	st.cd_total_time = 0
	st.isChargeConsuming = false
	st.chargeCount = 0
	st.maxChargeCount = 1
	st.chargeInterval = 1.0
	st.chargeAmount = 1
	st.chargeType = 0
	st.charge_timer = nil
	st.charge_start_time = 0
	st.isForbidden = false
	st.isForbiddenGrayout = false

	-- 计算拖拽范围（不隐藏节点，显示由 UIManager 控制）
	local moveRange = st.ImageMoveRange
	local touchPoint = st.ImageTouchPoint
	if moveRange and touchPoint and moveRange.Size and touchPoint.Size then
		st.touchRange = (moveRange.Size.x - touchPoint.Size.x) / 2
	else
		st.touchRange = 0
	end
	AbilitySlot.InitCDUI(node)
	AbilitySlot.Refresh(node)
	return node
end

-- 子节点字段绑定（按 name 查找）

-- 取可直接 SetPercent 的 ProgressTimer 节点：
-- 若找到的节点没有 SetPercent 方法（Layout 容器嵌套），取其第一个带 SetPercent 的后代。
local function _resolveTimer(node, name1, name2)
	local timer = EuiAdapter.FindFirstChild(node, name1) or EuiAdapter.FindFirstChild(node, name2)
	if timer and type(timer.SetPercent) ~= "function" then
		local children = EuiAdapter.GetDescendants(timer)
		for _, child in ipairs(children) do
			if type(child.SetPercent) == "function" then
				return child
			end
		end
	end
	return timer
end

-- 按子节点 name 解析字段；节点缺失时对应字段为 nil，调用方需判空。
-- 说明：ProgressTimer 在 euidata.json 中的 name 可能为 "progress_timer"（小写），
-- 但代码字段名是 ProgressTimer（大写），故同时兼容两种 name。
function AbilitySlot.BindChildren(node)
	if not node then
		return
	end
	local st = getState(node)
	st.ImageMoveRange = EuiAdapter.FindFirstChild(node, "ImageMoveRange")
	st.ImageTouchPoint = EuiAdapter.FindFirstChild(node, "ImageTouchPoint")
	st.ProgressTimer = _resolveTimer(node, "ProgressTimer", "progress_timer")
	st.CdText = EuiAdapter.FindFirstChild(node, "CdText")
	st.CdMask = EuiAdapter.FindFirstChild(node, "CdMask")
	st.ChargeBackground = EuiAdapter.FindFirstChild(node, "ChargeBackground")
	st.ChargeProgressTimer = _resolveTimer(node, "ChargeProgressTimer", "charge_progress_timer")
	st.ChargeCount = EuiAdapter.FindFirstChild(node, "ChargeCount")
end

-- 供 UIManager 等外部读取已解析的子节点引用（避免直接碰 userdata 字段）
function AbilitySlot.GetState(node)
	return getState(node)
end

-- CD UI

function AbilitySlot.InitCDUI(node)
	local st = getState(node)
	if st.ProgressTimer then
		EuiAdapter.SetVisible(st.ProgressTimer, false)
	end
	if st.CdText then
		EuiAdapter.SetVisible(st.CdText, false)
	end
	if st.CdMask then
		EuiAdapter.SetVisible(st.CdMask, st.isForbiddenGrayout)
	end
end

function AbilitySlot.StartCD(node, totalCD)
	local st = getState(node)
	st.cd_gen = st.cd_gen + 1
	AbilitySlot._StopCDTimer(node)
	st.cd_total_time = totalCD or 1
	st.cd_start_time = World:GetServerTime()
	AbilitySlot._UpdateCD(node)
	AbilitySlot._StartCDTimer(node)
end

function AbilitySlot.StopCD(node)
	local st = getState(node)
	st.cd_gen = st.cd_gen + 1
	AbilitySlot._StopCDTimer(node)
	st.cd_start_time = 0
	st.cd_total_time = 0
	AbilitySlot.InitCDUI(node)
end

function AbilitySlot._GetLeftCD(node)
	local st = getState(node)
	if st.cd_start_time <= 0 or st.cd_total_time <= 0 then
		return 0
	end
	local elapsed = World:GetServerTime() - st.cd_start_time
	local leftCD = st.cd_total_time - elapsed
	return leftCD > 0 and leftCD or 0
end

function AbilitySlot._UpdateCD(node)
	local st = getState(node)
	local leftCD = AbilitySlot._GetLeftCD(node)
	local totalCD = st.cd_total_time

	if leftCD <= 0 then
		return false
	end

	local progress = 0
	if totalCD > 0 then
		progress = (leftCD / totalCD) * 100
	end

	if st.ProgressTimer then
		EuiAdapter.SetVisible(st.ProgressTimer, true)
		EuiAdapter.SetPercent(st.ProgressTimer, progress)
	end

	if st.CdText then
		EuiAdapter.SetText(st.CdText, string.format("%.1f", leftCD))
		EuiAdapter.SetVisible(st.CdText, true)
	end

	if st.CdMask then
		EuiAdapter.SetVisible(st.CdMask, true)
	end

	return true
end

function AbilitySlot._StartCDTimer(node)
	local st = getState(node)
	if st.cd_timer then
		return
	end

	local gen = st.cd_gen

	local function tick()
		if st.cd_gen ~= gen then
			st.cd_timer = nil
			return
		end
		local shouldContinue = AbilitySlot._UpdateCD(node)
		if shouldContinue then
			st.cd_timer = Task:Delay(0.1, tick)
		else
			st.cd_timer = nil
			AbilitySlot.StopCD(node)
		end
	end

	st.cd_timer = Task:Delay(0.1, tick)
end

function AbilitySlot._StopCDTimer(node)
	local st = getState(node)
	if st.cd_timer then
		Task:Cancel(st.cd_timer)
		st.cd_timer = nil
	end
end

-- 禁用 / 置灰

function AbilitySlot.SetForbidden(node, isForbid, grayout)
	local st = getState(node)
	st.isForbidden = isForbid
	EuiAdapter.SetTouchEnabled(node, not isForbid)
	if grayout then
		st.isForbiddenGrayout = isForbid
		if st.CdMask then
			EuiAdapter.SetVisible(st.CdMask, isForbid)
		end
	end
end

-- 拖拽范围指示器

function AbilitySlot.ShowDragIndicator(node, beginPos)
	local st = getState(node)
	local localPos = EuiAdapter.ConvertToLocalPosition(node, beginPos)
	if st.ImageMoveRange then
		EuiAdapter.SetColor(st.ImageMoveRange, EuiAdapter.makeColor(0, 255, 255, 255))
		EuiAdapter.SetVisible(st.ImageMoveRange, true)
		EuiAdapter.SetPosition(st.ImageMoveRange, localPos)
	end
	if st.ImageTouchPoint then
		EuiAdapter.SetVisible(st.ImageTouchPoint, true)
		EuiAdapter.SetPosition(st.ImageTouchPoint, localPos)
	end
end

function AbilitySlot.UpdateDragIndicator(node, beginPos, movePos)
	local st = getState(node)
	local delta = movePos - beginPos
	-- Vector2 无 Length 声明，用欧氏距离
	local distance = math.sqrt(delta.x * delta.x + delta.y * delta.y)
	if distance > st.touchRange then
		delta:Normalize()
		movePos = beginPos + delta * st.touchRange
	end
	local localPos = EuiAdapter.ConvertToLocalPosition(node, movePos)
	if st.ImageTouchPoint then
		EuiAdapter.SetPosition(st.ImageTouchPoint, localPos)
	end
end

function AbilitySlot.HideDragIndicator(node)
	local st = getState(node)
	if st.ImageMoveRange then
		EuiAdapter.SetVisible(st.ImageMoveRange, false)
	end
	if st.ImageTouchPoint then
		EuiAdapter.SetVisible(st.ImageTouchPoint, false)
	end
end

-- 取消态高亮（青色 ↔ 粉红）
function AbilitySlot.SetCancelState(node, cancel)
	local st = getState(node)
	local color = EuiAdapter.makeColor(0, 255, 255, 255)
	if cancel then
		color = EuiAdapter.makeColor(255, 192, 203, 255)
	end
	if st.ImageMoveRange then
		EuiAdapter.SetColor(st.ImageMoveRange, color)
	end
end

-- 充能 UI

function AbilitySlot.InitChargeData(node, chargeData)
	local st = getState(node)
	st.isChargeConsuming = chargeData.IsChargeConsuming or false
	st.chargeCount = chargeData.ChargeCount or 0
	st.maxChargeCount = chargeData.MaxChargeCount or 1
	st.chargeInterval = chargeData.ChargeInterval or 1.0
	st.chargeAmount = chargeData.ChargeAmount or 1
	st.chargeType = chargeData.ChargeType or 0
	AbilitySlot.InitChargeUI(node)
end

function AbilitySlot.InitChargeUI(node)
	local st = getState(node)
	if st.isChargeConsuming then
		if st.ChargeBackground then
			EuiAdapter.SetVisible(st.ChargeBackground, true)
		end
		if st.ChargeProgressTimer then
			EuiAdapter.SetVisible(st.ChargeProgressTimer, true)
		end
		if st.ChargeCount then
			EuiAdapter.SetVisible(st.ChargeCount, true)
		end
		AbilitySlot.UpdateChargeUI(node, st.chargeCount)
	else
		if st.ChargeBackground then
			EuiAdapter.SetVisible(st.ChargeBackground, false)
		end
		if st.ChargeProgressTimer then
			EuiAdapter.SetVisible(st.ChargeProgressTimer, false)
		end
		if st.ChargeCount then
			EuiAdapter.SetVisible(st.ChargeCount, false)
		end
	end
end

function AbilitySlot.UpdateChargeUI(node, chargeCount, chargeConfig)
	local st = getState(node)
	if chargeConfig then
		if chargeConfig.IsChargeConsuming ~= nil then
			st.isChargeConsuming = chargeConfig.IsChargeConsuming
		end
		if chargeConfig.MaxChargeCount ~= nil then
			st.maxChargeCount = chargeConfig.MaxChargeCount
		end
		if chargeConfig.ChargeInterval ~= nil then
			st.chargeInterval = chargeConfig.ChargeInterval
		end
		if chargeConfig.ChargeType ~= nil then
			st.chargeType = chargeConfig.ChargeType
		end
		if chargeConfig.ChargeAmount ~= nil then
			st.chargeAmount = chargeConfig.ChargeAmount
		end
	end

	if not st.isChargeConsuming then
		return
	end

	local oldCount = st.chargeCount
	st.chargeCount = chargeCount or 0
	if st.ChargeCount then
		EuiAdapter.SetText(st.ChargeCount, tostring(st.chargeCount))
	end

	if st.charge_timer then
		Task:Cancel(st.charge_timer)
		st.charge_timer = nil
	end

	if st.ChargeProgressTimer then
		if st.chargeCount >= st.maxChargeCount then
			EuiAdapter.SetPercent(st.ChargeProgressTimer, 100)
			return
		end

		local shouldCharge = false
		if st.chargeType == 0 then
			EuiAdapter.SetVisible(st.ChargeProgressTimer, false)
			return
		elseif st.chargeType == 1 then
			shouldCharge = st.chargeCount < st.maxChargeCount
		elseif st.chargeType == 2 then
			shouldCharge = st.chargeCount == 0
		end

		if not shouldCharge then
			EuiAdapter.SetPercent(st.ChargeProgressTimer, 100)
			return
		end

		if st.chargeCount > oldCount or st.charge_start_time <= 0 then
			st.charge_start_time = World:GetServerTime()
		end

		if st.charge_start_time > 0 and st.chargeInterval > 0 then
			local function tick()
				local elapsed = World:GetServerTime() - st.charge_start_time
				local progress = (elapsed / st.chargeInterval) * 100
				if progress >= 100 then
					EuiAdapter.SetPercent(st.ChargeProgressTimer, 100)
					st.charge_timer = nil
				else
					EuiAdapter.SetPercent(st.ChargeProgressTimer, progress)
					st.charge_timer = Task:Delay(0.1, tick)
				end
			end
			tick()
		end
	end
end

-- 刷新钩子 / 清理

function AbilitySlot.Refresh(node) end

-- 节点销毁 / 解绑时清理定时器
function AbilitySlot.Cleanup(node)
	if not node then
		return
	end
	local st = getState(node)
	AbilitySlot._StopCDTimer(node)
	if st.charge_timer then
		Task:Cancel(st.charge_timer)
		st.charge_timer = nil
	end
	_nodeState[node] = nil
end

return AbilitySlot
