-- 服务端根能力入口：业务层只 require 本模块，不直接碰 server/packages/ability_system/。
-- 包内 api.lua 的服务端权威 API 在这里整体转发（名单见 common/AbilityAPIBase.lua）。
local AbilityAPIBase = require("common.AbilityAPIBase")
local AbilityPackageAPI = require("server.packages.ability_system.api")

local AbilityAPI = AbilityAPIBase.build(AbilityPackageAPI, AbilityAPIBase.SERVER_API)

-- #128 服务端动作闸门：技能包 RemoteEvent 只转发到包内 CastAbility，玩家死亡 / 濒死等状态不能由客户端绕过。
-- 业务侧由 MgrAbility 注入；守卫失败必须拒绝，不进入 vendor。
local packageCastAbility = AbilityAPI.CastAbility
local castGuard
-- #129 追加守卫链（MgrWeapon 的挥砍登记闸）：SetCastGuard 保持单设语义不变，追加守卫逐个跑，
-- 任一拒绝即拒绝。无追加守卫时行为与 #128 完全一致。
local extraGuards = {}
function AbilityAPI.AddCastGuard(guard)
	if type(guard) ~= 'function' then error('[AbilityAPI] CastGuard 必须是函数', 2) end
	extraGuards[#extraGuards + 1] = guard
end
function AbilityAPI.SetCastGuard(guard)
    if guard ~= nil and type(guard) ~= 'function' then error('[AbilityAPI] CastGuard 必须是函数', 2) end
    castGuard = guard
end
function AbilityAPI.CastAbility(unit, abilityIndex, releasePoint, releaseDir, releaseTarget)
    if castGuard then
        local ok, allowed = pcall(castGuard, unit, abilityIndex)
        if not ok then print('[AbilityAPI] 施法守卫失败', tostring(allowed)) end
        if not ok or allowed ~= true then return false end
    end
    for _, guard in ipairs(extraGuards) do
        local ok, allowed = pcall(guard, unit, abilityIndex)
        if not ok then print('[AbilityAPI] 追加施法守卫失败', tostring(allowed)) end
        if not ok or allowed ~= true then return false end
    end
    return packageCastAbility(unit, abilityIndex, releasePoint, releaseDir, releaseTarget)
end

-- #129 挥砍登记：MgrWeapon 发起近战前登记本次挥砍（伤害/射程按 GameCfg 表，空手 5、近战按表），
-- melee_hit 行为在 AnchorStart 时经 TakeSwing 取用登记值推导命中盒与伤害；未经登记的玩家挥砍
-- 不结算伤害（不再回落到预设属性 25），伪造 RequestCast 因此被结构性堵住。登记一次性消费、带 TTL。
local SWING_TTL_SEC = 1.5
local SWING_FUTURE_SKEW_SEC = 0.5
local swings = {}
local function swingClock()
    local ok, now = pcall(function() return game:GetService('World'):GetServerTime() end)
    if ok and type(now) == 'number' and now == now then return now end
end
local function swingAlive(entry)
    if not entry then return nil end
    local now = swingClock()
    if now == nil or entry.at == nil then return entry end -- 读不到时钟：宽松处理
    if entry.at > now + SWING_FUTURE_SKEW_SEC then return nil end -- 登记在未来（时钟回拨）视为过期
    if now - entry.at > SWING_TTL_SEC then return nil end
    return entry
end
function AbilityAPI.StageSwing(userId, swing)
    if type(userId) ~= 'number' or type(swing) ~= 'table' then return false end
    swings[userId] = { damage = swing.damage, range = swing.range, at = swingClock() }
    return true
end
function AbilityAPI.PeekSwing(userId)
    return swingAlive(swings[userId])
end
function AbilityAPI.TakeSwing(userId)
    local entry = swingAlive(swings[userId])
    swings[userId] = nil
    return entry
end

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
        local localBehavior = behaviorModule == "melee_hit" or behaviorModule == "eel_discharge"
		local modulePath = localBehavior
			and "server.AbilityBehaviors." .. behaviorModule
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
