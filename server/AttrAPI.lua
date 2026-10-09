-- 服务端根属性入口：业务层只 require 本模块，不直接碰 server/packages/attr_rule/。
-- 包内 api.lua 的 Funcs 在这里整体转发（名单见 common/AttrAPIBase.lua），
-- Enums / Prefabs 原样透传。
local AttrAPIBase = require("common.AttrAPIBase")
local AttrPackageAPI = require("server.packages.attr_rule.api")

local AttrAPI = AttrAPIBase.build(AttrPackageAPI.Funcs, AttrAPIBase.SERVER_API)
AttrAPI.Enums = AttrPackageAPI.Enums
AttrAPI.Prefabs = AttrPackageAPI.Prefabs

return AttrAPI
