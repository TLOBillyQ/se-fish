--效果系统包 - 暴露给编辑器的反射数据
--效果预设类型声明：效果直接挂在生物下，由服务端脚本 + 客户端脚本构成。

local PrefabDefine = {}

---效果预设类型：服务端脚本 + 客户端脚本结构，资源库/编辑器按模板创建该类型预设
---@export_prefab_type modifier
---@category Modifier
---@title 效果
---@root Script
---@extends Script
---@children {LocalScript}
---@prefab_icon "official://image/15649"
---@template_id map://preset/u1b5be6f141c4898956df10e229c33c3
PrefabDefine.modifier = true

return PrefabDefine
