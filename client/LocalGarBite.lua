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
    if entry.Projectile then
        local removed, err = pcall(function() entry.Projectile:Destroy() end)
        if not removed then print('[LocalGarBite] 收起投掷物失败', fishId, tostring(err)) end
    end
    if entry.Rain then
        local rainOk, rainErr = pcall(function() entry.Rain:Destroy() end)
        if not rainOk then print('[LocalGarBite] 收起暴雨失败', fishId, tostring(rainErr)) end
    end
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
    local circle = payload.shape == 'circle'
    local preset = circle and c.CirclePreset or c.EffectPreset
    local ok, units = pcall(world.CreateAsset, world, preset)
    local effect = ok and type(units) == 'table' and units[1] or nil
    if not effect then
        print('[LocalGarBite] 预警特效创建失败', preset, 'fish=' .. tostring(fishId), tostring(units))
        return
    end
    local p, scale = payload.position, payload.range / (circle and c.CircleRadius or c.EffectLength)
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
    if payload.move == 'airThrow' and type(payload.flightOrigin) == 'table' then
        local o = payload.flightOrigin
        if type(o.x)=='number' and type(o.y)=='number' and type(o.z)=='number'
            and o.x==o.x and o.y==o.y and o.z==o.z
            and math.abs(o.x)<math.huge and math.abs(o.y)<math.huge and math.abs(o.z)<math.huge then
            local created, projectile = pcall(world.CreateUnit, world, 'WorldUnit', {
                Name='FlightThrow_' .. tostring(fishId), Position=Vector3.New(o.x,o.y,o.z),
                RenderMeshId=GameCfg.Ability.Flight.ThrowMesh, PhysicsActive=false, CanQuery=false,
                Scale=Vector3.New(0.3,0.3,0.3) })
            if created and projectile then
                entry.Projectile, entry.Origin, entry.Destination = projectile, o, p
                entry.At, entry.Duration = world:GetServerTime(), payload.duration
            else print('[LocalGarBite] 投掷物创建失败',fishId,tostring(projectile)) end
        end
    end
    if payload.move == 'rain' then
        -- 暴雨是独立表现，方向指示器只表达危险范围；两者共用本招收尾生命周期。
        local rainOk, rainUnits = pcall(world.CreateAsset, world, GameCfg.FishCombat.dragon.RainEffect)
        local rain = rainOk and type(rainUnits) == 'table' and rainUnits[1] or nil
        if rain then
            entry.Rain = rain
            local rainPlaced, rainErr = pcall(function()
                rain.Position = Vector3.New(p.x, p.y + 3, p.z)
            end)
            if not rainPlaced then
                print('[LocalGarBite] 暴雨摆放失败', fishId, tostring(rainErr))
                entry.Rain = nil
                local destroyed, destroyErr = pcall(function() rain:Destroy() end)
                if not destroyed then print('[LocalGarBite] 清理失败暴雨失败', fishId, tostring(destroyErr)) end
            end
        else
            print('[LocalGarBite] 暴雨创建失败', fishId, tostring(rainUnits))
        end
    end
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
    self.FrameConn = game:GetService('RunService').Heartbeat:Connect(function()
        local now = game:GetService('World'):GetServerTime()
        for id,entry in pairs(self.Active) do
            if entry.Projectile then
                local t=math.min(1,math.max(0,(now-entry.At)/entry.Duration))
                local o,p=entry.Origin,entry.Destination
                local ok,err=pcall(function() entry.Projectile.Position=Vector3.New(
                    o.x+(p.x-o.x)*t,o.y+(p.y-o.y)*t,o.z+(p.z-o.z)*t) end)
                if not ok then print('[LocalGarBite] 投掷轨迹失败',id,tostring(err)); self:Hide(id)
                elseif t>=1 then self:Hide(id) end
            end
        end
    end)
end

function LocalGarBite:Stop()
    if self.Conn then self.Conn:Disconnect() end
    if self.FrameConn then self.FrameConn:Disconnect() end
    self.FrameConn=nil
    self.Conn = nil
    for fishId in pairs(self.Active) do self:Hide(fishId) end
end

return LocalGarBite
