-- tools/acceptance/cli/ir_dry.lua —— acceptance4lua gherkin-ir-dry-checker 的宿主 wrapper。
-- 在仓库根运行。检查只是 advisory：报告重复/近似/疑似同义的 step 文本，不拦流水线。
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
os.exit(require("acceptance4lua.cli.ir_dry").main(arg))
