--效果系统包 - 枚举
--供编辑器反射的枚举声明：结构体字段注解通过 style:modifierEnums.PerformanceType 引用，
--运行时代码不依赖本文件，配置类取值见 config.lua。

local modifierEnums = {}

---@export_enum
---@name 生效阵营
---@inherit Int
---@default 7
---@enum AffectCamp
modifierEnums.AffectCamp = {
	---@enumValue 自己
	Self = 1,
	---@enumValue 友军
	Friend = 2,
	---@enumValue 敌人
	Enemy = 4,
	---@enumValue 自己+友军
	SelfFriend = 3,
	---@enumValue 自己+敌人
	SelfEnemy = 5,
	---@enumValue 友军+敌人
	FriendEnemy = 6,
	---@enumValue 全部
	All = 7,
}

---@export_enum
---@name 表现形式
---@inherit Int
---@default 0
---@enum PerformanceType
modifierEnums.PerformanceType = {
	---@enumValue 特效
	Effect = 0,
	---@enumValue 音效
	Sound = 1,
	---@enumValue 皮肤材质替换
	SkinMaterial = 2,
}

---@export_enum
---@name 失去表现
---@inherit Int
---@default 0
---@enum LostPerformanceType
modifierEnums.LostPerformanceType = {
	---@enumValue 特效
	Effect = 0,
	---@enumValue 音效
	Sound = 1,
}

---@export_enum
---@name 特效挂点
---@inherit String
---@default "socket_origin"
---@enum EffectAttachPoint
modifierEnums.EffectAttachPoint = {
	---@enumValue 头部
	Head = "socket_head",
	---@enumValue 身体
	Spine = "socket_body",
	---@enumValue 底面中心
	Origin = "socket_origin",
	---@enumValue 左手武器
	LWeapon = "socket_weapon_l",
	---@enumValue 右手武器
	RWeapon = "socket_weapon_r",
	---@enumValue 左脚
	LFoot = "socket_foot_l",
	---@enumValue 右脚
	RFoot = "socket_foot_r",
	---@enumValue 左手
	LHand = "socket_hand_l",
	---@enumValue 右手
	RHand = "socket_hand_r",
	---@enumValue 左臂
	LForearm = "socket_forearm_l",
	---@enumValue 右臂
	RForearm = "socket_forearm_r",
}

---@export_enum
---@name 特效继承形式
---@inherit Int
---@default 7
---@enum EffectInherit
modifierEnums.EffectInherit = {
	---@enumValue 仅位置
	Position = 1,
	---@enumValue 仅旋转
	Rotation = 2,
	---@enumValue 仅缩放
	Scale = 4,
	---@enumValue 位置+旋转
	PositionRotation = 3,
	---@enumValue 位置+缩放
	PositionScale = 5,
	---@enumValue 旋转+缩放
	RotationScale = 6,
	---@enumValue 全部跟随
	All = 7,
}

---@export_enum
---@name 音效类别
---@inherit Int
---@default 1
---@enum SoundType
modifierEnums.SoundType = {
	---@enumValue 2D音效
	Sound2D = 0,
	---@enumValue 3D音效
	Sound3D = 1,
}

---@export_enum
---@name 皮肤材质
---@inherit Int
---@default 0
---@enum MaterialId
modifierEnums.MaterialId = {
	---@enumValue 无
	None = 0,
	---@enumValue 奶油蛋糕
	CreamCake = 1,
	---@enumValue 隐身
	Invisible = 2,
	---@enumValue 冰冻
	Freeze = 3,
	---@enumValue 无敌
	Invincible = 4,
	---@enumValue 剪影
	Outline = 5,
	---@enumValue 灵魂
	Ghost = 6,
	---@enumValue 穿梭之门
	Portal = 7,
	---@enumValue 测试
	Test = 8,
}

---@export_enum
---@name 属性名
---@inherit String
---@default ""
---@enum AttrKey
modifierEnums.AttrKey = {
	---@enumValue 移动速度
	WalkSpeed = "WalkSpeed",
	---@enumValue 跳跃垂直速度
	JumpPower = "JumpPower",
	---@enumValue 最大生命值
	MaxHealth = "MaxHealth",
	---@enumValue 生命值
	Health = "Health",
}

---@export_enum
---@name 属性分量类型
---@inherit Int
---@default 0
---@enum AttrType
modifierEnums.AttrType = {
	---@enumValue 基础值
	Base = 0,
	---@enumValue 基础额外值
	BaseExtra = 1,
	---@enumValue 加成比例
	Ratio = 2,
	---@enumValue 额外加成
	Bonus = 3,
}

---校验某个值是否是 AffectCamp 的合法成员。
---@param affectCamp any 待校验的值
---@return boolean 是否合法
local function isValidAffectCamp(affectCamp)
	for _, member in pairs(modifierEnums.AffectCamp) do
		if affectCamp == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 PerformanceType 的合法成员。
---@param performanceType any 待校验的值
---@return boolean 是否合法
local function isValidPerformanceType(performanceType)
	for _, member in pairs(modifierEnums.PerformanceType) do
		if performanceType == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 LostPerformanceType 的合法成员。
---@param lostPerformanceType any 待校验的值
---@return boolean 是否合法
local function isValidLostPerformanceType(lostPerformanceType)
	for _, member in pairs(modifierEnums.LostPerformanceType) do
		if lostPerformanceType == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 EffectAttachPoint 的合法成员。
---@param effectAttachPoint any 待校验的值
---@return boolean 是否合法
local function isValidEffectAttachPoint(effectAttachPoint)
	for _, member in pairs(modifierEnums.EffectAttachPoint) do
		if effectAttachPoint == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 EffectInherit 的合法成员。
---@param effectInherit any 待校验的值
---@return boolean 是否合法
local function isValidEffectInherit(effectInherit)
	for _, member in pairs(modifierEnums.EffectInherit) do
		if effectInherit == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 SoundType 的合法成员。
---@param soundType any 待校验的值
---@return boolean 是否合法
local function isValidSoundType(soundType)
	for _, member in pairs(modifierEnums.SoundType) do
		if soundType == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 MaterialId 的合法成员。
---@param materialId any 待校验的值
---@return boolean 是否合法
local function isValidMaterialId(materialId)
	for _, member in pairs(modifierEnums.MaterialId) do
		if materialId == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 AttrKey 的合法成员。
---@param attrKey any 待校验的值
---@return boolean 是否合法
local function isValidAttrKey(attrKey)
	for _, member in pairs(modifierEnums.AttrKey) do
		if attrKey == member then
			return true
		end
	end
	return false
end

---校验某个值是否是 AttrType 的合法成员。
---@param attrType any 待校验的值
---@return boolean 是否合法
local function isValidAttrType(attrType)
	for _, member in pairs(modifierEnums.AttrType) do
		if attrType == member then
			return true
		end
	end
	return false
end

local Enums = {
	AffectCamp = modifierEnums.AffectCamp,
	PerformanceType = modifierEnums.PerformanceType,
	LostPerformanceType = modifierEnums.LostPerformanceType,
	EffectAttachPoint = modifierEnums.EffectAttachPoint,
	EffectInherit = modifierEnums.EffectInherit,
	SoundType = modifierEnums.SoundType,
	MaterialId = modifierEnums.MaterialId,
	AttrKey = modifierEnums.AttrKey,
	AttrType = modifierEnums.AttrType,
	IsValidAffectCamp = isValidAffectCamp,
	IsValidPerformanceType = isValidPerformanceType,
	IsValidLostPerformanceType = isValidLostPerformanceType,
	IsValidEffectAttachPoint = isValidEffectAttachPoint,
	IsValidEffectInherit = isValidEffectInherit,
	IsValidSoundType = isValidSoundType,
	IsValidMaterialId = isValidMaterialId,
	IsValidAttrKey = isValidAttrKey,
	IsValidAttrType = isValidAttrType,
}

return Enums
