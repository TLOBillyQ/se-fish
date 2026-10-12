package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./tests/lib/?.lua",
  package.path,
}, ";")

local function check(name, condition, detail)
  if not condition then
    error(name .. ' 失败: ' .. tostring(detail))
  end
  io.stdout:write('[OK] ' .. name .. '\n')
end

local original = {
  game = rawget(_G, 'game'),
  Vector3 = rawget(_G, 'Vector3'),
  RaycastParams = rawget(_G, 'RaycastParams'),
  Color = rawget(_G, 'Color'),
  Quaternion = rawget(_G, 'Quaternion'),
  random = math.random,
}

local FishLift = require('tests.support.fish_lift')
local FishLoot = require('tests.support.fish_loot')
local FishCombat = require('tests.support.fish_combat')
local CombatWorld = require('tests.support.combat_world')

check('fixture modules expose methods without globals',
  type(FishLift.setUp) == 'function' and type(FishLoot.setUp) == 'function'
  and type(FishCombat.setUp) == 'function' and type(CombatWorld.new) == 'function')

do
  local env = setmetatable({}, { __index = FishLift })
  FishLift.setUp(env)
  env.mgr.Stop = function() error('stop-failed', 0) end
  local ok, err = pcall(function() FishLift.tearDown(env) end)
  check('FishLift teardown propagates stop failure and restores state',
    ok == false and tostring(err):find('stop%-failed') ~= nil
    and rawget(_G, 'game') == original.game and rawget(_G, 'Vector3') == original.Vector3
    and rawget(_G, 'RaycastParams') == original.RaycastParams
    and package.loaded['server.Mgr.MgrFishCarrier'] == nil
    and package.loaded['server.Mgr.MgrFishUnit'] == nil)
end

do
  local env = setmetatable({}, { __index = FishLoot })
  local originalLoadFile = _G.loadfile
  local attempted = false
  _G.loadfile = function(path)
    if not attempted and path == 'server/Mgr/MgrLoot.lua' then
      attempted = true
      error('partial-setup-failed', 0)
    end
    return originalLoadFile(path)
  end
  local okSetup, errSetup = pcall(function() FishLoot.setUp(env) end)
  _G.loadfile = originalLoadFile
  check('FishLoot injected setup failure happens at MgrLoot load', okSetup == false and tostring(errSetup):find('partial%-setup%-failed') ~= nil)
  FishLoot.tearDown(env)
  check('FishLoot partial setup leaves no globals or cached modules',
    rawget(_G, 'game') == original.game and rawget(_G, 'Vector3') == original.Vector3
    and rawget(_G, 'RaycastParams') == original.RaycastParams and rawget(_G, 'Color') == original.Color
    and package.loaded['server.Mgr.MgrFishCarrier'] == nil
    and package.loaded['server.Mgr.MgrFishUnit'] == nil
    and package.loaded['server.Mgr.MgrLoot'] == nil)
end

do
  local env = setmetatable({}, { __index = FishCombat })
  FishCombat.setUp(env)
  math.random = function() return 0 end
  _G.Quaternion = { Marker = true }
  FishCombat.tearDown(env)
  check('FishCombat teardown restores random and Quaternion replacements',
    math.random == original.random and rawget(_G, 'Quaternion') == original.Quaternion
    and rawget(_G, 'game') == original.game and rawget(_G, 'Vector3') == original.Vector3)
end

do
  local env = CombatWorld.new()
  CombatWorld.pinRandom(env)
  CombatWorld.close(env)
  check('CombatWorld close restores pinned random and fixture globals',
    math.random == original.random and rawget(_G, 'game') == original.game
    and rawget(_G, 'Vector3') == original.Vector3 and rawget(_G, 'RaycastParams') == original.RaycastParams)
end
