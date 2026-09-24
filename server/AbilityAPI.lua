-- 服务端根能力入口：业务层只 require 本模块，不直接碰 server/packages/ability_system/。
-- 包内 api.lua 的服务端权威 API 在这里整体转发（名单见 common/AbilityAPIBase.lua）。
local AbilityAPIBase = require("common.AbilityAPIBase")
local AbilityPackageAPI = require("server.packages.ability_system.api")

local AbilityAPI = AbilityAPIBase.build(AbilityPackageAPI, AbilityAPIBase.SERVER_API)

-- 锚点挂接（本图补充，不属于包内 api.lua 的导出）
-- 官方流程把锚点预设作为技能预设的子预设，靠锚点预设自己的壳源码调 anchor_logic.Attach；
-- 但本编辑器不认包内的 ---@export_prefab_type 自定义预设类型，锚点预设壳的编译代码为空、
-- 试玩里不会执行（结论见 issue #7）。壳该做的事在这里补上：加载锚点框架，再按业务侧给的
-- 行为模块名挂上行为逻辑。放在聚合入口里，业务代码仍然只依赖根 AbilityAPI 一个入口。
---把锚点单位挂到技能单位下（锚点应先 parent 到技能单位）
---@param anchorScript Script 锚点脚本单位
---@param behaviorModule string 锚点行为模块名（anchors/ 目录下的文件名，如 "speed_add"）
---@return boolean 是否已挂接
function AbilityAPI.AttachAnchor(anchorScript, behaviorModule)
	if not anchorScript then
		return false
	end

	require("server.packages.ability_system.anchor_logic").Attach(anchorScript)

	if behaviorModule and behaviorModule ~= "" then
		-- 本图挥砍受击体使用 BaseController；官方行为多传 owner 会触发类型告警。
		local modulePath = behaviorModule == "melee_hit"
			and "server.AbilityBehaviors.melee_hit"
			or "server.packages.ability_system.anchors." .. behaviorModule
		local behavior = require(modulePath)
		if type(behavior) ~= "table" or type(behavior.Attach) ~= "function" then
			error("[AbilityAPI] 锚点行为模块不可用: " .. tostring(behaviorModule), 2)
		end
		behavior.Attach(anchorScript)
	end

	return true
end

return AbilityAPI
