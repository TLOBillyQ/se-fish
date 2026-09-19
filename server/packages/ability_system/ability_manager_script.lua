--技能系统 - server技能管理器预设壳
-- 技能管理器服务端脚本（ScriptUnit，挂在 Player Character 之下）
-- 子节点为多个技能 ScriptUnit（ability_script.lua 预设壳）
-- 数据化预设壳：仅保留编辑器可编辑的 @type 配置属性声明，
-- 服务端业务逻辑统一委派给 ability_manager_logic.lua 的 Attach(script)。

---@type 配置属性（编辑器中可编辑）
-- 初始技能结构体定义在 common/packages/ability_system/data.lua（ability_system.AbilityInfo），此处仅声明容器引用限定名

---@type List<ability_system.AbilityInfo> 初始技能列表
InitAbilities = {}

-- 业务逻辑（委派共享模块）
-- 服务端行为集中在 ability_manager_logic.lua，此处仅在服务端调用 Attach(script)。
-- Attach 内部自带 IsServer() 判断与重复挂载保护。

local RunService = game:GetService("RunService")
if RunService:IsServer() then
	require("server.packages.ability_system.ability_manager_logic").Attach(script)
end
