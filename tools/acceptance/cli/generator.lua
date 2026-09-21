-- tools/acceptance/cli/generator.lua —— acceptance4lua 验收入口生成器的宿主 wrapper。
-- 在仓库根运行；不额外给 --steps-module 时，把生成的 spec 绑到本仓库的步骤模块
-- tools.acceptance.steps（acceptance4lua 默认的裸名 steps 不存在）。
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
local args = { table.unpack(arg) }
local has_steps = false
for _, a in ipairs(args) do if a == "--steps-module" then has_steps = true end end
if not has_steps then
  table.insert(args, 1, "tools.acceptance.steps")
  table.insert(args, 1, "--steps-module")
end
os.exit(require("acceptance4lua.cli.generator").main(args))
