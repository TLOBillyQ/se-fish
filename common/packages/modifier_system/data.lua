--效果系统包 - 数据结构体声明
--供编辑器反射的结构体定义：预设字段以 ---@type List<modifier_system.ModifierAttrConfig> 引用本文件；
--运行时代码不依赖本文件，预设字段经 GetAttribute 读取。

---单条属性修改配置：效果激活时按分量类型把修改值累加到目标属性，失活时回滚
---@export_struct
---@title 效果属性配置
---@class ModifierAttrConfig
---@field AttrKey String 属性名 style:modifierEnums.AttrKey
---@field AttrType Int 分量类型 style:modifierEnums.AttrType
---@field Value Fixed 修改值
local ModifierAttrConfig = { AttrKey = "", AttrType = 0, Value = 0 }

---获得表现条目：效果激活时按表现形式播放特效/音效或替换皮肤材质
---@export_struct
---@title 效果获得表现
---@class ModifierObtainPerformanceInfo
---@field AffectCamp Int 生效阵营 style:modifierEnums.AffectCamp
---@field PerformanceType Int 表现形式 style:modifierEnums.PerformanceType
---@field EffectID String 特效 style:EfxResource
---@field EffectAttachPoint String 特效挂点 style:modifierEnums.EffectAttachPoint
---@field EffectInherit Int 特效继承形式 style:modifierEnums.EffectInherit
---@field EffectScale Fixed 特效缩放系数
---@field EffectFrameRate Fixed 特效速率
---@field IsLoop Bool 是否循环播放
---@field SoundID Int 音效 style:AudioResource
---@field SoundType Int 音效类别 style:modifierEnums.SoundType
---@field SoundDuration Fixed 音效持续时间
---@field SoundDistance Fixed 3D衰减范围
---@field Mtg Int 替换皮肤材质 style:modifierEnums.MaterialId
---@field DestroyWithModifier Bool 是否跟随效果销毁
---@visible_if {"field":"EffectID","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectAttachPoint","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectInherit","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectScale","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectFrameRate","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"IsLoop","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"SoundID","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"SoundType","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"SoundDuration","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"SoundDistance","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"Mtg","depends":"PerformanceType","op":"=","value":2}
---@visible_if {"field":"DestroyWithModifier","depends":"PerformanceType","op":"!=","value":2}
local ModifierObtainPerformanceInfo = {
	AffectCamp = 7,
	PerformanceType = 0,
	EffectID = "-1",
	EffectAttachPoint = "socket_origin",
	EffectInherit = 7,
	EffectScale = 1.0,
	EffectFrameRate = 1.0,
	IsLoop = false,
	SoundID = -1,
	SoundType = 1,
	SoundDuration = -1.0,
	SoundDistance = 10,
	Mtg = 0,
	DestroyWithModifier = true,
}

---失去表现条目：效果失活时按表现形式播放特效/音效
---@export_struct
---@title 效果失去表现
---@class ModifierLostPerformanceInfo
---@field AffectCamp Int 生效阵营 style:modifierEnums.AffectCamp
---@field PerformanceType Int 表现形式 style:modifierEnums.LostPerformanceType
---@field EffectID String 特效 style:EfxResource
---@field EffectAttachPoint String 特效挂点 style:modifierEnums.EffectAttachPoint
---@field EffectInherit Int 特效继承形式 style:modifierEnums.EffectInherit
---@field EffectScale Fixed 特效缩放系数
---@field EffectFrameRate Fixed 特效速率
---@field IsLoop Bool 是否循环播放
---@field SoundID Int 音效 style:AudioResource
---@field SoundType Int 音效类别 style:modifierEnums.SoundType
---@field SoundDuration Fixed 音效持续时间
---@field SoundDistance Fixed 3D衰减范围
---@visible_if {"field":"EffectID","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectAttachPoint","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectInherit","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectScale","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"EffectFrameRate","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"IsLoop","depends":"PerformanceType","op":"=","value":0}
---@visible_if {"field":"SoundID","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"SoundType","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"SoundDuration","depends":"PerformanceType","op":"=","value":1}
---@visible_if {"field":"SoundDistance","depends":"PerformanceType","op":"=","value":1}
local ModifierLostPerformanceInfo = {
	AffectCamp = 7,
	PerformanceType = 0,
	EffectID = "-1",
	EffectAttachPoint = "socket_origin",
	EffectInherit = 7,
	EffectScale = 1.0,
	EffectFrameRate = 1.0,
	IsLoop = false,
	SoundID = -1,
	SoundType = 1,
	SoundDuration = -1.0,
	SoundDistance = 10,
}

return {
	ModifierAttrConfig = ModifierAttrConfig,
	ModifierObtainPerformanceInfo = ModifierObtainPerformanceInfo,
	ModifierLostPerformanceInfo = ModifierLostPerformanceInfo,
}
