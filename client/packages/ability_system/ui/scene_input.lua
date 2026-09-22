--技能系统 - client场景输入路由器
-- 职责：把用户输入中的"场景点击"转换为屏幕坐标 Vector2 并转发给
-- 当前处于瞄准状态的两段式释放策略（TwoStageStrategy），用于第二阶段落点。
--
-- 契约：
--   local SceneInput = require("client.packages.ability_system.ui.scene_input")
--   local disconnect = SceneInput.Connect(strategy, uis)
--     * strategy: 须有 isAiming 字段与 OnSceneClick(screenPos) 方法
--     * uis: 类 UserInputService 实例（须有 InputBegan 信号，
--       回调签名 (inputObject, gameProcessedEvent)）
--   * 仅在 strategy.isAiming == true 且 gameProcessedEvent == false 时：
--       将 inputObject.Position（Vector3 屏幕坐标）转换为 Vector2(x, y)
--       并调用 strategy:OnSceneClick(Vector2)
--   * gameProcessedEvent == true（UI/引擎已消费）或 strategy 未在瞄准时：一律忽略
--
-- 只对"鼠标左键 / 触摸"两类输入路由（Enums.UserInputType.MouseButton1/Touch）；
-- 输入对象无 UserInputType 字段时不做类型过滤。

local SceneInput = {}

-- 允许路由的输入类型（无 UserInputType 字段时跳过过滤）
local function isSceneClickType(inputObject)
	if not inputObject then
		return false
	end
	local inputType = inputObject.UserInputType
	if inputType == nil then
		return true
	end
	if Enums and Enums.UserInputType then
		return inputType == Enums.UserInputType.MouseButton1
			or inputType == Enums.UserInputType.Touch
	end
	return true
end

-- 连接场景输入路由；返回 disconnect() 函数，调用后不再转发
function SceneInput.Connect(strategy, uis)
	if not strategy or not uis or not uis.InputBegan then
		return function() end
	end

	local connection = uis.InputBegan:Connect(function(inputObject, gameProcessedEvent)
		if not strategy.isAiming then
			return
		end
		if gameProcessedEvent then
			return
		end
		if not isSceneClickType(inputObject) then
			return
		end

		local pos = inputObject and inputObject.Position
		if not pos then
			return
		end
		strategy:OnSceneClick(Vector2.New(pos.x, pos.y))
	end)

	return function()
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
end

return SceneInput
