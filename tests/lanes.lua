-- 迁移期双 runner 的车道定义（#82）。
-- 旧 LuaUnit 与原生 Busted 分进程运行互斥集合：同一目录只能属于一个 runner，
-- 否则 Busted 会 loadfile 整个 LuaUnit 套件（注册 0 个案例、退出码仍为 0），形成跨 runner 加载。
-- `.busted`、`tests/run.lua` 与聚合入口 `tests/run_migration.lua` 都从这里取清单，
-- 两套发现规则不会各自漂移。
local M = {}

-- 旧 LuaUnit 车道目录（不含 tests/native）。
M.legacy_lanes = {
  gameplay = { "tests/gameplay" },
  tooling = { "tests/tooling", "tests/tooling/slow" },
  fast = { "tests/gameplay", "tests/tooling" },
  full = { "tests/gameplay", "tests/tooling", "tests/tooling/slow" },
}

-- 原生 Busted 车道目录（不含任何 LuaUnit 目录）。full 追加 native/slow。
M.native_lanes = {
  fast = { "tests/native" },
  full = { "tests/native", "tests/native/slow" },
}

local function check(table, lane, what)
  local dirs = table[lane]
  if not dirs then
    error("未知" .. what .. "车道：" .. tostring(lane))
  end
  local out = {}
  for _, dir in ipairs(dirs) do
    out[#out + 1] = dir
  end
  return out
end

function M.legacy_dirs(lane)
  return check(M.legacy_lanes, lane, "旧")
end

function M.native_dirs(lane)
  return check(M.native_lanes, lane == "default" and "fast" or lane, "原生")
end

-- 一级目录内 `*_test.lua`（不递归）；只匹配 .lua，Python 回归（*_test.py）永不进清单。
local function list_files(dir)
  local handle = assert(io.popen('dir /b /a-d "' .. dir:gsub("/", "\\") .. '\\*_test.lua" 2>nul'))
  local files = {}
  for line in handle:lines() do
    local name = line:gsub("[\r\n]+$", "")
    if name ~= "" then
      files[#files + 1] = dir .. "/" .. name
    end
  end
  handle:close()
  return files
end

function M.legacy_files(lane)
  local files = {}
  for _, dir in ipairs(M.legacy_dirs(lane)) do
    for _, file in ipairs(list_files(dir)) do
      files[#files + 1] = file
    end
  end
  table.sort(files)
  return files
end

-- 原生侧文件清单按车道目录拼接，不排序：Busted 自己按 sort-files 决定执行顺序。
function M.native_files(lane)
  local files = {}
  for _, dir in ipairs(M.native_dirs(lane)) do
    for _, file in ipairs(list_files(dir)) do
      files[#files + 1] = file
    end
  end
  return files
end

return M
