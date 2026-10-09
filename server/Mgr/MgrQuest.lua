-- 新手任务管理器（#40）：已确认的任务事实排队写 Extra.quest，落账之后才发布。
-- 发送方只在自己的玩法成功之后调用，payload 带 itemId 与服务端生成的唯一 eventId（拾饵 = 鱼饵 id，
-- 喂食 / 购买 = 玩家 + 请求序号）；任务不反查玩法系统、不发奖励。
-- 状态变化时写玩家属性 QuestStep / QuestText，并经 QuestState 下发 {step, total, count, need, text, done, notice}；
-- notice 只在推进那一次带，客户端用消息条提示下一步。
local GameCfg = require('common.GameCfg')
local QuestSteps = require('common.QuestSteps')

local Mgr = { States = {}, Players = {}, Queues = {} }

local function cfg()
    return GameCfg.Quest
end

function Mgr:Send(player, state)
    _G.REUtil:GetRE('QuestState'):FireClient(player, state)
end

function Mgr:GetState(player)
    if player and self.Players[player.UserId] == player then return self.States[player.UserId] end
end

function Mgr:Publish(player, notice)
    local state = self:GetState(player)
    if not state then return end
    local c = cfg()
    local current = c.Steps[state.step]
    local text = QuestSteps.Text(c.Steps, state, c.Title, c.DoneText)
    local ok, err = pcall(function()
        player:SetAttribute('QuestStep', state.step)
        player:SetAttribute('QuestText', text)
    end)
    if not ok then print('[MgrQuest] 属性发布失败', player.UserId, tostring(err)) end
    self:Send(player, {
        step = state.step, total = #c.Steps, count = state.count, need = current and current.Need or 0,
        text = text, done = current == nil, notice = notice,
    })
end

-- 收到一条玩法事实；计数返回 true
function Mgr:Notify(kind, player, payload)
    local state = self:GetState(player)
    if not state or type(payload) ~= 'table' then return false end
    local c = cfg()
    if self.Save then
        local queue = self.Queues[player.UserId]
        if queue.leaving then return false end
        local data = self.PlayerData and self.PlayerData:GetDataInst(player)
        -- 任务落账或其他业务写档期间真实 data 暂时 Inited=false；已就绪会话的事实仍可排队。
        if not data and queue and self.Save:Status(player.UserId).loadState == 'ready'
            and queue.data.Player == player then data = queue.data end
        if not data then return false end
        local eventId = payload.eventId
        if type(eventId) ~= 'string' or #eventId < 1 or #eventId > 160 then return false end
        local candidate = QuestSteps.Restore(c.Steps, queue.tail or state)
        -- 运行时拾饵/抛竿序号会重新开始；以持久 epoch 隔开新的合法玩法事实。
        local fact = { kind = kind, itemId = payload.itemId, category = payload.category,
            eventId = tostring(data.SaveMeta.epoch) .. ':' .. eventId, count = payload.count }
        if not QuestSteps.Apply(c.Steps, candidate, fact) then return false end
        queue.events[#queue.events + 1] = fact
        queue.tail = candidate
        self:Drain(player)
        return true
    end
    local counted, advanced = QuestSteps.Apply(c.Steps, state, { kind = kind, itemId = payload.itemId,
        category = payload.category, eventId = payload.eventId, count = payload.count })
    if not counted then return false end
    local notice
    if advanced then
        local finished = c.Steps[state.step - 1]
        local nextStep = c.Steps[state.step]
        notice = nextStep and string.format(c.NextNotice, nextStep.Text) or c.DoneText
        print('[MgrQuest] 完成', player.UserId, 'step=' .. tostring(state.step - 1), finished.Kind, tostring(payload.eventId))
    else
        print('[MgrQuest] 计数', player.UserId, 'step=' .. tostring(state.step), kind,
            tostring(state.count) .. '/' .. tostring(c.Steps[state.step].Need), tostring(payload.eventId))
    end
    self:Publish(player, notice)
    return true
end

function Mgr:OnPlayerAdded(player)
    if not player or self.Players[player.UserId] == player then return end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if self.Save and not data then return end
    self.Players[player.UserId] = player
    self.States[player.UserId] = data and QuestSteps.Restore(cfg().Steps, data.Extra.quest) or QuestSteps.New()
    self.Queues[player.UserId] = { player = player, data = data, events = {} }
    self:Publish(player)
end

function Mgr:OnPlayerRemoving(player)
    if player and self.Players[player.UserId] == player then
        self.States[player.UserId], self.Players[player.UserId], self.Queues[player.UserId] = nil, nil, nil
    end
end

function Mgr:Drain(player)
    local queue = player and self.Queues[player.UserId]
    if not queue or queue.player ~= player or queue.writing or #queue.events == 0 then return end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return end
    local operation = self.Save:NextOperation(player, 'quest-fact')
    if not operation then return end
    local fact, c = queue.events[1], cfg()
    queue.writing = true
    local accepted = self.Save:Execute(player, data, operation, function(draft)
        local state = QuestSteps.Restore(c.Steps, draft.Extra.quest)
        local counted, advanced = QuestSteps.Apply(c.Steps, state, fact)
        draft.Extra.quest = state
        return { counted = counted, advanced = advanced }
    end, function(written, result)
        if self.Queues[player.UserId] ~= queue then return end
        queue.writing = false
        if not written then
            print('[MgrQuest] 任务未落账', player.UserId, tostring(result))
            queue.failed = true
            local leave = queue.leave
            queue.leave = nil
            if leave then leave() end
            return
        end
        table.remove(queue.events, 1)
        local restored = QuestSteps.Restore(c.Steps, data.Extra.quest)
        self.States[player.UserId] = restored
        local notice
        if result.advanced then
            local nextStep = c.Steps[restored.step]
            notice = nextStep and string.format(c.NextNotice, nextStep.Text) or c.DoneText
        end
        print('[MgrQuest] 任务落账', player.UserId, 'step=' .. restored.step,
            'count=' .. restored.count, fact.eventId)
        self:Publish(player, notice)
        if #queue.events == 0 then queue.tail = nil end
        self:Drain(player)
        if #queue.events == 0 and not queue.writing and queue.leave then
            local leave = queue.leave
            queue.leave = nil
            leave()
        end
    end)
    if not accepted then queue.writing = false end
end

-- 入口先排空已受理的事实再销毁 PlayerData；避免最后一只蚯蚓的事实还在队里就退出丢进度。
-- 写失败仍按 Save 屏障退出，不把未确认的进度写成成功。
function Mgr:FlushBeforeLeave(player, done)
    local queue = player and self.Queues[player.UserId]
    if not self.Save or not queue or queue.player ~= player or queue.failed
        or self.Save:Status(player.UserId).loadState ~= 'ready'
        or #queue.events == 0 and not queue.writing then return false end
    queue.leaving, queue.leave = true, done
    self:Drain(player)
    return true
end

function Mgr:Update()
    for _, queue in pairs(self.Queues) do self:Drain(queue.player) end
end

function Mgr:Start()
    if self.Connection then self.Connection:Disconnect() end
    self.Connection = _G.REUtil:GetRE('RequestQuest').OnServerEvent:Connect(function(player)
        if _G.REUtil:CheckRECD(player, 'RequestQuest', 0.5) then return end
        self:OnPlayerAdded(player)
        self:Publish(player)
    end)
end

return Mgr
