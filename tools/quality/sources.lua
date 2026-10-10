-- 三端业务源码范围，与 tools/quality/project.json 的 sources 保持一致。
local M = {}
local roots = { "client/", "common/", "server/" }
function M.owned(path)
  if not path:match("%.lua$") or path:find("/packages/", 1, true) then return false end
  if path:sub(1, #"server/_trigger/") == "server/_trigger/" then return false end
  for _, root in ipairs(roots) do
    if path:sub(1, #root) == root then return true end
  end
  return false
end
return M
