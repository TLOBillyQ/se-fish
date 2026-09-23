package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end

local json = require("acceptance4lua.json")
local shell = require("tools.win_shell")

for line in io.lines() do
  local decoded, job = pcall(json.decode, line)
  if not decoded or type(job) ~= "table" or type(job.id) ~= "string"
    or type(job.feature_json) ~= "string" or type(job.generated_dir) ~= "string" then
    io.stderr:write("无效的 runner-worker 任务\n")
    os.exit(1)
  end
  local output_path = job.work_dir .. "/runner-output.txt"
  local command = table.concat({
    "cd .",
    'set "ACCEPTANCE_FEATURE_JSON=' .. job.feature_json .. '"',
    'set "LUA_PATH=' .. bootstrap.lua_path() .. '"',
    "> " .. shell.q(output_path) .. " 2>&1 "
      .. shell.q(os.getenv("ACCEPTANCE_LUA_BIN") or "lua")
      .. " " .. shell.q(job.generated_dir .. "/feature_acceptance_spec.lua"),
  }, " & ")
  local _, _, code = os.execute(command)
  local file = io.open(output_path, "rb")
  local output = file and file:read("a") or ""
  if file then file:close() end
  local outcome
  if code == 0 and output:find("0 failed", 1, true) then
    outcome = "test_success"
  elseif code ~= 0 and output:find("not ok -", 1, true) then
    outcome = "test_failure"
  else
    outcome = "error"
  end
  io.write(json.encode_compact({
    id = job.id,
    outcome = outcome,
    output = output,
    error = outcome == "error" and ("验收运行器故障 exit=" .. tostring(code) .. ": " .. output) or "",
  }), "\n")
  io.flush()
end
