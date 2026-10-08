-- 客户端根效果入口：业务层只 require 本模块，不直接碰 client/packages/modifier_system/。
-- 包内 api.lua 的请求/查询接口在这里整体转发（名单见 common/ModifierAPIBase.lua）；
-- 客户端为请求端，修改经包内请求转发到服务端生效。
local ModifierAPIBase = require("common.ModifierAPIBase")
local ModifierPackageAPI = require("client.packages.modifier_system.api")

local ModifierAPI = ModifierAPIBase.build(ModifierPackageAPI, ModifierAPIBase.CLIENT_API)

return ModifierAPI
