-- 单测入口：在仓库根执行 `lua tests/run.lua [fast|gameplay|tooling|full]`。
-- 测试按被测对象放在 gameplay/ 或 tooling/；tooling/slow/ 只在完整集执行。
-- luaunit 在 tests/lib/（vendored，3.4，BSD）。
-- 迁移期（#82）：车道目录来自 tests/lanes.lua，与原生 Busted 集合互斥；基线来自 tests/support/baseline.lua。

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local lanes = require("tests.lanes")
local legacy_lanes = {
  fast = "fast",
  gameplay = "gameplay",
  tooling = "tooling",
  full = "full",
}
local selected = arg[1] or "full"
if not legacy_lanes[selected] or arg[2] then
  io.stderr:write("用法: lua tests/run.lua [fast|gameplay|tooling|full]\n")
  os.exit(1)
end

local files = lanes.legacy_files(selected)
if #files == 0 then
  -- 空集合：该车道没有旧测试文件（迁移后目录清空），正常跳过而不是误失败。
  io.stdout:write("旧车道没有测试文件（" .. selected .. "），跳过。\n")
  os.exit(0)
end

-- 离线套件的显式基线：与原生 Busted helper 共用同一接缝，避免两处各写一遍。
require("tests.support.baseline").apply()

for _, file in ipairs(files) do
  require((file:gsub("/", "."):gsub("%.lua$", "")))
end

local lu = require("luaunit")
arg[1] = nil
os.exit(lu.LuaUnit.run())
