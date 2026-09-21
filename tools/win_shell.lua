-- Windows 原生执行层：工具链里唯一直接起 cmd / robocopy 的地方。
-- 先例：se-defense tools/wsl_seam.lua 的 WSL 接缝层——本工程在 Windows 原生跑，
-- 目的地一律在本机，「跨接缝」不存在（判定恒真），robocopy 之外也没有本地 cp 回落分支。
--
-- 路径统一按逻辑形式（/ 分隔）收进来，出到命令行前换成 Windows 形式（\ 分隔）；
-- 本模块假定进程 cwd 是仓库根（与 tools/cli.lua 的约定一致），临时输出落 tmp/。
local M = {}

local SEP = "\\"
local OUT_DIR = "tmp"
local OUT_FILE = OUT_DIR .. SEP .. "cmd.out"
local LOG_FILE = OUT_DIR .. SEP .. "robocopy.log"

-- 逻辑路径 → Windows 路径。
function M.win(path)
  return (path:gsub("/", SEP))
end

-- 命令行参数引用：路径里只有仓库内固定字符，但统一加引号防呆。
function M.q(path)
  return '"' .. M.win(path) .. '"'
end

-- 跑一条 cmd 命令行，返回退出码。
local function run(cmd)
  local _, _, code = os.execute(cmd)
  return code
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local body = f:read("a") or ""
  f:close()
  return body
end

-- 跑一条命令，拿回退出码与 stdout+stderr。io.popen 拿不到退出码，所以输出先落文件。
-- 重定向必须写在命令前面：命令行以引号开头（引号包住的 exe 后面还有引号包住的参数）时
-- cmd 会按 cmd /? 的解析规则 2 剥掉首尾引号，把 exe 路径和后续参数一起解析坏
-- （实测报「文件名、目录名或卷标语法不正确」）。
function M.capture(cmd)
  run("if not exist " .. OUT_DIR .. " md " .. OUT_DIR .. " >nul 2>&1")
  local code = run("> " .. OUT_FILE .. " 2>&1 " .. cmd)
  return code, read_file(OUT_FILE)
end

-- 路径是否存在（目录或文件）。
function M.exists(path)
  return run("if exist " .. M.q(path) .. " (exit /b 0) else (exit /b 1)") == 0
end

-- 是否目录：pushd 只对真目录成功。
function M.is_dir(path)
  return run("pushd " .. M.q(path) .. " 2>nul && (popd & exit /b 0) || exit /b 1") == 0
end

-- 跑一条输出行清单的命令，返回去空行的结果。
local function lines(cmd)
  local out = {}
  local handle = io.popen(cmd)
  for line in handle:lines() do
    line = line:gsub("[\r\n]+$", "")
    if line ~= "" then out[#out + 1] = line end
  end
  handle:close()
  return out
end

-- 目录一级条目 { {name=, dir=}, ... }，按名排序（部署计划要稳定）。
-- 分两次 dir 拿目录与文件，省掉逐条目问一次文件系统。
function M.list_entries(dir)
  local dirs = {}
  for _, name in ipairs(lines("dir /b /ad " .. M.q(dir) .. " 2>nul")) do
    dirs[name] = true
  end
  local out = {}
  for _, name in ipairs(lines("dir /b /a-d " .. M.q(dir) .. " 2>nul")) do
    out[#out + 1] = { name = name, dir = false }
  end
  for name in pairs(dirs) do
    out[#out + 1] = { name = name, dir = true }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- 子树文件数，只用于打印一行进度。
function M.file_count(path, dir)
  if not dir then return 1 end
  local n = 0
  for _ in ipairs(lines("dir /s /b /a-d " .. M.q(path) .. " 2>nul")) do
    n = n + 1
  end
  return n
end

-- 目录的绝对路径（pushd + cd）；目录不存在返回 nil。只服务 list_files。
local function abs_dir(dir)
  local out = lines("pushd " .. M.q(dir) .. " 2>nul && (cd & popd)")
  return out[1]
end

-- 目录下全部文件（递归），返回相对 dir 的 / 分隔路径，按名排序；目录不存在返回 nil。
-- dir /s /b 无论入参是不是相对路径都打印绝对路径（实测），所以先拿绝对前缀再剥。
function M.list_files(dir)
  local root = abs_dir(dir)
  if not root then return nil end
  local prefix = (root:gsub("\\", "/"))
  local out = {}
  for _, p in ipairs(lines("dir /s /b /a-d " .. M.q(dir) .. " 2>nul")) do
    p = (p:gsub("\\", "/"))
    out[#out + 1] = p:sub(#prefix + 2)
  end
  table.sort(out)
  return out
end

-- 递归建目录；已存在不算失败。
function M.ensure_dir(path)
  run("if not exist " .. M.q(path) .. " md " .. M.q(path) .. " >nul 2>&1")
end

-- robocopy 退出码 0–7 都是成功（0 无变化、1 有拷贝、2/3 目的地多出东西、…），>= 8 才是
-- 失败。输出平时静音（/NFL 也挡不住 EXTRA 文件清单这类噪音），只在失败时带回原文。
local function robocopy(cmd)
  local code = run(cmd .. " > " .. LOG_FILE .. " 2>&1")
  if code ~= nil and code < 8 then return true end
  return false, code, read_file(LOG_FILE)
end

-- 镜像一个目标：目录走 robocopy /MIR，单文件按文件名过滤（非递归，目的地目录由
-- robocopy 自己建）。失败返回 nil, 退出码, robocopy 原文。
function M.mirror(target)
  local args = "/NFL /NDL /NJH /NJS /NP /R:2 /W:1"
  if target.dir then
    return robocopy("robocopy " .. M.q(target.src) .. " " .. M.q(target.dst) .. " /MIR " .. args)
  end
  local src_dir, name = target.src:match("^(.*)/([^/]+)$")
  local dst_dir = target.dst:match("^(.*)/[^/]+$")
  return robocopy("robocopy " .. M.q(src_dir) .. " " .. M.q(dst_dir) .. " " .. M.q(name) .. " " .. args)
end

-- 删掉一个目标（目录或单文件）；目标本来就不在不算失败。
function M.remove(target)
  if target.dir then
    run("if exist " .. M.q(target.dst) .. " rmdir /s /q " .. M.q(target.dst))
  else
    run("if exist " .. M.q(target.dst) .. " del /f /q " .. M.q(target.dst))
  end
end

return M
