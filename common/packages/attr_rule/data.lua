--属性规则包 - 数据结构体声明

---单条属性配置
---@export_struct
---@class AttrConfig
---@field AttrKey String 属性Key
---@field Default Float 默认值
---@field Min Float 最小值
---@field Max Float 最大值
---@field Icon String 属性图标
---@field TargetType String 目标类型
local AttrConfig = { AttrKey = "", Default = 0, Min = 0, Max = 999, Icon = "", TargetType = "" }

---单条属性初始值设置：把指定属性的初始值设为指定数值
---@export_struct
---@class AttrInitValue
---@field AttrKey String 属性Key
---@field Value Float 初始值
local AttrInitValue = { AttrKey = "", Value = 0 }

---单条属性加成配置
---@export_struct
---@class AttrBuffConfig
---@field AttrKey String 属性Key
---@field AttrComponentType Int 属性分量类型 style:Enums.AttrComponentType
---@field Value Float 属性值
local AttrBuffConfig = { AttrKey = "", AttrComponentType = 0, Value = 0 }

return {
	AttrConfig = AttrConfig,
	AttrInitValue = AttrInitValue,
	AttrBuffConfig = AttrBuffConfig,
}
