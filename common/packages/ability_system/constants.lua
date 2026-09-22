--技能系统 - common常量与枚举
-- 双端共享，纯数据。

local AbilityConstants = {}

-- 事件类型（技能级 18 个事件）
AbilityConstants.EventType = {
	BeforeCast = "BeforeCast", -- 施法前（可拦截）
	CastStart = "CastStart", -- 施法开始
	CastEnd = "CastEnd", -- 施法完成
	CastBreak = "CastBreak", -- 施法被打断
	BeforeUse = "BeforeUse", -- 使用前（可拦截）
	Used = "Used", -- 使用后
	CDStart = "CDStart", -- 进入 CD
	CDEnd = "CDEnd", -- CD 结束
	Charge = "Charge", -- 充能 +1
	ChargeFull = "ChargeFull", -- 充能已满
	AccumulateStart = "AccumulateStart", -- 蓄力开始
	AccumulateBreak = "AccumulateBreak", -- 蓄力被打断（先于 AccumulateEnd）
	AccumulateEnd = "AccumulateEnd", -- 蓄力结束（任何退出路径必发）
	OnDowngrade = "OnDowngrade", -- 技能降级
	AnchorStart = "AnchorStart", -- 锚点开始（施法开始后按 StartTime 点火）
	AnchorBreak = "AnchorBreak", -- 锚点中断（施法被打断时未终结的锚点）
	AnchorEnd = "AnchorEnd", -- 锚点结束（Duration 到点或施法正常结束）
	AnchorStop = "AnchorStop", -- 锚点终结（Break/End 之后必发，统一收尾信号）
}

-- 事件类型（锚点级 4 个事件）
-- 事件单位挂在锚点子单位下：每个锚点自带一套，监听方无需 groupId 过滤
AbilityConstants.AnchorEvent = {
	AnchorStart = "AnchorStart", -- 锚点开始（施法开始后按 StartTime 点火）
	AnchorBreak = "AnchorBreak", -- 锚点中断（施法被打断时未终结的锚点）
	AnchorEnd = "AnchorEnd", -- 锚点结束（Duration 到点或施法正常结束）
	AnchorStop = "AnchorStop", -- 锚点终结（Break/End 之后必发，统一收尾信号）
}

-- 事件类型（管理器级）
AbilityConstants.ManagerEvent = {
	AbilityAdded = "AbilityAdded", -- 技能加入管理器
	AbilityRemoved = "AbilityRemoved", -- 技能移除管理器
	AbilityUpgraded = "AbilityUpgraded", -- 技能升级
	SwitchNext = "SwitchNext", -- 子技能切换
}

-- 指针类型（数值/名称对齐官方 enums.lua）
AbilityConstants.PointerType = {
	None = 0, -- 无指示器
	Rectangle = 1, -- 矩形
	Circle = 2, -- 圆形
	Sector = 3, -- 扇形
	Parabola = 4, -- 抛物线
}

-- 释放策略（数值/名称对齐官方 enums.lua，0 即默认松开施放）
AbilityConstants.ReleaseType = {
	Release = 0, -- 松开施放（拖拽瞄准 → 松开施法；未配置默认即此）
	Hold = 1, -- 按住持续施法（松开结束）
	TwoStage = 2, -- 两段式点击
	Press = 3, -- 按下瞬发
}

-- SwitchMode 子技能切换时机
AbilityConstants.SwitchMode = {
	AfterCast = "AfterCast", -- 施法结束触发切换
	Timer = "Timer", -- 定时触发
	Manual = "Manual", -- 仅手动
}

-- SwitchOrder 子技能切换顺序
AbilityConstants.SwitchOrder = {
	Sequential = "Sequential", -- 顺序循环
	Shuffle = "Shuffle", -- 固定洗牌
	Random = "Random", -- 每次随机
}

-- ChargeType 充能策略
AbilityConstants.ChargeType = {
	None = 0, -- 不自动充能
	WhenNotFull = 1, -- 使用次数不满时充能
	WhenEmpty = 2, -- 使用次数为 0 时充能
}

-- UseLimitation 使用限制位掩码
AbilityConstants.UseLimitation = {
	None = 0, -- 无限制
	InCast = 1, -- 施法中可用
	UnControllable = 2, -- 失控时可用
	Roll = 4, -- 滚动时可用
	Freezed = 8, -- 冰冻时可用
}

-- TargetType 目标类型
AbilityConstants.TargetType = {
	NoTarget = 0, -- 无目标
	Direction = 1, -- 方向
	Point = 2, -- 点
	Unit = 3, -- 单位
}

-- Rarity 稀有度
AbilityConstants.Rarity = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
}

-- 槽位编号体系（0 基、无上限）：合法槽位为 [SLOT_BASE, +∞)，没有最大槽位数概念。
-- 槽位校验 / 遍历 / UI 匹配必须经由这两个常量，禁止硬编码基数。
AbilityConstants.SLOT_BASE = 0
-- "未入槽"哨兵：尚未分配真实槽位时的过渡值，不是合法槽位。
AbilityConstants.SLOT_INDEX_UNASSIGNED = -1

-- 默认配置
AbilityConstants.DEFAULT_PICK_RANGE = 2.0
AbilityConstants.DEFAULT_CAST_TIME = 0.5
AbilityConstants.DEFAULT_CD_TIME = 3.0
AbilityConstants.DEFAULT_MAX_CHARGE_COUNT = 5

-- Tag 标记
AbilityConstants.Tag = {
	AbilityUnit = "AbilityUnit",
	AbilityManager = "AbilityManager",
}

-- UI 节点识别（custom_kv 的 UIType 值）：AbilitySlot / AbilityAccumulateNode 带 Index=<槽位号>，
-- AbilityCancelArea 为取消区单例（无需 Index）。
AbilityConstants.UIType = {
	AbilitySlot = "AbilitySlot",
	AccumulateNode = "AbilityAccumulateNode",
	CancelArea = "AbilityCancelArea",
}

-- RemoteEvent 通道名
AbilityConstants.CHANNEL_NAME = "AbilitySystem"

return AbilityConstants
