-- #153 生物 AI 包装配骨架：官方包 official_ai_feature 的服务端挂载点，根聚合入口
-- 在此加载（包内模块加载期问题在 Start 阶段即暴露）。当前仅占位，AI 行为接线
-- 另开任务。
local AiAPI = require("server.AiAPI")

local Mgr = { AiAPI = AiAPI }

function Mgr:Start()
end

return Mgr
