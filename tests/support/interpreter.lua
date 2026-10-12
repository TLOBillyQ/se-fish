-- 取「启动当前进程的 lua 解释器」，给需要再起一个 lua 子进程的回归用（不靠 PATH 猜 `lua`）。
-- Lua 把解释器记在 arg 的负索引，但位置随启动选项前移：
--   lua s.lua            -> arg[-1]
--   lua -e 语句 s.lua     -> arg[-3]（arg[-1] 是语句原文，arg[-2] 是 "-e"）
--   lua -lluacov s.lua   -> arg[-2]（arg[-1] 是 "-lluacov"）
-- 只读 arg[-1] 的写法在覆盖率模式（#82 旧段的 `-e` 形态）下会把语句原文当解释器，
-- 子进程命令行变成 "local r=require(...)" "…/run.lua"，cmd 报「找不到路径」——
-- 于是所有起 lua 子进程的回归只在覆盖率模式下整片失败。
local M = {}

local MAX_BACK = 8

-- 像解释器的条目：不是启动选项（不以 - 开头），且当前真的读得到。
local function looks_like_exe(value)
  if type(value) ~= "string" or value == "" or value:match("^%-") then
    return false
  end
  local file = io.open(value, "rb")
  if not file then
    return false
  end
  file:close()
  return true
end

-- args 省略时取当前进程的 arg；找不到就回落 "lua"（交给 PATH）。
function M.path(args)
  args = args or arg
  if type(args) ~= "table" then
    return "lua"
  end
  for index = -1, -MAX_BACK, -1 do
    if looks_like_exe(args[index]) then
      return args[index]
    end
  end
  return "lua"
end

return M
