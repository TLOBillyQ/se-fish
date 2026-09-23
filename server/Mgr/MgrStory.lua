-- 开场对话（#54，#40 规格）：客户端主界面首次打开时发 RequestStory，服务端对这名玩家调一次
-- StoryService:StartStory(player, GameCfg.Story.StoryId)；同一玩家本局只调一次，界面重开不重播。
-- 跳过由剧情系统自带的跳过按钮负责；任务推进与剧情无关，OnStoryStart / OnStoryEnd / OnStorySkip 只打日志取证。
-- 降级：StoryId 未配置、StoryService 不可用、StartStory 报错，或 StartTimeoutSec 秒内没收到 OnStoryStart，
-- 就经 StoryNotice 给这名玩家发单行公告 FallbackText，并打「[MgrStory] 降级」日志（原因 / 影响 / 接受者）；不卡进图。
local GameCfg = require('common.GameCfg')

local Mgr = { States = {} }

local function cfg()
    return GameCfg.Story
end

function Mgr:Now()
    self.World = self.World or game:GetService('World')
    return self.World:GetServerTime()
end

function Mgr:Fallback(player, state, reason)
    if state.phase ~= 'pending' then return end
    state.phase = 'fallback'
    state.deadline = nil
    print('[MgrStory] 降级 开场剧情', player.UserId, '原因=' .. tostring(reason),
        '影响=没有剧情对话界面与跳过按钮，改为单行公告', '接受者=待用户确认')
    _G.REUtil:GetRE('StoryNotice'):FireClient(player, { text = cfg().FallbackText })
end

function Mgr:Begin(player)
    if not player or self.States[player.UserId] then return end
    local state = { phase = 'pending' }
    self.States[player.UserId] = state
    local storyId = cfg().StoryId
    if storyId == nil or storyId == '' then return self:Fallback(player, state, '未配置 storyID') end
    if not self.Service then return self:Fallback(player, state, 'StoryService 不可用') end
    local ok, err = pcall(function() self.Service:StartStory(player, storyId) end)
    if not ok then return self:Fallback(player, state, 'StartStory 报错 ' .. tostring(err)) end
    print('[MgrStory] StartStory', player.UserId, storyId)
    if state.phase == 'pending' then state.deadline = self:Now() + cfg().StartTimeoutSec end
end

function Mgr:OnSignal(name, player, storyId)
    local state = player and self.States[player.UserId]
    print('[MgrStory]', name, player and player.UserId, tostring(storyId), state and state.phase)
    if name == 'OnStoryStart' and state and state.phase == 'pending' then
        state.phase = 'started'
        state.deadline = nil
    end
end

function Mgr:Update()
    local now
    for userId, state in pairs(self.States) do
        if state.deadline then
            now = now or self:Now()
            if now >= state.deadline then
                local player
                for _, p in ipairs(game:GetService('Players'):GetPlayers()) do
                    if p.UserId == userId then player = p end
                end
                if player then
                    self:Fallback(player, state, cfg().StartTimeoutSec .. ' 秒内未收到 OnStoryStart（剧情配表里可能没有这条剧情）')
                else
                    state.deadline = nil
                end
            end
        end
    end
end

function Mgr:OnPlayerRemoving(player)
    if player then self.States[player.UserId] = nil end
end

function Mgr:Start()
    self.World = game:GetService('World')
    local ok, service = pcall(function() return game:GetService('StoryService') end)
    self.Service = ok and service or nil
    if self.Service then
        for _, name in ipairs({ 'OnStoryStart', 'OnStoryEnd', 'OnStorySkip' }) do
            local signal = self.Service[name]
            if signal then
                signal:Connect(function(player, storyId) self:OnSignal(name, player, storyId) end)
            end
        end
    end
    _G.REUtil:GetRE('RequestStory').OnServerEvent:Connect(function(player)
        self:Begin(player)
    end)
end

return Mgr
