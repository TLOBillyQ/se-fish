-- 礁石岛收线的来源灰盒：企鹅出水，其余自空中拉向玩家；与界面显隐无关。
-- CastState 仅描述表现，活鱼/奖励仍由服务端上岸结算；脱钩/收竿/死亡清除本地实体。
local GameCfg = require('common.GameCfg')
local Visual = {}
local function point(p)
    if not p then return false end
    for _,key in ipairs({'x','y','z'}) do
        local ok,v=pcall(function() return p[key] end)
        if not ok then return false end
        if type(v)~='number' or v~=v or math.abs(v)==math.huge then return false end
    end
    return true
end
function Visual:Clear()
    for _,unit in pairs({Body=self.Body,Line=self.Line}) do
        local ok,err=pcall(function() unit:Destroy() end)
        if not ok then print('[LocalCastSource] 收起来源失败',tostring(err)) end
    end
    self.Body,self.Line,self.State=nil,nil,nil
end
function Visual:Show(state)
    if type(state)~='table' then return end
    local fish=state.fishId and GameCfg.Fish[state.fishId]
    if state.phase~='hooked' or not fish or fish.ZoneId~='reefIsland' then self:Clear(); return end
    if type(state.castId)~='number' or not point(state.hookPosition) then return end
    if self.State and self.State.castId==state.castId and self.State.fishId==state.fishId then return end
    self:Clear()
    local world=game:GetService('World')
    local p=state.hookPosition
    local ok,body=pcall(world.CreateUnit,world,'WorldUnit',{
        Name='CastSource_'..tostring(state.castId),Position=Vector3.New(p.x,p.y,p.z),
        RenderMeshId='official://mesh/'..fish.Model,PhysicsActive=false,CanQuery=false,
        ModelColor1=Color.New(fish.VisualColor[1],fish.VisualColor[2],fish.VisualColor[3],fish.VisualColor[4]) })
    if not ok or not body then print('[LocalCastSource] 创建来源失败',tostring(body)); return end
    self.Body,self.State=body,state
    -- LinkEffectUnit 的 Position/EndPosition 在本地存根公开；不依赖不存在的 StartBindUnit。
    local lineOk,line=pcall(world.CreateUnit,world,'LinkEffectUnit',{
        Name='CastSourceLine_'..tostring(state.castId),EffectId=GameCfg.Casting.LineEffect,
        Position=Vector3.New(p.x,p.y,p.z),EndPosition=Vector3.New(p.x,p.y,p.z) })
    if lineOk and line then self.Line=line
    else print('[LocalCastSource] 创建鱼线失败',tostring(line)) end
    print('[LocalCastSource] 来源',state.castId,state.fishId,fish.CatchSource,p.y)
end
function Visual:Start()
    if self.Conn then return end
    self.Conn=require('common.REUtil'):GetRE('CastState').OnClientEvent:Connect(function(state) self:Show(state) end)
    self.Frame=game:GetService('RunService').Heartbeat:Connect(function()
        if not self.Body or not self.State then return end
        local player=game:GetService('Players').LocalPlayer
        local target=player and player.Character and player.Character.Position
        if not point(target) then return end
        local reel=_G.LocalReelIn
        local progress=reel and reel:DisplayProgress() or 50
        local t=math.min(1,math.max(0,((progress or 50)-50)/50))
        local o=self.State.hookPosition
        local p=Vector3.New(o.x+(target.x-o.x)*t,o.y+(target.y+2-o.y)*t,o.z+(target.z-o.z)*t)
        local ok,err=pcall(function()
            self.Body.Position=p
            if self.Line then self.Line.Position=Vector3.New(target.x,target.y+1,target.z); self.Line.EndPosition=p end
        end)
        if not ok then print('[LocalCastSource] 更新来源失败',tostring(err)); self:Clear() end
    end)
end
function Visual:Stop()
    if self.Conn then self.Conn:Disconnect() end
    if self.Frame then self.Frame:Disconnect() end
    self.Conn,self.Frame=nil,nil
    self:Clear()
end
return Visual
