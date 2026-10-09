-- #40：正式完成/跳过以及兜底的明确已读操作，落账到 Extra.story.read 后才确认。
-- 未配置正式 Story 资源时展示可保留阅读的对话，不自动把公告当成已读。
local GameCfg = require('common.GameCfg')

local Mgr = { States = {}, Requested = {}, Connections = {} }

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
        '影响=展示可读对话，正式剧情表现留待资源验收')
    self:SendFallback(player)
end

function Mgr:SendFallback(player)
    _G.REUtil:GetRE('StoryNotice'):FireClient(player, {
        text = cfg().FallbackText, lines = cfg().Lines or { cfg().FallbackText },
        readKey = cfg().ReadKey or 'opening', title = cfg().Title or '欢迎来到钓场',
    })
end

function Mgr:Begin(player)
    if not player then return end
    self.Requested[player.UserId] = player
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if self.Save and not data then return end
    local readKey = cfg().ReadKey or 'opening'
    if data and data.Extra.story.read and data.Extra.story.read[readKey] then
        self.Requested[player.UserId] = nil
        return
    end
    local previous = self.States[player.UserId]
    if previous and previous.player == player then
        if previous.phase == 'fallback' then self:SendFallback(player) end
        return
    end
    local state = { player = player, phase = 'pending', readKey = readKey }
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
    if not state or state.player ~= player or storyId ~= cfg().StoryId or storyId == nil then return end
    if name == 'OnStoryStart' and state.phase == 'pending' then
        state.phase = 'started'
        state.deadline = nil
    elseif (name == 'OnStoryEnd' or name == 'OnStorySkip')
        and (state.phase == 'started' or state.phase == 'pending') then
        self:Complete(player, state.readKey, name == 'OnStorySkip' and 'skip' or 'end')
    end
end

function Mgr:Complete(player, readKey, source)
    local state = player and self.States[player.UserId]
    if not state or state.player ~= player or readKey ~= state.readKey
        or source == 'read' and state.phase ~= 'fallback'
        or source ~= 'read' and source ~= 'end' and source ~= 'skip'
        or state.phase == 'read' or state.phase == 'saving' then return false end
    state.completeSource = source
    return self:PersistRead(player, state)
end

function Mgr:PersistRead(player, state)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if self.Save and not data then return true end
    if not self.Save then
        state.phase = 'read'
        _G.REUtil:GetRE('StoryState'):FireClient(player, { read = true, readKey = state.readKey })
        return true
    end
    local operation = self.Save:NextOperation(player, 'story-read')
    if not operation then return true end
    local previousPhase = state.phase
    state.phase = 'saving'
    local accepted = self.Save:Execute(player, data, operation, function(draft)
        draft.Extra.story.read = draft.Extra.story.read or {}
        draft.Extra.story.read[state.readKey] = true
        return { read = true, readKey = state.readKey }
    end, function(written, result)
        if self.States[player.UserId] ~= state then return end
        if not written then
            state.phase = previousPhase
            state.failed = true
            print('[MgrStory] 已读未落账', player.UserId, tostring(result))
            _G.REUtil:GetRE('StoryState'):FireClient(player, {
                read = false, readKey = state.readKey, text = '已读尚未保存，请稍后重进再试。',
            })
            local leave = state.leave
            state.leave = nil
            if leave then leave() end
            return
        end
        state.phase, state.completeSource, state.deadline = 'read', nil, nil
        print('[MgrStory] 已读落账', player.UserId, state.readKey)
        _G.REUtil:GetRE('StoryState'):FireClient(player, result)
        local leave = state.leave
        state.leave = nil
        if leave then leave() end
    end)
    if not accepted then state.phase = previousPhase end
    return accepted
end

function Mgr:FlushBeforeLeave(player, done)
    local state = player and self.States[player.UserId]
    if not self.Save or not state or state.player ~= player or state.failed
        or not state.completeSource or self.Save:Status(player.UserId).loadState ~= 'ready' then return false end
    state.leave = done
    if state.phase ~= 'saving' then self:PersistRead(player, state) end
    return true
end

function Mgr:OnPlayerAdded(player)
    if self.Requested[player.UserId] == player then self:Begin(player) end
end

function Mgr:Update()
    local now
    for _, player in pairs(self.Requested) do
        if not self.States[player.UserId] then self:Begin(player) end
    end
    for userId, state in pairs(self.States) do
        if state.completeSource and state.phase ~= 'saving' then self:PersistRead(state.player, state) end
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
    if player then
        if self.Requested[player.UserId] == player then self.Requested[player.UserId] = nil end
        local state = self.States[player.UserId]
        if state and state.player == player then self.States[player.UserId] = nil end
    end
end

function Mgr:Start()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections = {}
    self.World = game:GetService('World')
    local ok, service = pcall(function() return game:GetService('StoryService') end)
    self.Service = ok and service or nil
    if not ok then print('[MgrStory] StoryService 不可用', tostring(service)) end
    if self.Service then
        for _, name in ipairs({ 'OnStoryStart', 'OnStoryEnd', 'OnStorySkip' }) do
            local signal = self.Service[name]
            if signal then
                self.Connections[#self.Connections + 1] = signal:Connect(function(player, storyId)
                    self:OnSignal(name, player, storyId)
                end)
            end
        end
    end
    self.Connections[#self.Connections + 1] = _G.REUtil:GetRE('RequestStory').OnServerEvent:Connect(function(player)
        if _G.REUtil:CheckRECD(player, 'RequestStory', 0.5) then return end
        self:Begin(player)
    end)
    self.Connections[#self.Connections + 1] = _G.REUtil:GetRE('StoryRead').OnServerEvent:Connect(function(player, payload)
        if type(payload) ~= 'table' or payload.action ~= 'read' or type(payload.readKey) ~= 'string'
            or _G.REUtil:CheckRECD(player, 'StoryRead', 0.5) then return end
        self:Complete(player, payload.readKey, 'read')
    end)
end

return Mgr
