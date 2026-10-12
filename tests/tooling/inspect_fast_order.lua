-- 复刻 tests/run.lua 的加载行为：同一路径、同一共享配置修改、同一 require 顺序；
-- 由调用方先给出精确测试名，验证执行列表而不改变 runner 本身。
package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local selected = arg[1] or "full"
local lanes = {
  fast = { "gameplay", "tooling" },
  gameplay = { "gameplay" },
  tooling = { "tooling", "tooling/slow" },
  full = { "gameplay", "tooling", "tooling/slow" },
}
local files = {}
for _, lane in ipairs(lanes[selected]) do
  local directory = "tests/" .. lane
  local handle = assert(io.popen('dir /b /a-d "' .. directory:gsub("/", "\\") .. '\\*_test.lua" 2>nul'))
  for line in handle:lines() do
    line = line:gsub("[\r\n]+$", "")
    if line ~= "" then files[#files + 1] = directory .. "/" .. line end
  end
  handle:close()
end
table.sort(files)
local fixtureCfg = require('common.GameCfg')
fixtureCfg.Debug = { Enabled = true, InitialGrants = fixtureCfg.Debug.InitialGrants }
fixtureCfg.Save.AcceptanceSlot = ''
for _, file in ipairs(files) do
  require((file:gsub("/", "."):gsub("%.lua$", "")))
end

local lu = require('luaunit')
local names = {}
for _, className in ipairs(lu.LuaUnit.collectTests()) do
  names[#names + 1] = { className, _G[className] }
end
local expanded = lu.LuaUnit.expandClasses(names)
for _, item in ipairs(expanded) do
  io.stdout:write(tostring(item[1]), "\n")
end
