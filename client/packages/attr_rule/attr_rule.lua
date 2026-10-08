--属性规则包 - client端状态管理
--CAttrRuleManager：属性系统的客户端管理器；读取能力全部继承自 AttrRuleManager，客户端不持有状态。

local AttrRuleManager = require("common.packages.attr_rule.AttrRuleManager")

---属性规则管理器（客户端）
---@class CAttrRuleManager : AttrRuleManager
local CAttrRuleManager = setmetatable({}, { __index = AttrRuleManager })

return CAttrRuleManager
