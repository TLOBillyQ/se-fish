-- #38 失败方式（编码前列出）：沧龙砸击永不落地/重复伤害、巡航不叼人、不移入水域；
-- 哥斯拉吐息零伤害、跟踪必中、无方向；阶段被携带挡住/跨阈值重复切换/旧预警残留；
-- 正常血量死亡、逃跑时限、玩家离线后还结算旧招。
-- 接缝沿用 #37 的真实管理器 SpawnLanded/Drop/Update、Controller 和对外预警。
require('tests.gameplay.reef_combat_test')
local lu = require('luaunit')
local Cfg = require('common.GameCfg')
TestVolcanoCombat = {}
TestVolcanoCombat.setUp = function(self)
    TestReefCombat.setUp(self)
    self.savedRemote = _G.RemoteEvent
    _G.RemoteEvent = { New = function() return { OnServerEvent = {
        Connect = function() return {Disconnect=function() end} end } } end }
    self.savedAbility = package.loaded['server.AbilityAPI']
    package.loaded['server.AbilityAPI'] = nil
    local p = Cfg.Zones[7].Scene.SafePoint
    self.player.Character.Position = Vector3.New(p.x,p.y,p.z)
end
TestVolcanoCombat.tearDown = function(self)
    TestReefCombat.tearDown(self)
    _G.RemoteEvent=self.savedRemote
    package.loaded['server.AbilityAPI']=self.savedAbility
end
TestVolcanoCombat.drop = TestReefCombat.drop
TestVolcanoCombat.advance = TestReefCombat.advance

function TestVolcanoCombat:test_breath_warns_then_kills_only_locked_forward_line()
    self.player.Character.Controller.Health = 1000
    local fish = self:drop('fish56Boss')
    self.now=30; self.mgr:Update()
    self.now=30.1; self.mgr:Update()
    self.now=30.2; self.mgr:Update()
    local warning = self.notices[#self.notices]
    lu.assertNotNil(warning)
    lu.assertEquals(warning.move,'bossBreath')
    lu.assertEquals(warning.shape,'line')
    lu.assertTrue(self.player.Character.Controller.Health > 0)
    self.now=31.8; self.mgr:Update()
    lu.assertEquals(self.player.Character.Controller.Health,0)
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
end

function TestVolcanoCombat:test_breath_has_reachable_range_and_player_can_dodge_sideways()
    self.player.Character.Controller.Health=1000
    local fish=self:drop('fish56Boss')
    local p=fish.Carrier.Body.Position
    self.player.Character.Position=Vector3.New(p.x,p.y,p.z+8)
    self.now=30; self.mgr:Update()
    local warning=self.notices[#self.notices]
    lu.assertNotNil(warning)
    lu.assertEquals(warning.move,'bossBreath')
    self.player.Character.Position=Vector3.New(p.x+4,p.y,p.z+8)
    self.now=32; self.mgr:Update()
    lu.assertEquals(self.player.Character.Controller.Health,1000)
end

function TestVolcanoCombat:test_mosasaur_warns_lands_once_and_carries_player_toward_actual_water()
    self.player.Character.Controller.Health=1000
    local fish=self:drop('fish55Elite')
    self:advance(15.1)
    lu.assertEquals(self.notices[#self.notices].move,'mosasaurLeap')
    self:advance(18)
    lu.assertNotNil(fish.Carry)
    lu.assertTrue(self.player.Character.Controller.Health<=665)
    local MathWater=require('common.MathWaterJudge')
    self:advance(25)
    lu.assertNotNil(MathWater.HitZone(Cfg.Water.Zones,self.player.Character.Position))
end

function TestVolcanoCombat:test_water_phase_reaches_water_and_enrage_interrupts_carry_and_old_warning_once()
    self.player.Character.Controller.Health=5000
    local fish=self:drop('fish56Boss')
    fish.Carrier.Receiver.Controller:TakeDamage(11000)
    self.mgr:Update()
    self:advance(5)
    local MathWater=require('common.MathWaterJudge')
    lu.assertNotNil(MathWater.HitZone(Cfg.Water.Zones,fish.Carrier.Body.Position))
    self:advance(18)
    lu.assertNotNil(fish.Carry)
    fish.Carrier.Receiver.Controller:TakeDamage(10000)
    self.mgr:Update()
    lu.assertNil(fish.Carry)
    lu.assertNil(MathWater.HitZone(Cfg.Water.Zones,fish.Carrier.Body.Position))
    self.mgr:Update(); self.mgr:Update()
    lu.assertEquals(fish.Phase.Stats.Transitions,2)
    lu.assertEquals(fish.Phase.Phase,'enraged')
end

function TestVolcanoCombat:test_cross_two_thresholds_and_offline_or_death_clear_pending_breath()
    local fish=self:drop('fish56Boss')
    self.player.Character.Controller.Health=1000
    self.now=30; self.mgr:Update(); self.now=30.1; self.mgr:Update(); self.now=30.2; self.mgr:Update()
    fish.Carrier.Receiver.Controller:TakeDamage(21000)
    self.mgr:Update()
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    lu.assertEquals(fish.Phase.Phase,'enraged')
    lu.assertEquals(fish.Phase.Stats.Transitions,1)
    self.now=41; self.mgr:Update(); self.now=41.1; self.mgr:Update(); self.now=41.2; self.mgr:Update()
    self.mgr:OnPlayerRemoving(self.player)
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    self.mgr:Remove(fish)
    self.now=60; self.mgr:Update()
    lu.assertTrue(self.player.Character.Controller.Health>0)
end

-- 表/正文并集失败方式：有爪击却漏掉正文独立跺脚（2秒、脚边10米150）。
function TestVolcanoCombat:test_stomp_warns_with_ten_metre_radius_and_deals_documented_damage()
    self.player.Character.Controller.Health=1000
    local fish=self:drop('fish56Boss')
    local p=fish.Carrier.Body.Position
    self.player.Character.Position=Vector3.New(p.x,p.y,p.z+8)
    self:advance(2.1)
    lu.assertEquals(self.notices[#self.notices].move,'bossStomp')
    lu.assertEquals(self.notices[#self.notices].range,10)
    self:advance(3)
    lu.assertEquals(self.player.Character.Controller.Health,850)
end

function TestVolcanoCombat:test_lethal_grab_does_not_leave_carry_or_mount_and_death_cancels_warning()
    local fish=self:drop('fish55Elite')
    self:advance(15.1)
    self.now=17.7; self.mgr:Update()
    lu.assertEquals(self.player.Character.Controller.Health,0)
    lu.assertNil(fish.Carry)
    lu.assertNil(fish.CarryMount)
end

-- 携带不能推迟落地甩头；预警到期后必须清掉，不能带入水中才结算。
function TestVolcanoCombat:test_head_warning_expires_at_landing_deadline_even_during_carry()
    self.player.Character.Controller.Health=5000
    local fish=self:drop('fish55Elite')
    self:advance(15.1)
    self.now=17.7; self.mgr:Update()
    lu.assertNotNil(fish.Carry)
    lu.assertEquals(self.notices[#self.notices].move,'mosasaurHead')
    self.now=18.6; self.mgr:Update()
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    lu.assertEquals(self.notices[#self.notices].reason,'head')
end

function TestVolcanoCombat:test_stop_cancels_aquatic_and_boss_warnings_without_ai_adapter()
    self:drop('fish55Elite'); self:advance(15.1)
    self.mgr:Stop()
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    lu.assertEquals(self.notices[#self.notices].reason,'stop')
end

-- 控制起手取消水中旧招；解除后平移冷却，不能立即补放控制期间到期的跳跃。
function TestVolcanoCombat:test_control_cancels_aquatic_warning_and_resumes_without_overdue_leap()
    self.player.Character.Controller.Health=5000
    self:drop('fish55Elite'); self:advance(15.1)
    local controlled=true
    self.mgr.Ai={Pause=function() end,Custom=function() return true end,Sync=function() return true end,
        Remove=function() end,Stop=function() end}
    self.mgr.Ability={FishParalyzed=function() return controlled end,RemoveFish=function() end}
    self.now=15.2; self.mgr:Update()
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    lu.assertEquals(self.notices[#self.notices].reason,'controlled')
    self.now=40; self.mgr:Update()
    controlled=false
    self.now=40.1; self.mgr:Update()
    self.now=41; self.mgr:Update()
    lu.assertEquals(self.notices[#self.notices].kind,'clear')
    self.mgr.Ai=nil
end

-- 携带过程中撞到另一名玩家也应造成150，不能只伤害嘴里的目标。
function TestVolcanoCombat:test_carry_contact_hits_nearby_bystander_once_per_second()
    self.player.Character.Controller.Health=5000
    local fish=self:drop('fish55Elite')
    self:advance(18.7)
    local controller={Health=1000}
    function controller:TakeDamage(amount) self.Health=math.max(0,self.Health-amount) end
    local peer={UserId=3802,SetAttribute=function() end,
        Character={Controller=controller,Position=fish.Carrier.Body.Position}}
    self.players[2]=peer
    self.vitals:OnPlayerAdded(peer)
    controller.Health=1000
    while self.now<19.7-1e-8 do
        peer.Character.Position=fish.Carrier.Body.Position
        self.now=math.min(19.7,self.now+0.05)
        self.mgr:Update()
    end
    self.vitals:OnPlayerRemoving(peer)
    self.players[2]=nil
    lu.assertEquals(controller.Health,850)
end
