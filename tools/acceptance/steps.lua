-- Gherkin 步骤处理器聚合与分发。新增 feature 时在 SOURCES 中登记步骤模块。
-- acceptance4lua 按原始步骤文本查 handler；具体值在运行期才解析。
local SOURCES = { 'tools.acceptance.fish_damage_steps', 'tools.acceptance.ability_proto_steps',
  'tools.acceptance.pond_loop_steps' }
local M = {}

local PATTERNS = {}
for _, name in ipairs(SOURCES) do
  for _, entry in ipairs(require(name).patterns) do PATTERNS[#PATTERNS + 1] = entry end
end

local function dispatch(text)
  for _, entry in ipairs(PATTERNS) do
    local captures = { text:match(entry[1]) }
    if captures[1] ~= nil then return entry[2], captures end
  end
  return nil
end

local function handler_for(key)
  if not dispatch((key:gsub("<[^<>]+>", "0"))) then return nil end
  return function(w, _, _, resolved_text)
    local fn, captures = dispatch(resolved_text)
    if not fn then return nil, "步骤无法匹配: " .. tostring(resolved_text) end
    return fn(w, table.unpack(captures))
  end
end

function M.handlers()
  return setmetatable({}, { __index = function(_, key)
    if type(key) ~= "string" then return nil end
    return handler_for(key)
  end })
end

M.patterns = PATTERNS
return M
