-- sync 子命令：把编辑器宿主目录的产物回同步进仓库根——eggy.json、EggyAPI.lua、
-- EggyEditorAPI.lua 三份单文件 + data/ 整目录镜像（宿主侧删掉的文件在仓库里
-- 也跟着消失）。在仓库根执行 `lua tools/cli.lua sync`；正方向部署见 tools/deploy.lua。
--
-- 与 deploy 的字节镜像不同，回灌落盘前做 CRLF→LF 归一（与 .gitattributes 的 eol=lf
-- 配合，行尾不抖动），所以不用 robocopy，自己读写。全部源读成功才落盘
-- （all-or-nothing，不做半截同步）；内容没变的文件不重写（幂等，git status 没噪音）。
-- 回同步清单与镜像规则在 tools/sync_plan，宿主目录定位在 tools/eggy_workspace，
-- 目录枚举在 tools/win_shell。

package.path = "./?.lua;./?/init.lua;" .. package.path

local workspace = require("tools.eggy_workspace")
local plan = require("tools.sync_plan")
local shell = require("tools.win_shell")

local M = {}

-- 业务失败统一 error 出去，由 main 收成 stderr + 退出码 1。
local function fail(msg)
  error("sync: " .. msg, 0)
end

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua sync",
    "",
    "把宿主目录的 " .. table.concat(plan.ROOT_FILES, " / ") .. " 与 " .. plan.DATA_DIR .. "/ 整目录回同步进仓库根。",
    plan.DATA_DIR .. "/ 按镜像纪律抹平（宿主侧删掉的文件在仓库里跟着消失）；落盘前 CRLF→LF 归一。",
    "全部源读成功才落盘，内容没变的文件不重写；仓库根与宿主目录的其余内容互不触碰。",
    "宿主目录默认 " .. workspace.DEFAULT .. "，环境变量 EGGY_WORKSPACE 可覆盖。",
    "",
  }, "\n") .. "\n"
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

local function write_file(path, body)
  local dir = path:match("^(.-)/[^/]*$")
  if dir then shell.ensure_dir(dir) end
  local f = assert(io.open(path, "wb"), path .. " 写不进去")
  f:write(body)
  f:close()
end

-- 全部源读进内存并归一行尾，返回写盘顺序（rel 清单，/ 分隔）与 rel → 内容的表。
-- 任何一个源读不到都报全清单再失败——此时还没写过一个字节。
local function read_sources(WS)
  local missing = {}
  local write_order, contents = {}, {}
  local function take(rel, path)
    local body = read_file(path)
    if body == nil then
      missing[#missing + 1] = rel
    else
      write_order[#write_order + 1] = rel
      contents[rel] = plan.normalize_eol(body)
    end
  end
  for _, rel in ipairs(plan.ROOT_FILES) do
    take(rel, WS .. "/" .. rel)
  end
  local data_files = shell.list_files(WS .. "/" .. plan.DATA_DIR)
  if data_files == nil then
    missing[#missing + 1] = plan.DATA_DIR .. "/"
    data_files = {}
  end
  for _, f in ipairs(data_files) do
    take(plan.DATA_DIR .. "/" .. f, WS .. "/" .. plan.DATA_DIR .. "/" .. f)
  end
  if #missing > 0 then
    fail("宿主目录缺回同步源，整体未落盘（缺 " .. table.concat(missing, ", ") .. "）")
  end
  return write_order, contents, data_files
end

local function run_sync()
  local WS = workspace.resolve()
  if not shell.is_dir(WS) then
    fail("编辑器宿主目录不存在；可用环境变量 EGGY_WORKSPACE 覆盖（缺 " .. WS .. "）")
  end

  local write_order, contents, data_files = read_sources(WS)
  -- 仓库侧 data/ 是跟踪目录，枚举不到 = 当前目录多半不是仓库根，不能当空目录处理，
  -- 否则既漏删 stale 又会把产物写进错误的地方。
  local repo_files = shell.list_files(plan.DATA_DIR)
  if repo_files == nil then
    fail("仓库根缺 " .. plan.DATA_DIR .. "/；sync 须在仓库根执行")
  end
  local deletes = plan.stale_files(data_files, repo_files)

  -- 读全了才落盘：写（跳过内容没变的）→ 删 stale。
  local written, unchanged = 0, 0
  for _, rel in ipairs(write_order) do
    if read_file(rel) == contents[rel] then
      unchanged = unchanged + 1
    else
      write_file(rel, contents[rel])
      print("write " .. rel)
      written = written + 1
    end
  end
  for _, rel in ipairs(deletes) do
    local dst = plan.DATA_DIR .. "/" .. rel
    shell.remove({ dir = false, dst = dst })
    -- shell.remove 不看 del 的退出码；stale 没删掉（被占用等）不能报 ok，复核一次。
    if shell.exists(dst) then
      fail("stale 文件删不掉: " .. dst)
    end
    print("delete " .. dst)
  end

  print(string.format("sync ok ← %s: %d 写入, %d 删除, %d 未变", WS, written, #deletes, unchanged))
end

-- 退出码：0 成功 / 1 业务失败 / 2 用法错误。
function M.main(args)
  args = args or {}
  for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
      io.write(M.usage())
      return 0
    end
    io.stderr:write("sync: 未知参数: " .. a .. "\n")
    return 2
  end
  local ok, err = pcall(run_sync)
  if not ok then
    io.stderr:write(tostring(err) .. "\n")
    return 1
  end
  return 0
end

if ... == "tools.sync" then
  return M
end

os.exit(M.main(arg))
