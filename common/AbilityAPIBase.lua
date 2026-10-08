-- 双端根 AbilityAPI 聚合入口的共有拼装（纯 Lua，无引擎依赖，可单测）。
-- 接缝约定：业务层只 require 根 AbilityAPI（server/AbilityAPI.lua、client/AbilityAPI.lua），
-- 不直接 require 包内 api.lua——包内注释也声明了「仅由根聚合入口加载」。
-- 下面两份名单就是这条接缝的契约：单测拿包内源码校对，包升级改名时立刻可见。

local AbilityAPIBase = {}

-- 与 server/packages/ability_system/api.lua 的导出同名同序。
AbilityAPIBase.SERVER_API = {
	"AddAbility",
	"GetAbility",
	"GetAbilityByScript",
	"CastAbility",
	"StopAbility",
	"AccumulateAbility",
	"SwitchNextAbility",
	"SetAbilityToSlot",
	"RemoveAbility",
	"RemoveAbilityByKey",
	"GetAbilities",
	"GetAbilitiesFromIndexRange",
	"RegisterEvents",
}

-- 与 client/packages/ability_system/api.lua 的导出同名同序。
AbilityAPIBase.CLIENT_API = {
	"GetManagerForUnit",
	"GetAbility",
	"RequestCast",
	"RequestStop",
	"RequestAccumulate",
	"RequestSwitchNext",
	"Register",
	"GetUIManager",
	"StartClientLifecycle",
}

-- 按名单把包内 API 装成聚合入口。label 缺省按技能包报错；其他官方包的聚合入口
-- （AttrAPIBase 等）复用本函数时传自己的标签。
-- 缺名直接 error：接缝漂移要在加载时就炸出来，而不是等业务侧某次调用拿到 nil——
-- 运行时 require 失败只进日志并返回 nil，静默降级会让问题晚很久才被发现。
function AbilityAPIBase.build(impl, names, label)
	local prefix = label or "[AbilityAPI] 技能包"
	local api = {}
	for _, name in ipairs(names) do
		local impl_fn = impl and impl[name]
		if type(impl_fn) ~= "function" then
			error(prefix .. "缺少接口: " .. tostring(name), 2)
		end
		api[name] = function(...)
			return impl_fn(...)
		end
	end
	return api
end

return AbilityAPIBase
