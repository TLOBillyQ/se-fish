-- Busted 共享初始化（#81）：由 .busted 的 helper 在任何案例文件发现/加载前执行；helper 失败则整个运行退出。
-- 顶层建立与 tests/run.lua 相同的离线基线；返回的函数注册根级 before_each/after_each，
-- 每案例快照并恢复共享配置——案例失败时 after_each 链仍从失败层向上执行，修改不泄漏到后续案例。

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local GameCfg = require("common.GameCfg")
-- 离线套件的显式基线（对齐 tests/run.lua）：旧玩法夹具使用调试物资，验收槽为空串。
-- 只修改本测试进程的配置；业务默认保持关闭调试，编辑器验收槽不影响离线用例。
GameCfg.Debug = { Enabled = true, InitialGrants = GameCfg.Debug.InitialGrants }
GameCfg.Save.AcceptanceSlot = ""

return function(busted)
  local snapshot
  busted.executors.before_each(function()
    snapshot = { Debug = GameCfg.Debug, AcceptanceSlot = GameCfg.Save.AcceptanceSlot }
  end)
  busted.executors.after_each(function()
    GameCfg.Debug = snapshot.Debug
    GameCfg.Save.AcceptanceSlot = snapshot.AcceptanceSlot
    snapshot = nil
  end)
  return true
end
