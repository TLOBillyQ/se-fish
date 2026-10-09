-- 相机中央瞄准：公开 CameraService:ViewportPointToRay 的 x/y 是 [0,1]，Ray.Direction 为 Vector3。
-- 只发送方向；射线起点、长度、阻挡与伤害全部由服务端决定。
local Aim = {}
function Aim:AttackPayload()
    local payload = {action='attack'}
    local camera=game:GetService('CameraService')
    if not camera then return payload end
    local ok,direction=pcall(function() return camera:ViewportPointToRay(0.5,0.5).Direction end)
    if not ok or not direction then
        print('[WeaponAim] 读取相机瞄准失败',tostring(direction))
        return payload
    end
    payload.aim={x=direction.x,y=direction.y,z=direction.z}
    return payload
end
return Aim
