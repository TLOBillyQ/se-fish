-- 服务端根生物 AI 入口：业务层只 require 本模块，不直接碰 server/packages/official_ai_feature/。
-- 包内 api.lua 的 Funcs 在这里整体转发（名单见 common/AiAPIBase.lua），Configs 原样透传。
-- AI 包 client 侧无 api.lua，只有服务端入口。
local AiAPIBase = require("common.AiAPIBase")
local AiPackageAPI = require("server.packages.official_ai_feature.api")

local AiAPI = AiAPIBase.build(AiPackageAPI.Funcs, AiAPIBase.SERVER_API)
AiAPI.Configs = AiPackageAPI.Configs

-- 项目扩展，非 vendor 原生 API：依赖 BehaviorRuntime.getState 的 modeTask/disabled 生命周期。
-- 官方任务自然结束会清 modeTask；包升级时由真实 vendor 回归核对这条依赖。
local BehaviorRuntime = require('server.packages.official_ai_feature.behavior_runtime')
function AiAPI.HasActiveMove(unit)
    local state = BehaviorRuntime.getState(unit)
    return state ~= nil and state.modeTask ~= nil and not state.disabled
end

return AiAPI
