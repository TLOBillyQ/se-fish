--技能系统 - server子技能组
-- 子技能组管理服务端脚本（槽位共享版）：接收已创建好的 child AbilityItem ScriptUnit 引用 list，
--   负责 Group 激活 + 切换 + 反查；切换策略：AfterCast / Timer / Manual；切换顺序：Sequential / Shuffle / Random。
-- 槽位共享语义：切换经 managerHandler.setSlotAbility 换槽（服务端槽位缓存 + 信号 + 客户端通知三合一），
--   被切下成员 Index 置 SLOT_INDEX_UNASSIGNED(-1) 休眠；休眠不打断进行中的施法（Index 变更不触碰 InCast/castTimer）；
--   技能栏 UI 自动跟随；options.shareSlot=false 时退回纯"激活通知"行为（不改 Index、不动缓存）。
-- 回归计时（仅 AfterCast + revertTime>0）：切到非首成员启动，到时自动回父技能；
--   switchRefresh=true 时子技能间互切重置倒计时；回归不走切换冷却、不重置切换策略。
-- 切换触发：AfterCast 绑定全部成员的 CastEnd，仅活跃成员施法结束时轮转；
--   SwitchMode/Order 为字符串枚举；子技能由上层手工创建传入（无自动建组）。

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityEventDefs = require("common.packages.ability_system.event_defs")
local AbilityRegistry = require("common.packages.ability_system.registry")
local AbilityUtils = require("common.packages.ability_system.util")

local Task = game:GetService("Task")

local SubAbilityHandler = {}

-- 切换顺序算子（每个实现 next(group) -> newActiveIndex，1-based）

local function _nextSequential(group)
	return AbilityUtils.nextSequential(group.activeIndex, #group.members)
end

-- Shuffle 惰性逐轮重建：
-- 每轮 Fisher-Yates 重洗，上一轮末元素作为下一轮首元素排除项（轮间尾头不重复）
local function _buildShuffledList(count, exclude_first, rng)
	local list = {}
	for i = 1, count do
		list[i] = i
	end
	for i = count, 2, -1 do
		local j = rng.nextInt(1, i)
		list[i], list[j] = list[j], list[i]
	end
	if exclude_first ~= nil and count > 1 and list[1] == exclude_first then
		local swap_pos = rng.nextInt(2, count)
		list[1], list[swap_pos] = list[swap_pos], list[1]
	end
	return list
end

local function _nextShuffle(group)
	local count = #group.members
	if count <= 1 then
		return 1
	end
	local st = group.shuffleState
	if st == nil or st.pos >= #st.list then
		local last_of_prev = nil
		if st ~= nil and #st.list > 0 then
			last_of_prev = st.list[#st.list]
		end
		st = { list = _buildShuffledList(count, last_of_prev, group._rng), pos = 0 }
		group.shuffleState = st
	end
	st.pos = st.pos + 1
	return st.list[st.pos]
end

local function _nextRandom(group)
	local count = #group.members
	if count <= 1 then
		return 1
	end
	local pick
	repeat
		pick = group._rng.nextInt(1, count)
	until pick ~= group._lastPick
	group._lastPick = pick
	return pick
end

-- 工厂：create

-- 参数：
--   parentHandler - 父能力 handler（必需，Group 的第一个成员）
--   parentScript - 父能力 ScriptUnit 引用（用于 reverse 反查注册）
--   childHandlers - 子能力 handler 数组（{handler1, handler2, ...}，每个都对应一个 AbilityItem ScriptUnit）
--   switchMode - AbilityConstants.SwitchMode
--   switchOrder - AbilityConstants.SwitchOrder
--   timerDelay - SwitchMode.Timer 下切换间隔（秒），可选
--   options - 可选配置：
--     shareSlot boolean 槽位共享（Index 交换 + 服务端槽位缓存同步），默认 true
--     slotIndex number 组槽位号，缺省取父成员当前 Index
--     switchCooldown number 切换后冷却（秒），默认 0；回归路径不触发
--     revertTime number 回归计时（秒），默认 0=不启用；仅 AfterCast 模式生效
--     switchRefresh boolean 子技能间互切是否重置回归倒计时，默认 true
--     destroyWithMembers boolean 任一成员销毁时连带销毁其余成员，默认 true
function SubAbilityHandler.create(
	parentHandler,
	parentScript,
	childHandlers,
	switchMode,
	switchOrder,
	timerDelay,
	options
)
	if not parentHandler then
		return nil
	end
	options = options or {}

	local signals_owner = parentScript or game:GetService("World")
	local parent_script = parentHandler.getScript and parentHandler.getScript() or parentScript

	-- 管理器 handler（槽位缓存同步用）；manager_logic 未 Attach 时为 nil，退化为纯属性交换
	local manager_handler = nil
	local manager_script = parent_script and parent_script.Parent
	if manager_script then
		manager_handler = AbilityRegistry.getManagerHandler(manager_script)
	end

	-- 确定性随机种子：由槽位派生，不用时间 / 运行时 UnitId，保证双端一致
	local slot_index = options.slotIndex
		or (parent_script and parent_script:GetAttribute("Index"))
		or 0
	local group = {
		parentHandler = parentHandler,
		members = { parentHandler }, -- 主能力是第一个成员
		activeIndex = 1,
		switchMode = switchMode or AbilityConstants.SwitchMode.AfterCast,
		switchOrder = switchOrder or AbilityConstants.SwitchOrder.Sequential,
		shareSlot = options.shareSlot ~= false,
		slotIndex = slot_index,
		switchCooldown = options.switchCooldown or 0,
		revertTime = options.revertTime or 0,
		switchRefresh = options.switchRefresh ~= false,
		destroyWithMembers = options.destroyWithMembers ~= false,
		_managerHandler = manager_handler,
		_timerDelay = timerDelay or 3.0,
		_timerHandler = nil,
		_revertTimer = nil,
		_cleaning = false,
		_lastPick = nil,
		_rng = AbilityUtils.newRandom(slot_index * 131 + 1), -- 确定性随机源（Shuffle / Random）
		shuffleState = nil, -- { list = 洗牌序列, pos = 已消费位置 }
		_childHandlersKeys = {}, -- [tostring(child 脚本)] = true，供 registry.findGroupByChild 反查
		signals = {
			OnActivated = AbilityEventDefs.createEventUnit(signals_owner, "OnActivated"),
			OnDeactivated = AbilityEventDefs.createEventUnit(signals_owner, "OnDeactivated"),
			OnSwitchNext = AbilityEventDefs.createEventUnit(signals_owner, "OnSwitchNext"),
		},
	}

	-- 加入 childHandlers（注册键用 registry.unitKeyOf（UnitId），对齐 findGroupByChild 的查找键）
	for _, childHandler in ipairs(childHandlers or {}) do
		table.insert(group.members, childHandler)
		local child_script = childHandler.getScript and childHandler.getScript()
		if child_script then
			group._childHandlersKeys[AbilityRegistry.unitKeyOf(child_script)] = true
		end
		group._childHandlersKeys[tostring(childHandler)] = true
	end

	-- 注册到 AbilityRegistry（用于反查；统一用 handler 解析出的脚本作键）
	if parent_script then
		AbilityRegistry.registerGroup(parent_script, group)
	end

	-- 建组即休眠：子成员全部置未入槽哨兵，
	-- 否则子技能若带合法 Index，首次切换前会与父技能同时占槽
	if group.shareSlot then
		for i, member in ipairs(group.members) do
			if i > 1 then
				local member_script = member.getScript and member.getScript()
				if member_script then
					member_script:SetAttribute("Index", AbilityConstants.SLOT_INDEX_UNASSIGNED)
				end
			end
		end
	end

	-- 切换执行（唯一出口：_doSwitchTo）

	local _doSwitchTo
	local start_revert_timer
	local cancel_revert_timer

	-- 回归计时器（仅 AfterCast + revertTime>0）
	start_revert_timer = function()
		if group.revertTime <= 0 then
			return
		end
		if group.activeIndex == 1 then
			return
		end
		cancel_revert_timer()
		group._revertTimer = Task:Delay(group.revertTime, function()
			group._revertTimer = nil
			if group._cleaning then
				return
			end
			if group.activeIndex == 1 then
				return
			end
			_doSwitchTo(1, true)
		end)
	end

	cancel_revert_timer = function()
		if group._revertTimer then
			Task:Cancel(group._revertTimer)
			group._revertTimer = nil
		end
	end

	_doSwitchTo = function(target_index, is_revert)
		local old_handler = group.members[group.activeIndex]
		local new_handler = group.members[target_index]
		if not old_handler or not new_handler then
			return false
		end

		-- 槽位共享：经管理器 handler 换槽（服务端缓存/信号/客户端通知三合一）；
		-- 被切下成员转休眠（-1 哨兵，不打断进行中的施法）。
		-- manager handler 缺失时退化为纯属性交换。
		if group.shareSlot then
			local old_script = old_handler.getScript and old_handler.getScript()
			local new_script = new_handler.getScript and new_handler.getScript()
			if group._managerHandler and group._managerHandler.setSlotAbility then
				if new_script then
					group._managerHandler.setSlotAbility(group.slotIndex, new_script)
				end
				if old_script then
					old_script:SetAttribute("Index", AbilityConstants.SLOT_INDEX_UNASSIGNED)
				end
			else
				if old_script then
					old_script:SetAttribute("Index", AbilityConstants.SLOT_INDEX_UNASSIGNED)
				end
				if new_script then
					new_script:SetAttribute("Index", group.slotIndex)
				end
			end
		end

		-- 旧 active 失活 / 新 active 激活（钩子 + 组级事件）
		if old_handler.onDeactivate then
			old_handler.onDeactivate()
		end
		group.signals.OnDeactivated:Fire(old_handler, group.activeIndex)
		if new_handler.onActivate then
			new_handler.onActivate()
		end
		group.signals.OnActivated:Fire(new_handler, target_index)

		group.activeIndex = target_index

		-- 组级切换通知：作者可听 OnSwitchNext（事件单位挂父脚本下）+ s→c 广播
		--（UI 槽位跟随走 setSlotAbility 的 Removed/Added 通道，此通知仅为作者钩子/上层感知）
		group.signals.OnSwitchNext:Fire(new_handler, target_index)
		if group._managerHandler and group._managerHandler.notifySwitchNext then
			group._managerHandler.notifySwitchNext(group.slotIndex, target_index)
		end

		-- 切换冷却（回归路径不触发）
		if not is_revert and group.switchCooldown > 0 and new_handler.enterCD then
			new_handler.enterCD(group.switchCooldown)
		end

		-- 回归计时管理（仅 AfterCast + revertTime>0；Timer/Manual 忽略）
		if group.switchMode == AbilityConstants.SwitchMode.AfterCast and group.revertTime > 0 then
			if target_index == 1 then
				cancel_revert_timer()
			elseif group.switchRefresh or group._revertTimer == nil then
				start_revert_timer()
			end
		end

		return true
	end

	-- Group.activateNext 主流程

	function group.activateNext()
		local new_index
		if group.switchOrder == AbilityConstants.SwitchOrder.Shuffle then
			new_index = _nextShuffle(group)
		elseif group.switchOrder == AbilityConstants.SwitchOrder.Random then
			new_index = _nextRandom(group)
		else
			new_index = _nextSequential(group)
		end

		if new_index == group.activeIndex then
			return false
		end

		local switched = _doSwitchTo(new_index, false)

		-- Timer 模式：重排下一次切换（句柄先置 nil 再建新）
		if switched and group.switchMode == AbilityConstants.SwitchMode.Timer then
			if group._timerHandler then
				Task:Cancel(group._timerHandler)
				group._timerHandler = nil
			end
			group._timerHandler = Task:Delay(group._timerDelay, function()
				group._timerHandler = nil
				if group._cleaning then
					return
				end
				group.activateNext()
			end)
		end

		return switched
	end

	function group.getActiveIndex()
		return group.activeIndex
	end

	function group.getActiveHandler()
		return group.members[group.activeIndex]
	end

	function group.switchTo(targetIndex)
		if targetIndex < 1 or targetIndex > #group.members then
			return false
		end
		if targetIndex == group.activeIndex then
			return false
		end
		return _doSwitchTo(targetIndex, false)
	end

	function group.getMembers()
		return group.members
	end

	function group.getSignals()
		return group.signals
	end

	-- 切换时机绑定

	if group.switchMode == AbilityConstants.SwitchMode.AfterCast then
		-- 任一成员施法结束（非打断）→ 仅当施法者是当前活跃成员时轮转
		--（全成员绑定 CastEnd；CastEnd 即正常结束，打断走 CastBreak）
		for _, member in ipairs(group.members) do
			local member_signals = member.getSignals and member.getSignals()
			if member_signals and member_signals.CastEnd then
				member_signals.CastEnd:Connect(function()
					if group._cleaning then
						return
					end
					if group.getActiveHandler() ~= member then
						return
					end
					group.activateNext()
				end)
			end
		end
	elseif group.switchMode == AbilityConstants.SwitchMode.Timer then
		-- 启动定时器
		group._timerHandler = Task:Delay(group._timerDelay, function()
			group._timerHandler = nil
			if group._cleaning then
				return
			end
			group.activateNext()
		end)
	end
	-- SwitchMode.Manual: 无自动轮转，仅显式调用 group.activateNext / switchTo 触发
	--（客户端 SwitchNext 请求经 server/api.lua SwitchNextAbility、ECA 积木 SwitchAbilityOnceAtSlot）

	-- 销毁（显式调用 + 成员销毁联动共用，_cleaning 防重入）

	function group.destroy()
		if group._cleaning then
			return
		end
		group._cleaning = true
		cancel_revert_timer()
		if group._timerHandler then
			Task:Cancel(group._timerHandler)
			group._timerHandler = nil
		end
		-- 触发 group 的 onDeactivated（让所有成员失活）
		for _, member in ipairs(group.members) do
			if member.onDeactivate then
				member.onDeactivate()
			end
		end
		-- 销毁组级事件单位（不依赖父子级联销毁）
		AbilityEventDefs.destroySignals(group.signals)
		-- 反注册 group
		if parent_script then
			AbilityRegistry.unregisterGroup(parent_script)
		end
		group.members = {}
	end

	-- 整组销毁联动：任一成员销毁 → 清组 → 可选连带销毁其余成员
	local function _bindDestroyCleanup(handler)
		local script = handler.getScript and handler.getScript()
		if not script or not script.Destroying then
			return
		end
		script.Destroying:Connect(function()
			if group._cleaning then
				return
			end
			local others = {}
			for _, member in ipairs(group.members) do
				if member ~= handler then
					others[#others + 1] = member
				end
			end
			group.destroy()
			if group.destroyWithMembers then
				for _, member in ipairs(others) do
					local member_script = member.getScript and member.getScript()
					if member_script and member_script.UnitId then
						pcall(function()
							member_script:Destroy()
						end)
					end
				end
			end
		end)
	end
	_bindDestroyCleanup(parentHandler)
	for _, childHandler in ipairs(childHandlers or {}) do
		_bindDestroyCleanup(childHandler)
	end

	return group
end

-- 把 child 加入已有 group

function SubAbilityHandler.addChild(group, childHandler)
	if group._childHandlersKeys[tostring(childHandler)] then
		return false -- 已存在
	end
	table.insert(group.members, childHandler)
	local child_script = childHandler.getScript and childHandler.getScript()
	if child_script then
		group._childHandlersKeys[AbilityRegistry.unitKeyOf(child_script)] = true
	end
	group._childHandlersKeys[tostring(childHandler)] = true
	-- 新增成员默认休眠（对齐建组语义）
	if group.shareSlot then
		local child_script = childHandler.getScript and childHandler.getScript()
		if child_script then
			child_script:SetAttribute("Index", AbilityConstants.SLOT_INDEX_UNASSIGNED)
		end
	end
	-- Shuffle 序列由 _nextShuffle 惰性逐轮重建，增删成员无需手动重洗
	return true
end

function SubAbilityHandler.removeChild(group, childHandler)
	local target_index = nil
	for i, handler in ipairs(group.members) do
		if handler == childHandler then
			target_index = i
			break
		end
	end
	if not target_index then
		return false
	end
	-- 不允许从主能力（index 1）remove
	if target_index == 1 then
		return false
	end
	local removed = group.members[target_index]
	local was_active = (target_index == group.activeIndex)

	-- 失活 + 休眠化被删成员
	if removed then
		if removed.onDeactivate then
			removed.onDeactivate()
		end
		group.signals.OnDeactivated:Fire(removed, target_index)
		if group.shareSlot then
			local removed_script = removed.getScript and removed.getScript()
			if removed_script then
				removed_script:SetAttribute("Index", AbilityConstants.SLOT_INDEX_UNASSIGNED)
			end
		end
	end

	table.remove(group.members, target_index)
	group._childHandlersKeys[tostring(childHandler)] = nil
	local removed_script = childHandler.getScript and childHandler.getScript()
	if removed_script then
		group._childHandlersKeys[AbilityRegistry.unitKeyOf(removed_script)] = nil
	end

	-- 调整 activeIndex；被删的是活跃成员时，新活跃成员上位（经管理器换槽，缓存/通知同步）
	if group.activeIndex > target_index then
		group.activeIndex = group.activeIndex - 1
	elseif was_active then
		group.activeIndex = math.max(1, group.activeIndex - 1)
		if group.shareSlot then
			local new_active = group.members[group.activeIndex]
			local new_active_script = new_active and new_active.getScript and new_active.getScript()
			if
				new_active_script
				and group._managerHandler
				and group._managerHandler.setSlotAbility
			then
				group._managerHandler.setSlotAbility(group.slotIndex, new_active_script)
			end
		end
	end
	return true
end

return SubAbilityHandler
