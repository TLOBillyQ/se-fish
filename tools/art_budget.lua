-- 网格封闭性预算（#112）的唯一仓库侧读取入口：
--   默认预算：<美术资产根目录>/mesh-budget.json
--   单鱼豁免：<美术资产根目录>/<鱼名>/mesh-budget.json
-- 与美术工作区 scripts/04-validate.py 的 mesh_limits() 保持同一套规则：
--   - 默认预算必须带齐三项数值；
--   - 豁免只能放宽数值（比默认更严视为配置错误），必须写非空 reason，未知键直接失败。
--
-- 报告里也抄了一份生效预算，但验收不拿报告自证：本模块重新读盘再比对，
-- 这样改了预算却没重跑 04-validate 时会暴露成「报告已过期」。
local report = require('tools.art_report')

local M = {}

local DEFAULT_FILE = 'mesh-budget.json'
local KEYS = { 'max_components', 'max_open_edge_ratio', 'max_boundary_loop_edges' }

local function is_number(value)
  return type(value) == 'number'
end

local function read(root, relative)
  local path = root .. '/' .. relative
  local handle = io.open(path, 'rb')
  if not handle then return 'missing', nil, path end
  local body = handle:read('a')
  handle:close()
  local ok, value = pcall(report.decode_json, path, body)
  if not ok then return 'invalid', value, path end
  return 'ok', value, path
end

local function has_key(source, key)
  for _, name in ipairs(KEYS) do
    if name == key then return true end
  end
  return false
end

-- 返回 { limits = {...}, override = { reason = ..., limits = {...} } | nil, problems = {...} }
function M.effective(fish)
  local root = report.root()
  local problems = {}
  local status, body, path = read(root, DEFAULT_FILE)
  local limits = {}
  if status == 'ok' and type(body) == 'table' and type(body.limits) == 'table' then
    for _, key in ipairs(KEYS) do limits[key] = body.limits[key] end
  elseif status == 'invalid' then
    problems[#problems + 1] = path .. ' 不是合法 JSON：' .. tostring(body)
  else
    problems[#problems + 1] = '读不到默认网格预算 ' .. path
  end
  for _, key in ipairs(KEYS) do
    if not is_number(limits[key]) then
      problems[#problems + 1] = path .. ' 缺少数值项 ' .. key
    end
  end

  local override = nil
  local override_status, override_body, override_path = read(root, fish .. '/' .. DEFAULT_FILE)
  if override_status == 'invalid' then
    problems[#problems + 1] = override_path .. ' 不是合法 JSON：' .. tostring(override_body)
  elseif override_status == 'ok' then
    if type(override_body) ~= 'table' then
      problems[#problems + 1] = override_path .. ' 不是 JSON 对象'
    else
      local reason = override_body.reason
      if type(reason) ~= 'string' or reason:match('^%s*$') then
        problems[#problems + 1] = override_path .. ' 必须用 reason 写明放宽理由'
      end
      override = { reason = reason, limits = {} }
      for key, value in pairs(override_body) do
        if key ~= 'reason' then
          if not has_key(KEYS, key) then
            problems[#problems + 1] = override_path .. ' 含未知项 ' .. tostring(key)
          elseif not is_number(value) then
            problems[#problems + 1] = override_path .. ' 的 ' .. key .. ' 不是数值'
          elseif is_number(limits[key]) and value < limits[key] then
            problems[#problems + 1] = override_path .. ' 把 ' .. key .. ' 收紧到 '
              .. tostring(value) .. '（默认 ' .. tostring(limits[key]) .. '）；豁免只能放宽'
          else
            limits[key] = value
            override.limits[key] = value
          end
        end
      end
    end
  end
  return { limits = limits, override = override, problems = problems }
end

function M.limits_only(value)
  local limits = {}
  for _, key in ipairs(KEYS) do limits[key] = value[key] end
  return limits
end

return M
