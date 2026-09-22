--技能系统 - common编辑器反射数据
-- 作者版技能系统自定义预设类型定义
-- 技能 / 技能管理器均为 Script（服务端）+ LocalScript（客户端）结构。
-- 属性由 ScriptUnit 的 @type 字段承载，此处 Name 仅为必备属性占位（空表会导致类型解析失败）。

local PrefabDefine = {}

---@export_prefab_type ability
---@category Ability
---@title 技能
---@root Script
---@extends Script
---@children {LocalScript}
---@prefab_icon "official://image/15649"
---@template_id map://preset/uc57b9f26db1463083f9ace34d6db0d5
PrefabDefine.ability = true

---@export_prefab_type ability_manager
---@category Ability
---@title 技能背包
---@root Script
---@extends Script
---@children {LocalScript}
---@prefab_icon "official://image/15649"
---@template_id map://preset/u014968df4aa4427aebac4388ed79bf7
PrefabDefine.ability_manager = true

---@export_prefab_type ability_anchor
---@category Ability
---@title 锚点
---@root Script
---@prefab_icon "official://image/15649"
---@template_id map://preset/uccfb9dbe3f4428bb972096ba01f1f25
PrefabDefine.ability_anchor = true

return PrefabDefine
