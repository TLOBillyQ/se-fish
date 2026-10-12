-- 迁移失败方式：DRY 不能把业务源码解析失败当成成功报告。
-- 迁移自 tests/tooling/slow/quality_report_test.lua（#92，LuaUnit → 原生 Busted）。
-- 平台条件：shell.capture 起的是 cmd 子进程（tools/win_shell.lua 的命令行语法），只在 Windows 可跑；
-- 非 Windows 登记为 pending（名称保留旧方法名，`--list` 行数不变、运行时报 pending 而非失败）。
-- 解释器沿用旧文件的 `"lua"`（走 PATH），不改成 tests/support/interpreter.lua：本案例断言的是
-- report.lua 对坏源码的失败口径，换解释器来源与它无关，保持等价。
local shell = require("tools.win_shell")

local WINDOWS = package.config:sub(1, 1) == "\\"
local SKIP = "仅 Windows 可跑（真实 cmd 子进程）"
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

describe("TestQualityReport", function()
  if WINDOWS then
    after_each(function()
      shell.remove({ dir = true, dst = ROOT })
    end)
  end

  it("test_invalid_source_does_not_publish_dry_report", function()
    if not WINDOWS then
      return pending("test_invalid_source_does_not_publish_dry_report: " .. SKIP)
    end
    shell.ensure_dir(ROOT)
    local source, manifest, output = ROOT .. "/broken.lua", ROOT .. "/sources.txt", ROOT .. "/dry.json"
    write(source, "local function broken(\n")
    write(manifest, source .. "\n")
    os.remove(output)
    -- report.lua 已自包含工具路径，只需调用脚本本身。
    local code, log = shell.capture("lua tools/quality/report.lua " .. shell.q(manifest) .. " " .. shell.q(output))
    assert.are_not.equal(0, code, log)
    assert.matches("broken.lua", log, 1, true)
    assert.is_nil(read(output))
  end)
end)
