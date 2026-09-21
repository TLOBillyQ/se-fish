-- tools/acceptance/bootstrap.lua —— 把 acceptance4lua 放到 package.path 上，
-- 树不存在时先从内网 Gitea clone 到 .toolcache/（在仓库根运行）。
--
-- 与 se-defense 那套的差别：不走 luarocks。acceptance4lua 是纯 Lua（src/acceptance4lua/*.lua），
-- 不必编译、不必装 rock，clone 下来把 src/ 直接拼进 LUA_PATH 即可；本机也没有 luarocks。
-- 树的位置可用 SE_FISH_LUA_TOOLS 覆盖；跟随上游 main（不锁版本），删掉 .toolcache/ 即重装。
local shell = require("tools.win_shell")

local M = {}

M.tree = os.getenv("SE_FISH_LUA_TOOLS") or ".toolcache/acceptance4lua"
M.repo_url = "http://lzxsvn:3000/eggy/acceptance4lua"

-- 装好的标志：框架的 init.lua 就位。
local function marker()
  return M.tree .. "/src/acceptance4lua/init.lua"
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function run(cmd)
  local _, _, code = os.execute(cmd)
  return code == 0
end

-- URL 只加引号：tools.win_shell 的 q() 会把 / 换成 \（那是给文件路径用的），
-- 套到 URL 上会把 http:// 拧成 http:\，git 就当成别的协议了。
local function url_q(value)
  return '"' .. tostring(value) .. '"'
end

-- 子进程（生成的 spec）用的 LUA_PATH：框架树最前，其后是仓库根（步骤模块按
-- tools.acceptance.* 解析），末尾 ;; 展开成解释器的默认路径。
function M.lua_path()
  local src = M.tree .. "/src"
  local parts = {
    src .. "/?.lua",
    src .. "/?/init.lua",
    "./?.lua",
    "./?/init.lua",
    "",
    "",
  }
  return table.concat(parts, ";")
end

function M.install()
  print("[acceptance] clone " .. M.repo_url .. " → " .. M.tree)
  shell.ensure_dir(M.tree:match("^(.*)/[^/]+$") or ".")
  if not run("git clone --depth 1 " .. url_q(M.repo_url) .. " " .. shell.q(M.tree)) then
    return nil, "git clone 失败: " .. M.repo_url .. "（内网 Gitea 要可访问）"
  end
  if not exists(marker()) then
    return nil, "clone 完仍找不到 " .. marker() .. "（仓库布局变了？）"
  end
  return true
end

-- 就位检查 + 装 path；失败返回 nil, 原因（调用方负责打印并退出）。
function M.ensure()
  if not exists(marker()) then
    local ok, err = M.install()
    if not ok then return nil, "error: " .. err end
  end
  package.path = M.lua_path() .. ";" .. package.path
  return true
end

return M
