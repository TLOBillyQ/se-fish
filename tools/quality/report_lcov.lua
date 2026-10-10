-- 将 LuaCov 统计转换为 crapper、mutator 自动发现的 LCOV。
local statsfile, reportfile = arg[1], arg[2]
assert(statsfile and reportfile, "用法：lua tools/quality/report_lcov.lua <统计文件> <LCOV 输出文件>")
local runner = require("luacov.runner")
runner.load_config({
    statsfile = statsfile,
    reportfile = reportfile,
    exclude = {"/packages/", "server/_trigger/"},
})
local reporter = require("luacov.reporter")
local R = setmetatable({}, reporter.ReporterBase)
R.__index = R
function R:on_new_file(filename)
    self:write("SF:", filename:gsub("\\", "/"), "\n")
end
function R:on_hit_line(_, lineno, _, hits)
    self:write(("DA:%d,%d\n"):format(lineno, hits))
end
function R:on_mis_line(_, lineno)
    self:write(("DA:%d,0\n"):format(lineno))
end
function R:on_end_file(_, hits, miss)
    self:write(("LF:%d\nLH:%d\nend_of_record\n"):format(hits + miss, hits))
end
function R:on_file_error(filename, kind, message)
    error(("%s: %s: %s"):format(filename, kind, message))
end
reporter.report(R)
