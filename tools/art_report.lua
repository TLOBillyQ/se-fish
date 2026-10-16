-- 美术工作区里重导入校验报告的定位与读取（唯一真源）：
--   <宿主目录的父目录>/美术资产/<鱼名>/validation/validation.json
-- 美术资产根目录（`美术资产`）可用 EGGY_ART_ASSETS 覆盖；换鱼或换工作区时用。
-- 资产本体与校验报告都在仓库外（见 docs/agents/art-pipeline.md），仓库侧只按这个约定去读。
--
-- 报告缺席直接失败：报告不在说明流程没跑到重导入校验，
-- 那正是「不做重导入校验不得宣布资产可用」要拦住的状态。
--
-- 报告是 JSON，解析器由 acceptance4lua 提供、只在验收运行时的 package.path 上
-- （见 tools/acceptance/bootstrap.lua），所以延迟到读报告时再 require：
-- tests/native/slow 的接缝用例会在 busted 下装载验收步骤模块，那会儿没有 .toolcache。
local workspace = require('tools.eggy_workspace')

local M = {}

M.REPORT = 'validation/validation.json'

function M.root()
  local override = os.getenv('EGGY_ART_ASSETS')
  if override and override ~= '' then return override end
  local host = workspace.resolve()
  local parent = host:match('^(.*)[/\\][^/\\]+$')
  assert(parent, 'EGGY_WORKSPACE 不像一个目录路径: ' .. host)
  return parent .. '/美术资产'
end

function M.path(fish)
  return M.root() .. '/' .. fish .. '/' .. M.REPORT
end

local function decode(path, body)
  local ok, json = pcall(require, 'acceptance4lua.json')
  assert(ok, '模块 tools.art_report 解析 ' .. path
    .. ' 需要 acceptance4lua.json，请用 bash tools/acceptance/run_acceptance.sh 跑这条车道；错误：'
    .. tostring(json))
  return json.decode(body)
end

-- 同一份报告一个场景里读一次就够，缓存在 world 上（world 由验收 harness 提供）
function M.load(world, fish)
  world.art_reports = world.art_reports or {}
  if world.art_reports[fish] then return world.art_reports[fish] end
  local path = M.path(fish)
  local handle = io.open(path, 'rb')
  assert(handle, '读不到 ' .. fish .. ' 的重导入校验报告 ' .. path
    .. '（先把流程跑到步骤 04，或用 EGGY_ART_ASSETS 指到美术资产根目录）')
  local body = handle:read('a')
  handle:close()
  local report = decode(path, body)
  assert(type(report) == 'table' and type(report.files) == 'table',
    path .. ' 不是一份重导入校验报告')
  world.art_reports[fish] = report
  return report
end

-- 报告里某个交付件的条目（相对该鱼的目录，例如 Model/Carp.fbx）
function M.entry(world, fish, relative)
  local value = M.load(world, fish).files[relative]
  assert(value, '校验报告里没有 ' .. relative)
  return value
end

return M
