-- 电鳗放电：每次锚点点火只结算一次，对球形范围内所有活着的玩家扣血。
-- 不按鱼主人或小队过滤；非玩家受击体不会被放电误伤。#128 起伤害经统一命中身份。
local MgrVitals = require('server.Mgr.MgrVitals')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')

local M = {}

function M.Discharge(owner, radius, damage, hit)
    hit = hit or MgrVitals:NewHit(MgrFishCarrier:ResolveCarrier(owner) or owner, 'fishAttack')
    local position = owner.Position
    local hits = 0
    for _, player in ipairs(game:GetService('Players'):GetPlayers()) do
        local character = player.Character
        local controller = character and character.Controller
        if controller and controller.Health > 0 then
            local pos = character.Position
            local dx, dy, dz = pos.x - position.x, pos.y - position.y, pos.z - position.z
            if dx * dx + dy * dy + dz * dz <= radius * radius then
                if MgrVitals:ApplyHit(hit, player, damage) then
                    hits = hits + 1
                    print('[EelDischarge] 命中', player.UserId, damage, 'health=' .. tostring(controller.Health))
                end
            end
        end
    end
    return hits
end

function M.Attach(anchor)
    local start = anchor:FindFirstChild('AnchorStart')
    if not start then error('[EelDischarge] 缺少 AnchorStart') end
    local connection = start:Connect(function()
        local ability = anchor.Parent
        local manager = ability and ability.Parent
        local owner = manager and manager.Parent
        if not owner or not owner.Controller or owner.Controller.Health <= 0 then return end
        M.Discharge(owner, anchor:GetAttribute('DischargeRadius'), anchor:GetAttribute('DischargeDamage'))
    end)
    local destroying
    destroying = anchor.Destroying:Connect(function()
        connection:Disconnect()
        destroying:Disconnect()
    end)
end

return M
