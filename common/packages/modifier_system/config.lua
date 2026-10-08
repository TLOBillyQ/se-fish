--效果系统包 - 配置表

local config = {}

-- 效果创建结果状态：AddModifier 等接口的返回值，
-- 调用方据此区分新增实例 / 叠加到已有实例 / 被规则拒绝 / 系统失败
config.CreateResult = {
	Added = "added",
	Reobtained = "reobtain",
	Rejected = "rejected",
	Failed = "failed",
}

-- 效果生命周期事件名：效果单位下的 BindableEvent 子单位名，供子脚本监听；
-- Modifier* 事件同时作为 ECA「效果自身事件」的绑定名；蛋码按 unit:FindFirstChild(事件名) 绑定
config.EventType = {
	BeforeObtain = "BeforeObtain",
	Obtain = "ModifierObtain",
	Loss = "ModifierLoss",
	Reobtain = "ModifierReobtain",
	StackChange = "StackChange",
	Pause = "Pause",
	Resume = "Resume",
	DurationFinish = "DurationFinish",
}

-- 运行时同步属性名：服务端 SetAttribute 写入，引擎自动同步到客户端
config.Attr = {
	IsActive = "IsActive",
	CurrCount = "CurrCount",
	CharMtg = "CharMtg",
	IsPaused = "IsPaused",
	EndTime = "EndTime",
	ModifierKey = "ModifierKey",
}

-- 拥有者容器事件名：拥有者单位下的 BindableEvent 子单位名；
-- ModifierObtainBefore 同时作为 ECA「生物即将获得效果」的绑定名
config.ManagerEvent = {
	ModifierAdded = "ModifierAdded",
	ModifierRemoved = "ModifierRemoved",
	ModifierRefresh = "ModifierRefresh",
	ObtainBefore = "ModifierObtainBefore",
}

-- 叠加层数策略：重新获得时层数如何变化
config.StackCountMode = {
	None = 0,
	Override = 1,
	Add = 2,
}

-- 叠加时间策略：重新获得时倒计时如何变化
config.StackDurationMode = {
	None = 0,
	Override = 1,
	Add = 2,
	StandAlone = 3,
}

-- 效果类型，与 UgcModifierType 三态一致
config.ModifierType = {
	Beneficial = 0,
	Harmful = 1,
	Neutral = 2,
}

-- 表现类型：区分获得/失去表现的不同形式
config.PerformanceType = {
	Effect = 0,
	Sound = 1,
	SkinMaterial = 2,
}

-- 单位标记：打在效果单位上，用于类型识别
config.Tag = {
	ModifierUnit = "ModifierUnit",
}

-- 跨端通信通道名：客户端与服务端通过同名通道拿到同一 RemoteEvent 实例
config.CHANNEL_NAME = "ModifierRemote"

-- 默认配置值
config.DEFAULT_MAX_MODIFIER_COUNT = 99
config.DEFAULT_DURATION = 5
config.DEFAULT_MAX_STACK_COUNT = 999
config.DEFAULT_STACK_COUNT_STEP = 1

return config
