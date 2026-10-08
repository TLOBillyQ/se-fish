--效果系统包 - 服务端预设壳
--效果实例服务端脚本：声明编辑器可配置字段，运行时把效果注册到效果管理器。
--效果 Key 由系统写入：动态添加时恒等于效果预设 Asset；预放置实例如需 Key 寻址，
--可在运行时 SetAttribute("ModifierKey", ...) 自行写入。

local modifierSystem = require("server.packages.modifier_system.modifier_system")

-- 以下字段为编辑器反射声明，运行时由效果管理器经效果单位属性读取，脚本不直接引用

-- 基础信息

---@type number
---@title 持续时间
local Duration = 5

---@type Int
---@style enum
---@enum [[0, "Beneficial", "有益"], [1, "Harmful", "有害"], [2, "Neutral", "中立"]]
---@title 效果类型
local UgcModifierType = 2

---@type Int
---@style enum
---@enum [[0, "None", "无"], [1, "OnDie", "击败后清除"]]
---@title 清除规则
local RemoveMode = 1

-- 叠加配置，允许叠加时生效

---@type boolean
---@title 允许叠加
local Stackable = false

---@type boolean
---@title 仅同源叠加
---@filter ["EQ","Stackable",true]
local SameSourceStack = false

---@type Int
---@title 获取时增加层数
---@filter ["EQ","Stackable",true]
local StackCountStep = 1

---@type Int
---@title 最大层数
---@filter ["EQ","Stackable",true]
local MaxStackCount = 999

---@type Int
---@style enum
---@enum [[0,"None","不变"],[1,"Overlay","覆盖"],[2,"Accumulate","增加"],[3,"Independent","独立"]]
---@title 叠加时间变化
---@filter ["EQ","Stackable",true]
local StackDurationMode = 0

---@type Int
---@style enum
---@enum [[0, "None", "不变"], [1, "Overlay", "覆盖"], [2, "Accumulate", "增加"]]
---@title 叠加层数变化
---@filter ["EQ","Stackable",true]
local StackCountMode = 0

-- 属性修改

---@type List<modifier_system.ModifierAttrConfig> 属性修改配置列表
---@desc 效果生效时累加到拥有者属性，移除时回滚
local AttrConfigs = {}

-- 获得表现

---@type List<modifier_system.ModifierObtainPerformanceInfo> 获得表现列表
---@desc 获得效果时播放，含特效/音效/皮肤材质替换
local ObtainPerformanceList = {}

-- 失去表现

---@type List<modifier_system.ModifierLostPerformanceInfo> 失去表现列表
---@desc 失去效果时播放，含特效与音效；材质还原由系统自动处理
local LostPerformanceList = {}

-- 业务逻辑，委派效果管理器
-- 服务端预设壳自身即效果实体，script 即效果单位；注册幂等，拒绝/失败不缓存，允许后续重挂时再次注册

local function onPosted()
	modifierSystem:registerModifier(script)
end

onPosted()

-- 动态创建的效果先挂在临时父节点上执行一次，注册被拒绝且不缓存结果，
-- 之后由 ParentChanged 触发重新注册，落到拥有者下后注册生效
if script.ParentChanged then
	script.ParentChanged:Connect(function()
		modifierSystem:registerModifier(script)
	end)
end
