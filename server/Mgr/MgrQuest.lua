-- 新手任务管理器（#51，#40 规格）：按玩家持单局内存态的任务进度，唯一入口 Notify(kind, player, payload)。
-- 发送方只在自己的玩法成功之后调用，payload 带 itemId 与服务端生成的唯一 eventId（拾饵 = 鱼饵 id，
-- 喂食 / 购买 = 玩家 + 请求序号）；任务不反查玩法系统、不发奖励。
-- 状态变化时写玩家属性 QuestStep / QuestText，并经 QuestState 下发 {step, total, count, need, text, done, notice}；
-- notice 只在推进那一次带，客户端用消息条提示下一步。
local GameCfg = require('common.GameCfg')
local QuestSteps = require('common.QuestSteps')

local Mgr = { States = {} }

local function cfg()
    return GameCfg.Quest
end

function Mgr:Send(player, state)
    _G.REUtil:GetRE('QuestState'):FireClient(player, state)
end

function Mgr:GetState(player)
    return player and self.States[player.UserId]
end

function Mgr:Publish(player, notice)
    local state = self:GetState(player)
    if not state then return end
    local c = cfg()
    local current = c.Steps[state.step]
    local text = QuestSteps.Text(c.Steps, state, c.Title, c.DoneText)
    pcall(function()
        player:SetAttribute('QuestStep', state.step)
        player:SetAttribute('QuestText', text)
    end)
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
    local counted, advanced = QuestSteps.Apply(c.Steps, state, kind, payload.itemId, payload.eventId, payload.count)
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
    if not player or self.States[player.UserId] then return end
    self.States[player.UserId] = QuestSteps.New()
    self:Publish(player)
end

function Mgr:OnPlayerRemoving(player)
    if player then self.States[player.UserId] = nil end
end

function Mgr:Start()
    _G.REUtil:GetRE('RequestQuest').OnServerEvent:Connect(function(player)
        self:Publish(player)
    end)
end

return Mgr
