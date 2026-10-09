-- #40 只读存档/文案观察：在 server 运行，九步正常触发复用 pond_loop_runtime.lua。
-- 新验收槽须保持 Debug=false；每步退出前后重跑本文件，保留同轮 log trace 与界面截图。
-- 这份探针只读取公开任务状态/真实玩家数据，不代替九步正常经济或正式 Story 资源验收。
local Quest = require('server.Mgr.MgrQuest')
local PlayerData = require('server.Mgr.MgrPlayerData')
local GameCfg = require('common.GameCfg')
local Dialogue = require('common.NpcDialogue')
for _, player in ipairs(game:GetService('Players'):GetPlayers()) do
    local data, state = PlayerData:GetDataInst(player), Quest:GetState(player)
    if data and state then
        print('GUIDE40_SNAPSHOT', player.UserId, 'step=' .. state.step, 'count=' .. state.count,
            'coin=' .. data.Data.FishCoin,
            'read=' .. tostring(data.Extra.story.read[GameCfg.Story.ReadKey or 'opening'] == true))
    else
        print('GUIDE40_NOT_READY', player.UserId)
    end
end
for _, zone in ipairs(GameCfg.Zones) do
    for i, line in ipairs(Dialogue.Lines(zone.Id)) do print('GUIDE40_NPC', zone.Id, i, line) end
end
