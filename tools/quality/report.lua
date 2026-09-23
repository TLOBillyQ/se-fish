local common = require("crap4lua._internal.common")
local coverage = require("crap4lua.coverage")
local analyzer = require("crap4lua.analyzer")
local json = require("crap4lua._internal.json_writer")
local dry = require("dry4lua.analysis")

local owned = require("tools.quality.sources").owned

local files = {}
local handle = assert(io.popen('git ls-files --cached --others --exclude-standard "*.lua"'))
for line in handle:lines() do
  line = line:gsub("\r$", "")
  if owned(line) then files[#files + 1] = line end
end
assert(handle:close())
assert(#files > 0, "没有可分析的自有 Lua 源码")
table.sort(files)
local crap_ast = require("crap4lua.ast")
local dry_ast = require("dry4lua.ast")
for _, path in ipairs(files) do
  local parsed_crap, err_crap = crap_ast.analyze_file(path)
  assert(parsed_crap, path .. ": " .. tostring(err_crap))
  local parsed_dry, err_dry = dry_ast.parse_file(path)
  assert(parsed_dry, path .. ": " .. tostring(err_dry))
end

local source = assert(io.open("build/quality/luacov.report.out", "rb"))
local report_text = source:read("a")
source:close()
local raw = coverage.parse_luacov_report(report_text)
local parsed = {}
for path, entry in pairs(raw) do
  parsed[path:gsub("\\", "/")] = entry
end
local covered = 0
for _, path in ipairs(files) do
  if parsed[path] then covered = covered + 1 end
end
assert(covered > 0, "luacov 报告未匹配到自有 Lua 源码")
local cwd = common.normalize_path(assert(io.popen("cd"):read("*l")))
local original_collect = common.collect_files
common.collect_files = function()
  local selected = {}
  for _, path in ipairs(files) do selected[#selected + 1] = common.resolve_path(cwd, path) end
  return selected
end
local crap = analyzer.build_report({
  project_root = cwd, project_name = "se-fish", source_roots = { "." }, top = 0,
  coverage_result = { files = parsed, coverage_available = true, lanes = {{lane = "unit", failed = false}} },
})
common.collect_files = original_collect
assert(#crap.functions > 0 and crap.summary.na_count < #crap.functions, "CRAP 无可度量函数")
local out = assert(io.open("build/quality/crap.json", "wb"))
out:write(json.encode(crap))
out:close()

-- dry4lua 上游通过 POSIX find 枚举文件；Windows 原生 Lua 的 io.popen 走 cmd.exe，
-- 只在分析调用期间把这一步替换为同一份自有源码清单，不修改缓存中的上游实现。
local original_popen = io.popen
io.popen = function(cmd, mode)
  if cmd:sub(1, 5) == "find " then
    local index = 0
    return {
      lines = function()
        return function()
          index = index + 1
          return files[index]
        end
      end,
      close = function() return true end,
    }
  end
  return original_popen(cmd, mode)
end
local ok, candidates = pcall(dry.find_duplicates, { paths = { "." } })
io.popen = original_popen
assert(ok, candidates)
out = assert(io.open("build/quality/dry.json", "wb"))
out:write(json.encode({ candidates = candidates, source_count = #files }))
out:close()
print(string.format("质量分析完成：%d 个自有 Lua 文件，%d 个有覆盖数据，%d 个 CRAP 函数（%d 个 N/A），%d 对重复候选；仅报告、不设门槛。", #files, covered, #crap.functions, crap.summary.na_count, #candidates))
