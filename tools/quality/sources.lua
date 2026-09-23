local M = {}
local roots = { "client/", "common/", "server/", "tools/", "tests/" }
function M.owned(path)
  if not path:match("%.lua$") or path:find("/packages/", 1, true) then return false end
  for _, root in ipairs(roots) do
    if path:sub(1, #root) == root then return true end
  end
  return false
end
return M
