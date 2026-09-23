package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end

local mutator = require("acceptance4lua.mutator")
local work_dir = "build/acceptance/mutation"
local report, run_err = mutator.run({
  feature = work_dir .. "/deploy-mirror.feature",
  work_dir = work_dir,
  generated_dir = work_dir .. "/generated",
  steps_module = "tools.acceptance.steps",
  runner_worker = '"' .. (os.getenv("ACCEPTANCE_LUA_BIN") or "lua") .. '" tools/acceptance/cli/mutation_worker.lua',
  workers = 1,
  level = "full",
  status_interval_seconds = 0,
})
if not report then
  io.stderr:write(tostring(run_err) .. "\n")
  os.exit(1)
end
local path = work_dir .. "/report.json"
local file, open_err = io.open(path, "wb")
if not file then
  io.stderr:write(tostring(open_err) .. "\n")
  os.exit(1)
end
local written, write_err = file:write(mutator.format_json_report(report))
local closed, close_err = file:close()
if not written or not closed then
  io.stderr:write(tostring(write_err or close_err) .. "\n")
  os.exit(1)
end
io.write(mutator.format_text_report(report, { verbose = true }))
if report.summary.total == 0 or report.summary.errors > 0 then
  os.exit(1)
end
