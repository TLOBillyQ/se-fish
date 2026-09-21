-- 回同步计划：编辑器宿主目录 → 仓库根要回灌哪些产物、行尾怎么归一、data/ 的 stale
-- 集合。纯模块：不碰文件系统、不起子进程，目录清单由调用方注入
-- （tools/sync.lua 交给 tools/win_shell 枚举）。回同步规则在这里回答一次，
-- sync 只搬字节。
local M = {}

-- 宿主目录根要回灌的单文件：工程绑定 + 运行时 / 编辑时两份 API 存根
-- （本工程比 se-defense 多一份 EggyEditorAPI.lua）；顺序即回灌顺序。
M.ROOT_FILES = { "eggy.json", "EggyAPI.lua", "EggyEditorAPI.lua" }

-- 编辑器插件导出的数据目录，整目录镜像：宿主侧删掉的文件在仓库里也跟着消失。
M.DATA_DIR = "data"

-- CRLF / 裸 CR → LF：与 .gitattributes 的 eol=lf 配合，回灌后行尾不抖动。
-- 含 NUL 的字节串按二进制对待，原样返回（编辑器哪天导出非文本产物也不会被改写）。
function M.normalize_eol(text)
  if text:find("\0", 1, true) then return text end
  return (text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

-- data/ 的 stale 集合：host_files / repo_files 是 data/ 下 / 分隔相对路径列表，
-- 返回仓库有而宿主没有的 rel，按名排序。写侧就是宿主侧全量（内容没变就跳过，
-- 幂等判断要读文件内容，在调用方做），不需要在这里单列。
function M.stale_files(host_files, repo_files)
  local host = {}
  for _, f in ipairs(host_files) do host[f] = true end
  local stale = {}
  for _, f in ipairs(repo_files) do
    if not host[f] then stale[#stale + 1] = f end
  end
  table.sort(stale)
  return stale
end

return M
