-- Busted 共享初始化（#81 建立，#82 接共享基线接缝）：由 .busted 的 helper 在任何案例文件发现/加载前执行；
-- helper 失败则整个运行退出。基线来自 tests/support/baseline.lua，避免同一份配置在两处各写一遍。
-- 返回的函数注册根级 before_each/after_each：每案例快照并在 after_each 恢复共享配置。
-- before_each 失败时 Busted 仍从失败层向上执行 after_each，因此部分 setup 失败也完成清理，修改不泄漏到后续案例。
-- 逐例快照/还原 GameCfg.Debug 与 Save.AcceptanceSlot 的语义与旧 LuaUnit 套件一致：旧入口只在进程启动时设一次基线，
-- 但每个旧测试文件自己 setUp 存、tearDown 还原这两个字段，实际效果就是逐例隔离，这里换的只是钩子名，没引入新行为。
-- 边际差别是更稳：after_each 无条件执行，旧 tearDown 在断言提前失败时会跳过还原。

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  package.path,
}, ";")

local baseline = require("tests.support.baseline")
baseline.apply()

return function(busted)
  local snapshot
  busted.executors.before_each(function()
    snapshot = baseline.snapshot()
  end)
  busted.executors.after_each(function()
    baseline.restore(snapshot)
    snapshot = nil
  end)
  return true
end
