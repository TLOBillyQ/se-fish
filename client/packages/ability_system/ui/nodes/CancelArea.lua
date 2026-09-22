--技能系统 - clientCancelArea 取消施法区域节点行为
--
-- 使用方式：UIManager 拿到节点后调用 CancelArea.Attach(node)，之后以
-- CancelArea.xxx(node, ...) 形式调用。取消区无子节点约定：取消态高亮直接作用于根节点本体。
--
-- 注意：EUI 节点是引擎 userdata，禁止挂自定义字段，状态存 Lua 侧 _nodeState[node]。

local EuiAdapter = require("client.packages.ability_system.ui.eui_adapter")

local CancelArea = {}
CancelArea.__index = CancelArea

local _nodeState = {} -- [node] = { attached }

local function getState(node)
	if not _nodeState[node] then
		_nodeState[node] = {
			attached = false,
		}
	end
	return _nodeState[node]
end

-- Attach：把行为初始化挂到节点上（幂等）
function CancelArea.Attach(node)
	if not node then
		return nil
	end
	local st = getState(node)
	if st.attached then
		return node
	end
	st.attached = true
	return node
end

-- 取消态高亮（白色 ↔ 粉红），直接作用于根节点本体
function CancelArea.SetCancelState(node, cancel)
	if not node then
		return
	end
	local color = EuiAdapter.makeColor(255, 255, 255, 255)
	if cancel then
		color = EuiAdapter.makeColor(255, 192, 203, 255)
	end
	EuiAdapter.SetColor(node, color)
end

-- 供外部读取节点状态
function CancelArea.GetState(node)
	return getState(node)
end

return CancelArea
