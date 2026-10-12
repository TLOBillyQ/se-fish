-- 共享初始化与顺序契约（#82）：两套 runner 必须走同一份基线接缝，顺序各自稳定。
-- 失败方式：基线在两处各写一遍（改一处忘另一处）、聚合入口打乱旧入口的文件顺序、
-- 或部分 setup 失败时共享夹具没有清理就进入下一案例。
local lu = require("luaunit")
local lanes = require("tests.lanes")
local migration = require("tests.run_migration")

TestSharedInit = {}

function TestSharedInit:test_baseline_has_one_source_for_both_runners()
  local baseline = require("tests.support.baseline")
  lu.assertEquals(type(baseline.apply), "function", "共享基线必须暴露 apply()")
  local GameCfg = require("common.GameCfg")

  baseline.apply()
  lu.assertEquals(GameCfg.Debug.Enabled, true)
  lu.assertNotEquals(GameCfg.Debug.InitialGrants, nil)
  lu.assertEquals(GameCfg.Save.AcceptanceSlot, "")

  -- 两个入口都必须调用同一接缝，而不是各自复制两行配置。
  for _, path in ipairs({ "tests/run.lua", "tests/native/helper.lua" }) do
    local source = assert(io.open(path, "rb")):read("a")
    lu.assertNotEquals(source:find("tests.support.baseline", 1, true), nil,
                       path .. " 没有使用共享基线接缝")
    lu.assertNil(source:find("AcceptanceSlot%s*=%s*[\"']", 1),
                 path .. " 仍在入口里直接写基线值，基线会漂移")
  end
end

function TestSharedInit:test_baseline_apply_is_idempotent_and_preserves_initial_grants()
  local baseline = require("tests.support.baseline")
  local GameCfg = require("common.GameCfg")
  baseline.apply()
  local grants = GameCfg.Debug.InitialGrants
  baseline.apply()
  lu.assertEquals(GameCfg.Debug.InitialGrants, grants, "重复 apply 丢失 InitialGrants 引用")
  lu.assertEquals(GameCfg.Debug.Enabled, true)
end

function TestSharedInit:test_baseline_snapshot_restore_survives_a_failing_case()
  local baseline = require("tests.support.baseline")
  local GameCfg = require("common.GameCfg")
  baseline.apply()
  local snapshot = baseline.snapshot()
  GameCfg.Debug = { Enabled = false }
  GameCfg.Save.AcceptanceSlot = "dirty"
  -- 部分 setup 失败：清理必须在测试体根本没跑的情况下也把基线恢复。
  baseline.restore(snapshot)
  lu.assertEquals(GameCfg.Debug.Enabled, true)
  lu.assertEquals(GameCfg.Save.AcceptanceSlot, "")
end

-- 起 lua 子进程的回归必须取到真正的解释器：arg 里解释器的下标会随启动选项前移，
-- 覆盖率模式（旧段的 `-e` 形态）下 arg[-1] 是 `-e` 的语句原文，写死 arg[-1] 会让
-- 整片临时仓库回归只在 `--coverage` 下失败。
function TestSharedInit:test_interpreter_helper_reads_exe_from_any_launch_shape()
  local interpreter = require("tests.support.interpreter")
  local exe
  for index = -1, -8, -1 do
    local value = arg[index]
    if type(value) == "string" and not value:match("^%-") and value:lower():match("%.exe$") then
      exe = value
      break
    end
  end
  lu.assertNotNil(exe, "回归进程应当能从 arg 里定位解释器")

  local shapes = {
    { [-1] = exe },                    -- lua s.lua
    { [-1] = "-lluacov", [-2] = exe }, -- lua -lluacov s.lua
    { [-1] = "local r=require('luacov.runner')", [-2] = "-e", [-3] = exe }, -- lua -e 语句 s.lua
  }
  for _, shape in ipairs(shapes) do
    lu.assertEquals(interpreter.path(shape), exe,
                    "取错解释器（arg[-1] = " .. tostring(shape[-1]) .. "）")
  end
end

function TestSharedInit:test_interpreter_helper_falls_back_when_nothing_looks_like_exe()
  local interpreter = require("tests.support.interpreter")
  lu.assertEquals(interpreter.path({ [-1] = "-e", [-2] = "local x = 1" }), "lua")
  lu.assertEquals(interpreter.path({ [-1] = "not-a-real-lua-binary-xyz" }), "lua")
  lu.assertEquals(interpreter.path({}), "lua", "空 arg 也要回落")
end

function TestSharedInit:test_child_spawning_regessions_use_the_helper()
  -- 防止退回顾 arg[-1] 的写法：起子进程的回归统一走 tests.support.interpreter。
  for _, path in ipairs({
    "tests/tooling/migration_cli_test.lua",
    "tests/native/slow/sync_transport_test.lua",
  }) do
    local source = assert(io.open(path, "rb")):read("a")
    lu.assertNotEquals(source:find("tests.support.interpreter", 1, true), nil,
                       path .. " 没有用解释器接缝取 lua")
    lu.assertNil(source:find("arg[-1]", 1, true),
                 path .. " 仍直接读 arg[-1]，覆盖率模式下会取到 -e 语句")
  end
end

function TestSharedInit:test_legacy_order_matches_the_old_entry_file_sort()
  for _, lane in ipairs({ "fast", "full" }) do
    local files = lanes.legacy_files(lane)
    for index = 2, #files do
      lu.assertTrue(files[index - 1] <= files[index],
                    "旧车道清单必须按文件名排序：" .. files[index - 1] .. " / " .. files[index])
    end
  end
end

function TestSharedInit:test_aggregator_keeps_legacy_before_native()
  local plan = migration.plan("full")
  lu.assertEquals(plan.segments[1].runner, "legacy")
  lu.assertEquals(plan.segments[2].runner, "native")
  -- 旧入口内部顺序由 tests/run.lua 的排序保证；原生段顺序由 .busted 的 sort-files 保证。
  local cfg = dofile(".busted")
  lu.assertEquals(cfg._all["sort-files"], true, "原生段必须按文件名排序以对齐旧入口顺序")
end
