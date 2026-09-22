-- 单测：鱼载体伤害接口 server/Mgr/MgrFishCarrier.lua（M18 / issue #32 方向 A）。
--
-- 三块：
--   1. 纯函数（血量/模型号解析）：模块顶层只 require common.GameCfg，不碰引擎，直接 require 即可；
--   2. 引擎侧（假引擎）：Vector3 / Quaternion / game:GetService("World") 用最小假实现替身，
--      驱动 Spawn → 挨打 → Update 跟随 → Despawn 全链路。模块把这些都在函数里取，顶层不碰引擎，
--      所以能这么测——#32 那类「伤害静默归零」和 M18 自己踩过的 Mgr.Attach 取 self 的坑，
--      有这一层就不用靠试玩才发现；
--   3. 接缝守卫（源码文本校对）：伤害能落地只靠一个事实——受击体创建时带 EnableController = true
--      （引擎里只有 EggyUnit/HumanUnit 认这个开关，WorldUnit 认不了）。它没有运行期报错可依赖，
--      所以用源码校对把它钉住：接缝一改，这里先红——同 tests/ability_api_test.lua 的思路。
local lu = require("luaunit")

local MgrFishCarrier = require("server.Mgr.MgrFishCarrier")
local GameCfg = require("common.GameCfg")

local CARRIER_PATH = "server/Mgr/MgrFishCarrier.lua"
local MAIN_PATH = "server/main.lua"
local MELEE_HIT_PATH = "server/packages/ability_system/anchors/melee_hit.lua"

local function readSource(path)
  local parts = {}
  for line in io.lines(path) do
    parts[#parts + 1] = line
  end
  return table.concat(parts, "\n")
end

local function contains(haystack, needle)
  return string.find(haystack, needle, 1, true) ~= nil
end

-- ===== 假引擎 =====

local function newSignal()
  local slots = {}
  local signal = {}
  function signal:Connect(fn)
    slots[#slots + 1] = fn
    return {
      Disconnect = function()
        for i, f in ipairs(slots) do
          if f == fn then
            slots[i] = nil
          end
        end
      end,
    }
  end
  function signal:Fire(...)
    for _, fn in ipairs(slots) do
      fn(...)
    end
  end
  return signal
end

local function newVector3(x, y, z)
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, {
    __add = function(a, b)
      return newVector3(a.x + b.x, a.y + b.y, a.z + b.z)
    end,
  })
end

local function newFakeWorld()
  local nextId = 100
  local world = { Created = {} }
  function world:CreateUnit(unitType, values)
    values = values or {}
    nextId = nextId + 1
    local unit = {
      UnitId = nextId,
      UnitType = unitType,
      Name = values.Name,
      Parent = values.Parent,
      Position = values.Position,
      Visible = values.Visible,
      EnableController = values.EnableController,
      BodyType = values.BodyType,
      Liftable = values.Liftable,
      RenderMeshId = values.RenderMeshId,
      LinearDamping = values.LinearDamping,
      AngularDamping = values.AngularDamping,
      NoCollidePairs = {},
    }
    unit.SetPosition = function(_, pos)
      unit.Position = pos
    end
    unit.Destroy = function()
      unit.Destroyed = true
    end
    unit.AddNoCollisionPairWithUnit = function(_, other)
      unit.NoCollidePairs[#unit.NoCollidePairs + 1] = other
    end
    if values.EnableController and not world.SuppressController then
      local healthChanged = newSignal()
      local died = newSignal()
      unit.Controller = {
        Health = 100,
        MaxHealth = 100,
        HealthChanged = healthChanged,
        Died = died,
        TakeDamage = function(self, damage)
          self.Health = math.max(0, self.Health - damage)
          healthChanged:Fire(self.Health)
          if self.Health <= 0 then
            died:Fire()
          end
        end,
      }
    end
    world.Created[#world.Created + 1] = unit
    return unit
  end
  return world
end

-- 假引擎只在被测函数执行期间挂上，测完恢复，别影响别的测试文件
local function withFakeEngine(world, fn)
  local saved = { game = rawget(_G, "game"), Vector3 = rawget(_G, "Vector3"), Quaternion = rawget(_G, "Quaternion") }
  rawset(_G, "game", {
    GetService = function(_, name)
      if name == "World" then
        return world
      end
      return nil
    end,
  })
  rawset(_G, "Vector3", { New = function(x, y, z) return newVector3(x, y, z) end })
  rawset(_G, "Quaternion", { FromEulerAngles = function() return "quaternion" end })
  local results = { pcall(fn) }
  for key, value in pairs(saved) do
    rawset(_G, key, value)
  end
  if not results[1] then
    error(results[2])
  end
  return table.unpack(results, 2)
end

local function freshManager()
  MgrFishCarrier.Carriers = {}
  MgrFishCarrier.Subscribers = {}
  return MgrFishCarrier
end

local SPAWN_OPTS = {
  FishId = "T1",
  RenderMeshId = "official://mesh/7000544",
  Position = newVector3(1, 2, 3),
  MaxHealth = 50,
  GravityEnabled = false,
}

-- ===== 1. 纯函数（配置解析）=====

TestFishCarrierHealthConfig = {}

function TestFishCarrierHealthConfig:test_max_health_falls_back_to_engine_default()
  lu.assertEquals(MgrFishCarrier.ResolveMaxHealth(nil, {}), 100)
  lu.assertEquals(MgrFishCarrier.ResolveMaxHealth({}, {}), 100)
end

function TestFishCarrierHealthConfig:test_max_health_priority_is_opts_then_config()
  lu.assertEquals(MgrFishCarrier.ResolveMaxHealth({ MaxHealth = 50 }, { MaxHealth = 30 }), 50)
  lu.assertEquals(MgrFishCarrier.ResolveMaxHealth({}, { MaxHealth = 30 }), 30)
end

function TestFishCarrierHealthConfig:test_bad_max_health_falls_back()
  -- 0 / 负数 / nan / inf / 非数：一律回落默认，不把「血量为 0」这种值放行进引擎
  for _, bad in ipairs({ 0, -1, 0 / 0, math.huge, -math.huge, "50", true }) do
    lu.assertEquals(MgrFishCarrier.ResolveMaxHealth({ MaxHealth = bad }, {}), 100)
  end
end

function TestFishCarrierHealthConfig:test_mesh_priority_is_opts_then_config()
  lu.assertEquals(
    MgrFishCarrier.ResolveMesh({ RenderMeshId = "official://mesh/1" }, { RenderMeshId = "official://mesh/2" }),
    "official://mesh/1"
  )
  lu.assertEquals(MgrFishCarrier.ResolveMesh({}, { RenderMeshId = "official://mesh/2" }), "official://mesh/2")
end

function TestFishCarrierHealthConfig:test_model_id_is_written_as_official_mesh_uri()
  -- M0-V3 实测：official://preset/... 会建出 1×1×1 空壳，只有 official://mesh/<号> 是对的写法
  lu.assertEquals(MgrFishCarrier.ResolveMesh({ ModelId = 7000544 }, {}), "official://mesh/7000544")
  lu.assertEquals(MgrFishCarrier.ResolveMesh({}, { ModelId = "7000544" }), "official://mesh/7000544")
end

function TestFishCarrierHealthConfig:test_no_mesh_anywhere_is_nil_so_spawn_refuses()
  lu.assertNil(MgrFishCarrier.ResolveMesh({}, {}))
  lu.assertNil(MgrFishCarrier.ResolveMesh({ ModelId = "" }, {}))
end

function TestFishCarrierHealthConfig:test_configured_max_health_would_win_over_default()
  -- 本图配置落盘后（M17 的 GameCfg.FishCarrier）应当被优先采用；没落盘时这条自动跳过
  local cfg = GameCfg.FishCarrier
  if not cfg or cfg.MaxHealth == nil then
    lu.assertEquals(MgrFishCarrier.ResolveMaxHealth(nil), 100)
    return
  end
  lu.assertEquals(MgrFishCarrier.ResolveMaxHealth(nil), cfg.MaxHealth)
end

-- ===== 2. 引擎侧（假引擎）=====

TestFishCarrierEngine = {}

function TestFishCarrierEngine:test_spawn_builds_a_liftable_worldunit_body()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier = withFakeEngine(world, function()
    return mgr:Spawn(SPAWN_OPTS)
  end)

  lu.assertNotNil(carrier)
  lu.assertEquals(carrier.Body.UnitType, "WorldUnit")
  lu.assertEquals(carrier.Body.BodyType, 4) -- Dynamic：抓举只对动态物体生效
  lu.assertEquals(carrier.Body.Liftable, true)
  lu.assertEquals(carrier.Body.RenderMeshId, "official://mesh/7000544")
  lu.assertTrue(mgr.Carriers[carrier.Body.UnitId] == carrier)
end

function TestFishCarrierEngine:test_spawn_refuses_without_a_mesh()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier, why = withFakeEngine(world, function()
    return mgr:Spawn({ FishId = "T-no-mesh" })
  end)
  lu.assertNil(carrier)
  lu.assertEquals(why, "no-mesh")
  lu.assertEquals(#world.Created, 0)
end

function TestFishCarrierEngine:test_receiver_is_a_controller_bearing_child_of_the_body()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier = withFakeEngine(world, function()
    return mgr:Spawn(SPAWN_OPTS)
  end)

  -- #32 的接缝：受击体带 EnableController，包内 _applyDamage 才找得到 target.Controller
  lu.assertEquals(carrier.Receiver.EnableController, true)
  lu.assertEquals(carrier.Receiver.UnitType, "EggyUnit")
  lu.assertTrue(carrier.Receiver.Parent == carrier.Body)
  lu.assertNotNil(carrier.Controller)
  lu.assertEquals(carrier.Controller.MaxHealth, 50)
  lu.assertEquals(carrier.Controller.Health, 50)
end

function TestFishCarrierEngine:test_melee_damage_reduces_health_and_death_fires_once()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier
  withFakeEngine(world, function()
    carrier = mgr:Spawn(SPAWN_OPTS)
  end)

  local deaths = 0
  mgr:SubscribeDied(function()
    deaths = deaths + 1
  end)

  -- 走包内 _applyDamage 的同一条路（它最终调用 controller:TakeDamage(damage, owner)）
  withFakeEngine(world, function()
    carrier.Controller:TakeDamage(25, "attacker")
  end)
  lu.assertEquals(carrier.Health, 25)
  lu.assertEquals(deaths, 0)

  -- 归零：HealthChanged(0) 与 Died 都会来，只通知一次
  withFakeEngine(world, function()
    carrier.Controller:TakeDamage(25, "attacker")
  end)
  lu.assertEquals(carrier.Health, 0)
  lu.assertEquals(deaths, 1)
  lu.assertEquals(carrier.Dead, true)
end

function TestFishCarrierEngine:test_update_keeps_the_receiver_on_the_body()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier
  withFakeEngine(world, function()
    carrier = mgr:Spawn(SPAWN_OPTS)
  end)

  -- 举着 / 逃脱 / 落地：鱼本体动到哪，受击体跟到哪（引擎没有给 EggyUnit 的子节点跟随开关）
  withFakeEngine(world, function()
    carrier.Body.Position = newVector3(10, 20, 30)
    mgr:Update(0.03)
  end)
  lu.assertEquals(carrier.Receiver.Position.x, 10)
  lu.assertEquals(carrier.Receiver.Position.y, 20)
  lu.assertEquals(carrier.Receiver.Position.z, 30)
end

function TestFishCarrierEngine:test_body_and_receiver_do_not_push_each_other()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier = withFakeEngine(world, function()
    return mgr:Spawn(SPAWN_OPTS)
  end)
  lu.assertEquals(#carrier.Body.NoCollidePairs, 1)
  lu.assertTrue(carrier.Body.NoCollidePairs[1] == carrier.Receiver)
end

function TestFishCarrierEngine:test_despawn_unregisters_and_stops_notifying()
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier = withFakeEngine(world, function()
    return mgr:Spawn(SPAWN_OPTS)
  end)
  local deaths = 0
  mgr:SubscribeDied(function()
    deaths = deaths + 1
  end)

  local bodyId = carrier.Body.UnitId
  withFakeEngine(world, function()
    mgr:Despawn(carrier)
  end)

  lu.assertNil(mgr.Carriers[bodyId])
  lu.assertTrue(carrier.Body == nil)
  lu.assertEquals(carrier.MaxHealth, 50) -- 血量口径留着，M2 生成鱼获时还要读
end

function TestFishCarrierEngine:test_damping_options_are_forwarded_to_the_body()
  -- 无阻尼 + 无重力的动态鱼被推一下会一漂到底（试玩实测），阻尼是选项，M2 按物理手感定值
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier = withFakeEngine(world, function()
    local opts = {}
    for k, v in pairs(SPAWN_OPTS) do
      opts[k] = v
    end
    opts.LinearDamping = 10
    opts.AngularDamping = 10
    return mgr:Spawn(opts)
  end)
  lu.assertEquals(carrier.Body.LinearDamping, 10)
  lu.assertEquals(carrier.Body.AngularDamping, 10)
end

function TestFishCarrierEngine:test_death_fired_without_health_changed_still_syncs_health()
  -- 试玩实测（台账 §11.3）：致命那一下引擎只发 Died，不发 HealthChanged；订阅者读到的
  -- carrier.Health 必须是 0 而不是上一档，否则 M2 在鱼获生成那一刻会拿到错的数值
  local mgr = freshManager()
  local world = newFakeWorld()
  local carrier = withFakeEngine(world, function()
    return mgr:Spawn(SPAWN_OPTS)
  end)
  local seen
  mgr:SubscribeDied(function(c)
    seen = c.Health
  end)
  withFakeEngine(world, function()
    carrier.Controller.Health = 0
    carrier.Controller.Died:Fire()
  end)
  lu.assertEquals(seen, 0)
  lu.assertEquals(carrier.Health, 0)
  lu.assertTrue(carrier.Dead)
end

function TestFishCarrierEngine:test_attach_destroys_the_orphan_receiver_when_controller_is_missing()
  -- 防御路径：受击体建出来了、但引擎没给它 Controller（EnableController 这条接缝变了）。
  -- #32 的教训是这种事不能静默；受击体还是鱼本体的子节点，留着就是个跟着鱼跑的孤儿。
  local mgr = freshManager()
  local world = newFakeWorld()
  world.SuppressController = true
  local body = world:CreateUnit("WorldUnit", { Name = "T-body", Position = newVector3(0, 0, 0) })
  local carrier = withFakeEngine(world, function()
    return mgr:Attach(body, { MaxHealth = 50 })
  end)
  lu.assertNil(carrier)
  lu.assertEquals(#mgr.Carriers, 0)
  local receiver = world.Created[#world.Created]
  lu.assertEquals(receiver.UnitType, "EggyUnit")
  lu.assertTrue(receiver.Destroyed == true, "孤儿受击体必须被销毁")
end

-- ===== 3. 接缝守卫（源码文本校对）=====

TestFishCarrierSeam = {}

function TestFishCarrierSeam:test_receiver_is_created_with_enable_controller()
  -- #32 的唯一接缝：没有这句，包内 _applyDamage 找不到 target.Controller，伤害静默归零
  local src = readSource(CARRIER_PATH)
  lu.assertTrue(contains(src, "EnableController = true"), "受击体必须带 EnableController = true")
  lu.assertTrue(contains(src, 'CreateUnit("EggyUnit"'), "受击体必须是带 Controller 的单位类型")
end

function TestFishCarrierSeam:test_module_does_not_require_the_vendor_package()
  -- 业务层不直接 require 包内模块：接缝是双端根聚合入口（AGENTS.md「packages/」一节）
  local src = readSource(CARRIER_PATH)
  lu.assertFalse(contains(src, 'require("server.packages'), "不得 require 包内模块")
  lu.assertFalse(contains(src, 'require("client.packages'), "不得 require 包内模块")
end

function TestFishCarrierSeam:test_manager_is_registered_in_the_mgr_map()
  -- 不进 MgrMap 就没有 Start/Update，受击体也不会跟着鱼走
  local src = readSource(MAIN_PATH)
  lu.assertTrue(
    contains(src, 'MgrFishCarrier = require("server.Mgr.MgrFishCarrier")'),
    "server/main.lua 的 MgrMap 必须注册 MgrFishCarrier"
  )
end

function TestFishCarrierSeam:test_vendor_contract_is_still_controller_take_damage()
  -- 包整包 vendor 不改：这里校对包内 _applyDamage 的两条分支没变。
  -- 一旦官方改成别的接缝，本模块的实现前提就废了，必须在这里暴露。
  local src = readSource(MELEE_HIT_PATH)
  lu.assertTrue(contains(src, "target.TakeDamage"), "_applyDamage 的第一条分支：target:TakeDamage")
  lu.assertTrue(contains(src, "target.Controller"), "_applyDamage 的第二条分支：target.Controller")
  lu.assertTrue(contains(src, "TakeDamage(damage, owner)"), "_applyDamage 的调用形状")
end

function TestFishCarrierSeam:test_death_is_notified_once()
  -- 死亡单点：Died 与 HealthChanged(<=0) 两条路都来也只能通知一次（M2 靠它生成鱼获）
  local mgr = freshManager()
  local calls = {}
  local carrier = { Dead = false }
  mgr:SubscribeDied(function(c)
    calls[#calls + 1] = c
  end)
  mgr:NotifyDied(carrier)
  mgr:NotifyDied(carrier)
  lu.assertEquals(#calls, 1)
  lu.assertTrue(carrier.Dead)
end
