--技能系统 - server技能实例预设壳
-- 技能实例服务端脚本（ScriptUnit，挂在 AbilityManager ScriptUnit 之下）
-- 数据化预设壳：仅保留编辑器可编辑的 @type 配置属性声明，
-- 服务端业务逻辑统一委派给 ability_logic.lua 的 Attach(script)（CD / 施法 / 蓄力 / 充能 四状态机）。

---@type 配置属性（编辑器中可编辑，作者创建预设时配置）
-- 运行时状态（InCD/InCast/CdFinishTime/ChargeCount 等）不在此声明，
-- 而是在 Attach() 中通过 SetAttribute 初始化，避免在属性面板暴露运行时字段。

---@type number 冷却时间
CdTime = 3.0
---冷却时间

---@type number 充能间隔 @visible_when IsChargeConsuming==true && ChargeType!=0
ChargeInterval = 1.0
---充能间隔

---@type boolean 能否升级
Upgradable = false
---能否升级

---@type integer 技能最大等级 @visible_when Upgradable==true
MaxLevel = 5
---技能最大等级

---@type Int[] 学习时需求角色等级 @visible_when Upgradable==true
LevelRequirements = {}
---学习时需求角色等级（下标=目标技能等级，值=所需角色等级）

---@type boolean 能否蓄力
EnableAccumulate = false
---能否蓄力

---@type number 满蓄力时间 @visible_when EnableAccumulate==true
MaxAccumulateTime = 1.0
---满蓄力时间

---@type number 施法时间
CastTime = 0.5
---施法时间

---@type Int
---@style enum
---@enum [[0,"None","无限制"],[1,"InCast","施法可用"],[2,"UnControllable","失控可用"],[4,"Roll","滚动可用"]]
---@title 使用限制
UseLimitation = 0
---使用限制

---@type Int
---@style enum
---@enum [[0,"Release","松开施放"],[1,"Hold","按住持续施法"],[2,"TwoStage","两段式点击"],[3,"Press","按下施放"]]
---@title 释放方式
ReleaseType = 0
---释放方式

---@type Int
---@style enum
---@enum [[0,"None","无指示器"],[1,"Rectangle","矩形"],[2,"Circle","圆形"],[3,"Sector","扇形"],[4,"Parabola","抛物线"]]
---@title 指示器类型
PointerType = 0
---指示器类型

---@type number 施法范围 @visible_when PointerType!=0
ReleaseDistance = 10.0
---施法范围

---@type number 影响宽度 @visible_when PointerType==1
AffectWidth = 1.0
---影响宽度

---@type number 扇形广角 @visible_when PointerType==3
SectorAngle = 90.0
---扇形广角

---@type number 影响半径 @visible_when PointerType in {2,3}
ReleaseRadius = 3.0
---影响半径

---@type number 水平速度 @visible_when PointerType==4
ParabolaHorizontalSpeed = 10.0
---水平速度（沿释放方向）

---@type number 垂直速度 @visible_when PointerType==4
ParabolaVerticalSpeed = 10.0
---垂直速度（竖直上抛）

---@type String[] 目标筛选类型
TargetFilterType = {}
---目标筛选类型（空=不筛选，可多选，任一命中即通过，如 "EggyUnit"/"HumanUnit"/"PhysicsUnit"）

---@type Int
---@style enum
---@enum [[0, "NoTarget", "无目标"],[1, "Direction", "方向"],[2, "Point", "点"],[3, "Unit", "单位"]]
---@title 目标类型
TargetType = 1
---目标类型

---@type Int
---@style enum
---@enum [[0, "None", "不限"],[1, "Enemy", "敌方"],[2, "Ally", "友方"]]
---@title 目标筛选阵营
TargetFilterCamp = 0
---目标筛选阵营

---@type String[] 筛选必需标签
TargetRequiredTags = {}
---筛选必需标签（所有标签必须满足）

---@type String[] 筛选忽略标签
TargetIgnoredTags = {}
---筛选忽略标签（含有任意一个则跳过）

---@type Int @visible_when IsChargeConsuming==true
---@style enum
---@enum [[0, "None", "不充能"],[1, "WhenNotFull", "不满时充能"],[2, "WhenEmpty", "用完后充能"]]
---@title 充能类型
ChargeType = 0
---充能类型

---@type integer 充能数量 @visible_when IsChargeConsuming==true
MaxChargeCount = 5
---充能数量

---@type integer 每次充能增加次数 @visible_when IsChargeConsuming==true && ChargeType!=0
ChargeAmount = 1
---每次充能增加次数

---@type boolean 充能是否开启
IsChargeConsuming = false
---充能是否开启

-- 子技能组（可选）

---@type Int
---@style enum
---@enum [[0, "None", "不切换"],[1, "AfterCast", "施法后切换"],[2, "Timer", "定时切换"],[3, "Manual", "仅手动"]]
---@title 切换方式
SwitchMode = 0
---切换方式（非 0 且子技能列表非空时建组）

---@type List<ability_system.SubAbilityInfo> 子技能列表
SubAbilities = {}
---子技能列表（与父技能共用同一槽位）

---@type Int @visible_when SwitchMode!=0
---@style enum
---@enum [[0, "Sequential", "顺序循环"],[1, "Shuffle", "洗牌"],[2, "Random", "随机"]]
---@title 切换顺序
SwitchOrder = 0
---切换顺序

---@type number 切换间隔 @visible_when SwitchMode==2
SwitchInterval = 3.0
---切换间隔（秒，Timer 模式）

---@type number 切换后冷却 @visible_when SwitchMode!=0
SwitchCooldown = 0.5
---切换后冷却（秒）

---@type number 回归计时 @visible_when SwitchMode==1
RevertTime = 0
---回归计时（秒，0=不回归）

---@type boolean 切换刷新计时 @visible_when SwitchMode==1
SwitchRefresh = true
---切换刷新计时

-- 业务逻辑（委派共享模块）
-- 服务端行为集中在 ability_logic.lua，此处仅在服务端调用 Attach(script)。
-- Attach 内部自带 IsServer() 判断与重复挂载保护。

local RunService = game:GetService("RunService")
if RunService:IsServer() then
	require("server.packages.ability_system.ability_logic").Attach(script)
end
