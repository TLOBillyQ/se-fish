--属性规则包 - 配置表（双端共用）
--常量键与配置数据直接定义在这张导出表上，一行即最终值；包内各模块只读。

local editorConfig = require("common.packages.attr_rule.editor")

local Configs = {}

-- 属性单位自身承载状态的属性键（服务端写入，随单位同步到客户端）
Configs.ATTR_BUFFS_ATTRIBUTE = "AttrBuffs"
Configs.ATTR_BUFF_NEXT_ID_ATTRIBUTE = "AttrBuffNextId"
Configs.INIT_VALUES_ATTRIBUTE = "InitValues"

-- 属性加成单位自身承载状态的属性键
Configs.ATTR_BUFF_CONFIGS_ATTRIBUTE = "AttrBuffConfigs"
Configs.ATTR_BUFF_TARGET_UNIT_ATTRIBUTE = "AttrBuffTargetUnit"
Configs.ATTR_BUFF_ID_ATTRIBUTE = "AttrBuffId"

-- 预设类型绑定属性：编辑器写在 Script 的 PresetLink 载体节点上，用于按结构识别单位
Configs.PREFAB_TYPE_ATTRIBUTE = "PrefabType"
Configs.ATTR_UNIT_PREFAB_TYPE = "AttrUnit"
Configs.ATTR_BUFF_UNIT_PREFAB_TYPE = "AttrBuffUnit"

-- 属性单位预设 AssetKey
Configs.DEFAULT_ATTR_UNIT_KEY = "map://preset/u801ef1a3a924db391741602e6eee295"

-- 属性Buff单位预设 AssetKey
Configs.DEFAULT_ATTR_BUFF_UNIT_KEY = "map://preset/u95e3ac002304b8483aa099a955e14a8"

---包默认属性配置
---@type AttrConfig[]
Configs.DefaultAttrs = {}

-- 属性最终值同步到目标单位 Controller 的字段映射：属性键 → Controller 字段名。
-- 只有列在这里的属性才会同步控制器，字段名即基础控制器（BaseController）的属性名。
Configs.ControllerAttrMap = {
	WalkSpeed = "WalkSpeed",
	JumpPower = "JumpPower",
	MaxHealth = "MaxHealth",
	Health = "Health",
}

---全局属性配置表：属性键 → 配置；包默认属性与编辑器面板配置在这里合并
---@type table<String, AttrConfig>
Configs.AllAttrConfigs = {}
for _, attrConfig in ipairs(Configs.DefaultAttrs) do
	Configs.AllAttrConfigs[attrConfig.AttrKey] = attrConfig
end
if editorConfig ~= nil then
	for _, attrConfig in ipairs(editorConfig) do
		local attrKey = attrConfig.AttrKey
		if type(attrKey) == "string" and attrKey ~= "" then
			Configs.AllAttrConfigs[attrKey] = attrConfig
		end
	end
end

return Configs
