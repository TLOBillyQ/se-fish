-- 失败方式：派生范围无消费者、非法复制属性扩大距离、相机覆盖其他模式、角色重建残留。
-- 接缝：BodyScale.InteractionRadius、LocalAttr.Refresh/Stop、MgrInteract.InRange。
local lu=require('luaunit')
TestAttrPresentation={}
function TestAttrPresentation:test_camera_refresh_respects_other_owner_and_restores_on_stop()
    local env=setmetatable({}, {__index=_G})
    local mgr=assert(loadfile('client/LocalAttr.lua','t',env))()
    local character={GetAttribute=function()return 24 end}
    local camera={Distance=8,TrackingUnit=character}
    lu.assertTrue(mgr:Refresh(character,camera)) lu.assertEquals(camera.Distance,18)
    camera.Distance=12
    lu.assertFalse(mgr:Refresh(character,camera)) lu.assertEquals(camera.Distance,12)
    mgr:Stop() lu.assertEquals(camera.Distance,12)
    local fresh=assert(loadfile('client/LocalAttr.lua','t',env))()
    camera.Distance=8
    lu.assertTrue(fresh:Refresh(character,camera))
    fresh:Stop() lu.assertEquals(camera.Distance,8)
end
function TestAttrPresentation:test_server_range_scales_radius_but_keeps_slack_and_rejects_missing_character()
    local mgr=assert(loadfile('server/Mgr/MgrInteract.lua'))()
    local anchor={Position={x=0,z=0}}
    mgr.FindAnchor=function()return anchor end
    local value=require('common.BodyScale').Derive(3).InteractRange
    local character={Position={x=12.5,z=0},GetAttribute=function()return value end}
    local p={Character=character}
    local point={AnchorName='test',Radius=4,Slack=0.5}
    lu.assertEquals(mgr:InRange(p,point),anchor)
    character.Position.x=12.51 lu.assertNil(mgr:InRange(p,point))
    value=math.huge character.Position.x=4.5 lu.assertEquals(mgr:InRange(p,point),anchor)
    character.Position.x=4.51 lu.assertNil(mgr:InRange(p,point))
    p.Character=nil lu.assertNil(mgr:InRange(p,point))
end
function TestAttrPresentation:test_camera_rebuild_restores_old_camera_and_uses_new_character_projection()
    local mgr=assert(loadfile('client/LocalAttr.lua'))()
    local first={GetAttribute=function()return 18 end}
    local second={GetAttribute=function()return 6 end}
    local camera={Distance=8,TrackingUnit=first}
    lu.assertTrue(mgr:Refresh(first,camera))
    camera.TrackingUnit=second
    lu.assertTrue(mgr:Refresh(second,camera)) lu.assertEquals(camera.Distance,6)
    mgr:Stop() lu.assertEquals(camera.Distance,8)
end
function TestAttrPresentation:test_interaction_radius_scales_and_falls_back_for_invalid_attributes()
    local body=require('common.BodyScale')
    local value=body.Derive(3).InteractRange
    local character={GetAttribute=function()return value end}
    lu.assertEquals(body.InteractionRadius(character,4),12)
    value=math.huge lu.assertEquals(body.InteractionRadius(character,4),4)
    value=body.Derive(100).InteractRange lu.assertEquals(body.InteractionRadius(character,4),12)
end
