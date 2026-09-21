-- tools/acceptance/cli/parser.lua —— acceptance4lua gherkin-parser 的宿主 wrapper。
-- 在仓库根运行；包内自带 --help/用法错误处理，退出码由它给。
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
os.exit(require("acceptance4lua.cli.parser").main(arg))
