-- acceptance 接缝防回归（#89 迁移遗留断裂的补丁）：
-- tools/acceptance/platform_steps.lua 曾经 dofile('tests/gameplay/revive_callback_test.lua')
-- 并用 setmetatable 借用那个全局 LuaUnit 类；旧文件随迁移删除后 dofile 目标不存在，
-- 而 tools/acceptance/steps.lua 把 platform_steps 列入步骤清单，于是整条 acceptance 装载失败。
-- 这里钉两件事：
--   1. tools/ 与 tests/ 下 Lua 里的 dofile/loadfile/load 字符串字面量目标必须存在
--      （删除或改名被复用为夹具的测试文件时，这条会红，不再靠人肉发现）；
--   2. acceptance 步骤清单里的每个模块都能装载，且复活场景步骤真跑通（不止 require 成功）。
-- 车道：放 tests/native/slow，只被 full 发现。日常 fast 入口
-- （busted --run=fast）计数因此不受本文件影响；
-- 本测试要遍历 tools/ 与 tests/ 全部 Lua 并装载十个步骤模块（拉起真实管理器与引擎替身），
-- 比同级单元测试重，落在 slow 也符合语义。
-- 边界：只检查「左括号后紧跟字符串字面量」的调用；拼路径、变量路径不在静态扫描范围。

-- 步骤模块与夹具按仓库根相对路径 require；busted 从仓库根运行，这里补自己的路径。
if not package.path:find('./?.lua', 1, true) then
  package.path = table.concat({ './?.lua', './?/init.lua', package.path }, ';')
end

local LOADER = { dofile = true, loadfile = true, load = true }

local function lua_files(dir)
  local handle = assert(io.popen('dir /s /b /a-d ' .. dir .. '\\*.lua 2>nul'))
  local files = {}
  for line in handle:lines() do
    local name = line:gsub('[\r\n]+$', '')
    if name ~= '' then
      files[#files + 1] = name:gsub('\\', '/')
    end
  end
  handle:close()
  table.sort(files)
  return files
end

local function path_exists(path)
  local f = io.open(path, 'rb')
  if not f then return false end
  f:close()
  return true
end

-- 逐行扫描，命中形如 dofile('a/b.lua') / loadfile("x.lua", 't', env) 的字面量目标。
-- 先剥掉行注释（本文件开头的说明就写着那个坏掉的 dofile，不剥会自我误报）。
local function loader_targets(dir)
  local found = {}
  for _, file in ipairs(lua_files(dir)) do
    local src = assert(io.open(file, 'rb')):read('a')
    local lineno = 0
    for line in (src .. '\n'):gmatch('[^\n]*') do
      lineno = lineno + 1
      for kind, target in (line:gsub('%-%-.*', '')):gmatch('(%w+)%(%s*["\']([^"\']+)["\']') do
        if LOADER[kind] and target:match('%.lua$') then
          found[#found + 1] = { file = file, line = lineno, kind = kind, target = target }
        end
      end
    end
  end
  return found
end

-- 从 steps.lua 源码取清单，避免与在途批次各写一份 SOURCES 而漂移。
local function step_module_names()
  local src = assert(io.open('tools/acceptance/steps.lua', 'rb')):read('a')
  local names = {}
  for name in src:gmatch('"tools%.acceptance%.([%w_]+)"') do
    names[#names + 1] = name
  end
  for name in src:gmatch("'tools%.acceptance%.([%w_]+)'") do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

describe('acceptance 接缝防回归', function()
  it('tools 与 tests 的加载器字面量目标都存在的', function()
    local missing = {}
    local scanned = 0
    for _, dir in ipairs({ 'tools', 'tests' }) do
      for _, hit in ipairs(loader_targets(dir)) do
        scanned = scanned + 1
        if not path_exists(hit.target) then
          missing[#missing + 1] = hit.file .. ':' .. hit.line .. ' ' .. hit.kind .. ' -> ' .. hit.target
        end
      end
    end
    assert.is_true(scanned > 0, '扫描到 0 个加载器字面量，扫描本身失效')
    assert.is_same({}, missing)
  end)

  it('acceptance 步骤清单里的每个模块都能装载', function()
    local names = step_module_names()
    assert.is_true(#names >= 8, '步骤清单异常短：' .. #names)
    for _, name in ipairs(names) do
      local ok, err = pcall(require, 'tools.acceptance.' .. name)
      assert.is_true(ok, '步骤模块装载失败 tools.acceptance.' .. name .. ' ：' .. tostring(err))
    end
    local steps = require('tools.acceptance.steps')
    assert.is_true(#steps.patterns > 0)
  end)

  -- 复活场景逐步驱动 platform_steps 的 handler：夹具与验收调用形状对得上才算接缝恢复。
  it('平台复活验收场景步骤可执行', function()
    local savedRE = package.loaded['common.REUtil']
    local GameCfg = require('common.GameCfg')
    local patterns = require('tools.acceptance.platform_steps').patterns

    local function dispatch(text)
      for _, entry in ipairs(patterns) do
        local captures = { text:match(entry[1]) }
        if captures[1] ~= nil then return entry[2], captures end
      end
      error('步骤未匹配：' .. text)
    end

    local function run(world, text)
      local fn, captures = dispatch(text)
      fn(world, table.unpack(captures))
    end

    local ok, err = pcall(function()
      -- 广告成功后迟到超时：本轮只允许一次满血复活
      local a = {}
      run(a, '复活回调测试档已死亡')
      run(a, '广告成功后免费倒计时与迟到超时再次触发')
      run(a, '本轮只有一次满血复活结果')
      -- 平台取消后免费倒计时兜底：只产生一次 10% 血量虚弱复活
      local b = {}
      run(b, '复活回调测试档已死亡')
      run(b, '平台回调为 cancel 后免费倒计时结束')
      run(b, '本轮只产生一次10%血量虚弱复活')
      -- 肾上腺素自救：盲盒世界与复活夹具在同一场景里配合
      local c = {}
      run(c, '平台接缝测试档已就绪')
      run(c, '玩家濒死后购买一份肾上腺素并自救')
      run(c, '玩家恢复10%血量且只消耗一份肾上腺素')
      assert.is_true(GameCfg.Survival.DeadSec > 0)
    end)
    package.loaded['common.REUtil'] = savedRE
    assert.is_true(ok, err)
  end)
end)
