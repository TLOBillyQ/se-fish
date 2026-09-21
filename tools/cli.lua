-- tools/cli.lua —— 工具链对外面（先例：monopoly / se-defense tools/cli.lua 的封闭命令集）。
--
-- 用法（在仓库根执行）：
--   lua tools/cli.lua <子命令> [args...]
--   lua tools/cli.lua --help | -h
--
-- 顶层查静态路由表 → require("tools.<mod>") → mod.main(args) → 统一 os.exit。
-- 子模块接口：return { main = function(args) -> 退出码 }；包内自行消费 --help/-h。
-- 退出码：0 成功 / 1 业务失败 / 2 用法错误。

local commands = {
  { name = "deploy", mod = "tools.deploy", summary = "仓库三端一级子树镜像进编辑器宿主目录（robocopy /MIR + 编辑器收尾）" },
  { name = "sync",   mod = "tools.sync",   summary = "从编辑器宿主目录回同步 eggy.json / 两份 API 存根 / data/ 到仓库根" },
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local function usage()
  local lines = { "用法: lua tools/cli.lua <子命令> [args...]", "", "子命令（封闭命令集）：" }
  for _, c in ipairs(commands) do
    lines[#lines + 1] = string.format("  %-12s %s", c.name, c.summary)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  lua tools/cli.lua <子命令> --help   子命令帮助"
  return table.concat(lines, "\n") .. "\n"
end

local name = arg[1]
if name == nil or name == "--help" or name == "-h" then
  io.write(usage())
  os.exit(0)
end

local entry
for _, c in ipairs(commands) do
  if c.name == name then entry = c end
end
if not entry then
  io.stderr:write("未知子命令: " .. name .. "\n\n" .. usage())
  os.exit(2)
end

local ok, mod = pcall(require, entry.mod)
if not ok or type(mod) ~= "table" or type(mod.main) ~= "function" then
  -- 只印第一行：require 失败时后面跟着一长串搜索路径，对使用者是噪音；
  -- 真要追，直接 `lua <模块文件>` 跑一次就有完整报错。
  io.stderr:write("子命令加载失败: " .. name .. " (" .. entry.mod .. ")\n"
    .. (tostring(mod):match("^[^\r\n]*") or "") .. "\n")
  os.exit(2)
end

local rest = {}
for i = 2, #arg do rest[#rest + 1] = arg[i] end
local code = mod.main(rest)
os.exit(type(code) == "number" and code or 0)
