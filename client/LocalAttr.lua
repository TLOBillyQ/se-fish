-- 服务端体型投影的相机表现；CameraUnit.Distance签名见EggyAPI.lua。
-- 引擎预设相机是否接受该写入仍待最终人工试玩；其他模块改相机后让出拥有权。
local BodyScale = require('common.BodyScale')
local GameCfg = require('common.GameCfg')
local M = {}
function M:Release()
    if self.Camera and self.LastDistance and self.Camera.Distance == self.LastDistance then
        self.Camera.Distance = self.OriginalDistance
    end
    self.Camera, self.Character, self.LastDistance, self.OriginalDistance, self.Yielded = nil, nil, nil, nil, nil
end
function M:Refresh(character, camera)
    if camera ~= self.Camera or character ~= self.Character then
        self:Release()
        self.Camera, self.Character = camera, character
        self.OriginalDistance = camera and camera.Distance
    end
    if not character or not camera or self.Yielded then return false end
    if camera.TrackingUnit and camera.TrackingUnit ~= character then return false end
    if self.LastDistance and camera.Distance ~= self.LastDistance then self.Yielded = true return false end
    local distance = character:GetAttribute('CameraDistance')
    if type(distance) ~= 'number' or distance ~= distance or distance <= 0 or distance == math.huge then return false end
    local base = GameCfg.Ability.BodyScale.CameraDistance
    local target = BodyScale.Derive(BodyScale.Sanitize(distance / base)).CameraDistance
    if self.LastDistance ~= target then camera.Distance = target self.LastDistance = target end
    return true
end
function M:Stop()
    if self.Link then self.Link:Disconnect() self.Link = nil end
    self:Release()
end
function M:Start()
    self:Stop()
    local players = game:GetService('Players')
    local cameraService = game:GetService('CameraService')
    local run = game:GetService('RunService')
    self.Link = run.Heartbeat:Connect(function()
        local player = players.LocalPlayer
        local ok, err = pcall(self.Refresh, self, player and player.Character, cameraService.MainCamera)
        if not ok and self.LastError ~= tostring(err) then
            self.LastError = tostring(err)
            print('[LocalAttr] 相机刷新失败', self.LastError)
        elseif ok then self.LastError = nil end
    end)
end
return M
