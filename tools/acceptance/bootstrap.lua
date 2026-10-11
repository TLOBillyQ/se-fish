-- acceptance4lua 与 dry4lua 按固定提交放入 .toolcache/；缓存存在时只校验，不访问网络。
-- acceptance4lua 的位置可用 SE_FISH_LUA_TOOLS 覆盖；不依赖 luarocks。
local shell = require("tools.win_shell")

local M = {}

M.tree = os.getenv("SE_FISH_LUA_TOOLS") or ".toolcache/acceptance4lua"
M.repo_url = "http://lzxsvn:3000/eggy/acceptance4lua"
M.pins = {
  acceptance4lua = "8dd107144a7635596d75e4fccfce35121dc67570",
  dry4lua = "1dd42d73116921cd54a00c7b132a9b097e4a288a",
}

local function tree(name)
  if name == "acceptance4lua" then return M.tree end
  return ".toolcache/" .. name
end

local function marker(name)
  return tree(name) .. "/src/" .. name .. "/" .. (name == "acceptance4lua" and "init" or "cli") .. ".lua"
end

local function revision(name)
  local code, output = shell.capture("git -C " .. shell.q(tree(name)) .. " rev-parse HEAD")
  if code ~= 0 then return nil end
  local hash = output:match("(%x+)")
  return hash and #hash == 40 and hash or nil
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

function M.install(name)
  name = name or "acceptance4lua"
  if not M.pins[name] then return nil, "未知工具: " .. tostring(name) end
  local dest = tree(name)
  local url = name == "acceptance4lua" and M.repo_url or "http://lzxsvn:3000/eggy/" .. name
  print("[4lua] clone " .. url .. " → " .. dest)
  shell.ensure_dir(dest:match("^(.*)/[^/]+$") or ".")
  if not run("git clone " .. url_q(url) .. " " .. shell.q(dest)) then
    return nil, "git clone 失败: " .. url
  end
  if not run("git -C " .. shell.q(dest) .. " checkout --detach " .. M.pins[name]) then
    return nil, "检出固定提交失败: " .. name
  end
  return true
end

function M.ensure(name)
  name = name or "acceptance4lua"
  if not M.pins[name] then return nil, "未知工具: " .. tostring(name) end
  if not exists(marker(name)) and not revision(name) then
    local ok, err = M.install(name)
    if not ok then return nil, err end
  end
  if revision(name) ~= M.pins[name] or not exists(marker(name)) then
    return nil, name .. " 缓存缺失或提交不符（期望 " .. M.pins[name] .. "）"
  end
  local code, changes = shell.capture("git -C " .. shell.q(tree(name)) .. " status --porcelain --untracked-files=no")
  if code ~= 0 or changes:match("%S") then
    return nil, name .. " 缓存源码已修改或状态不可读"
  end
  if name == "acceptance4lua" then
    package.path = M.lua_path() .. ";" .. package.path
  else
    package.path = tree(name) .. "/src/?.lua;" .. tree(name) .. "/src/?/init.lua;" .. package.path
  end
  return true
end

return M
