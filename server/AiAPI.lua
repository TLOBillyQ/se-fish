-- 服务端根生物 AI 入口：业务层只 require 本模块，不直接碰 server/packages/official_ai_feature/。
-- 包内 api.lua 的 Funcs 在这里整体转发（名单见 common/AiAPIBase.lua），Configs 原样透传。
-- AI 包 client 侧无 api.lua，只有服务端入口。
local AiAPIBase = require("common.AiAPIBase")
local AiPackageAPI = require("server.packages.official_ai_feature.api")

local AiAPI = AiAPIBase.build(AiPackageAPI.Funcs, AiAPIBase.SERVER_API)
AiAPI.Configs = AiPackageAPI.Configs

return AiAPI
