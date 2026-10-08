--属性规则包 - 枚举

local Enums = {}

---分量类型：一个属性的最终值由四种分量叠加而成。
---属性最终值公式：最终值 = (基础值 + 额外基础值) * (1 + 加成比例) + 额外加成
---@export_enum
---@enum AttrComponentType
---@name 属性分量类型
---@inherit Int
---@default 0
Enums.AttrComponentType = {
	---@enumValue 基础值
	Base = 0,
	---@enumValue 额外基础值
	BaseExtra = 1,
	---@enumValue 加成比例
	Ratio = 2,
	---@enumValue 额外加成
	Bonus = 3,
}

---分量类型的可读后缀：整型枚举落成自定义属性键名时映射成后缀，保持键名可读（如 WalkSpeedBase）
Enums.AttrComponentTypeSuffix = {
	[Enums.AttrComponentType.Base] = "Base",
	[Enums.AttrComponentType.BaseExtra] = "BaseExtra",
	[Enums.AttrComponentType.Ratio] = "Ratio",
	[Enums.AttrComponentType.Bonus] = "Bonus",
}

---校验某个值是否是 AttrComponentType 的合法成员。
---@param attrComponentType any 待校验的值
---@return Bool 是否合法
local function isValidAttrComponentType(attrComponentType)
	for _, member in pairs(Enums.AttrComponentType) do
		if attrComponentType == member then
			return true
		end
	end
	return false
end

Enums.IsValidAttrComponentType = isValidAttrComponentType

return Enums
