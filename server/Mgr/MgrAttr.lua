-- #153 属性规则包装配骨架：官方包 attr_rule 的服务端挂载点，根聚合入口在此加载
-- （包内模块加载期问题在 Start 阶段即暴露）。当前仅占位，属性初始化 / Buff 挂载等
-- 玩法接线另开任务。
local AttrAPI = require("server.AttrAPI")

local Mgr = { AttrAPI = AttrAPI }

function Mgr:Start()
end

return Mgr
