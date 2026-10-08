-- 服务端根效果入口：业务层只 require 本模块，不直接碰 server/packages/modifier_system/。
-- 包内 api.lua 的服务端权威 API 在这里整体转发（名单见 common/ModifierAPIBase.lua），
-- Enums 原样透传。
local ModifierAPIBase = require("common.ModifierAPIBase")
local ModifierPackageAPI = require("server.packages.modifier_system.api")

local ModifierAPI = ModifierAPIBase.build(ModifierPackageAPI, ModifierAPIBase.SERVER_API)
ModifierAPI.Enums = ModifierPackageAPI.Enums

return ModifierAPI
