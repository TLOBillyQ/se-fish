-- #38 失败方式（先列后写）：本地未保存就提交平台、未配置ID伪成功、异常后丢任务、
-- 重试累加进度重复授予、重进漏补交、旧玩家回调串到新会话。
-- 接缝：真实PlayerData序列化与管理器公开Update；ArchiveService由引擎替身提供。
local lu=require('luaunit')
local Cfg=require('common.GameCfg')
TestAchievementDelivery={}
function TestAchievementDelivery:setUp()
    self.savedId=Cfg.Achievements.final.PlatformId
    Cfg.Achievements.final.PlatformId=3801
    self.now,self.calls,self.completed=0,0,false
    self.player={UserId=38,SetAttribute=function() end}
    self.data=assert(loadfile('server/Data/PlayerData.lua'))().New(self.player,function() end)
    self.data:Init()
    self.mgr=assert(loadfile('server/Mgr/MgrAchievements.lua'))()
    local env=self
    self.mgr.PlayerData={GetDataInst=function(_,p) return p==env.player and env.data end}
    self.mgr.Players={GetPlayers=function() return {env.player} end}
    self.mgr.World={GetServerTime=function() return env.now end}
    self.mgr.Archive={
        IsAchievementCompleted=function() if env.unavailable then error('平台暂不可用') end return env.completed end,
        SetAchievementProgress=function(_,p,id,count)
            lu.assertEquals(p,env.player); lu.assertEquals(id,3801); lu.assertEquals(count,1)
            env.calls=env.calls+1
        end}
end
function TestAchievementDelivery:tearDown() Cfg.Achievements.final.PlatformId=self.savedId end
function TestAchievementDelivery:test_completed_local_mark_retries_absolute_progress_and_only_acknowledges_platform_confirmation()
    self.mgr:Update()
    lu.assertEquals(self.calls,0)
    self.data.Extra.achievements.final=true
    self.unavailable=true; self.mgr:Update()
    self.unavailable=false; self.now=20; self.mgr:Update()
    lu.assertEquals(self.calls,1)
    lu.assertNil(self.data.Extra.achievementDelivered and self.data.Extra.achievementDelivered.final)
    self.completed=true; self.now=40; self.mgr:Update()
    lu.assertTrue(self.data.Extra.achievementDelivered.final)
    self.now=60; self.mgr:Update()
    lu.assertEquals(self.calls,1)
    local saved=self.data:Serialize()
    self.data:ApplySave(saved)
    self.mgr:OnPlayerRemoving(self.player)
    self.now=80; self.mgr:Update()
    lu.assertEquals(self.calls,1)
end
function TestAchievementDelivery:test_missing_platform_id_keeps_local_completion_pending()
    self.data.Extra.achievements.final=true
    Cfg.Achievements.final.PlatformId=nil
    self.mgr:Update()
    lu.assertEquals(self.calls,0)
    lu.assertNil(self.data.Extra.achievementDelivered)
end

-- 存档入口同步拒绝不调用回调，不能锁住之后的真实补交。
function TestAchievementDelivery:test_save_busy_rejection_retries_platform_confirmation_later()
    self.data.Extra.achievements.final=true
    self.completed=true
    local attempts=0
    self.mgr.Save={
        NextOperation=function() return {id='38:1'} end,
        Execute=function(_,player,data,operation,transform,done)
            attempts=attempts+1
            if attempts==1 then return false,'pending' end
            transform(data); done(true,{ok=true}); return true
        end}
    self.mgr:Update()
    self.now=20; self.mgr:Update()
    lu.assertTrue(self.data.Extra.achievementDelivered and self.data.Extra.achievementDelivered.final)
    lu.assertEquals(attempts,2)
end
