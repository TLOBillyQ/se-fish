-- 单测入口：在仓库根执行 `lua tests/run.lua [fast|gameplay|tooling|full]`。
-- 测试按被测对象放在 gameplay/ 或 tooling/；tooling/slow/ 只在完整集执行。
-- luaunit 在 tests/lib/（vendored，3.4，BSD）。

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local lanes = {
  fast = { "gameplay", "tooling" },
  gameplay = { "gameplay" },
  tooling = { "tooling", "tooling/slow" },
  full = { "gameplay", "tooling", "tooling/slow" },
}
local selected = arg[1] or "full"
if not lanes[selected] or arg[2] then
  io.stderr:write("用法: lua tests/run.lua [fast|gameplay|tooling|full]\n")
  os.exit(1)
end

local files = {}
for _, lane in ipairs(lanes[selected]) do
  local directory = "tests/" .. lane
  local handle = assert(io.popen('dir /b /a-d "' .. directory:gsub("/", "\\") .. '\\*_test.lua" 2>nul'))
  local count = 0
  for line in handle:lines() do
    line = line:gsub("[\r\n]+$", "")
    if line ~= "" then
      files[#files + 1] = directory .. "/" .. line
      count = count + 1
    end
  end
  handle:close()
  if count == 0 then
    io.stderr:write("没找到测试文件（" .. directory .. "/*_test.lua）\n")
    os.exit(1)
  end
end
table.sort(files)
for _, file in ipairs(files) do
  require((file:gsub("/", "."):gsub("%.lua$", "")))
end

local lu = require("luaunit")
arg[1] = nil
os.exit(lu.LuaUnit.run())
