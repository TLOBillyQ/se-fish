-- 迁移期聚合入口（#82）：旧 LuaUnit 与原生 Busted 分进程运行互斥集合，任一失败使整体失败。
-- 本模块只做「发现 + 分进程调度 + 覆盖率统计合并」，不加载任何测试框架，也不含断言桥接层。
-- 迁移完成（#93）后随旧 runner 一并移除。
local lanes = require("tests.lanes")

local M = {}

local function path_value(value)
  return (tostring(value):gsub("\\", "/"))
end

-- 旧 LuaUnit 段 argv。覆盖率模式在同一 argv 里显式挂 luacov 并指向该段自己的配置，
-- 不能靠默认 .luacov / luacov.stats.out 约定——那会让两段互相清空统计。
function M.legacy_command(lane, opts)
  if opts and opts.coverage then
    return {
      "lua",
      "-e", "local r=require('luacov.runner') r.init([[" .. path_value(opts.luacov_config) .. "]])",
      "tests/run.lua",
      lane,
    }
  end
  return { "lua", "tests/run.lua", lane }
end

-- 原生 Busted 段 argv：车道由 --run 选定；覆盖率用 --coverage-config-file 指定该段统计路径。
function M.native_command(lane, opts)
  if opts and opts.coverage then
    return { "busted", "--run=" .. lane, "--coverage", "--coverage-config-file=" .. path_value(opts.luacov_config) }
  end
  return { "busted", "--run=" .. lane }
end

-- 构建执行计划：两段各一条独立 argv（分进程）；覆盖率模式下每段独立统计文件与 luacov 配置。
-- opts = { coverage = bool, build = 分段统计目录（默认 build/quality）, merged = 合并输出（默认 luacov.stats.out） }
-- 合并默认落在 run_coverage 读取的仓库根 luacov.stats.out；分段统计留在 build 目录，失败时保留原快照。
function M.plan(lane, opts)
  opts = opts or {}
  local build = path_value(opts.build or "build/quality")
  local segments = {}
  local specs = {
    { runner = "legacy", dirs = lanes.legacy_dirs(lane), files = lanes.legacy_files(lane), build = M.legacy_command },
    { runner = "native", dirs = lanes.native_dirs(lane), files = lanes.native_files(lane), build = M.native_command },
  }
  for _, spec in ipairs(specs) do
    local segment = { runner = spec.runner, lane = lane, dirs = spec.dirs, files = spec.files }
    segment.empty = #spec.files == 0
    if opts.coverage then
      segment.stats = build .. "/luacov-" .. spec.runner .. ".out"
      segment.luacov_config = build .. "/luacov-" .. spec.runner .. ".lua"
      segment.command = spec.build(lane, { coverage = true, luacov_config = segment.luacov_config })
    else
      segment.command = spec.build(lane, nil)
    end
    segments[#segments + 1] = segment
  end
  local plan = { lane = lane, segments = segments, build = build }
  if opts.coverage then
    plan.merged = path_value(opts.merged or "luacov.stats.out")
  end
  return plan
end

function M.by_runner(plan)
  local out = {}
  for _, segment in ipairs(plan.segments) do
    out[segment.runner] = segment
  end
  return out
end

-- 写出每段的 luacov 配置（只登记自己的统计文件），并清掉本轮之前的分段统计，避免上一轮的残留被合并。
-- 两段互不引用，因此不会互相清空；合并输出只在两段都成功后由 execute 一次写出。
function M.prepare(plan)
  if not plan.merged then
    return 0
  end
  local build = plan.build
  os.execute("if not exist " .. build:gsub("/", "\\") .. " md " .. build:gsub("/", "\\") .. " >nul 2>nul")
  for _, segment in ipairs(plan.segments) do
    os.remove(segment.stats)
    local file = assert(io.open(segment.luacov_config, "wb"))
    file:write("return { statsfile = [[" .. segment.stats .. "]], runreport = false }\n")
    file:close()
  end
  return 0
end

-- 空集合跳过：该段没有 *_test.lua 时不执行命令，视为成功（0），不报误失败。
function M.decide(segment)
  if segment.empty or (segment.files and #segment.files == 0) then
    return { action = "skip", code = 0, reason = "empty lane (" .. segment.runner .. " " .. tostring(segment.lane) .. ")" }
  end
  return { action = "run" }
end

-- 任一失败使整体失败：取首个非零退出码，全 0 才 0。
function M.exit_code(results)
  for _, result in ipairs(results) do
    if result.code and result.code ~= 0 then
      return result.code
    end
  end
  return 0
end

-- 覆盖率合并：读取各段独立统计，行命中相加，一次写出 out。
-- 跳过段视为无贡献；运行段缺统计则整体失败，不产出半量合并（调用方因此保留上一次快照）。
function M.merge(results, out)
  for _, result in ipairs(results) do
    if not result.skipped and (result.code or 0) ~= 0 then
      return nil, "segment failed: " .. tostring(result.runner)
    end
  end
  local ok, stats = pcall(require, "luacov.stats")
  if not ok then
    return nil, "luacov.stats unavailable: " .. tostring(stats)
  end
  local merged
  for _, result in ipairs(results) do
    if not result.skipped then
      if not result.stats then
        return nil, "missing stats path for " .. tostring(result.runner)
      end
      local loaded = stats.load(result.stats)
      if not loaded then
        return nil, "segment stats not found: " .. tostring(result.stats)
      end
      if not merged then
        merged = loaded
      else
        for name, data in pairs(loaded) do
          local target = merged[name]
          if not target then
            merged[name] = data
          else
            target.max = math.max(target.max, data.max)
            target.max_hits = target.max_hits or 0
            data.max, data.max_hits = nil, nil
            for line, hits in pairs(data) do
              target[line] = (target[line] or 0) + hits
              target.max_hits = math.max(target.max_hits, target[line])
            end
          end
        end
      end
    end
  end
  stats.save(out, merged or {})
  return 0
end

-- 分进程执行两段：旧段在前、原生段在后（与旧入口的车道顺序一致）。
-- hooks.runner(segment) 起一个进程并返回退出码；hooks.merged 给合并输出路径。
-- 只有两段都成功才合并一次；任一失败不合并，由调用方保留原快照。
function M.execute(plan, hooks)
  hooks = hooks or {}
  local runner = hooks.runner or function(segment)
    local parts = {}
    for _, item in ipairs(segment.command) do
      local text = tostring(item)
      -- 含空格的 argv（例如 -e 语句）必须整体加引号，否则 cmd 会把它拆成多个参数、
      -- lua 的 -e 只取到 `local` 就报 <name> expected。
      if text:find("[ \t&^<>|]") then
        parts[#parts + 1] = '"' .. text .. '"'
      else
        parts[#parts + 1] = text
      end
    end
    local _, _, code = os.execute(table.concat(parts, " "))
    return code or 1
  end
  local results = {}
  for _, segment in ipairs(plan.segments) do
    local decision = M.decide(segment)
    if decision.action == "skip" then
      results[#results + 1] = {
        runner = segment.runner,
        action = "skip",
        code = decision.code,
        skipped = true,
        reason = decision.reason,
        stats = segment.stats,
      }
    else
      results[#results + 1] = {
        runner = segment.runner,
        action = "run",
        code = runner(segment) or 0,
        stats = segment.stats,
      }
    end
  end
  if plan.merged and M.exit_code(results) == 0 then
    local code, reason = M.merge(results, hooks.merged or plan.merged)
    if not code then
      results[#results + 1] = { runner = "merge", action = "merge", code = 1, reason = reason }
    else
      results[#results + 1] = { runner = "merge", action = "merge", code = 0 }
    end
  end
  return results
end

-- 两套 runner 的失败报告：列出每段 runner、案例数、动作与退出码；空集合只报 skip。
function M.report(plan, results)
  local lines = { "迁移期双 runner（车道 " .. plan.lane .. "）" }
  local by_runner = M.by_runner(plan)
  for _, result in ipairs(results) do
    if result.action == "merge" then
      lines[#lines + 1] = string.format("merge: %s%s", result.code == 0 and "ok" or "FAILED",
                                        result.reason and (" " .. result.reason) or "")
    else
      local segment = by_runner[result.runner]
      local count = segment and #segment.files or 0
      if result.action == "skip" then
        lines[#lines + 1] = string.format("%s: %d 案例 skip（空集合，不报失败）", result.runner, count)
      elseif result.code == 0 then
        lines[#lines + 1] = string.format("%s: %d 案例 ok code=0", result.runner, count)
      else
        lines[#lines + 1] = string.format("%s: %d 案例 FAILED code=%d", result.runner, count, result.code)
      end
    end
  end
  return table.concat(lines, "\n")
end

function M.main(argv)
  local lane = argv[1] or "full"
  if lane ~= "fast" and lane ~= "full" then
    io.stderr:write("用法: lua tests/run_migration.lua [fast|full] [--coverage] [--list]\n")
    return 1
  end
  local coverage = false
  local listing = false
  for index = 2, #argv do
    if argv[index] == "--coverage" then
      coverage = true
    elseif argv[index] == "--list" then
      listing = true
    else
      io.stderr:write("用法: lua tests/run_migration.lua [fast|full] [--coverage] [--list]\n")
      return 1
    end
  end
  local plan = M.plan(lane, { coverage = coverage })
  if listing then
    for _, segment in ipairs(plan.segments) do
      io.stdout:write("[" .. segment.runner .. "] " .. segment.lane .. " " .. #segment.files .. " 案例\n")
      for _, file in ipairs(segment.files) do
        io.stdout:write("  " .. file .. "\n")
      end
    end
    return 0
  end
  M.prepare(plan)
  local results = M.execute(plan)
  io.stdout:write(M.report(plan, results) .. "\n")
  return M.exit_code(results)
end

-- 作为脚本直接执行时才跑 CLI。脚本块里的 `...` 是脚本参数（不是 modname），
-- 因此用 arg[0] 判定入口：回归测试通过 require 加载时 arg[0] 指向别的文件，不会触发调度。
local entry = arg and arg[0] and path_value(arg[0]):match("run_migration%.lua$")
if entry then
  local code = M.main(arg)
  io.stdout:flush()
  os.exit(code)
end

return M
