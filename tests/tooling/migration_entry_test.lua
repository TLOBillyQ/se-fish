-- 迁移期聚合入口契约（#82）：两套 runner 分进程运行互斥集合，命令选择、案例清单与退出码在这里定死。
-- 聚合入口是临时设施（#93 移除），因此其计划/执行接缝以模块形式暴露，供轻量回归验证——不跑真实 mutation。
local lu = require("luaunit")
local migration = require("tests.run_migration")
local lanes = require("tests.lanes")

TestMigrationPlan = {}

function TestMigrationPlan:test_two_segments_in_separate_processes()
  for _, lane in ipairs({ "fast", "full" }) do
    local plan = migration.plan(lane)
    lu.assertEquals(#plan.segments, 2, lane .. " 必须恰好两段（旧 LuaUnit + 原生 Busted）")
    local by_runner = {}
    for _, segment in ipairs(plan.segments) do
      lu.assertIsNil(by_runner[segment.runner], lane .. " 同一 runner 出现两段：" .. segment.runner)
      by_runner[segment.runner] = segment
    end
    lu.assertNotNil(by_runner.legacy)
    lu.assertNotNil(by_runner.native)
    -- 分进程：每段一条独立 argv，首项分别是 Lua 解释器与 busted 命令。
    lu.assertEquals(by_runner.legacy.command[1], "lua")
    lu.assertEquals(by_runner.native.command[1], "busted")
    lu.assertNotEquals(by_runner.legacy.command, by_runner.native.command)
  end
end

function TestMigrationPlan:test_segment_file_sets_are_disjoint_and_complete()
  for _, lane in ipairs({ "fast", "full" }) do
    local plan = migration.plan(lane)
    local seen = {}
    for _, segment in ipairs(plan.segments) do
      for _, file in ipairs(segment.files) do
        lu.assertIsNil(seen[file], lane .. " 同一文件被两段注册：" .. file)
        seen[file] = segment.runner
      end
    end
    lu.assertTrue(#plan.segments > 0, lane .. " 计划必须至少有一段")
  end
end

function TestMigrationPlan:test_plan_files_match_the_lane_source()
  for _, lane in ipairs({ "fast", "full" }) do
    local plan = migration.plan(lane)
    local by_runner = migration.by_runner(plan)
    lu.assertEquals(by_runner.legacy.files, lanes.legacy_files(lane), lane .. " 旧段清单与车道定义不一致")
    lu.assertEquals(by_runner.native.files, lanes.native_files(lane), lane .. " 原生段清单与车道定义不一致")
  end
end

function TestMigrationPlan:test_full_includes_slow_and_fast_excludes_it()
  local slow = { legacy = "tests/tooling/slow/", native = "tests/native/slow/" }
  for _, lane in ipairs({ "fast", "full" }) do
    local plan = migration.plan(lane)
    for runner, prefix in pairs(slow) do
      local found = false
      for _, file in ipairs(migration.by_runner(plan)[runner].files) do
        if file:sub(1, #prefix) == prefix then
          found = true
        end
      end
      if lane == "fast" then
        lu.assertFalse(found, "fast 不得包含 slow 案例文件：" .. prefix)
      else
        lu.assertTrue(found, "full 必须包含 slow 案例文件：" .. prefix)
      end
    end
  end
end

function TestMigrationPlan:test_empty_segment_is_skipped_not_failed()
  local segment = { runner = "native", lane = "full", files = {}, command = { "busted" }, empty = true }
  local decision = migration.decide(segment)
  lu.assertEquals(decision.action, "skip", "空集合必须跳过而不是执行")
  lu.assertEquals(decision.code, 0, "空集合不得报失败：" .. tostring(decision.reason))
  lu.assertNotEquals(decision.code, nil)
  local nonempty = { runner = "native", lane = "full", files = { "tests/native/x_test.lua" }, command = { "busted" } }
  lu.assertEquals(migration.decide(nonempty).action, "run")
end

function TestMigrationPlan:test_any_segment_failure_fails_the_whole_run()
  lu.assertEquals(migration.exit_code({ { runner = "legacy", code = 0 }, { runner = "native", code = 0 } }), 0)
  lu.assertNotEquals(migration.exit_code({ { runner = "legacy", code = 1 }, { runner = "native", code = 0 } }), 0)
  lu.assertNotEquals(migration.exit_code({ { runner = "legacy", code = 0 }, { runner = "native", code = 3 } }), 0)
  -- 两段都失败时仍报失败，不被后一段覆盖。
  lu.assertNotEquals(migration.exit_code({ { runner = "legacy", code = 2 }, { runner = "native", code = 5 } }), 0)
end

function TestMigrationPlan:test_no_assertion_bridge_in_the_aggregator()
  -- 临时聚合入口只做「发现 + 分进程调度」，不含断言桥接层：模块本身不加载任一测试框架。
  -- （本检查不能在自己所在的 LuaUnit 进程里断言 package.loaded，直接读模块源码。）
  local source = assert(io.open("tests/run_migration.lua", "rb")):read("a")
  lu.assertNil(source:match("require%s*%(?[\"']luaunit"), "聚合入口不得 require LuaUnit")
  lu.assertNil(source:match("require%s*%(?[\"']busted"), "聚合入口不得 require Busted")
  lu.assertNil(source:match("require%s*%(?[\"']luassert"), "聚合入口不得 require Luassert")
  lu.assertNil(source:match("assert%."), "聚合入口不得持有断言调用")
end

function TestMigrationPlan:test_coverage_mode_uses_distinct_stats_per_segment()
  local plan = migration.plan("full", { coverage = true })
  local by_runner = migration.by_runner(plan)
  lu.assertNotEquals(by_runner.legacy.stats, nil, "覆盖率模式必须给旧段独立统计文件")
  lu.assertNotEquals(by_runner.native.stats, nil, "覆盖率模式必须给原生段独立统计文件")
  lu.assertNotEquals(by_runner.legacy.stats, by_runner.native.stats, "两段共用统计文件会互相清空")
  lu.assertNotEquals(by_runner.legacy.stats, plan.merged, "合并输出不能与某段共用")
  lu.assertNotEquals(by_runner.native.stats, plan.merged, "合并输出不能与某段共用")
  -- 非覆盖率模式不写统计，也不引入 luacov。
  local plain = migration.by_runner(migration.plan("fast"))
  lu.assertIsNil(plain.legacy.stats)
  lu.assertIsNil(plain.native.stats)
end

function TestMigrationPlan:test_python_regression_is_not_a_segment()
  local plan = migration.plan("full", { coverage = true })
  for _, segment in ipairs(plan.segments) do
    lu.assertNotEquals(segment.runner, "python", "Python 回归不得并入 Lua 聚合入口")
    for _, file in ipairs(segment.files) do
      lu.assertNil(file:match("%.py$"), "Lua 段发现 Python 回归：" .. file)
    end
  end
end
