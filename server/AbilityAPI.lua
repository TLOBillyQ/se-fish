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

-- #132 T11 原型接缝：三倍体型（SetScale）与挂点附着/释放。
-- 纯逻辑（倍率净化、派生量、挂点净空）在 common/BodyScale.lua 与 common/CarryMount.lua，
-- 这里只做「代码里的可调用接缝」：把净化后的参数落到引擎 API 上，失败返回 { Ok=false, Error } 而不抛错。
-- 真机表现（缩放后碰撞体/相机是否跟着变、挂件是否穿模）本单未试玩，见 issue #132 待办清单。
local BodyScale = require("common.BodyScale")
local CarryMount = require("common.CarryMount")

---三倍体型的落地接口：按倍率设置单位缩放。
---本地 stub（~/.eggitor/eggy_api/api_lua_doc/EggyAPI.lua）中 HumanUnit:SetScale(scale: Vector3)
---注明「影响模型大小和碰撞体积」，倍率非法时由 BodyScale.Sanitize 回落 1 倍，绝不写入 NaN。
---@param unit any 带 SetScale 的单位（玩家角色 / EggyUnit）
---@param factor any 目标倍率（1..3）
---@return table { Ok, Scale, Derived?, Error? }
function AbilityAPI.SetBodyScale(unit, factor)
	if not unit then return { Ok = false, Error = 'no-unit' } end
	local scale = BodyScale.Sanitize(factor)
	if type(unit.SetScale) ~= 'function' then return { Ok = false, Error = 'no-set-scale', Scale = scale } end
	local ok, err = pcall(unit.SetScale, unit, Vector3.New(scale, scale, scale))
	if not ok then
		print('[AbilityAPI] SetScale 失败', tostring(err))
		return { Ok = false, Error = tostring(err), Scale = scale }
	end
	return { Ok = true, Scale = scale, Derived = BodyScale.Derive(scale) }
end

---挂点附着的落地接口：在宿主下建 SkeletalSocketMount。
---unit 传 nil 时只建挂点（携带物由服务端每帧写位置，见 common/CarryMount.Follow）——
---把玩家角色 parent 到挂点下会不会打断控制器/相机本单未试玩（标 [未查证]），所以两种模式都留着。
---挂点位移应由调用方用 common.CarryMount.SafeOffset 净化（保证清空宿主与携带物身体）。
---@param world any World 服务（业务侧注入，便于测试与复用）
---@param unit? any 被携带的单位（nil 表示只建挂点）
---@param host any 宿主单位（挂点的 Parent）
---@param socketName string 骨骼挂点名
---@param offset? table { x, y, z } 已净化的挂点位移
---@param rotation? any Quaternion 挂点旋转（缺省不写该字段，用预设默认）
---@return table { Ok, Mount?, Offset?, Error? }
function AbilityAPI.AttachToSocket(world, unit, host, socketName, offset, rotation)
	if not host then return { Ok = false, Error = 'no-host' } end
	if type(socketName) ~= 'string' or socketName == '' then return { Ok = false, Error = 'no-socket' } end
	world = world or game:GetService('World')
	local pos = CarryMount.SafeOffset(offset or { x = 0, y = 0, z = 0 }, 0, 0).Offset
	local options = {
		Name = 'CarryMount_' .. tostring(host.Name or 'host'),
		Parent = host,
		SocketName = socketName,
		SocketOffset = Vector3.New(pos.x, pos.y, pos.z),
	}
	if rotation ~= nil then options.SocketRotation = rotation end
	local ok, mount = pcall(world.CreateUnit, world, 'SkeletalSocketMount', options)
	if not ok or not mount then
		print('[AbilityAPI] 挂点创建失败', tostring(mount))
		return { Ok = false, Error = tostring(mount) }
	end
	if unit ~= nil then
		local parentOk, parentErr = pcall(function() unit.Parent = mount end)
		if not parentOk then
			pcall(function() mount:Destroy() end)
			print('[AbilityAPI] 挂点挂载失败', tostring(parentErr))
			return { Ok = false, Error = tostring(parentErr) }
		end
	end
	return { Ok = true, Mount = mount, Offset = pos }
end

---挂点释放：销毁挂点单位（携带物由调用方另行落位，避免「单位随挂点一起被销毁」）。
---@return boolean
function AbilityAPI.DetachFromSocket(mount)
	if not mount then return false end
	local ok = pcall(function()
		if mount.Parent then mount.Parent = nil end
		mount:Destroy()
	end)
	if not ok then print('[AbilityAPI] 挂点销毁失败') end
	return ok
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
