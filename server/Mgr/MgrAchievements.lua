-- 通关成就以本地存档为交付队列；平台只设置绝对进度，不递增。
-- 平台ID未交付/平台不可用时保留本地完成标记，重进后继续补交；仅确认完成后落已送达标记。
-- API：SE ArchiveService 服务端 SetAchievementProgress / IsAchievementCompleted（当前实例meta已核）。
local GameCfg=require('common.GameCfg')
local Mgr={RetryAt={},Busy={}}

function Mgr:Confirm(player,data,key)
    if self.PlayerData:GetDataInst(player)~=data or self.Busy[player.UserId] then return end
    if self.Save then
        local operation=self.Save:NextOperation(player,'achievement-confirm')
        if not operation then return end
        self.Busy[player.UserId]=true
        local accepted,reason=self.Save:Execute(player,data,operation,function(draft)
            if not draft.Extra.achievements[key] then return nil,'not-completed' end
            draft.Extra.achievementDelivered=draft.Extra.achievementDelivered or {}
            draft.Extra.achievementDelivered[key]=true
            return {ok=true,achievement=key}
        end,function(ok,result)
            if self.PlayerData:GetDataInst(player)~=data then return end
            self.Busy[player.UserId]=nil
            if not ok then print('[MgrAchievements] 平台确认落账失败',player.UserId,key,tostring(result)) end
        end)
        if not accepted and self.PlayerData:GetDataInst(player)==data then
            self.Busy[player.UserId]=nil
            print('[MgrAchievements] 平台确认暂不能落账，保留补交',player.UserId,key,tostring(reason))
        end
    else
        data.Extra.achievementDelivered=data.Extra.achievementDelivered or {}
        data.Extra.achievementDelivered[key]=true
        data:UpdateData(function() end,true)
    end
end

function Mgr:Update()
    if not self.PlayerData or not self.Players or not self.World then return end
    local now=self.World:GetServerTime()
    for _, player in ipairs(self.Players:GetPlayers()) do
        local data=self.PlayerData:GetDataInst(player)
        if data and data.Inited and not self.Busy[player.UserId]
            and now>=(self.RetryAt[player.UserId] or 0) then
            for key,definition in pairs(GameCfg.Achievements) do
                local id=definition.PlatformId
                if data.Extra.achievements and data.Extra.achievements[key]
                    and not (data.Extra.achievementDelivered and data.Extra.achievementDelivered[key])
                    and type(id)=='number' and id>0 and id==math.floor(id) then
                    self.RetryAt[player.UserId]=now+GameCfg.AchievementDelivery.RetrySec
                    if self.Archive then
                        local ok,done=pcall(self.Archive.IsAchievementCompleted,self.Archive,player,id)
                        if not ok then
                            print('[MgrAchievements] 平台查询失败，保留补交',player.UserId,key,tostring(done))
                        elseif done==true then
                            self:Confirm(player,data,key)
                        elseif done==false then
                            local sent,err=pcall(self.Archive.SetAchievementProgress,self.Archive,player,id,1)
                            if not sent then print('[MgrAchievements] 平台提交失败，保留补交',player.UserId,key,tostring(err)) end
                        end
                    end
                end
            end
        end
    end
end

function Mgr:OnPlayerRemoving(player)
    self.RetryAt[player.UserId],self.Busy[player.UserId]=nil,nil
end

function Mgr:Start()
    self.World=game:GetService('World')
    self.Players=game:GetService('Players')
    self.Archive=game:GetService('ArchiveService')
end

return Mgr
