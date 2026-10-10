-- 迁移失败方式：DRY 不能把业务源码解析失败当成成功报告。
local lu = require("luaunit")
local shell = require("tools.win_shell")
local ROOT = "tmp/quality-report-test"

local function write(path, body)
  local f = assert(io.open(path, "wb"))
  f:write(body)
  f:close()
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

TestQualityReport = {}

function TestQualityReport:test_invalid_source_does_not_publish_dry_report()
  shell.ensure_dir(ROOT)
  local source, manifest, output = ROOT .. "/broken.lua", ROOT .. "/sources.txt", ROOT .. "/dry.json"
  write(source, "local function broken(\n")
  write(manifest, source .. "\n")
  os.remove(output)
  -- report.lua 已自包含工具路径，只需调用脚本本身。
  local code, log = shell.capture("lua tools/quality/report.lua " .. shell.q(manifest) .. " " .. shell.q(output))
  lu.assertNotEquals(code, 0)
  lu.assertStrContains(log, "broken.lua")
  lu.assertNil(read(output))
end
