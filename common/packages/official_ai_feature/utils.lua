--生物AI包 - 纯函数工具集
--无状态、无副作用；双端各加载一份。

local utils = {}

---单位有效性：nil 或 Parent 为 nil（已销毁/未挂载）视为无效
---@param unit Unit? 目标单位
---@return Bool 是否有效
function utils.isValidUnit(unit)
	if unit == nil then
		return false
	end
	return unit.Parent ~= nil
end

---向量归一化，返回新向量（不修改入参）。
---有的环境提供 GetNormalized（返回新向量），有的只有 Normalize（原地修改、不依赖返回值），
---这里统一兜底：优先 GetNormalized，否则按长度手工构造新向量，避免改到调用方传入的向量。
---@param v Vector3? 待归一化的向量
---@return Vector3? 单位向量；空值或零向量时返回 nil
function utils.normalized(v)
	if v == nil then
		return nil
	end
	if v.GetNormalized then
		return v:GetNormalized()
	end
	local len = v.Length and v:Length()
	if not len or len <= 0 then
		return nil
	end
	return math.Vector3(v.x / len, v.y / len, v.z / len)
end

---水平方向单位向量：由 fromPos 指向 toPos，忽略 Y 轴
---@param fromPos Vector3 起点
---@param toPos Vector3 终点
---@return Vector3? 单位向量；水平距离过近时返回 nil
function utils.horizontalDirection(fromPos, toPos)
	local offset = toPos - fromPos
	local horizontal = math.Vector3(offset.x, 0, offset.z)
	local len = horizontal:Length()
	if len <= 0.01 then
		return nil
	end
	return math.Vector3(horizontal.x / len, 0, horizontal.z / len)
end

return utils
