-- #132 T11 高风险能力原型 · 能力 C：巡航叼人的挂点附着、携带跟随与释放。
-- 数值来源：GameSpec §12（沧龙绕岛咬最近岛中心玩家、咬中 300、叼走入海）。
-- 配置见 GameCfg.Ability.Carry。
--
-- 服务端语义：宿主（沧龙）用 SkeletalSocketMount 挂点带着玩家走，位置由服务端每帧写回，
-- 所以「跟随」不是父子关系而是每帧校验：
--   * 挂点不穿出：挂点位移必须清空宿主与携带物的身体（中心距 ≥ 两者半高之和，球形间隙近似）；
--   * 挂点坐标随宿主位姿与体型：位置 = 宿主位置 + 绕 Y 旋转后的挂点位移，位移由 BodyScale 放大；
--   * 携带跟随：偏出容差才整段钳回挂点（容差内不动它，否则每帧纠正会抖）；
--   * 越界与坏值：超抓取距离不叼、无挂点不叼；目标位置出现 NaN/inf 立即释放并给有限落点。
-- 真机挂点是否穿模、玩家是否被甩出仍需编辑器窗口试玩，见 issue #132 待办清单。
local GameCfg = require('common.GameCfg')

local M = {}

local function cfg()
    return GameCfg.Ability.Carry
end

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

local function isBadPoint(p)
    return type(p) ~= 'table' or isBadNumber(p.x) or isBadNumber(p.y) or isBadNumber(p.z)
end

local function num(v)
    if isBadNumber(v) then return 0 end
    return v
end

local function copy(p)
    return { x = num(p.x), y = num(p.y), z = num(p.z) }
end

local function pointDistance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.Length(offset)
    if type(offset) ~= 'table' then return 0 end
    return math.sqrt(num(offset.x) ^ 2 + num(offset.y) ^ 2 + num(offset.z) ^ 2)
end

---挂点位移净化：中心距不足「宿主半高 + 携带物半高」就沿原方向推出去。
---零位移没有方向可用时用 +z（宿主正前方）兜底，而不是产出 NaN 方向。
---@param offset table { x, y, z }
---@param hostHalf number 宿主半高
---@param carriedHalf number 携带物半高
---@return table { Offset, Corrected }
function M.SafeOffset(offset, hostHalf, carriedHalf)
    local safe = { x = num(offset and offset.x), y = num(offset and offset.y), z = num(offset and offset.z) }
    local need = math.max(0, num(hostHalf)) + math.max(0, num(carriedHalf))
    local length = M.Length(safe)
    if length >= need and length > 0 then return { Offset = safe, Corrected = false } end
    if length <= 1e-9 then return { Offset = { x = 0, y = 0, z = need }, Corrected = true } end
    local k = need / length
    return { Offset = { x = safe.x * k, y = safe.y * k, z = safe.z * k }, Corrected = true }
end

---挂点世界坐标：宿主位置 + 绕 Y 轴 yaw（弧度）旋转后的挂点位移。
---@param host table 宿主位置
---@param offset table 挂点位移（1 倍体型下的基准值 × 体型倍率）
---@param yaw number 宿主朝向（弧度）
---@return table { x, y, z }
function M.MountPoint(host, offset, yaw)
    host = host or { x = 0, y = 0, z = 0 }
    offset = offset or { x = 0, y = 0, z = 0 }
    yaw = num(yaw)
    local cos, sin = math.cos(yaw), math.sin(yaw)
    local ox, oz = num(offset.x), num(offset.z)
    return {
        x = num(host.x) + ox * cos + oz * sin,
        y = num(host.y) + num(offset.y),
        z = num(host.z) - ox * sin + oz * cos,
    }
end

---释放落点：宿主前方 DropForward 米、离地 DropHeight 米（不会跟着宿主继续飞）。
function M.DropPoint(host, yaw, groundY, carryCfg)
    carryCfg = carryCfg or cfg()
    host = host or { x = 0, y = 0, z = 0 }
    yaw = num(yaw)
    return {
        x = num(host.x) + math.sin(yaw) * carryCfg.DropForward,
        y = num(groundY) + carryCfg.DropHeight,
        z = num(host.z) + math.cos(yaw) * carryCfg.DropForward,
    }
end

---新建携带状态。host 是宿主（沧龙）位置，groundY 是所在地面的高度（释放落点用）。
---@param carryCfg? table
---@param host? table
---@param yaw? number
---@param now? number
function M.New(carryCfg, host, yaw, now)
    carryCfg = carryCfg or cfg()
    host = host and copy(host) or { x = 0, y = 0, z = 0 }
    local safe = M.SafeOffset(carryCfg.Offset, carryCfg.HostHalfHeight, carryCfg.CarriedHalfHeight)
    return {
        Cfg = carryCfg, Host = host, Yaw = num(yaw), GroundY = host.y,
        Offset = safe.Offset, Corrected = safe.Corrected,
        Carried = false, Target = nil, Mount = nil,
        StartedAt = num(now), ReleasedAt = nil,
        Stats = { Frames = 0, Attaches = 0, Snaps = 0, Releases = 0 },
    }
end

function M.Carried(state)
    return state.Carried == true
end

function M.InRange(state, target)
    if isBadPoint(target) then return false end
    -- 只比水平距离：宿主常在十几米高空，按三维距离永远叼不到站地上的玩家
    local dx, dz = target.x - state.Host.x, target.z - state.Host.z
    return math.sqrt(dx * dx + dz * dz) <= state.Cfg.GrabRange
end

---叼起目标。
---@return table { Ok, Reason?, Damage? }
function M.Attach(state, target, now)
    if type(state.Cfg.Socket) ~= 'string' or state.Cfg.Socket == '' then
        return { Ok = false, Reason = 'noSocket' }
    end
    if isBadPoint(target) then return { Ok = false, Reason = 'noTarget' } end
    if not M.InRange(state, target) then return { Ok = false, Reason = 'outOfRange' } end
    state.Carried = true
    state.Target = copy(target)
    state.StartedAt = num(now)
    state.ReleasedAt = nil
    state.Mount = M.MountPoint(state.Host, state.Offset, state.Yaw)
    state.Stats.Attaches = state.Stats.Attaches + 1
    return { Ok = true, Damage = state.Cfg.GrabDamage, Position = state.Mount }
end

---释放携带，返回落点。重复释放是空操作（不会把玩家扔两次）。
function M.Release(state, now, reason)
    if not state.Carried then return { Ok = false, Reason = 'notCarrying' } end
    state.Carried = false
    state.ReleasedAt = num(now)
    state.Stats.Releases = state.Stats.Releases + 1
    local drop = M.DropPoint(state.Host, state.Yaw, state.GroundY, state.Cfg)
    state.Target = nil
    return { Ok = true, Reason = reason or 'manual', DropPoint = drop, Position = drop }
end

---携带跟随：偏出容差才钳回挂点；目标位置出现坏值时释放而不是把 NaN 写回玩家。
---@return table { Position?, Snapped?, Released?, Reason? }
function M.Follow(state, targetPos, now, dt)
    if not state.Carried then return { Position = nil } end
    local desired = M.MountPoint(state.Host, state.Offset, state.Yaw)
    state.Mount = desired
    if isBadPoint(targetPos) then
        local released = M.Release(state, now, 'nan')
        return { Position = released.DropPoint, Released = true, Reason = 'nan' }
    end
    if pointDistance(targetPos, desired) > state.Cfg.FollowTolerance then
        state.Stats.Snaps = state.Stats.Snaps + 1
        return { Position = desired, Snapped = true }
    end
    return { Position = targetPos, Snapped = false }
end

---每帧推进：超时自动释放，否则回到挂点。
---@return table { Released, Reason?, DropPoint?, Position? }
function M.Step(state, now, dt)
    state.Stats.Frames = state.Stats.Frames + 1
    if not state.Carried then return { Released = false, Position = nil } end
    if num(now) - state.StartedAt >= state.Cfg.MaxCarrySec then
        local released = M.Release(state, now, 'timeout')
        return { Released = true, Reason = 'timeout', DropPoint = released.DropPoint, Position = released.DropPoint }
    end
    return { Released = false, Position = state.Mount or M.MountPoint(state.Host, state.Offset, state.Yaw) }
end

return M
