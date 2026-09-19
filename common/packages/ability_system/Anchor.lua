--技能系统 - common锚点调度器
-- 按 Phase 自订阅窗口事件：Phase=2 施法（CastStart/CastEnd/CastBreak）、Phase=1 蓄力
--   （AccumulateStart/AccumulateBreak/AccumulateEnd，销毁兜底 CastBreak）。
-- 按 StartTime 点火 AnchorStart；正常结束派 AnchorEnd、打断派 AnchorBreak，之后必发 AnchorStop。

---锚点调度器：按阶段订阅宿主窗口事件，驱动单个锚点的点火 / 终结 / 中断。
---@class Anchor
---@field groupId integer 锚点组 Id（一般取锚点单位 UnitId）
---@field startTime number 点火延迟（秒）
---@field duration number 持续时长（秒，0=保持到窗口结束）
---@field phase integer 所属阶段（1 蓄力 / 2 施法）
---@field _ability Script 宿主技能脚本单位
---@field _signals table 技能级事件单位集合
---@field _anchorSignals table? 锚点级事件单位集合
---@field _task Timer Task 服务
---@field _isRunning boolean 是否已点火
---@field _startTimer any 点火排程句柄
---@field _endTimer any 自然终结排程句柄
---@field _connections Connection[] 自订阅连接句柄
local Anchor = {}
Anchor.__index = Anchor

-- 锚点所属时间轴阶段（与编辑器 AbilityPhaseType 对齐）
local PHASE_ACCUMULATE = 1
local PHASE_CAST = 2

function Anchor.new(anchorConf, abilityScript, signals, anchorSignals)
	local obj = setmetatable({}, Anchor)

	obj.groupId = anchorConf.GroupId
	obj.startTime = anchorConf.StartTime or 0
	obj.duration = anchorConf.Duration or 0
	obj.phase = anchorConf.Phase or PHASE_CAST
	obj._ability = abilityScript
	obj._signals = signals
	-- 锚点级 signals（挂在锚点子单位下，每个锚点自带一套；nil 时仅发技能级事件）
	obj._anchorSignals = anchorSignals
	obj._task = game:GetService("Task")
	obj._isRunning = false
	obj._startTimer = nil
	obj._endTimer = nil
	obj._connections = {} -- 自订阅连接句柄（Destroy 时成对断开）
	obj:_registerEvents()
	return obj
end

function Anchor:_registerEvents()
	if self.phase == PHASE_ACCUMULATE then
		-- 蓄力阶段窗口：进入蓄力 → 排程点火；蓄力结束 → 自然终结；被打断 → Break。
		-- AccumulateBreak 先于 AccumulateEnd 发：Break 先收尾，随后 End 因已停而空跑。
		self:_connect("AccumulateStart", function()
			self:beginProcess()
		end)
		self:_connect("AccumulateBreak", function()
			self:finishCast(true)
		end)
		self:_connect("AccumulateEnd", function()
			self:finishCast(false)
		end)
		-- 能力中途销毁兜底：销毁时先发 CastBreak 再拆信号
		self:_connect("CastBreak", function()
			self:finishCast(true)
		end)
		return
	end

	-- 施法阶段窗口（默认）
	self:_connect("CastStart", function()
		self:beginProcess()
	end)
	self:_connect("CastEnd", function()
		self:finishCast(false)
	end)
	self:_connect("CastBreak", function()
		self:finishCast(true)
	end)
end

function Anchor:_connect(name, func)
	local sig = self._signals[name]
	if sig then
		self._connections[#self._connections + 1] = sig:Connect(func)
	end
end

function Anchor:_fire(name)
	local sig = self._signals[name]
	if sig then
		sig:Fire(self._ability, self.groupId)
	end
	-- 锚点级事件：主体是锚点自身，监听方无需 groupId 过滤，载荷=宿主 abilityScript
	local anchor_sig = self._anchorSignals and self._anchorSignals[name]
	if anchor_sig then
		anchor_sig:Fire(self._ability)
	end
end

function Anchor:_clearTimers()
	if self._startTimer then
		self._task:Cancel(self._startTimer)
		self._startTimer = nil
	end
	if self._endTimer then
		self._task:Cancel(self._endTimer)
		self._endTimer = nil
	end
end

-- 施法开始：StartTime>0 排程点火，否则立即点火；持续锚点（Duration>0）再排自然终结
function Anchor:beginProcess()
	if self.startTime > 0 then
		self._startTimer = self._task:Delay(self.startTime, function()
			self:start()
		end)
	else
		self:start()
	end
end

function Anchor:start()
	if self._isRunning then
		return
	end
	self._isRunning = true
	self:_fire("AnchorStart")
	if self.duration > 0 then
		-- 有结束时间就认为是持续锚点
		self._endTimer = self._task:Delay(self.duration, function()
			self:finish()
		end)
	end
end

-- 施法结束入口：无论是否已启动，先作废排程 timer 再按 isBreak 分派 Break/End
function Anchor:finishCast(isBreak)
	self:_clearTimers()
	if isBreak then
		self:onBreak()
	else
		self:finish()
	end
end

function Anchor:onBreak()
	if not self._isRunning then
		return
	end
	self:_fire("AnchorBreak")
	self:stop()
end

-- Duration 到点的自然终结路径
function Anchor:finish()
	if not self._isRunning then
		return
	end
	self:_fire("AnchorEnd")
	self:stop()
end

-- 终结收尾：清 timer → AnchorStop → 复位运行标记
function Anchor:stop()
	if not self._isRunning then
		return
	end
	self:_clearTimers()
	self:_fire("AnchorStop")
	self._isRunning = false
end

-- 销毁：清 timer + 断开自订阅连接
function Anchor:Destroy()
	self:_clearTimers()
	self._isRunning = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return Anchor
