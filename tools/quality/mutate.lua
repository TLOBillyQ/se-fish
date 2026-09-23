local root = assert(os.getenv("SE_FISH_ROOT"))
table.insert(package.searchers, 1, function(name)
  local suffix = name:match("^mutate4lua%.(.+)$")
  if suffix then
    local file = root .. "/.toolcache/mutate4lua/src/" .. suffix:gsub("%.", "/") .. ".lua"
    return loadfile(file)
  end
end)
-- 上游的 POSIX 子命令在 Windows Lua 中会被 cmd.exe 解释；把它们交给 Git Bash，缓存源码不打补丁。
local bash = assert(os.getenv("SE_FISH_BASH"))
local native_execute, native_popen = os.execute, io.popen
local counter = 0
local function script(command)
  counter = counter + 1
  local path = "../shell-" .. counter .. ".sh"
  local file = assert(io.open(path, "wb"))
  command = command:gsub("(%a:)[\\]([^']*)", function(drive, rest)
    return drive .. "/" .. rest:gsub("\\", "/")
  end)
  file:write("#!/usr/bin/env bash\n", command, "\n")
  file:close()
  return '""' .. bash .. '" "' .. path .. '""'
end
os.execute = function(command)
  return native_execute(script(command))
end
io.popen = function(command, mode)
  return native_popen(script(command), mode)
end
local cli = require("mutate4lua.cli")
os.exit(cli.run(arg, { command_name = "tools/quality/mutate.sh" }))
