-- 单测入口：在仓库根执行 `lua tests/run.lua`。
-- 发现 tests/*_test.lua（不递归，测试文件平铺在 tests/ 下），按名排序保证顺序稳定；
-- luaunit 在 tests/lib/（vendored，3.4，BSD）。

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local files = {}
local handle = io.popen('dir /b "tests\\*_test.lua" 2>nul')
for line in handle:lines() do
  line = line:gsub("[\r\n]+$", "")
  if line ~= "" then files[#files + 1] = line end
end
handle:close()
table.sort(files)

if #files == 0 then
  io.stderr:write("没找到测试文件（tests/*_test.lua）\n")
  os.exit(1)
end

for _, file in ipairs(files) do
  require("tests." .. (file:gsub("%.lua$", "")))
end

local lu = require("luaunit")
os.exit(lu.LuaUnit.run())
