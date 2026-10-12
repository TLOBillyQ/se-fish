-- 分段执行契约（#82）：两段分进程运行，统计经各自 luacov 配置注入、互不覆盖；
-- 任一失败则整体失败且不合并；空集合段跳过不执行。轻量回归：runner 用桩替换，不起真实测试。
local lu = require("luaunit")
local migration = require("tests.run_migration")

local ROOT = "tmp/segment-run-test"

local function reset_dir()
  os.execute("rd /s /q " .. ROOT:gsub("/", "\\") .. " 2>nul")
  os.execute("md " .. ROOT:gsub("/", "\\") .. " 2>nul")
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

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

-- 子串断言用 plain find：命令行里的 `-` 在 Lua pattern 里是惰性量词，不能当普通字符匹配。
local function assertContainsText(haystack, needle, message)
  lu.assertNotEquals(haystack:find(needle, 1, true), nil,
                     (message or ("缺少子串 " .. needle)) .. "：" .. haystack)
end

local function assertNotContainsText(haystack, needle, message)
  lu.assertEquals(haystack:find(needle, 1, true), nil,
                  (message or ("不应包含子串 " .. needle)) .. "：" .. haystack)
end

TestSegmentRun = {}

function TestSegmentRun:test_coverage_plan_gives_each_segment_its_own_luacov_config()
  reset_dir()
  local plan = migration.plan("fast", { coverage = true, build = ROOT })
  local legacy, native = plan.segments[1], plan.segments[2]
  lu.assertNotEquals(legacy.stats, nil)
  lu.assertNotEquals(native.stats, nil)
  lu.assertNotEquals(legacy.stats, native.stats, "两段共用统计文件会互相清空")
  lu.assertNotEquals(legacy.luacov_config, native.luacov_config)
  -- 两段各自的统计路径必须写进自己的 argv：共用默认 .luacov / luacov.stats.out 会让两段互相清空。
  local native_line = table.concat(native.command, " ")
  local statement = table.concat(legacy.command, " ")
  assertContainsText(native_line, "--coverage", "原生段覆盖率必须走 busted --coverage")
  assertContainsText(native_line, "--coverage-config-file=" .. native.luacov_config,
                       "原生段必须显式指定自己的覆盖率配置")
  assertContainsText(statement, "luacov.runner")
  assertContainsText(statement, legacy.luacov_config)
  assertContainsText(statement, "tests/run.lua")
  assertNotContainsText(native_line, legacy.stats, "原生段 argv 引用了旧段统计路径")
  assertNotContainsText(statement, native.stats, "旧段 argv 引用了原生段统计路径")
end

function TestSegmentRun:test_luacov_config_files_persist_and_point_at_their_own_stats()
  reset_dir()
  local plan = migration.plan("fast", { coverage = true, build = ROOT })
  migration.prepare(plan)
  for _, segment in ipairs(plan.segments) do
    local body = read(segment.luacov_config)
    lu.assertNotNil(body, segment.runner .. " 的覆盖率配置未写出")
    assertContainsText(body, segment.stats)
  end
  assertNotContainsText(read(plan.segments[1].luacov_config), plan.segments[2].stats,"旧段配置引用了原生段统计，两段会互相清空")
end

function TestSegmentRun:test_non_coverage_plan_has_no_injection()
  reset_dir()
  local plan = migration.plan("fast")
  for _, segment in ipairs(plan.segments) do
    lu.assertIsNil(segment.stats)
    lu.assertIsNil(segment.luacov_config)
    lu.assertEquals(segment.env, nil)
  end
  local legacy, native = plan.segments[1], plan.segments[2]
  lu.assertEquals(legacy.command, { "lua", "tests/run.lua", "fast" })
  lu.assertEquals(native.command, { "busted", "--run=fast" })
end

function TestSegmentRun:test_execute_runs_legacy_then_native_in_separate_processes()
  reset_dir()
  local plan = migration.plan("full", { coverage = true, build = ROOT })
  migration.prepare(plan)
  local executed = {}
  local results = migration.execute(plan, {
    runner = function(segment)
      executed[#executed + 1] = segment.runner
      local file = assert(io.open(segment.stats, "wb"))
      file:write(segment.runner == "legacy" and "1:common/Legacy.lua\n1 \n" or "1:common/Native.lua\n2 \n")
      file:close()
      return 0
    end,
    merged = ROOT .. "/merged.out",
  })
  lu.assertEquals(executed, { "legacy", "native" }, "两段必须按旧→原生顺序各跑一个进程")
  lu.assertEquals(migration.exit_code(results), 0)
  local body = read(ROOT .. "/merged.out")
  lu.assertNotNil(body, "两段都成功后必须一次发布合并统计")
  assertContainsText(body, "common/Legacy.lua")
  assertContainsText(body, "common/Native.lua")
end

function TestSegmentRun:test_first_failure_keeps_going_but_never_merges()
  reset_dir()
  local plan = migration.plan("full", { coverage = true, build = ROOT })
  migration.prepare(plan)
  local executed = {}
  local results = migration.execute(plan, {
    runner = function(segment)
      executed[#executed + 1] = segment.runner
      local file = assert(io.open(segment.stats, "wb"))
      file:write("1:common/" .. segment.runner .. ".lua\n1 \n")
      file:close()
      return segment.runner == "legacy" and 3 or 0
    end,
    merged = ROOT .. "/merged.out",
  })
  lu.assertEquals(executed, { "legacy", "native" }, "任一段失败仍要跑完另一段以给出两套失败报告")
  lu.assertEquals(migration.exit_code(results), 3)
  lu.assertIsNil(read(ROOT .. "/merged.out"), "失败时不得发布合并统计（保留原快照由调用方保证）")
end

function TestSegmentRun:test_empty_segment_skips_without_false_failure()
  reset_dir()
  local plan = migration.plan("full", { coverage = true, build = ROOT })
  migration.prepare(plan)
  local native = plan.segments[2]
  native.files, native.empty = {}, true
  local executed = {}
  local results = migration.execute(plan, {
    runner = function(segment)
      executed[#executed + 1] = segment.runner
      local file = assert(io.open(segment.stats, "wb"))
      file:write("1:common/Legacy.lua\n1 \n")
      file:close()
      return 0
    end,
    merged = ROOT .. "/merged.out",
  })
  lu.assertEquals(executed, { "legacy" }, "空集合段必须跳过而不是执行")
  lu.assertEquals(migration.exit_code(results), 0, "空集合不得报误失败")
  lu.assertEquals(results[2].action, "skip")
  local body = read(ROOT .. "/merged.out")
  lu.assertNotNil(body, "空集合跳过不阻塞另一段成功后的合并")
  assertContainsText(body, "common/Legacy.lua")
end

function TestSegmentRun:test_missing_stats_of_a_run_segment_fails_the_merge()
  reset_dir()
  local plan = migration.plan("full", { coverage = true, build = ROOT })
  migration.prepare(plan)
  local results = migration.execute(plan, {
    runner = function(segment)
      if segment.runner == "legacy" then
        local file = assert(io.open(segment.stats, "wb"))
        file:write("1:common/Legacy.lua\n1 \n")
        file:close()
      end
      -- 原生段退出 0 但没写统计（runner 半途而废）：合并必须失败而不是静默半量发布。
      return 0
    end,
    merged = ROOT .. "/merged.out",
  })
  lu.assertNotEquals(migration.exit_code(results), 0, "运行段缺统计必须报失败")
  lu.assertIsNil(read(ROOT .. "/merged.out"))
end

function TestSegmentRun:test_real_command_builders_target_the_two_runners()
  local legacy = migration.legacy_command("full", { coverage = true })
  local native = migration.native_command("full", { coverage = true })
  lu.assertEquals(legacy[1], "lua")
  -- 覆盖率模式经 -e 显式 init 自己的配置文件；不能用 -lluacov（它会先 init 默认配置，
  -- luacov 之后忽略后到的配置，两段统计就会写进同一个文件互相清空）。
  lu.assertEquals(legacy[2], "-e")
  lu.assertEquals(legacy[4], "tests/run.lua")
  lu.assertEquals(legacy[5], "full")
  assertNotContainsText(legacy[2], "-lluacov", "覆盖率模式不得用 -lluacov")
  lu.assertEquals(native[1], "busted")
  lu.assertEquals(native[2], "--run=full")
  lu.assertTrue(contains(native, "--coverage"))
  -- 非覆盖率模式保持原来的最小 argv，旧入口行为不变。
  lu.assertEquals(migration.legacy_command("full", nil), { "lua", "tests/run.lua", "full" })
  lu.assertEquals(migration.native_command("fast", nil), { "busted", "--run=fast" })
end
