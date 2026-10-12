-- 聚合入口 CLI 契约（#82）：明确的两套 runner 案例清单、失败报告、退出码与统计落点。
-- 轻量回归：用桩 runner 替换真实 lua/busted 子进程，只核对命令选择、清单、报告与退出码。
local lu = require("luaunit")
local shell = require("tools.win_shell")
local interpreter = require("tests.support.interpreter")
local lanes = require("tests.lanes")
local migration = require("tests.run_migration")

local ROOT = "tmp/migration-cli-test"
local FAKE_ROOT = "tmp/migration-cli-empty-lane"
local FAKE_REPO = FAKE_ROOT .. "/repo"
-- 本仓库根的绝对路径：LUA_PATH、run.lua 与重定向落点都从它拼（假仓库里只有空目录，没有模块）。
local REPO = (io.popen("cd"):read("l")):gsub("[\r\n]+$", "")

local function reset_dir()
  os.execute("rd /s /q " .. ROOT:gsub("/", "\\") .. " 2>nul")
  os.execute("md " .. ROOT:gsub("/", "\\") .. " 2>nul")
end

local function capture(command)
  local handle = assert(io.popen(command .. " 2>&1"))
  local output = handle:read("a") or ""
  local ok, _, code = handle:close()
  return output, (ok == true and 0) or (code or 1)
end

local LUA = interpreter.path()
local function run(args)
  return capture(string.format('"%s" tests/run_migration.lua %s', LUA, args))
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local body = file:read("a")
  file:close()
  return body
end

-- plain find：命令与路径里的 `-`、`[` 在 Lua pattern 里是特殊字符。
local function assertContainsText(haystack, needle, message)
  lu.assertNotEquals(haystack:find(needle, 1, true), nil,
                     (message or ("缺少子串 " .. needle)) .. "：" .. haystack)
end

local function assertNotContainsText(haystack, needle, message)
  lu.assertEquals(haystack:find(needle, 1, true), nil,
                  (message or ("不应包含子串 " .. needle)) .. "：" .. haystack)
end

TestMigrationCli = {}

function TestMigrationCli:test_usage_rejects_unknown_lane()
  local output, code = run("nonsense")
  lu.assertNotEquals(code, 0, "未知车道必须失败")
  lu.assertStrContains(output, "fast")
  lu.assertStrContains(output, "full")
end

function TestMigrationCli:test_list_prints_both_case_lists_per_runner()
  local output, code = run("full --list")
  lu.assertEquals(code, 0, output)
  -- 两套 runner 各有明确案例清单：分段标题带 runner 名与车道，逐文件列出。
  assertContainsText(output, "[legacy] full", "清单缺旧 runner 分段")
  assertContainsText(output, "[native] full", "清单缺原生 runner 分段")
  -- 锚点取自车道定义本身而不是写死某个案例文件名：迁移期旧清单逐批变短（#84~#92），
  -- 写死名字会在它被迁走的那天误红；native 侧同理。
  local legacy, native = lanes.legacy_files("full"), lanes.native_files("full")
  lu.assertNotEquals(#legacy, 0, "full 旧清单为空，逐文件断言会失去意义")
  lu.assertNotEquals(#native, 0, "full 原生清单为空，逐文件断言会失去意义")
  assertContainsText(output, legacy[1], "旧清单缺案例文件")
  assertContainsText(output, native[1], "原生清单缺案例文件")
  assertContainsText(output, "[legacy] full " .. #legacy .. " 案例", "旧清单计数与车道定义不符")
  assertContainsText(output, "[native] full " .. #native .. " 案例", "原生清单计数与车道定义不符")
  assertContainsText(output, "tests/tooling/slow/", "full 清单必须含旧 slow 案例")
  assertContainsText(output, "tests/native/slow/", "full 清单必须含原生 slow 案例")
  assertNotContainsText(output, "_test.py", "清单不得出现 Python 回归")
end

function TestMigrationCli:test_fast_list_excludes_slow()
  local output, code = run("fast --list")
  lu.assertEquals(code, 0, output)
  lu.assertNil(output:find("tests/tooling/slow/", 1, true))
  lu.assertNil(output:find("tests/native/slow/", 1, true))
end

function TestMigrationCli:test_merged_stats_land_where_the_quality_entry_reads_them()
  -- 依赖路径契约：合并统计落在 run_coverage 读取的位置（仓库根 luacov.stats.out），
  -- 分段统计各自落在 build/quality 下并保留，失败时可用原快照诊断。
  local plan = migration.plan("full", { coverage = true })
  lu.assertEquals(plan.merged, "luacov.stats.out")
  local legacy, native = plan.segments[1], plan.segments[2]
  lu.assertNotEquals(legacy.stats, native.stats)
  lu.assertNotEquals(legacy.luacov_config, native.luacov_config)
  lu.assertNotEquals(legacy.stats, plan.merged, "分段统计不得直接写合并位置")
  lu.assertNotEquals(native.stats, plan.merged, "分段统计不得直接写合并位置")
  lu.assertStrContains(legacy.stats, "build/quality/")
  lu.assertStrContains(native.stats, "build/quality/")
end

function TestMigrationCli:test_empty_lane_reports_skip_not_failure()
  reset_dir()
  local plan = migration.plan("full", { coverage = true, build = ROOT })
  migration.prepare(plan)
  plan.segments[2].files, plan.segments[2].empty = {}, true
  local results = migration.execute(plan, {
    runner = function(segment)
      local file = assert(io.open(segment.stats, "wb"))
      file:write("1:common/Legacy.lua\n1 \n")
      file:close()
      return 0
    end,
    merged = ROOT .. "/merged.out",
  })
  lu.assertEquals(migration.exit_code(results), 0)
  lu.assertEquals(results[2].action, "skip")
  lu.assertNotEquals(results[2].reason:find("empty", 1, true), nil)
  local report = migration.report(plan, results)
  lu.assertStrContains(report, "skip")
  lu.assertNil(report:find("FAILED", 1, true), "空集合不得报失败")
end

function TestMigrationCli:test_failure_report_names_the_runner_and_exit_code()
  reset_dir()
  local plan = migration.plan("full", { coverage = true, build = ROOT })
  migration.prepare(plan)
  local results = migration.execute(plan, {
    runner = function(segment)
      return segment.runner == "native" and 7 or 0
    end,
    merged = ROOT .. "/merged.out",
  })
  lu.assertEquals(migration.exit_code(results), 7, "原生段失败必须原样传退出码")
  local report = migration.report(plan, results)
  lu.assertStrContains(report, "FAILED")
  lu.assertStrContains(report, "native")
  lu.assertStrContains(report, "code=7")
  lu.assertStrContains(report, "legacy", "报告要同时列出通过的段，失败不掩盖另一套清单")
end

function TestMigrationCli:test_non_coverage_mode_skips_merge()
  reset_dir()
  local plan = migration.plan("fast")
  local results = migration.execute(plan, {
    runner = function() return 0 end,
  })
  lu.assertEquals(migration.exit_code(results), 0)
  lu.assertEquals(results[1].action, "run")
  lu.assertEquals(#results, 2, "非覆盖率模式不做合并段")
  lu.assertIsNil(plan.merged)
  lu.assertIsNil(read(ROOT .. "/merged.out"), "非覆盖率模式不得写合并统计")
end

-- 旧入口的空集合发现：真跑 tests/run.lua 子进程，cwd 换成只有空 tests/ 目录的假仓库
-- （LUA_PATH 指回本仓库取 tests.lanes、tests.support.baseline 与 vendored luaunit），
-- 让「车道没有 *_test.lua」这条分支被验证，而不是留成未测代码。
local function lua_bin()
  return interpreter.path()
end

local function write_file(path, body)
  local dir = path:match("^(.-)[/\\][^/\\]*$")
  if dir then shell.ensure_dir(dir) end
  local file = assert(io.open(path, "wb"), path .. " 建不出来")
  file:write(body)
  file:close()
end

local function run_legacy_entry(lane)
  -- cmd 的 `&` 链里重定向只绑紧跟它前面那一条命令，所以重定向与 lua 写在同一个片段里；
  -- 落点取绝对路径，因为子进程已经 cd 进假仓库，相对落点会写进假仓库、读回来就是空。
  local out = REPO .. "\\tmp\\migration-cli-empty-lane.out"
  shell.ensure_dir(REPO .. "\\tmp")
  local parts = {
    "cd .",
    'set "LUA_PATH=' .. REPO .. '\\?.lua;' .. REPO .. '\\?\\init.lua;'
      .. REPO .. '\\tests\\lib\\?.lua;;"',
    "cd /d " .. shell.q(FAKE_REPO),
    "> " .. shell.q(out) .. " 2>&1 " .. shell.q(lua_bin()) .. " " .. shell.q(REPO .. "/tests/run.lua") .. " " .. lane,
  }
  local _, _, code = os.execute(table.concat(parts, " & "))
  return (code or 1), (read(out) or "")
end

local function seed_fake_repo(with_case)
  shell.remove({ dir = true, dst = shell.win(FAKE_REPO) })
  shell.ensure_dir(shell.win(FAKE_REPO .. "/tests/gameplay"))
  shell.ensure_dir(shell.win(FAKE_REPO .. "/tests/tooling"))
  if with_case then
    write_file(shell.win(FAKE_REPO .. "/tests/gameplay/empty_lane_case_test.lua"),
      "TestEmptyLaneCase = {}\nfunction TestEmptyLaneCase:test_ok() end\nreturn TestEmptyLaneCase\n")
  end
end

function TestMigrationCli:test_empty_legacy_lane_exits_zero_without_false_failure()
  seed_fake_repo(false)
  local code, output = run_legacy_entry("gameplay")
  shell.remove({ dir = true, dst = shell.win(FAKE_ROOT) })
  lu.assertEquals(code, 0, "空车道必须退出码 0，不得误失败：" .. output)
  assertContainsText(output, "跳过", "空车道要走跳过分支：" .. output)
  assertNotContainsText(output, "FAILED", "空车道不得报失败：" .. output)
end

function TestMigrationCli:test_non_empty_legacy_lane_still_runs_cases()
  -- 反向控制：同一假仓库补上一个案例文件，跳过分支就不再命中，证明上一条是「没文件」而非「总退 0」。
  seed_fake_repo(true)
  local code, output = run_legacy_entry("gameplay")
  shell.remove({ dir = true, dst = shell.win(FAKE_ROOT) })
  lu.assertEquals(code, 0, "带案例的车道应正常跑完：" .. output)
  assertNotContainsText(output, "跳过", "有案例时不得走空车道分支：" .. output)
  assertContainsText(output, "Ran 1 test", "案例确实被执行：" .. output)
end
