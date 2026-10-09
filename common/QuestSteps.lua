-- 新手任务步骤状态机（#51，#40 规格），纯函数、不碰引擎对象。
-- 步骤表来自 GameCfg.Quest.Steps：每步 { Kind=玩法事实种类, ItemId=要求的物品（nil 不限）,
-- Category=要求的物品类别（nil 不限）, Need=次数, Text=文案 }。
-- 只有当前步对应的事实计数；同一 eventId 只记一次（按事实身份去重，不按物品载荷）；只进不退。
local QuestSteps = {}

function QuestSteps.New()
    return { step = 1, count = 0, seen = {} }
end

-- 旧存档未保存 seen 时按空表恢复；返回独立副本，草稿计算不改已发布进度。
function QuestSteps.Restore(steps, saved)
    if type(saved) ~= 'table' then return QuestSteps.New() end
    local step, count = saved.step, saved.count
    if type(step) ~= 'number' or step ~= math.floor(step) or step < 1 or step > #steps + 1
        or type(count) ~= 'number' or count ~= math.floor(count) or count < 0
        or count >= (steps[step] and steps[step].Need or 1) then return QuestSteps.New() end
    local state = { step = step, count = count, seen = {} }
    for id, seen in pairs(type(saved.seen) == 'table' and saved.seen or {}) do
        if type(id) == 'string' and seen == true then state.seen[id] = true end
    end
    return state
end

function QuestSteps.Done(steps, state)
    return state.step > #steps
end

-- 收到一条玩法事实 fact = {kind, itemId, category, eventId, count}；计数返回 true, 是否推进到下一步，不计数返回 false
function QuestSteps.Apply(steps, state, fact)
    local eventId = fact.eventId
    if eventId == nil or state.seen[eventId] then return false end
    local current = steps[state.step]
    if not current or current.Kind ~= fact.kind or (current.ItemId and current.ItemId ~= fact.itemId)
        or (current.Category and current.Category ~= fact.category) then return false end
    state.seen[eventId] = true
    state.count = state.count + math.max(1, math.floor(tonumber(fact.count) or 1))
    if state.count < (current.Need or 1) then return true, false end
    state.step = state.step + 1
    state.count = 0
    return true, true
end

-- 任务条文案：「新手任务 1/3：拾取 5 只蚯蚓（2/5）」；全部完成返回 doneText
function QuestSteps.Text(steps, state, title, doneText)
    local current = steps[state.step]
    if not current then return doneText end
    local text = string.format('%s %d/%d：%s', title, state.step, #steps, current.Text)
    if (current.Need or 1) > 1 then
        text = text .. string.format('（%d/%d）', state.count, current.Need)
    end
    return text
end

return QuestSteps
