--技能系统 - server道具箱表现逻辑
-- 道具箱表现 · 服务端增强组件（可选挂载，技能本体的子 Script 节点形态）
-- 用法：在技能预设下挂一个子 Script 节点，SourceCode 贴同目录 item_box_shell.lua；
--       不需要道具箱表现的技能不挂该子节点即可，本组件完全可选。
-- 约定：属性一律 abilityScript:GetAttribute(...)；定时用 Task:Delay；
--       摘 UI 用 abilityScript:SetAttribute("Index", nil)；销毁用 abilityScript:Destroy()。

local AbilityConstants = require("common.packages.ability_system.constants")

local ItemBoxLogic = {}

-- 防重复挂载：同一 script 实例只 Attach 一次（弱键，实例销毁后自动释放）
local _attached = setmetatable({}, { __mode = "k" })

function ItemBoxLogic.Attach(script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end

	if _attached[script] then
		print("[item_box] Attach skipped (already attached): " .. tostring(script))
		return
	end
	_attached[script] = true
	print("[item_box] Attach start: " .. tostring(script))

	-- 宿主（只跟技能本体打交道）
	local abilityScript = script.Parent -- 技能本体 ScriptUnit

	if not abilityScript then
		print(
			"[item_box] WARN: script.Parent 不是技能本体（应挂为技能本体子节点）:",
			tostring(script)
		)
	end

	-- 宿主事件是技能本体下的 BindableEvent 子单位（ability_logic.Attach 里创建）。
	-- 子脚本可能先于父技能脚本执行（见 log 时序），此处不能一次性取 handler/signals，
	-- 否则事件单位尚不存在会永久漏订阅；改为延迟连接（惯例同 anchor_logic）。
	local REQUIRED_HOST_EVENTS = { "CastStart", "CastEnd", "CastBreak" }

	local function _hostEventsReady()
		if not abilityScript then
			return false
		end
		for _, name in ipairs(REQUIRED_HOST_EVENTS) do
			if not abilityScript:FindFirstChild(name) then
				return false
			end
		end
		return true
	end

	-- 内部常量

	local HoldAnimId = "official://animation/25862" -- 举横批，循环、半身

	-- OnCastEnd 立刻 _enterHoldState 会让 hold 循环抢占动画通道、截断放置动画尾巴
	local PostPlaceDelay = 0.3

	-- "技能用尽"后 Index=nil 摘 UI 到真正 Destroy 的延迟，保留 cast 跑完
	local DestroyDelay = 50.0

	-- 默认回退参数（GetAttribute 读不到时用）
	-- 字段名与数据壳 item_box_shell.lua 的 @type 声明逐字一致。

	local DEF = {
		HeadPrefab = nil,
		HeadOffset = Vector3.New(0.0, 2.0, 0.0),
		HeadRotation = Vector3.New(0.0, 0.0, 0.0),
		HeadScale = Vector3.New(1.0, 1.0, 1.0),
		PlaceAnimId = "official://animation/25205",
	}

	-- 内部状态（每实例闭包，互不串扰）

	local _bindModel = nil
	local _bindMount = nil
	local _postPlaceTimer = nil
	local _pendingDestroyTimer = nil
	local _stateConn = nil
	local _chargeConn = nil
	local _indexConn = nil
	local _connList = {} -- 需要清理的 connection 收集
	local _isHiddenByState = false

	-- 处于以下主状态时隐藏头顶模型：
	local HIDE_MODEL_STATES = {
		[Enums.ControllerStateType.EggyRush] = true, -- 蛋仔前仆（飞扑）
		[Enums.ControllerStateType.EggyRoll] = true, -- 蛋仔滚动
		[Enums.ControllerStateType.EggyLifted] = true, -- 被举起
		[Enums.ControllerStateType.EggyLiftStart] = true, -- 起手举人
		[Enums.ControllerStateType.EggyLiftThrow] = true, -- 投掷
	}

	local function _trackConn(conn)
		if conn then
			table.insert(_connList, conn)
		end
		return conn
	end

	-- 工具函数

	local function _getAttr(key, default)
		local v = script:GetAttribute(key)
		if v == nil then
			return default
		end
		return v
	end

	local function _getOwner()
		-- 子 Script.Parent = 技能本体；技能本体.Parent = AbilityManager；角色 = manager.Parent
		local m = script.Parent and script.Parent.Parent
		return m and m.Parent
	end

	local function _ownerInfo(ownerUnit)
		if not ownerUnit then
			return "nil"
		end
		local stateStr = "?"
		if ownerUnit.Controller and ownerUnit.Controller.GetState then
			local ok, s = pcall(function()
				return ownerUnit.Controller:GetState()
			end)
			if ok then
				stateStr = tostring(s)
			end
		end
		return string.format("Unit(id=%s,state=%s)", tostring(ownerUnit.UnitId or "?"), stateStr)
	end

	-- 充能判定：IsChargeConsuming 由技能壳 @type 声明，Attach 时初始化
	local function _isChargeable()
		if not abilityScript then
			return false
		end
		return abilityScript:GetAttribute("IsChargeConsuming") == true
	end

	local function _hasCharges()
		if not _isChargeable() then
			return true
		end
		return (abilityScript:GetAttribute("ChargeCount") or 0) > 0
	end

	-- 播放角色动画：isLoop 控制循环，isHalfBody 时按上半身骨骼过滤
	local function _playAnim(animId, isLoop, isHalfBody)
		if not animId or animId == "" then
			return
		end
		local ownerUnit = _getOwner()
		if not ownerUnit then
			return
		end
		local ok, err = pcall(function()
			if not ownerUnit.Animator then
				return
			end
			local track = ownerUnit.Animator:LoadAnimation(animId)
			if track == nil then
				return
			end
			-- 半身动画
			if isHalfBody then
				track.FilterType = 30 -- 上半身：Head(1<<1)|Trunk(1<<2)|LeftArm(1<<3)|RightArm(1<<4)
			end
			-- 循环控制
			if isLoop ~= nil then
				track.Looped = isLoop
			end
			track:Play(0.1, 1, 1)
		end)
		if not ok then
			print("[item_box] _playAnim ERROR:", err, animId)
		end
	end

	-- 停止角色动画
	local function _stopAnim(animId)
		if not animId or animId == "" then
			return
		end
		local ownerUnit = _getOwner()
		if not ownerUnit then
			return
		end
		local ok, err = pcall(function()
			if not ownerUnit.Animator then
				return
			end
			local track = ownerUnit.Animator:LoadAnimation(animId)
			if track ~= nil then
				track:Stop()
			end
		end)
		if not ok then
			print("[item_box] _stopAnim ERROR:", err, animId)
		end
	end

	-- 组件绑定

	-- 递归把预制件所有子节点的 CanCollide 置 false（仅设根节点不够）。
	local function _disableCollisionDeep(unit)
		if not unit then
			return
		end
		pcall(function()
			unit.CanCollide = false
		end)
		if unit.GetChildren then
			for _, child in ipairs(unit:GetChildren()) do
				_disableCollisionDeep(child)
			end
		end
	end

	-- WorldUnit 没有 Visible 属性，必须用 ModelVisible（BasePart 属性）。
	local function _updateModelVisible()
		if not _bindModel then
			return
		end
		local ownerUnit = _getOwner()
		if not ownerUnit or not ownerUnit.Controller then
			return
		end
		local shouldHide = HIDE_MODEL_STATES[ownerUnit.Controller:GetState()] == true

		if shouldHide and not _isHiddenByState then
			_bindModel.ModelVisible = false
			_stopAnim(HoldAnimId)
			_isHiddenByState = true
		elseif not shouldHide and _isHiddenByState then
			_bindModel.ModelVisible = true
			_playAnim(HoldAnimId, true, true)
			_isHiddenByState = false
		end
	end

	-- 挂点：与锚点 add_bind_diy_model 的 SocketType 默认值一致（Enums.SkeletalSocketType.Origin）
	local HEAD_SOCKET = "origin"

	-- 反射值可能是 Vector3，也可能是裸表 {x,y,z} / {0,0,0}，统一成三个数字
	local function _vec3(v)
		if v == nil then
			return 0.0, 0.0, 0.0
		end
		local x = v.x
		if x == nil then x = v[1] end
		local y = v.y
		if y == nil then y = v[2] end
		local z = v.z
		if z == nil then z = v[3] end
		return x or 0.0, y or 0.0, z or 0.0
	end

	local function _bindHeadComponent()
		if _bindModel then
			return
		end
		local prefab = _getAttr("HeadPrefab", DEF.HeadPrefab)
		if not prefab then
			print("[item_box] _bindHeadComponent ERROR: HeadPrefab is nil")
			return
		end
		local ownerUnit = _getOwner()
		if not ownerUnit then
			return
		end

		local offset = _getAttr("HeadOffset", DEF.HeadOffset)
		local rotation = _getAttr("HeadRotation", DEF.HeadRotation)
		local scale = _getAttr("HeadScale", DEF.HeadScale)

		local ox, oy, oz = _vec3(offset)
		local rx, ry, rz = _vec3(rotation)
		local sx, sy, sz = _vec3(scale)
		-- 零缩放/缺省会导致模型不可见，兜底为 1
		if sx == 0 then sx = 1 end
		if sy == 0 then sy = 1 end
		if sz == 0 then sz = 1 end

		local World = game:GetService("World")

		-- 骨骼挂点 + 资产（world_extend 公开通道在 SE 沙盒不可用，挂点方案同 melee_hit）
		local ok, modelOrErr, mountOrErr = pcall(function()
			local mount = World:CreateUnit("SkeletalSocketMount", {
				Name = "ItemBoxMount_" .. tostring(ownerUnit.UnitId),
				Parent = ownerUnit,
				SocketName = HEAD_SOCKET,
				SocketOffset = math.Vector3(ox, oy, oz),
				-- 必须 3 数字参数形式：math.Quaternion(Vector3) 在本引擎下返回 identity
				SocketRotation = math.Quaternion(math.rad(rx), math.rad(ry), math.rad(rz)),
			})
			if not mount then
				return nil, nil
			end

			local assets = World:CreateAsset(prefab)
			local unit = assets and assets[1]
			if not unit then
				pcall(function() mount:Destroy() end)
				return nil, nil
			end

			unit.Parent = mount
			unit.Scale = math.Vector3(sx, sy, sz)
			if unit.ModelVisible ~= nil then unit.ModelVisible = true end
			if unit.PhysicsActive ~= nil then unit.PhysicsActive = false end
			if unit.CanCollide ~= nil then unit.CanCollide = false end
			if unit.CanTouch ~= nil then unit.CanTouch = false end
			if unit.CanTrigger ~= nil then unit.CanTrigger = false end
			if unit.CanQuery ~= nil then unit.CanQuery = false end
			return unit, mount
		end)
		if not ok then
			print("[item_box] _bindHeadComponent ERROR:", modelOrErr)
			return
		end
		if not modelOrErr then
			print("[item_box] _bindHeadComponent FAILED: mount/model nil, HeadPrefab =", tostring(prefab))
			return
		end
		_bindModel = modelOrErr
		_bindMount = mountOrErr

		-- 头顶组件仅作展示，不应参与物理碰撞（避免顶到天花板/挡角色/被其他物理体推动）
		_disableCollisionDeep(_bindModel)

		if _bindModel and ownerUnit.Controller then
			_stateConn = _trackConn(ownerUnit.Controller.StateChanged:Connect(function()
				local ok2, err = pcall(_updateModelVisible)
				if not ok2 then
					print("[item_box] StateChanged ERROR:", err)
				end
			end))
			_updateModelVisible()
		end
	end

	local function _unbindHeadComponent()
		if _stateConn then
			_stateConn:Disconnect()
			_stateConn = nil
		end
		if _bindModel then
			-- 模型挂在挂点下，先销毁模型再销毁挂点
			pcall(function() _bindModel:Destroy() end)
			_bindModel = nil
		end
		if _bindMount then
			pcall(function() _bindMount:Destroy() end)
			_bindMount = nil
		end
		_isHiddenByState = false
	end

	-- 状态切换

	local function _enterHoldState()
		if not _hasCharges() then
			print(
				"[item_box] _enterHoldState SKIPPED: no charges (ChargeCount=",
				tostring(abilityScript and abilityScript:GetAttribute("ChargeCount")),
				")"
			)
			return
		end
		_playAnim(HoldAnimId, true, true)
		_bindHeadComponent()
	end

	local function _exitHoldState()
		_stopAnim(HoldAnimId)
		_unbindHeadComponent()
	end

	-- 事件回调

	-- 注意：Task:Delay 返回的句柄只能用 Task:Cancel 取消。
	local function _cancelPostPlaceTimer()
		if _postPlaceTimer then
			local Task = game:GetService("Task")
			Task:Cancel(_postPlaceTimer)
			_postPlaceTimer = nil
		end
	end

	local function _cancelPendingDestroy()
		if _pendingDestroyTimer then
			local Task = game:GetService("Task")
			Task:Cancel(_pendingDestroyTimer)
			_pendingDestroyTimer = nil
		end
	end

	-- 摘 UI：把技能本体的 Index attribute 置 nil 触发客户端 AttributeChangedSignal，
	-- uiManager:UnBindAbility 立刻解绑技能槽位图标。幂等。
	local function _hideSkillIcon()
		if not abilityScript then
			return
		end
		if abilityScript:GetAttribute("Index") == nil then
			return
		end
		print(
			"[item_box] _hideSkillIcon: was Index=",
			tostring(abilityScript:GetAttribute("Index"))
		)
		abilityScript:SetAttribute("Index", nil)
	end

	-- 延时 DestroyDelay 后真正销毁技能本体 ScriptUnit（重复调度幂等）。
	-- 摘 UI 由 _hideSkillIcon 先于本函数调用，否则图标会等 Destroy 时才消失。
	-- 不能用 manager:removeAbility（会同步打断 cast）。
	local function _scheduleDelayedDestroy(reason)
		if _pendingDestroyTimer then
			return
		end
		print("[item_box] _scheduleDelayedDestroy: reason=", reason, "delay=", DestroyDelay, "s")
		local Task = game:GetService("Task")
		_pendingDestroyTimer = Task:Delay(DestroyDelay, function()
			_pendingDestroyTimer = nil
			print(
				"[item_box] delayed destroy fired, Destroy abilityScript=",
				tostring(abilityScript)
			)
			if abilityScript then
				abilityScript:Destroy()
			end
		end)
	end

	local function _disconnectChargeWatch()
		if _chargeConn then
			_chargeConn:Disconnect()
			_chargeConn = nil
		end
	end

	-- ChargeCount: 0 → >0 自动回到持有态；>0 → 0 放下箱子，并对不可恢复（ChargeType==0）调度延时销毁。
	-- 充能属性挂在技能本体上，这里监听 abilityScript 的 ChargeCount 变化。
	local function _connectChargeWatch()
		_disconnectChargeWatch()
		if not abilityScript then
			return
		end
		if not _isChargeable() then
			return
		end
		local signal = abilityScript:GetAttributeChangedSignal("ChargeCount")
		if not signal then
			return
		end
		_chargeConn = _trackConn(signal:Connect(function()
			local count = abilityScript:GetAttribute("ChargeCount") or 0
			print("[item_box] ChargeCount ->", count, "bindModel=", tostring(_bindModel))
			if count > 0 and not _bindModel then
				-- 回持有态统一走 PostPlaceDelay：CastStart 解绑模型后 ChargeCount 立刻变化，
				-- 若此刻直接 _enterHoldState，hold 循环动画会抢占动画通道，把放置/挥击动画截断
				-- （现象：施法有日志但角色「没动作」）。
				if _postPlaceTimer == nil then
					local Task = game:GetService("Task")
					_postPlaceTimer = Task:Delay(PostPlaceDelay, function()
						_postPlaceTimer = nil
						_enterHoldState()
					end)
				end
			elseif count <= 0 then
				_cancelPostPlaceTimer()
				-- 若箱子还顶着（如外部改 ChargeCount 触发的场景），放下箱子。
				if _bindModel then
					_exitHoldState()
				end
				-- 不可恢复的充能技能（ChargeType==0）：摘 UI + 调度延时销毁。
				-- 此分支不依赖 _bindModel 状态（CastStart 可能已解绑模型），照常执行。
				if (abilityScript:GetAttribute("ChargeType") or 0) == 0 then
					_hideSkillIcon()
					_scheduleDelayedDestroy("charges exhausted (non-rechargeable)")
				end
			end
		end))
	end

	-- 技能事件回调（由技能本体 signals 转发）

	-- 入槽：进入持有态 + 监听充能
	local function _onAbilityAdded()
		print(
			"[item_box] OnAbilityAdded owner=",
			_ownerInfo(_getOwner()),
			"IsChargeConsuming=",
			tostring(abilityScript and abilityScript:GetAttribute("IsChargeConsuming")),
			"ChargeCount=",
			tostring(abilityScript and abilityScript:GetAttribute("ChargeCount")),
			"MaxChargeCount=",
			tostring(abilityScript and abilityScript:GetAttribute("MaxChargeCount"))
		)
		_cancelPostPlaceTimer()
		_connectChargeWatch()
		_enterHoldState()
	end

	-- CastStart：播放放置动画 + 解绑模型
	local function _onCastStart()
		local placeAnim = _getAttr("PlaceAnimId", DEF.PlaceAnimId)
		print("[item_box] OnCastStart owner=", _ownerInfo(_getOwner()), "PlaceAnimId=", placeAnim)
		_cancelPostPlaceTimer()
		-- 非充能技能：cast 一开始就摘 UI，让玩家点击瞬间感知图标消失；
		-- 真正销毁推迟到 CastEnd（_scheduleDelayedDestroy + 50s）等放置动画演完
		if not _isChargeable() then
			_hideSkillIcon()
		end
		_stopAnim(HoldAnimId)
		-- 全身动画（弯腰 + 放下）
		_playAnim(placeAnim, false, false)
		_unbindHeadComponent()
	end

	-- CastEnd：可充能技能 0.3s 后回持有态；非充能技能延时销毁
	local function _onCastEnd()
		_cancelPostPlaceTimer()
		if not _isChargeable() then
			_scheduleDelayedDestroy("non-chargeable, one-shot done")
			return
		end
		print("[item_box] OnCastEnd, _enterHoldState in", PostPlaceDelay, "s")
		local Task = game:GetService("Task")
		_postPlaceTimer = Task:Delay(PostPlaceDelay, function()
			_postPlaceTimer = nil
			_enterHoldState()
		end)
	end

	-- 移除：回收全部状态
	local function _onAbilityRemoved()
		print("[item_box] OnAbilityRemoved")
		_cancelPostPlaceTimer()
		_cancelPendingDestroy()
		_disconnectChargeWatch()
		_exitHoldState()
	end

	-- 订阅技能级事件（等宿主 BindableEvent 子单位齐套再连）
	-- 子脚本先于父技能脚本执行时，CastStart/CastEnd/CastBreak 子单位尚不存在，
	-- 用 ChildAdded 等待齐套后再连接（惯例同 anchor_logic），连接一次后幂等。

	local _hostEventsConnected = false
	local _hostEventsPending = nil

	local function _connectHostEvents()
		if _hostEventsConnected or not _hostEventsReady() then
			return
		end
		_hostEventsConnected = true
		if _hostEventsPending then
			_hostEventsPending:Disconnect()
			_hostEventsPending = nil
		end
		_trackConn(abilityScript:FindFirstChild("CastStart"):Connect(function()
			local ok2, err = pcall(_onCastStart)
			if not ok2 then
				print("[item_box] CastStart ERROR:", err)
			end
		end))
		_trackConn(abilityScript:FindFirstChild("CastEnd"):Connect(function()
			local ok2, err = pcall(_onCastEnd)
			if not ok2 then
				print("[item_box] CastEnd ERROR:", err)
			end
		end))
		_trackConn(abilityScript:FindFirstChild("CastBreak"):Connect(function()
			-- 打断施法：同样回持有态
			local ok2, err = pcall(_onCastEnd)
			if not ok2 then
				print("[item_box] CastBreak ERROR:", err)
			end
		end))
		print("[item_box] host events connected")
	end

	if _hostEventsReady() then
		_connectHostEvents()
	elseif abilityScript and abilityScript.ChildAdded then
		_hostEventsPending = abilityScript.ChildAdded:Connect(_connectHostEvents)
		_connectHostEvents() -- 连接建立后再补查一次，防竞态
	end

	-- 「技能已加入槽位」：监听技能本体 Index 属性变化
	-- manager_logic.addAbility 会 SetAttribute("Index", slotIndex)。

	local function _tryInitOnIndexSet()
		if not abilityScript then
			return
		end
		local index = abilityScript:GetAttribute("Index")
		if index and index >= AbilityConstants.SLOT_BASE then
			local ok2, err = pcall(_onAbilityAdded)
			if not ok2 then
				print("[item_box] init-by-Index ERROR:", err)
			end
			return true
		end
		return false
	end

	if abilityScript and abilityScript.GetAttributeChangedSignal then
		local sig = abilityScript:GetAttributeChangedSignal("Index")
		if sig then
			_indexConn = _trackConn(sig:Connect(function(newVal)
				if newVal and newVal >= AbilityConstants.SLOT_BASE then
					-- 一次生效后断开，避免重复初始化
					if _indexConn then
						_indexConn:Disconnect()
						_indexConn = nil
					end
					_tryInitOnIndexSet()
				end
			end))
		end
	end

	-- 兜底：若子 Script Attach 时 Index 已设置（技能已加入槽位，如场景预摆放），直接初始化
	if not _tryInitOnIndexSet() then
		-- 未加入槽位：等待上方 Index 变化监听触发
	end

	-- 「技能移除」：监听技能本体 Destroying
	-- removeAbility 后技能本体会被 Destroy（api.lua RemoveAbility）。

	if abilityScript and abilityScript.Destroying then
		_trackConn(abilityScript.Destroying:Connect(function()
			local ok2, err = pcall(_onAbilityRemoved)
			if not ok2 then
				print("[item_box] ability Destroying ERROR:", err)
			end
		end))
	end

	-- 销毁清理（回收 timer / conn / 组件）

	script.Destroying:Connect(function()
		print("[item_box] Destroying clean up")
		_cancelPostPlaceTimer()
		_cancelPendingDestroy()
		_disconnectChargeWatch()
		if _hostEventsPending then
			_hostEventsPending:Disconnect()
			_hostEventsPending = nil
		end
		if _indexConn then
			_indexConn:Disconnect()
			_indexConn = nil
		end
		for _, conn in ipairs(_connList) do
			if conn and conn.Disconnect then
				pcall(function()
					conn:Disconnect()
				end)
			end
		end
		_connList = {}
		_exitHoldState()
		_attached[script] = nil
	end)

	print("[item_box] Attach complete: " .. tostring(script))
end

return ItemBoxLogic
