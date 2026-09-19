--技能系统 - common结构体声明
-- 参考 def.lua 的定义方式：export_struct + field + 初始值表，
-- 供本包脚本对象（ability_script / ability_manager_script）的 List<> 容器以限定名引用，
-- 脚本对象上只写容器声明，不重复定义结构体
-- 注：AnchorData/TimelineLineData 已随 AnchorInfos/TimelineInfos 镜像退役删除（锚点统一 unit 化）

local ability_system

---@export_struct
---@title 初始技能
---@field AssetId String 技能预设 style:AssetResource unit_types:["ability"]
---@field Index Int 槽位
ability_system.AbilityInfo = {
	AssetId = "",
	Index = 0,
}

---@export_struct
---@title 子技能
---@field AssetId String 技能预设 style:AssetResource unit_types:["ability"]
ability_system.SubAbilityInfo = {
	AssetId = "",
}

return ability_system
