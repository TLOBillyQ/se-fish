-- 鳄雀鳝头部攻击预警（#134）：只消费服务端 GarBiteNotice，在鱼身中点按锁定的头部朝向贴地摆红色指示器，
-- 咬出 / 咬空 / 取消 / 鱼没了（clear）或超时后收起。纯表现，判定与伤害都在服务端 MgrFishUnit。
-- 特效用官方「扇形指示器-红色」（GameCfg.FishCombat.gar.Warning）：箭头与环形波纹提示锁定朝向和范围。
local GameCfg = require('common.GameCfg')
local GarBiteNotice = require('common.GarBiteNotice')

local LocalGarBite = { Active = {}, Generation = 0 }

local function cfg()
    return GameCfg.FishCombat.gar.Warning
end

function LocalGarBite:Hide(fishId)
    local entry = self.Active[fishId]
    if not entry then return end
    self.Active[fishId] = nil
    local ok, err = pcall(function() entry.Effect:Destroy() end)
    if not ok then print('[LocalGarBite] 收起预警失败', 'fish=' .. tostring(fishId), tostring(err)) end
end

function LocalGarBite:Show(payload)
    if not GarBiteNotice.Valid(payload) then return end
    local fishId = payload.fishId
    self:Hide(fishId)
    if payload.kind ~= 'lock' then return end
    local c = cfg()
    local world = game:GetService('World')
    local ok, units = pcall(world.CreateAsset, world, c.EffectPreset)
    local effect = ok and type(units) == 'table' and units[1] or nil
    if not effect then
        print('[LocalGarBite] 预警特效创建失败', c.EffectPreset, 'fish=' .. tostring(fishId), tostring(units))
        return
    end
    local p, scale = payload.position, payload.range / c.EffectLength
    local placed, err = pcall(function()
        effect.Position = Vector3.New(p.x, p.y + c.GroundOffset, p.z)
        effect.Rotation = Quaternion.FromEulerAngles(0, payload.yaw + c.EffectYawOffset, 0)
        -- 等比缩放：技能包 Sector/CirclePointer 对 7189/7187 写 y=0，但 7190 在技能包里从未实例化，
        -- y=0 对它是否仍可见无证据；等比缩放不会压成零厚度，贴地特效也仍是平的。
        effect.Scale = Vector3.New(scale, scale, scale)
    end)
    if not placed then
        print('[LocalGarBite] 预警特效摆放失败', 'fish=' .. tostring(fishId), tostring(err))
        local destroyed, destroyErr = pcall(function() effect:Destroy() end)
        if not destroyed then
            print('[LocalGarBite] 清理失败预警失败', 'fish=' .. tostring(fishId), tostring(destroyErr))
        end
        return
    end
    self.Generation = self.Generation + 1
    local entry = { Effect = effect, Generation = self.Generation }
    self.Active[fishId] = entry
    -- 兜底：clear 丢失（迟加入 / 断线）时按预警时长收起；新一轮预警已替换则不动
    local task = game:GetService('Task')
    if task and task.Delay then
        task:Delay(payload.duration + c.GraceSec, function()
            if self.Active[fishId] == entry then self:Hide(fishId) end
        end)
    end
end

function LocalGarBite:Start()
    if self.Conn then return end
    self.Conn = require('common.REUtil'):GetRE(GarBiteNotice.EventName).OnClientEvent:Connect(function(payload)
        self:Show(payload)
    end)
end

function LocalGarBite:Stop()
    if self.Conn then self.Conn:Disconnect() end
    self.Conn = nil
    for fishId in pairs(self.Active) do self:Hide(fishId) end
end

return LocalGarBite
