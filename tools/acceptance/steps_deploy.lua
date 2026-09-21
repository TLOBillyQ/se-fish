-- tools/acceptance/steps_deploy.lua —— deploy-mirror 车道的步骤处理器（不启动对局）。
--
-- 临时工作区固定在 tmp/ 下（gitignored），由背景步骤「一个空的临时工作区」负责建与清。
-- 这一车道只验磁盘镜像语义：部署步骤把 USERPROFILE 指到空的临时 home，编辑器收尾因此跳过
-- （工作区里的 eggy.json 是伪造的绑定，真去 code validate 必然失败；见下面部署步骤的注释）。
-- 条目形状与 steps.lua 的分发表一致：{ lua-pattern, handler(w, captures...) }。
--
-- 命令一律走 cmd：Windows 版 Lua 的 os.execute 就是 cmd.exe，rm/mkdir/find 那套用不了；
-- 路径与引用交给 tools.win_shell（工具链里唯一起 cmd 的地方）。
local shell = require("tools.win_shell")
local plan = require("tools.deploy_plan")

local M = {}

local WS = "tmp/deploy-mirror-workspace"
local FAKE_HOME = "tmp/deploy-mirror-home"
local DEPLOY_OUT = "tmp/deploy-mirror.out"

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function run(cmd)
  local _, _, code = os.execute(cmd)
  return code
end

-- 空格分隔的参数列表（路径列表、预置列表、白名单；空白的多少不参与语义）。
local function split_words(list)
  local words = {}
  for word in list:gmatch("%S+") do words[#words + 1] = word end
  return words
end

-- 跑本 spec 的那个 Lua 解释器（Lua 把解释器路径记在 arg[-1]），不走 PATH 猜。
local function lua_bin()
  local exe = arg and arg[-1]
  if type(exe) == "string" and exe ~= "" and not exe:match("^%-") then return exe end
  return "lua"
end

local function workspace(w)
  if not w.workspace then return nil, "尚未创建临时工作区（背景步骤没跑）" end
  return w.workspace
end

-- 工作区前置条件收在一处，步骤本体只处理该工作区。
local function needs_workspace(fn)
  return function(w, ...)
    local ws, err = workspace(w)
    if not ws then return nil, err end
    return fn(ws, ...)
  end
end

M.patterns = {
  { "^一个空的临时工作区$", function(w)
      w.workspace = WS
      shell.remove({ dir = true, dst = WS })
      shell.ensure_dir(WS)
      return true end },

  { "^临时工作区预置文件(.+)$", needs_workspace(function(ws, list)
      for _, path in ipairs(split_words(list)) do
        local full = ws .. "/" .. path
        local parent = full:match("^(.*)/[^/]+$")
        if parent then shell.ensure_dir(parent) end
        local f = io.open(full, "wb")
        if not f then return nil, "无法写入 " .. full end
        f:write("-- preset\n")
        f:close()
      end
      return true end) },

  -- 走公开入口 tools/cli.lua（与手工部署同一条路），工作区用 EGGY_WORKSPACE 指过去。
  -- USERPROFILE 指到空的临时 home，让编辑器收尾按「找不到 editor-cli.exe」跳过：工作区里预置的
  -- eggy.json 是伪造的绑定，真去 code validate 必然失败，而这一车道验的是磁盘镜像语义，
  -- 不是编辑器收尾（那条要真编辑器，留真机跑）。顺带也去掉「本机装没装 editor-cli」的差别。
  -- 命令行开头那条 `cd .` 与中段的重定向不是装饰：重定向要写在所修饰的命令前面，
  -- 而命令行以引号开头时 cmd 会剥掉首尾引号、把命令行解析坏（见 tools/win_shell.lua）。
  { "^执行部署到临时工作区$", needs_workspace(function(ws)
      local cmd = table.concat({
        "cd .",
        'set "EGGY_WORKSPACE=' .. ws .. '"',
        'set "USERPROFILE=' .. FAKE_HOME .. '"',
        "> " .. shell.q(DEPLOY_OUT) .. " 2>&1 " .. shell.q(lua_bin()) .. " tools/cli.lua deploy",
      }, " & ")
      local code = run(cmd)
      if code == 0 then return true end
      return nil, "deploy 失败 exit=" .. tostring(code) .. "\n" .. (read_file(DEPLOY_OUT) or "") end) },

  { "^临时工作区存在文件(.+)$", needs_workspace(function(ws, list)
      for _, path in ipairs(split_words(list)) do
        if not file_exists(ws .. "/" .. path) then
          return nil, "临时工作区缺文件 " .. path
        end
      end
      return true end) },

  { "^临时工作区不存在目录(%S+)$", needs_workspace(function(ws, path)
      if not shell.is_dir(ws .. "/" .. path) then return true end
      return nil, "临时工作区仍存在目录 " .. path end) },

  -- 白名单的真源是部署计划模块，不是部署脚本：这一步只问规则，不该把镜像与编辑器收尾
  -- 那套 IO 也 require 进来。
  { "^部署白名单为(.+)$", function(w, list)
      local want = split_words(list)
      if table.concat(plan.REALMS, " ") == table.concat(want, " ") then return true end
      return nil, "部署白名单实际为 " .. table.concat(plan.REALMS, " ") end },
}

return M
