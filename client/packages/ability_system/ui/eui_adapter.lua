--技能系统 - clientEUI 节点操作适配层
-- 封装 EUI 节点的可见性/文本/颜色/位置等读写、颜色构造、节点树查找
-- 与本地玩家角色获取，让上层 UI 代码与节点读写方式解耦。

local EuiAdapter = {}

-- 颜色工具

-- 构造颜色对象（参数 0~255）
function EuiAdapter.makeColor(r, g, b, a)
	return Color.New(r, g, b, a or 255)
end

-- 节点属性读写

local function _hasMethod(node, methodName)
	return node ~= nil and type(node[methodName]) == "function"
end

function EuiAdapter.SetVisible(node, visible)
	if not node then
		return
	end
	if _hasMethod(node, "SetVisible") then
		local ok, result = pcall(function()
			return node:SetVisible(visible)
		end)
		if ok then
			return result
		end
	end
	local ok, result = pcall(function()
		node.Visible = visible
	end)
	if ok then
		return result
	end
	return nil
end

function EuiAdapter.GetVisible(node)
	if not node then
		return false
	end
	if _hasMethod(node, "GetVisible") then
		local ok, result = pcall(function()
			return node:GetVisible()
		end)
		if ok and result ~= nil then
			return result
		end
	end
	local ok, result = pcall(function()
		return node.Visible
	end)
	if ok and result ~= nil then
		return result
	end
	return false
end

-- image 为 nil 时跳过
function EuiAdapter.SetImage(node, image)
	if not node or image == nil then
		return
	end
	if _hasMethod(node, "SetImage") then
		node:SetImage(image)
	else
		node.Image = image
	end
end

function EuiAdapter.SetText(node, text)
	if not node then
		return
	end
	if _hasMethod(node, "SetText") then
		node:SetText(text)
	else
		node.Text = text
	end
end

function EuiAdapter.SetPercent(node, percent)
	if not node then
		return
	end
	if _hasMethod(node, "SetPercent") then
		node:SetPercent(percent)
	else
		node.Percent = percent
	end
end

function EuiAdapter.SetColor(node, color)
	if not node or color == nil then
		return
	end
	if _hasMethod(node, "SetColor") then
		node:SetColor(color)
	else
		node.Color = color
	end
end

function EuiAdapter.SetPosition(node, pos)
	if not node then
		return
	end
	if _hasMethod(node, "SetPosition") then
		node:SetPosition(pos)
	else
		node.Position = pos
	end
end

function EuiAdapter.GetPosition(node)
	if not node then
		return nil
	end
	if _hasMethod(node, "GetPosition") then
		return node:GetPosition()
	end
	return node.Position
end

function EuiAdapter.SetTouchEnabled(node, enabled)
	if not node then
		return
	end
	if _hasMethod(node, "SetTouchEnabled") then
		node:SetTouchEnabled(enabled)
	else
		node.TouchEnabled = enabled
	end
end

-- HitTest / ConvertToLocalPosition
function EuiAdapter.HitTest(node, pos)
	if not node or not _hasMethod(node, "HitTest") then
		return false
	end
	local ok, result = pcall(function()
		return node:HitTest(pos)
	end)
	if ok then
		return result
	end
	return false
end

function EuiAdapter.ConvertToLocalPosition(node, worldPos)
	if not node or not _hasMethod(node, "ConvertToLocalPosition") then
		return worldPos
	end
	local ok, result = pcall(function()
		return node:ConvertToLocalPosition(worldPos)
	end)
	if ok and result then
		return result
	end
	return worldPos
end

-- 节点树查找

function EuiAdapter.FindFirstChild(node, name, recursive)
	if not node then
		return nil
	end
	if _hasMethod(node, "FindFirstChild") then
		local ok, result = pcall(function()
			return node:FindFirstChild(name, recursive)
		end)
		if ok and result then
			return result
		end
	end
	-- GetChildByName 兜底（非递归）
	if _hasMethod(node, "GetChildByName") then
		local ok, result = pcall(function()
			return node:GetChildByName(name)
		end)
		if ok and result then
			return result
		end
	end
	if _hasMethod(node, "GetChildren") then
		for _, child in ipairs(node:GetChildren()) do
			local childName = child.Name or child.name
			if childName == name then
				return child
			end
			if recursive then
				local sub = EuiAdapter.FindFirstChild(child, name, recursive)
				if sub then
					return sub
				end
			end
		end
	end
	return nil
end

-- 深度遍历收集全部子节点
function EuiAdapter.GetDescendants(node)
	local result = {}
	if not node then
		return result
	end
	if _hasMethod(node, "GetDescendants") then
		return node:GetDescendants()
	end
	if _hasMethod(node, "GetChildren") then
		local function walk(n)
			for _, child in ipairs(n:GetChildren()) do
				table.insert(result, child)
				walk(child)
			end
		end
		walk(node)
	end
	return result
end

-- EuiManager / 根节点 / 玩家角色工具

-- 获取本地玩家的 EuiManager
function EuiAdapter.GetEuiManager()
	local player = game:GetService("Players").LocalPlayer
	if not player or not player.PlayerGui then
		return nil
	end
	return player.PlayerGui.EuiManager
end

-- 获取 UI 根节点（EUIRootNode）
function EuiAdapter.GetRootNode()
	local euiManager = EuiAdapter.GetEuiManager()
	if not euiManager or not _hasMethod(euiManager, "GetRootNode") then
		return nil
	end
	return euiManager:GetRootNode()
end

-- 获取玩家角色 UnitId（读 Character.UnitId）
function EuiAdapter.GetCharacterUnitId(player)
	if not player then
		return nil
	end
	if player.Character then
		return player.Character.UnitId
	end
	return nil
end

-- 本地玩家角色 Unit（用于归属判定）
function EuiAdapter.GetLocalCharacter()
	local player = game:GetService("Players").LocalPlayer
	if not player then
		return nil
	end
	return player.Character
end

return EuiAdapter
