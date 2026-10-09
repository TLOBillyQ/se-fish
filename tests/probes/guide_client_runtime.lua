-- #40 可重跑观察探针：先在 client 执行，再用合法 input 点击对话/下一段/已读和走九步。
-- 中途停止重开试玩后再次执行，比较 GUIDE40_QUEST 的 step/count 与 GUIDE40_STORY_STATE。
-- 只监听状态并请求快照，不写任务事实、不发物资、不模拟正式 Story 信号。
local REUtil = require('common.REUtil')
if _G.Guide40Links then
    for _, link in ipairs(_G.Guide40Links) do link:Disconnect() end
end
_G.Guide40Links = {}
local function listen(name, callback)
    _G.Guide40Links[#_G.Guide40Links + 1] = REUtil:GetRE(name).OnClientEvent:Connect(callback)
end
listen('QuestState', function(state)
    print('GUIDE40_QUEST', state.step, state.count, state.need, state.done, state.text)
end)
listen('StoryNotice', function(state)
    print('GUIDE40_STORY_NOTICE', state.readKey, state.title, #state.lines)
end)
listen('StoryState', function(state)
    print('GUIDE40_STORY_STATE', state.readKey, state.read, state.text)
end)
REUtil:GetRE('RequestQuest'):FireServer()
REUtil:GetRE('RequestStory'):FireServer()
print('GUIDE40_CLIENT_READY')
