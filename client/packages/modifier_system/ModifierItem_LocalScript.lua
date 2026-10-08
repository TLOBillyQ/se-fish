--效果系统包 - 客户端预设壳
--效果实例客户端脚本：把效果实体注册到客户端效果管理器，表现由属性同步驱动。

local modifierSystem = require("client.packages.modifier_system.modifier_system")

local function onPosted()
	local modifier = script.Parent
	if not modifier then
		return
	end
	modifierSystem:registerModifier(modifier)
end

onPosted()
