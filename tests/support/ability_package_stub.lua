-- #90 迁移期共享夹具：技能包 api 的离线替身。
-- 接缝契约在 common/AbilityAPIBase.lua：服务端根入口 server/AbilityAPI.lua 加载时
-- 按 SERVER_API 全名单校验包内 api 的导出，缺名即 error（接缝漂移要在加载时炸出来）。
--
-- 因此「给 server.packages.ability_system.api 装个只有一两个函数的桩」是不够的：
-- 旧 tests/gameplay/weapon_system_test.lua 的 preload 桩只给 CastAbility，能跑通完全依赖
-- 另一份文件先把真包模块灌进 package.loaded 让 preload 永不被调用（跨文件的隐性耦合，
-- 与 damage_float 的 Color 全局泄漏同类）。Busted 逐 spec 独立加载后这条残留不可依赖，
-- 所以按名单建齐桩：除调用方指定的函数外，其余接口一律返回 false（未被业务用到的接口不该被调到）。
-- 桩只走 package.preload，不改包内源码。
local AbilityAPIBase = require('common.AbilityAPIBase')

local M = {}

---@param overrides? table 接口名到实现的覆盖表，如 { CastAbility = function() return true end }
---@return table 满足 SERVER_API 名单的包内 api 替身
function M.packageApi(overrides)
    local impl = {}
    for _, name in ipairs(AbilityAPIBase.SERVER_API) do impl[name] = function() return false end end
    for name, fn in pairs(overrides or {}) do
        assert(type(fn) == 'function', '覆盖项必须是函数：' .. tostring(name))
        impl[name] = fn
    end
    return impl
end

return M
