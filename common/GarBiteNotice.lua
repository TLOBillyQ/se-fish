-- 鳄雀鳝头部攻击预警通知协议（#134）：服务端锁定朝向起咬时广播 lock，咬出 / 咬空 / 取消 / 鱼没了时广播 clear。
-- 只传可序列化字段；判定与伤害都在服务端，客户端只据此画贴地预警。
local GarBiteNotice = { EventName = 'GarBiteNotice' }

local function finite(v)
    return type(v) == 'number' and v == v and math.abs(v) < math.huge
end

---起咬预警：fishId 为 MgrFishUnit 的鱼编号，(fx,fz) 为锁定的头部朝向（单位向量）
function GarBiteNotice.Lock(fishId, pos, fx, fz, range, halfAngleDeg, duration)
    return {
        kind = 'lock', fishId = fishId,
        position = { x = pos.x, y = pos.y, z = pos.z },
        yaw = math.atan(fx, fz), range = range, halfAngleDeg = halfAngleDeg, duration = duration,
    }
end

---reason：bite（咬中）/ miss（绕后咬空）/ cancel（目标出咬距或失效）/ gone（鱼逃脱或被移除）
function GarBiteNotice.Clear(fishId, reason)
    return { kind = 'clear', fishId = fishId, reason = reason }
end

function GarBiteNotice.Valid(payload)
    if type(payload) ~= 'table' or type(payload.fishId) ~= 'number' then return false end
    if payload.kind == 'clear' then return true end
    if payload.kind ~= 'lock' then return false end
    local p = payload.position
    return type(p) == 'table' and finite(p.x) and finite(p.y) and finite(p.z) and finite(payload.yaw)
        and finite(payload.range) and payload.range > 0
        and finite(payload.duration) and payload.duration > 0
end

function GarBiteNotice.Publish(payload)
    require('common.REUtil'):GetRE(GarBiteNotice.EventName):FireAllClients(payload)
end

return GarBiteNotice
