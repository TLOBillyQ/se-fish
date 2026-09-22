-- 客户端根能力入口：业务层只 require 本模块，不直接碰 client/packages/ability_system/。
-- 客户端只发请求（Cast / Stop / Accumulate / SwitchNext），权威判定在服务端。
local AbilityAPIBase = require("common.AbilityAPIBase")
local AbilityPackageAPI = require("client.packages.ability_system.api")

return AbilityAPIBase.build(AbilityPackageAPI, AbilityAPIBase.CLIENT_API)
