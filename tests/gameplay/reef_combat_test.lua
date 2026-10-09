-- #37 失败方式（编码前列出）：空中鱼仍不可抽取；飞过水面即消失；投掷未执行或重复结算；
-- 预警不锁落点导致无法躲避；俯冲不预警；死亡/超时留下攻击；本体与受击体错帧。
-- 接缝：真实业务管理器的 SpawnLanded/Drop/Update、RemoteEvent 和 Controller 血量。
-- 仅替换引擎对象、时间和 RemoteEvent，不替换业务管理器；不作为编辑器 E2E 证据。
local lu = require('luaunit')
local Cfg = require('common.GameCfg')
TestReefCombat = {}
local function signal()
    local slots = {}
    return { Connect = function(_, fn)
        slots[fn] = true
        return { Disconnect = function() slots[fn] = nil end }
    end, Fire = function(_, ...) for fn in pairs(slots) do fn(...) end end }
end
local function vec(x,y,z)
    return setmetatable({x=x,y=y,z=z}, {__add=function(a,b) return vec(a.x+b.x,a.y+b.y,a.z+b.z) end})
end
function TestReefCombat:setUp()
    self.saved = { game=_G.game, Vector3=_G.Vector3, Quaternion=_G.Quaternion, REUtil=_G.REUtil }
    self.modules = {}
    for _,name in ipairs({'server.Mgr.MgrFishCarrier','server.Mgr.MgrFishUnit','server.Mgr.MgrVitals','common.REUtil','client.LocalGarBite','client.LocalCastSource'}) do
        self.modules[name] = package.loaded[name]; package.loaded[name] = nil
    end
    self.now, self.notices, self.players, self.castStates = 0, {}, {}, {}
    self.units, self.heartbeat = {}, signal()
    local env = self
    self.world = { GetServerTime=function() return env.now end,
        CreateUnit=function(_,kind,values)
            local unit = {UnitType=kind, UnitId=tostring({}), OnLiftedBegin=signal(), OnLiftedEnd=signal()}
            for k,v in pairs(values) do unit[k]=v end
            env.units[#env.units+1]=unit
            function unit:Destroy() self.Destroyed=true end
            function unit:AddNoCollisionPairWithUnit() end
            function unit:SetPosition(p) self.Position=p end
            if values.EnableController then
                unit.Controller={Health=100,MaxHealth=100,HealthChanged=signal(),Died=signal()}
                function unit.Controller:TakeDamage(d)
                    self.Health=math.max(0,self.Health-d); self.HealthChanged:Fire(self.Health)
                    if self.Health==0 then self.Died:Fire() end
                end
            end
            return unit
        end }
    function self.world:CreateAsset(id) return {self:CreateUnit('WorldUnit',{Name=id})} end
    _G.Vector3={New=vec}; _G.Quaternion={FromEulerAngles=function() return {GetForward=function() return vec(0,0,1) end} end}
    _G.game={GetService=function(_,name)
        if name=='World' then return env.world end
        if name=='RunService' then return {IsServer=function() return true end,Heartbeat=env.heartbeat} end
        if name=='Players' then return {GetPlayers=function() return env.players end,PlayerRemoving=signal()} end
    end, CreateRemoteEvent=function(_,name) return {
        FireAllClients=function(_,p) if name=='GarBiteNotice' then env.notices[#env.notices+1]=p end end,
        FireClient=function(_,player,p) if name=='CastState' then env.castStates[#env.castStates+1]=p end end,
        OnServerEvent=signal(),OnClientEvent=signal() } end}
    self.carrier=require('server.Mgr.MgrFishCarrier')
    self.mgr=require('server.Mgr.MgrFishUnit')
    self.vitals=require('server.Mgr.MgrVitals'); self.vitals:Start()
    self.mgr.Vitals=self.vitals; self.mgr:Start()
    local safe=Cfg.Zones[6].Scene.SafePoint
    local c={Health=300,HealthChanged=signal(),Died=signal(),Lift=function() end}
    function c:TakeDamage(d) self.Health=math.max(0,self.Health-d); self.HealthChanged:Fire(self.Health) end
    self.player={UserId=3701,Character={Controller=c,Position=vec(safe.x,safe.y,safe.z),Rotation=_G.Quaternion.FromEulerAngles()},
        CharacterAdded=signal(),CharacterRemoving=signal(),SetAttribute=function() end}
    self.players[1]=self.player
    self.vitals:OnPlayerAdded(self.player); self.mgr:OnPlayerAdded(self.player)
end
function TestReefCombat:tearDown()
    for _,fish in pairs(self.mgr.Fish) do self.mgr:Remove(fish) end
    self.mgr:Stop(); self.vitals:OnPlayerRemoving(self.player)
    for name in pairs(self.modules) do package.loaded[name]=self.modules[name] end
    for _,name in ipairs({'server.Mgr.MgrFishCarrier','server.Mgr.MgrFishUnit','server.Mgr.MgrVitals','common.REUtil','client.LocalGarBite','client.LocalCastSource'}) do package.loaded[name]=self.modules[name] end
    for _,name in ipairs({'game','Vector3','Quaternion','REUtil'}) do _G[name]=self.saved[name] end
end
function TestReefCombat:drop(id)
    local fish=assert(self.mgr:SpawnLanded(self.player,{fishId=id,mult=1},self.player.Character.Position))
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    lu.assertTrue(self.mgr:Drop(self.player))
    return fish
end
function TestReefCombat:advance(to)
    while self.now < to-1e-8 do self.now=math.min(to,self.now+0.05); self.mgr:Update() end
end
function TestReefCombat:test_reef_fish_enter_normal_draw_pool_and_distinguish_air_source()
    local FishCatch=require('common.FishCatch')
    local rows=Cfg.Casting.Zones['reefIsland.water']
    lu.assertEquals(FishCatch.Select(rows,1,nil,function() return 0 end),'item81')
    lu.assertEquals(Cfg.Fish.item81.CatchSource,'air')
    lu.assertEquals(Cfg.Fish.item82.CatchSource,'water')
    lu.assertEquals(Cfg.Fish.item88.CatchSource,'water')
end
function TestReefCombat:test_flying_above_water_survives_and_receiver_follows_same_frame()
    local fish=self:drop('fish47Elite')
    local water=Cfg.Zones[6].Scene.Waters[1]
    fish.Carrier.Body.Position=vec(water.Center.x,water.SurfaceY+12,water.Center.z)
    -- 重新起飞以这条真实世界坐标作为轨迹起点。
    self.mgr:StartFlight(fish,self.now)
    self:advance(0.05)
    lu.assertEquals(fish.State,'flying')
    lu.assertEquals(fish.Carrier.Receiver.Position,fish.Carrier.Body.Position)
end
function TestReefCombat:test_pterosaur_throw_warns_then_hits_locked_ground_once()
    self:drop('fish48Boss')
    self:advance(4)
    local notice=self.notices[#self.notices]
    lu.assertNotNil(notice)
    lu.assertEquals(notice.move,'airThrow')
    lu.assertEquals(notice.range,5)
    lu.assertEquals(self.player.Character.Controller.Health,300)
    self:advance(5.3)
    lu.assertEquals(self.player.Character.Controller.Health,200)
    self.mgr:Update(); self.mgr:Update()
    lu.assertEquals(self.player.Character.Controller.Health,200)
end
function TestReefCombat:test_air_normal_escapes_after_one_second_but_penguin_stays_grounded()
    local air=self:drop('item81')
    lu.assertEquals(air.State,'flying')
    self:advance(1.05)
    lu.assertNil(self.mgr.Fish[air.Id])
    local penguin=self:drop('item82')
    lu.assertEquals(penguin.State,'escaping')
end
function TestReefCombat:test_stop_clears_inflight_warning_without_applying_pending_hit()
    self:drop('fish48Boss'); self:advance(4)
    self.mgr:Stop()
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    lu.assertEquals(self.notices[#self.notices].reason,'stop')
end
function TestReefCombat:test_throw_client_displays_falling_body_and_clear_destroys_it()
    local warn=require('client.LocalGarBite'); warn:Start()
    local n=require('common.GarBiteNotice')
    local p=n.Lock(-37,{x=0,y=6,z=0},0,1,5,180,1.2)
    p.move,p.shape,p.flightOrigin='airThrow','circle',{x=0,y=21,z=0}
    warn:Show(p)
    local body
    for _,u in ipairs(self.units) do if u.Name=='FlightThrow_-37' then body=u end end
    lu.assertNotNil(body)
    self.now=0.6; self.heartbeat:Fire()
    lu.assertTrue(body.Position.y>6 and body.Position.y<21)
    warn:Show(n.Clear(-37,'miss'))
    lu.assertTrue(body.Destroyed)
    warn:Stop()
end
function TestReefCombat:test_cast_state_exposes_air_origin_and_preserves_water_landing()
    local cast=assert(loadfile('server/Mgr/MgrCast.lua'))()
    local session={phase='hooked',castId=37,fishId='item81',landing={x=880,y=3,z=144}}
    cast:SendState(self.player,session)
    local s=self.castStates[#self.castStates]
    lu.assertEquals(s.catchSource,'air')
    lu.assertEquals(s.hookPosition,{x=880,y=15,z=144})
    lu.assertEquals(s.landing,{x=880,y=3,z=144})
    session.fishId='item82'; cast:SendState(self.player,session)
    lu.assertEquals(self.castStates[#self.castStates].hookPosition,session.landing)
end
function TestReefCombat:test_air_source_client_reuses_snapshot_and_clears_when_unhooked()
    local visual=require('client.LocalCastSource')
    local s={phase='hooked',castId=37,fishId='item81',hookPosition={x=880,y=15,z=144}}
    visual:Show(s)
    local count=#self.units
    visual:Show(s)
    lu.assertEquals(#self.units,count)
    local body
    for _,u in ipairs(self.units) do if u.Name=='CastSource_37' then body=u end end
    lu.assertNotNil(body)
    lu.assertEquals(body.Position.y,15)
    visual:Show({phase='unhooked',castId=37})
    lu.assertTrue(body.Destroyed)
end
function TestReefCombat:test_dive_cannot_follow_a_target_outside_reef_boundary()
    local fish=self:drop('fish47Elite')
    local b=Cfg.Zones[6].Scene.Boundary
    self.player.Character.Position=vec(b.MaxX+10,6,100)
    self:advance(20)
    while self.now<21.75 do
        self:advance(self.now+0.05)
        lu.assertTrue(fish.Carrier.Body.Position.x<=b.MaxX)
    end
end
function TestReefCombat:test_boss_summoned_at_other_water_keeps_the_current_zone_flight_bounds()
    local safe=Cfg.Zones[1].Scene.SafePoint
    self.player.Character.Position=vec(safe.x,safe.y,safe.z)
    local fish=self:drop('fish48Boss')
    self:advance(0.05)
    local b=Cfg.Zones[1].Scene.Boundary
    lu.assertTrue(fish.Carrier.Body.Position.x>=b.MinX and fish.Carrier.Body.Position.x<=b.MaxX)
end
