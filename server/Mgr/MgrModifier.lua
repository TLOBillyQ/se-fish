-- #153 效果包装配骨架：官方包 modifier_system 的服务端挂载点，根聚合入口在此加载
-- （包内模块加载期问题在 Start 阶段即暴露）。当前仅占位，效果创建 / 生命周期接线
-- 另开任务。
local ModifierAPI = require("server.ModifierAPI")

local Mgr = { ModifierAPI = ModifierAPI }

function Mgr:Start()
end

return Mgr
