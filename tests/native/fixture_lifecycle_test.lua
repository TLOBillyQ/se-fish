-- 迁移自 tests/tooling/fixture_verify.lua（#93，手工脚本 → 原生 Busted）。
-- 旧文件名字不含 `_test`，在任何车道里都发现不到，是 tests/support/combat_world.lua
-- 唯一的自动检查（它只被探针与 acceptance 引用）。转成原生案例后由 fast 车道接管。
-- 失败方式（先列后写）：夹具 setUp 中途失败后 tearDown 不还原全局（把 _G.game / Vector3 /
-- RaycastParams / Color / Quaternion / math.random 留给下一个案例），或还原时把别的替换也一起抹掉。
local FishLift = require("tests.support.fish_lift")
local FishLoot = require("tests.support.fish_loot")
local FishCombat = require("tests.support.fish_combat")
local CombatWorld = require("tests.support.combat_world")

-- 逐案例取现场：旧脚本在进程启动时取一次，迁移后同一进程要跑几百个案例，
-- 装载期快照会与案例实际起点脱节（别的描述块可能已经装过全局）。
local function snapshot()
  return {
    game = rawget(_G, "game"),
    Vector3 = rawget(_G, "Vector3"),
    RaycastParams = rawget(_G, "RaycastParams"),
    Color = rawget(_G, "Color"),
    Quaternion = rawget(_G, "Quaternion"),
    random = math.random,
  }
end

local function assert_fixture_globals_restored(original)
  assert.are.equal(rawget(_G, "game"), original.game, "game 未还原")
  assert.are.equal(rawget(_G, "Vector3"), original.Vector3, "Vector3 未还原")
  assert.are.equal(rawget(_G, "RaycastParams"), original.RaycastParams, "RaycastParams 未还原")
end

describe("共享夹具生命周期", function()
  it("夹具模块暴露方法而不装全局", function()
    assert.are.equal(type(FishLift.setUp), "function")
    assert.are.equal(type(FishLoot.setUp), "function")
    assert.are.equal(type(FishCombat.setUp), "function")
    assert.are.equal(type(CombatWorld.new), "function")
  end)

  it("FishLift 拆卸把 stop 失败抛出并还原状态", function()
    local original = snapshot()
    local env = setmetatable({}, { __index = FishLift })
    FishLift.setUp(env)
    env.mgr.Stop = function() error("stop-failed", 0) end
    local ok, err = pcall(function() FishLift.tearDown(env) end)
    assert.is_false(ok)
    assert.is_not_nil(tostring(err):find("stop%-failed"))
    assert_fixture_globals_restored(original)
    assert.is_nil(package.loaded["server.Mgr.MgrFishCarrier"])
    assert.is_nil(package.loaded["server.Mgr.MgrFishUnit"])
  end)

  it("FishLoot 在 MgrLoot 装载处注入的 setup 失败可复现且不留残留", function()
    local original = snapshot()
    local env = setmetatable({}, { __index = FishLoot })
    local originalLoadFile = _G.loadfile
    local attempted = false
    _G.loadfile = function(path)
      if not attempted and path == "server/Mgr/MgrLoot.lua" then
        attempted = true
        error("partial-setup-failed", 0)
      end
      return originalLoadFile(path)
    end
    local okSetup, errSetup = pcall(function() FishLoot.setUp(env) end)
    _G.loadfile = originalLoadFile

    assert.is_false(okSetup)
    assert.is_not_nil(tostring(errSetup):find("partial%-setup%-failed"))
    FishLoot.tearDown(env)
    assert_fixture_globals_restored(original)
    assert.are.equal(rawget(_G, "Color"), original.Color, "Color 未还原")
    assert.is_nil(package.loaded["server.Mgr.MgrFishCarrier"])
    assert.is_nil(package.loaded["server.Mgr.MgrFishUnit"])
    assert.is_nil(package.loaded["server.Mgr.MgrLoot"])
  end)

  it("FishCombat 拆卸还原被替换的 random 与 Quaternion", function()
    local original = snapshot()
    local env = setmetatable({}, { __index = FishCombat })
    FishCombat.setUp(env)
    math.random = function() return 0 end
    _G.Quaternion = { Marker = true }
    FishCombat.tearDown(env)

    assert.are.equal(math.random, original.random, "random 未还原")
    assert.are.equal(rawget(_G, "Quaternion"), original.Quaternion, "Quaternion 未还原")
    assert_fixture_globals_restored(original)
  end)

  it("CombatWorld close 还原钉住的 random 与夹具全局", function()
    local original = snapshot()
    local env = CombatWorld.new()
    CombatWorld.pinRandom(env)
    CombatWorld.close(env)

    assert.are.equal(math.random, original.random, "random 未还原")
    assert_fixture_globals_restored(original)
  end)
end)
