-- 双 runner 互斥发现规则（#82）。
-- 失败方式：原生 Busted 与旧 LuaUnit 发现到同一批文件（重复注册）、某批文件两边都发现不到（遗漏）、
-- 或一侧 ROOT/目录里混进另一侧的测试文件（跨 runner 加载，Busted 会 loadfile 整个 LuaUnit 套件却注册 0 案例）。
-- 三条规则必须在同一份车道定义上核对，因此车道目录清单只能有一个来源：tests/lanes.lua。
local lu = require("luaunit")
local lanes = require("tests.lanes")

local function to_set(paths)
  local set = {}
  for _, path in ipairs(paths) do
    set[path] = true
  end
  return set
end

local function sorted(values)
  local out = {}
  for value in pairs(values) do
    out[#out + 1] = value
  end
  table.sort(out)
  return out
end

-- 扫磁盘上真实存在的文件（dir /b /s），作为「不应有遗漏」的独立来源。
-- dir /s 打绝对路径，这里裁回仓库相对的 tests/... 形式，和车道清单同一口径。
local function scan_dirs(pattern)
  local handle = assert(io.popen('dir /b /s "tests\\' .. pattern .. '" 2>nul'))
  local dirs = {}
  for line in handle:lines() do
    local path = (line:gsub("[\r\n]+$", ""):gsub("\\", "/")):match("tests/.+")
    local dir = path and path:match("^(.*)/[^/]*$")
    if dir then
      dirs[dir] = true
    end
  end
  handle:close()
  return dirs
end

TestDualLanes = {}

function TestDualLanes:test_two_runner_dirs_are_mutually_exclusive()
  for _, lane in ipairs({ "fast", "full" }) do
    local legacy, native = to_set(lanes.legacy_dirs(lane)), to_set(lanes.native_dirs(lane))
    for _, dir in ipairs(sorted(native)) do
      lu.assertNil(legacy[dir], lane .. " 车道同一目录被两个 runner 发现：" .. dir)
    end
  end
end

function TestDualLanes:test_busted_roots_are_exactly_the_native_dirs()
  local cfg = dofile(".busted")
  for _, task in ipairs({ "default", "fast", "full" }) do
    local expected = lanes.native_dirs(task == "default" and "fast" or task)
    lu.assertEquals(cfg[task].ROOT, expected, task .. " 的 Busted ROOT 必须与原生车道目录完全一致")
  end
end

function TestDualLanes:test_no_legacy_dir_is_handed_to_busted()
  -- 跨 runner 加载的根因：Busted 的 ROOT 里混进旧测试目录。
  local cfg = dofile(".busted")
  local legacy = to_set(lanes.legacy_dirs("full"))
  for _, task in ipairs({ "default", "fast", "full" }) do
    for _, root in ipairs(cfg[task].ROOT) do
      lu.assertNil(legacy[root], task .. " 不得把旧测试目录交给 Busted：" .. root)
    end
  end
end

function TestDualLanes:test_no_test_dir_is_left_out()
  local covered = to_set(lanes.legacy_dirs("full"))
  for _, dir in ipairs(lanes.native_dirs("full")) do
    covered[dir] = true
  end
  for _, dir in ipairs(sorted(scan_dirs("*_test.lua"))) do
    lu.assertTrue(covered[dir], "有 *_test.lua 的目录不属于任何 runner：" .. dir)
  end
end

function TestDualLanes:test_full_includes_slow_and_fast_excludes_it()
  for _, lane in ipairs({ "fast", "full" }) do
    for _, key in ipairs({ "legacy_dirs", "native_dirs" }) do
      for _, dir in ipairs(lanes[key](lane)) do
        if lane == "fast" then
          lu.assertNil(dir:match("slow"), "fast 车道混入 slow 目录：" .. dir)
        end
      end
    end
  end
  local full_legacy, full_native = to_set(lanes.legacy_dirs("full")), to_set(lanes.native_dirs("full"))
  lu.assertTrue(full_legacy["tests/tooling/slow"], "full 旧车道必须含 tooling/slow")
  lu.assertTrue(full_native["tests/native/slow"], "full 原生车道必须含 native/slow")
end

function TestDualLanes:test_python_regression_is_never_a_lua_lane()
  -- Python 回归保持独立车道：两套 Lua 发现规则都只可能命中 .lua，.py 永不进清单。
  local python_files = scan_dirs("*_test.py")
  lu.assertNotNil(next(python_files), "tests/tooling/slow 下应有 Python 回归")
  for _, lane in ipairs({ "fast", "full" }) do
    for _, file in ipairs(lanes.legacy_files(lane)) do
      lu.assertNotNil(file:match("%.lua$"), "旧车道发现非 Lua 文件：" .. file)
    end
  end
  local cfg = dofile(".busted")
  lu.assertStrContains(cfg._all.pattern, "_test", "Busted pattern 必须只匹配 Lua 案例文件")
  lu.assertNil(cfg._all.pattern:match("py"), "Busted pattern 不得匹配 Python 文件")
  for _, root in ipairs(cfg.full.ROOT) do
    lu.assertNil(python_files[root], "Busted ROOT 覆盖了 Python 回归目录：" .. root)
  end
end
