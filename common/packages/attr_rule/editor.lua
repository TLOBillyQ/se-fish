--属性规则包 - 暴露给编辑器的反射数据

local PrefabDefine = {}

---@export_prefab_type AttrUnit
---@title 属性单位
---@root Script
---@extend Script
---@template_id map://preset/u801ef1a3a924db391741602e6eee295
PrefabDefine.AttrUnit = true

---@export_prefab_type AttrBuffUnit
---@title 属性Buff单位
---@root Script
---@extend Script
---@template_id map://preset/u95e3ac002304b8483aa099a955e14a8
PrefabDefine.AttrBuffUnit = true

---属性规则配置
---@export_data
---@title 全局默认属性
---@category 属性规则
---@type List<attr_rule.AttrConfig> 全局默认属性
local AttrRuleConfig = {}

return AttrRuleConfig
