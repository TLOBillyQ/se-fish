-- 服务端伤害通知协议：只传可序列化的目标编号、真实扣血和受伤时世界位置。
local DamageNotice = {}

function DamageNotice.Publish(payload)
    require('common.REUtil'):GetRE('DamageNotice'):FireAllClients(payload)
end

function DamageNotice.FromHealth(targetId, previous, current, position, critical, targetType, height)
    if type(previous) ~= 'number' or type(current) ~= 'number'
        or previous ~= previous or current ~= current
        or math.abs(previous) == math.huge or math.abs(current) == math.huge
        or type(targetId) ~= 'number' or not position then return nil end
    local amount = math.max(0, previous) - math.max(0, current)
    if amount <= 0 then return nil end
    return {
        targetType = targetType or 'fish', targetId = targetId, amount = amount,
        position = { x = position.x, y = position.y, z = position.z },
        height = type(height) == 'number' and height > 0 and height < math.huge and height or nil,
        critical = critical == true,
    }
end

return DamageNotice
