--技能系统 - client技能槽位蓄力进度节点行为
--
-- 使用方式：Attach 模式 + Lua 侧 _nodeState 缓存（EUI userdata 不能挂字段）
-- + BindChildren 按名绑定子节点。
--
-- 节点结构约定（作者在编辑器摆放）：
--   [根节点] custom_kv: UIType="AbilityAccumulateNode"（全局共享单例，无需 Index，
--     当前蓄力的技能驱动其进度）
--     └─ ProgressTimer (EUIProgressTimer) ← 进度本体，SetPercent 驱动
--          └─ Icon (图标) ← 纯展示，仅绑引用不参与逻辑
--
-- 进度更新由服务端时间驱动的客户端 tick：
--   percent = min((serverTime - AccumulateStartTime) / MaxAccumulateTime, 1) * 100
--   走满 100 后保持满格（停表但不清零），由 StopAccumulate 统一停表隐藏。

local EuiAdapter = require("client.packages.ability_system.ui.eui_adapter")

local AccumulateNode = {}
AccumulateNode.__index = AccumulateNode

local Task = game:GetService("Task")
local World = game:GetService("World")

-- Lua 侧节点状态缓存（EUI userdata 不能挂字段）

local _nodeState = {} -- [node] = state table

local function getState(node)
	if not _nodeState[node] then
		_nodeState[node] = {
			attached = false,
			timer = nil, -- Task:Delay 句柄（进度刷新）
			gen = 0, -- 代际标记，防止旧定时器回调污染新状态
			start_time = 0, -- 服务端 AccumulateStartTime（服务器时间戳）
			max_time = 1.0, -- MaxAccumulateTime（秒）
			ProgressTimer = nil,
			Icon = nil,
		}
	end
	return _nodeState[node]
end

-- Attach：把行为初始化挂到节点上（幂等）

function AccumulateNode.Attach(node)
	if not node then
		return nil
	end
	local st = getState(node)
	if st.attached then
		return node
	end
	st.attached = true

	AccumulateNode.BindChildren(node)

	st.timer = nil
	st.gen = 0
	st.start_time = 0
	st.max_time = 1.0

	-- 蓄力节点默认隐藏，纯展示不可触摸
	EuiAdapter.SetVisible(node, false)
	EuiAdapter.SetTouchEnabled(node, false)
	return node
end

-- 子节点字段绑定（按名/能力查找）

-- 取可直接 SetPercent 的进度节点：
-- 根节点自身就是 EUIProgressTimer 时直接用；否则取第一个带 SetPercent 的后代
-- （兼容扁平 EUIProgressTimer 与 Layout 容器嵌套）。
local function _resolveTimer(node)
	if type(node.SetPercent) == "function" then
		return node
	end
	local descendants = EuiAdapter.GetDescendants(node)
	for _, child in ipairs(descendants) do
		if type(child.SetPercent) == "function" then
			return child
		end
	end
	return nil
end

function AccumulateNode.BindChildren(node)
	if not node then
		return
	end
	local st = getState(node)
	st.ProgressTimer = _resolveTimer(node)
	-- Icon 纯展示：按名绑引用，当前不参与逻辑
	st.Icon = EuiAdapter.FindFirstChild(node, "Icon")
end

-- 供 UIManager 等外部读取已解析的子节点引用（避免直接碰 userdata 字段）
function AccumulateNode.GetState(node)
	return getState(node)
end

-- 蓄力进度

-- 开始蓄力展示：startTime = 服务端 AccumulateStartTime，maxTime = MaxAccumulateTime
function AccumulateNode.StartAccumulate(node, startTime, maxTime)
	if not node then
		return
	end
	local st = getState(node)
	st.gen = st.gen + 1
	AccumulateNode._StopTimer(node)
	st.start_time = startTime or 0
	st.max_time = (maxTime and maxTime > 0) and maxTime or 1.0
	EuiAdapter.SetVisible(node, true)
	AccumulateNode._Update(node)
	AccumulateNode._StartTimer(node)
end

-- 刷新一次进度；返回是否继续刷新（走满后返回 false：保持满格等释放/取消）
function AccumulateNode._Update(node)
	local st = getState(node)
	if st.start_time <= 0 then
		return false
	end

	local elapsed = World:GetServerTime() - st.start_time
	local ratio = 0
	if st.max_time > 0 then
		ratio = elapsed / st.max_time
	end
	if ratio < 0 then
		ratio = 0
	end
	if ratio > 1 then
		ratio = 1
	end

	if st.ProgressTimer then
		EuiAdapter.SetPercent(st.ProgressTimer, ratio * 100)
	end

	-- 走满后停表保持满格
	if ratio >= 1 then
		return false
	end
	return true
end

function AccumulateNode._StartTimer(node)
	local st = getState(node)
	if st.timer then
		return
	end

	local gen = st.gen

	local function tick()
		if st.gen ~= gen then
			st.timer = nil
			return
		end
		if AccumulateNode._Update(node) then
			st.timer = Task:Delay(0.1, tick)
		else
			st.timer = nil
		end
	end

	st.timer = Task:Delay(0.1, tick)
end

function AccumulateNode._StopTimer(node)
	local st = getState(node)
	if st.timer then
		Task:Cancel(st.timer)
		st.timer = nil
	end
end

-- 停止蓄力展示（释放捕获后 / 取消蓄力）：停表 + 进度归零 + 隐藏
function AccumulateNode.StopAccumulate(node)
	if not node then
		return
	end
	local st = getState(node)
	st.gen = st.gen + 1
	AccumulateNode._StopTimer(node)
	st.start_time = 0
	if st.ProgressTimer then
		EuiAdapter.SetPercent(st.ProgressTimer, 0)
	end
	EuiAdapter.SetVisible(node, false)
end

-- 清理（节点销毁 / 解绑时清定时器）

function AccumulateNode.Cleanup(node)
	if not node then
		return
	end
	local st = getState(node)
	AccumulateNode._StopTimer(node)
	_nodeState[node] = nil
end

return AccumulateNode
