--技能系统 - server锚点运行时逻辑
-- 锚点预设壳在服务端 require 并调用 Attach(script)：读自身 StartTime/Duration/Phase，找宿主能力
--   （script.Parent），按 Phase=1 蓄力 / Phase=2 施法订阅宿主对应窗口事件，复用 Anchor.lua 调度；
--   锚点下挂 AnchorStart/Break/End/Stop 四事件单位；窗口结束/打断或宿主销毁时经事件语义清理。

local RunService = game:GetService("RunService")
local AbilityAnchor = require("common.packages.ability_system.Anchor")
local AbilityEventDefs = require("common.packages.ability_system.event_defs")

local AnchorLogic = {}
local _attached = setmetatable({}, { __mode = "k" })

-- 调度器依赖的宿主事件单位（ability_logic Attach 经 createAbilitySignals 产物）
local CAST_PHASE = 2 -- 与编辑器 AbilityPhaseType.CAST_PHASE 对齐
local ACCUMULATE_PHASE = 1 -- 与编辑器 AbilityPhaseType.ACCUMULATE_PHASE 对齐

local PHASE_REQUIRED_EVENTS = {
	[ACCUMULATE_PHASE] = { "AccumulateStart", "AccumulateBreak", "AccumulateEnd", "CastBreak" },
	[CAST_PHASE] = { "CastStart", "CastEnd", "CastBreak" },
}

-- 惰性信号视图：按事件名实时解析宿主下的 BindableEvent 单位
local function _buildSignalView(ability_script)
	return setmetatable({}, {
		__index = function(_, name)
			return ability_script:FindFirstChild(name)
		end,
	})
end

local function _signalsReady(ability_script, required)
	for _, name in ipairs(required) do
		if not ability_script:FindFirstChild(name) then
			return false
		end
	end
	return true
end

local function _readUnitId(script)
	local ok, unit_id = pcall(function()
		return script.UnitId
	end)
	if ok and unit_id then
		return unit_id
	end
	return tostring(script)
end

function AnchorLogic.Attach(script)
	if not RunService:IsServer() then
		return
	end
	if not script or _attached[script] then
		return
	end
	_attached[script] = true

	local ability_script = script.Parent
	if not ability_script then
		print("[AnchorLogic] anchor has no parent ability, skip: " .. tostring(script.Name))
		return
	end

	-- Phase 路由：Phase=1 蓄力阶段 / Phase=2 施法阶段，各自订阅对应窗口事件
	local phase = script:GetAttribute("Phase") or CAST_PHASE
	local required = PHASE_REQUIRED_EVENTS[phase]
	if not required then
		print(
			"[AnchorLogic] unsupported phase anchor, skip: "
				.. tostring(script.Name)
				.. " phase="
				.. tostring(phase)
		)
		return
	end

	local conf = {
		GroupId = _readUnitId(script),
		StartTime = script:GetAttribute("StartTime") or 0,
		Duration = script:GetAttribute("Duration") or 0,
		Phase = phase,
	}

	local signals = _buildSignalView(ability_script)
	-- 锚点级四事件单位挂在锚点自身下（监听方无需 groupId 过滤）
	local anchor_signals = AbilityEventDefs.createAnchorSignals(script)
	local anchor = nil
	local pending_connection = nil

	local function _start()
		if anchor then
			return
		end
		anchor = AbilityAnchor.new(conf, ability_script, signals, anchor_signals)
		print("[AnchorLogic] 锚点已挂载: " .. tostring(script.Name) ..
			" phase=" .. tostring(phase) .. " startTime=" .. tostring(conf.StartTime) ..
			" duration=" .. tostring(conf.Duration) .. " gid=" .. tostring(conf.GroupId))
	end

	if _signalsReady(ability_script, required) then
		_start()
	else
		-- 宿主信号单位就绪时序可能晚于锚点脚本：ChildAdded 重查，连接建立后再补查一次防竞态
		local function _tryStart()
			if anchor then
				return
			end
			if _signalsReady(ability_script, required) then
				if pending_connection then
					pending_connection:Disconnect()
					pending_connection = nil
				end
				_start()
			end
		end
		pending_connection = ability_script.ChildAdded:Connect(_tryStart)
		_tryStart()
	end

	-- 锚点子单位销毁：成对销毁调度器 + 断开等待连接 + 销毁锚点级事件单位
	script.Destroying:Connect(function()
		if pending_connection then
			pending_connection:Disconnect()
			pending_connection = nil
		end
		if anchor then
			anchor:Destroy()
			anchor = nil
		end
		if anchor_signals then
			AbilityEventDefs.destroySignals(anchor_signals)
			anchor_signals = nil
		end
	end)
end

return AnchorLogic
