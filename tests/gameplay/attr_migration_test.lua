-- 失败方式：永久成长重复累加、默认100污染、重复乘区、写入失败误报、重建/退出残留。
-- 接缝：MgrAttr公开刷新/读取，真实根AttrAPI/vendor，仅Unit/World为离线引擎替身。
local lu = require('luaunit')
local function fixture()
    local all, cache = {}, {}
    local world = {}
    local function unit(kind, parent)
        local u = { Parent = parent, attrs = {}, Controller = kind == 'Character' and { WalkSpeed = 7, MaxHealth = 100, Health = 100 } or nil }
        function u:GetAttribute(k) return self.attrs[k] end
        function u:SetAttribute(k,v) self.attrs[k]=v end
        function u:IsA(k) return k == kind end
        function u:GetChildren() local out={} for _,v in ipairs(all) do if v.Parent==self then out[#out+1]=v end end return out end
        function u:FindFirstChildOfClass(k) if k=='PresetLink' and kind=='Script' then return { GetAttribute=function()return 'AttrUnit'end } end end
        function u:Destroy() self.Parent=nil self.destroyed=true end
        function u:SetScale(v) self.scale=v.x end
        all[#all+1]=u return u
    end
    function world:CreateAsset() return {unit('Script',world)} end
    local env=setmetatable({game={GetService=function()return world end}, Vector3={New=function(x,y,z)return{x=x,y=y,z=z}end}}, {__index=_G})
    env.require=function(name)
        if cache[name] then return cache[name] end
        cache[name]=assert(loadfile(name:gsub('%.','/')..'.lua','t',env))() return cache[name]
    end
    local mgr=env.require('server.Mgr.MgrAttr')
    local player={UserId=51,Character=unit('Character',world)}
    local data={body=2,speed=3,level=2}
    function data:PotionCount(id)return id=='item167' and self.speed or self.body end
    function data:ShopUpgradeLevel()return self.level end
    mgr.PlayerData={GetDataInst=function()return data end}
    mgr.MoveMultiplierProvider=function()return 0.35 end
    return mgr,player,data,all,unit,world
end
TestAttrMigration={}
function TestAttrMigration:test_hunger_and_weapon_use_vendor_without_new_save_authority()
    local mgr,p,data=fixture()
    local ok,hunger=mgr:ProjectHunger(p,1000)
    lu.assertTrue(ok) lu.assertEquals(hunger,300)
    lu.assertEquals(select(2,mgr:ProjectHunger(p,-2)),0)
    lu.assertAlmostEquals(mgr:WeaponDamageScale(p,'melee'),1.2,1e-8)
    data.level=3
    lu.assertAlmostEquals(mgr:WeaponDamageScale(p,'melee'),1.3,1e-8)
    lu.assertAlmostEquals(mgr:WeaponDamageScale(p,'melee'),1.3,1e-8)
end
function TestAttrMigration:test_capped_growth_and_paralysis_clear_without_residue()
    local mgr,p,data=fixture()
    data.body,data.speed=1000,1000
    mgr.MoveMultiplierProvider=function()return 0 end
    lu.assertTrue(mgr:ApplyGrowth(p).Ok)
    lu.assertEquals(mgr:MaxHealth(p),900) lu.assertEquals(p.Character.scale,3)
    lu.assertEquals(p.Character.Controller.WalkSpeed,0)
    mgr.MoveMultiplierProvider=function()return 1 end
    lu.assertTrue(mgr:RefreshMoveSpeed(p))
    lu.assertEquals(p.Character.Controller.WalkSpeed,21)
end
function TestAttrMigration:test_character_rebuild_and_leave_release_owned_attr_units()
    local mgr,p,_,all,unit,world=fixture()
    lu.assertTrue(mgr:ApplyGrowth(p).Ok)
    local first=mgr.AttrAPI.GetAttrUnit(p.Character)
    p.Character=unit('Character',world)
    p.Character.Controller.WalkSpeed=8
    lu.assertTrue(mgr:ApplyGrowth(p).Ok)
    lu.assertTrue(first.destroyed)
    lu.assertAlmostEquals(p.Character.Controller.WalkSpeed,3.64,1e-8)
    local current=mgr.AttrAPI.GetAttrUnit(p.Character)
    mgr:OnPlayerRemoving(p)
    lu.assertTrue(current.destroyed)
end
function TestAttrMigration:test_missing_character_retry_captures_real_base_when_character_arrives()
    local mgr,p,_,_,unit,world=fixture()
    p.Character=nil
    mgr:OnPlayerAdded(p)
    p.Character=unit('Character',world)
    p.Character.Controller.WalkSpeed=10
    mgr:Update()
    lu.assertAlmostEquals(p.Character.Controller.WalkSpeed,4.55,1e-8)
end
function TestAttrMigration:test_write_failure_is_reported_and_refresh_retries_current_projection()
    local mgr,p,data=fixture()
    local values={WalkSpeed=7,MaxHealth=100,Health=100}
    local deny=true
    p.Character.Controller=setmetatable({}, {__index=values,__newindex=function(_,k,v)
        if deny and k=='WalkSpeed' then error('write-denied') end values[k]=v
    end})
    local result=mgr:ApplyGrowth(p)
    lu.assertFalse(result.Ok) lu.assertStrContains(result.Error,'write-denied')
    data.speed=20 deny=false
    mgr.MoveMultiplierProvider=function()return 1 end
    lu.assertTrue(mgr:ApplyGrowth(p).Ok)
    lu.assertEquals(values.WalkSpeed,21)
end
function TestAttrMigration:test_vitals_food_and_revive_use_projected_health_and_hunger()
    local mgr,p,data=fixture()
    data.body=10
    local vitals=assert(loadfile('server/Mgr/MgrVitals.lua'))()
    vitals.Now=function()return 100 end
    vitals.Attr=mgr mgr.Vitals=vitals
    vitals.MaxHealthProvider=function(player)return mgr:MaxHealth(player)end
    lu.assertTrue(mgr:ApplyGrowth(p).Ok)
    vitals:OnPlayerAdded(p)
    lu.assertEquals(p.Character.Controller.Health,900)
    p.Character.Controller.Health=300
    lu.assertTrue(vitals:SetHunger(p,100))
    lu.assertTrue(vitals:Eat(p,'goldfish'))
    lu.assertEquals(p.Character.Controller.Health,570)
    lu.assertEquals(vitals:GetState(p).hunger,190)
    lu.assertEquals(mgr.AttrAPI.GetAttr(p.Character,'PlayerHunger'),190)
    local state=vitals:GetState(p) state.dead=true
    p.Character.scale=1 p.Character.Controller.WalkSpeed=7
    vitals:Revive(state,'test')
    lu.assertEquals(p.Character.scale,3)
    lu.assertAlmostEquals(p.Character.Controller.WalkSpeed,3.185,1e-8)
    lu.assertEquals(p.Character.Controller.Health,900)
    lu.assertEquals(mgr.AttrAPI.GetAttr(p.Character,'PlayerHunger'),300)
end
function TestAttrMigration:test_real_vendor_growth_is_idempotent_and_combines_one_move_multiplier()
    local mgr,p=fixture()
    local a=mgr:ApplyGrowth(p)
    lu.assertTrue(a.Ok,a.Error)
    lu.assertEquals(mgr:MaxHealth(p),420)
    lu.assertAlmostEquals(p.Character.Controller.WalkSpeed,3.185,1e-8)
    lu.assertEquals(p.Character.scale,1.4)
    lu.assertEquals(p.Character.attrs.InteractRange,require('common.BodyScale').Derive(1.4).InteractRange)
    lu.assertTrue(mgr:ApplyGrowth(p).Ok)
    lu.assertAlmostEquals(p.Character.Controller.WalkSpeed,3.185,1e-8)
end
