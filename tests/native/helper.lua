-- Busted 共享初始化（#81 建立，#82 接共享基线接缝）：由 .busted 的 helper 在任何案例文件发现/加载前执行；
-- helper 失败则整个运行退出。基线来自 tests/support/baseline.lua，避免同一份配置在两处各写一遍。
-- 返回的函数注册根级 before_each/after_each：每案例快照并在 after_each 恢复共享配置。
-- before_each 失败时 Busted 仍从失败层向上执行 after_each，因此部分 setup 失败也完成清理，修改不泄漏到后续案例。

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
