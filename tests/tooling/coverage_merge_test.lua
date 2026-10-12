-- 覆盖率合并契约（#82）：两段统计不互相清空，两段都成功后才合并一次。
-- 失败方式：合并在某段失败时发生、合并把 a 段的文件行数清成 0、或合并重复执行把同一行累加两次。
-- 用临时目录真实 luacov.stats 文件验证，不启动真实测试 runner（轻量回归）。
local lu = require("luaunit")
local migration = require("tests.run_migration")

local ROOT = "tmp/coverage-merge-test"

local function reset_dir()
  os.execute("rd /s /q " .. ROOT:gsub("/", "\\") .. " 2>nul")
  os.execute("md " .. ROOT:gsub("/", "\\") .. " 2>nul")
end

local function write_stats(path, body)
  local file = assert(io.open(path, "wb"))
  file:write(body)
  file:close()
end

local function read_stats(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local body = file:read("a")
  file:close()
  return body
end

-- luacov.stats 文本格式：<max>:<filename>\n<hit hit ...>\n
local LEGACY_STATS = "3:common/Legacy.lua\n1 2 1 \n"
local NATIVE_STATS = "2:common/Native.lua\n1 3 \n"

TestCoverageMerge = {}

function TestCoverageMerge:test_merge_writes_only_after_both_pass()
  reset_dir()
  local legacy = ROOT .. "/legacy.out"
  local native = ROOT .. "/native.out"
  local merged = ROOT .. "/merged.out"
  write_stats(legacy, LEGACY_STATS)
  write_stats(native, NATIVE_STATS)

  -- 任一失败：不合并，输出文件保持不存在（调用方保留上一次有效快照）。
  lu.assertIsNil(migration.merge({ { runner = "legacy", code = 0, stats = legacy },
                                   { runner = "native", code = 1, stats = native } }, merged),
                 "有段失败时不得产出合并统计")
  lu.assertIsNil(read_stats(merged), "有段失败时合并输出不得存在")

  -- 两段都成功：合并一次。
  local result = migration.merge({ { runner = "legacy", code = 0, stats = legacy },
                                   { runner = "native", code = 0, stats = native } }, merged)
  lu.assertEquals(result, 0)
  local body = read_stats(merged)
  lu.assertNotNil(body, "两段都成功时必须产出合并统计")
  lu.assertStrContains(body, "common/Legacy.lua")
  lu.assertStrContains(body, "common/Native.lua")
end

function TestCoverageMerge:test_merge_preserves_hits_without_wiping_either_segment()
  reset_dir()
  local legacy = ROOT .. "/legacy.out"
  local native = ROOT .. "/native.out"
  local merged = ROOT .. "/merged.out"
  write_stats(legacy, LEGACY_STATS)
  write_stats(native, NATIVE_STATS)
  lu.assertEquals(migration.merge({ { runner = "legacy", code = 0, stats = legacy },
                                    { runner = "native", code = 0, stats = native } }, merged), 0)
  local stats = require("luacov.stats")
  local data = assert(stats.load(merged), "合并输出必须可被 luacov.stats 解析")
  lu.assertNotNil(data["common/Legacy.lua"], "合并把旧段统计清空")
  lu.assertNotNil(data["common/Native.lua"], "合并把原生段统计清空")
  lu.assertEquals(data["common/Legacy.lua"][1], 1, "旧段第 1 行命中数丢失")
  lu.assertEquals(data["common/Legacy.lua"][2], 2, "旧段第 2 行命中数丢失")
  lu.assertEquals(data["common/Native.lua"][2], 3, "原生段第 2 行命中数丢失")
end

function TestCoverageMerge:test_same_file_in_both_segments_is_summed_once()
  reset_dir()
  local legacy = ROOT .. "/legacy.out"
  local native = ROOT .. "/native.out"
  local merged = ROOT .. "/merged.out"
  -- 同一业务文件被两段都覆盖（共享模块）：行命中必须相加，且只加一次。
  write_stats(legacy, "2:common/Shared.lua\n1 2 \n")
  write_stats(native, "2:common/Shared.lua\n4 1 \n")
  lu.assertEquals(migration.merge({ { runner = "legacy", code = 0, stats = legacy },
                                    { runner = "native", code = 0, stats = native } }, merged), 0)
  local data = assert(require("luacov.stats").load(merged))
  lu.assertEquals(data["common/Shared.lua"][1], 5, "第 1 行应为 1+4=5")
  lu.assertEquals(data["common/Shared.lua"][2], 3, "第 2 行应为 2+1=3")
  lu.assertEquals(data["common/Shared.lua"].max, 2)
end

function TestCoverageMerge:test_missing_segment_stats_fails_the_merge()
  reset_dir()
  local legacy = ROOT .. "/legacy.out"
  write_stats(legacy, LEGACY_STATS)
  lu.assertIsNil(migration.merge({ { runner = "legacy", code = 0, stats = legacy },
                                   { runner = "native", code = 0, stats = ROOT .. "/absent.out" } },
                                 ROOT .. "/merged.out"),
                 "某段统计缺失时不得静默产出不完整合并")
  lu.assertIsNil(read_stats(ROOT .. "/merged.out"))
end

function TestCoverageMerge:test_empty_segment_contributes_nothing_but_still_merges()
  reset_dir()
  local legacy = ROOT .. "/legacy.out"
  local merged = ROOT .. "/merged.out"
  write_stats(legacy, LEGACY_STATS)
  -- 空集合被跳过的段（无统计文件）不应阻塞合并：empty 段视为无贡献。
  local result = migration.merge({ { runner = "legacy", code = 0, stats = legacy },
                                   { runner = "native", code = 0, skipped = true } }, merged)
  lu.assertEquals(result, 0, "空集合跳过段不得阻塞合并")
  local data = assert(require("luacov.stats").load(merged))
  lu.assertNotNil(data["common/Legacy.lua"])
  lu.assertIsNil(data["common/Native.lua"])
end
