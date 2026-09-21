-- tools/acceptance/steps.lua —— Gherkin 步骤处理器聚合与分发。
--
-- acceptance4lua 按步骤文本精确查 handler（<占位符> 留在 key 里），所以下面用
-- Lua pattern 在「代入例子值之后的文本」上再解析一次：只差一个数值的同类句子
-- 共用一个实现。handler 收到 (world, example, step, resolved_text)，返回 true，
-- 或 nil + 消息。消息里避开 "not found"：runner 把它当成基础设施错误。
--
-- 本仓库目前只有 deploy-mirror 一条车道（只查仓库与临时工作区，不启动对局），
-- 所以 SOURCES 只有一个源。加车道时在这里挂上对应的 steps_*.lua，各文件仍只
-- 负责自己那套步骤（规则真源 CONTEXT.md「部署树」）。
local SOURCES = {
  "tools.acceptance.steps_deploy",
}

local M = {}

-- 每一项：resolved 步骤文本上的 Lua pattern → handler(w, captures...)。
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

-- 原始步骤文本（带占位符）的 handler：真正解析推迟到运行期代入例子值之后。
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
