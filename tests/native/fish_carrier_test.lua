-- #84 迁移：鱼载体伤害接口 server/Mgr/MgrFishCarrier.lua（原 tests/gameplay/fish_carrier_test.lua，7 + 16 + 5 例）。
-- 三块接缝：1) 血量/模型号解析纯函数；2) 假引擎驱动 Spawn → 挨打 → Update 跟随 → Despawn 全链路；
-- 3) 接缝守卫（源码文本校对）：受击体 EnableController、不 require 包内模块、MgrMap 注册、官方 melee_hit 契约。
-- 假引擎只在被测函数执行期间挂上（withFakeEngine），测完恢复 _G，不影响别的文件；
-- Busted 案例体在沙箱 _ENV 里，业务模块读的是真 _G，因此引擎全局必须 rawset 到 _G。
-- describe/it 名称保留旧类名与方法名，按类名字典序 + 方法名字典序注册以保持旧套件执行顺序。
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')
local GameCfg = require('common.GameCfg')

local CARRIER_PATH = 'server/Mgr/MgrFishCarrier.lua'
local MAIN_PATH = 'server/main.lua'
local MELEE_HIT_PATH = 'server/packages/ability_system/anchors/melee_hit.lua'

local function readSource(path)
  local parts = {}
  for line in io.lines(path) do
    parts[#parts + 1] = line
  end
  return table.concat(parts, '\n')
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
  local saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion') }
  rawset(_G, 'game', {
    GetService = function(_, name)
      if name == 'World' then
        return world
      end
      return nil
    end,
  })
  rawset(_G, 'Vector3', { New = function(x, y, z) return newVector3(x, y, z) end })
  rawset(_G, 'Quaternion', { FromEulerAngles = function() return 'quaternion' end })
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
  FishId = 'T1',
  RenderMeshId = 'official://mesh/7000544',
  Position = newVector3(1, 2, 3),
  MaxHealth = 50,
  GravityEnabled = false,
}

-- ===== 1. 纯函数（配置解析）=====

describe('TestFishCarrierHealthConfig', function()
  it('test_bad_max_health_falls_back', function()
    -- 0 / 负数 / nan / inf / 非数：一律回落默认，不把「血量为 0」这种值放行进引擎
    for _, bad in ipairs({ 0, -1, 0 / 0, math.huge, -math.huge, '50', true }) do
      assert.are.equal(100, MgrFishCarrier.ResolveMaxHealth({ MaxHealth = bad }, {}))
    end
  end)

  it('test_configured_max_health_would_win_over_default', function()
    -- 本图配置落盘后（M17 的 GameCfg.FishCarrier）应当被优先采用；没落盘时这条自动跳过
    local cfg = GameCfg.FishCarrier
    if not cfg or cfg.MaxHealth == nil then
      assert.are.equal(100, MgrFishCarrier.ResolveMaxHealth(nil))
      return
    end
    assert.are.equal(cfg.MaxHealth, MgrFishCarrier.ResolveMaxHealth(nil))
  end)

  it('test_max_health_falls_back_to_engine_default', function()
    assert.are.equal(100, MgrFishCarrier.ResolveMaxHealth(nil, {}))
    assert.are.equal(100, MgrFishCarrier.ResolveMaxHealth({}, {}))
  end)

  it('test_max_health_priority_is_opts_then_config', function()
    assert.are.equal(50, MgrFishCarrier.ResolveMaxHealth({ MaxHealth = 50 }, { MaxHealth = 30 }))
    assert.are.equal(30, MgrFishCarrier.ResolveMaxHealth({}, { MaxHealth = 30 }))
  end)

  it('test_mesh_priority_is_opts_then_config', function()
    assert.are.equal('official://mesh/1',
      MgrFishCarrier.ResolveMesh({ RenderMeshId = 'official://mesh/1' }, { RenderMeshId = 'official://mesh/2' }))
    assert.are.equal('official://mesh/2', MgrFishCarrier.ResolveMesh({}, { RenderMeshId = 'official://mesh/2' }))
  end)

  it('test_model_id_is_written_as_official_mesh_uri', function()
    -- M0-V3 实测：official://preset/... 会建出 1×1×1 空壳，只有 official://mesh/<号> 是对的写法
    assert.are.equal('official://mesh/7000544', MgrFishCarrier.ResolveMesh({ ModelId = 7000544 }, {}))
    assert.are.equal('official://mesh/7000544', MgrFishCarrier.ResolveMesh({}, { ModelId = '7000544' }))
  end)

  it('test_no_mesh_anywhere_is_nil_so_spawn_refuses', function()
    assert.is_nil(MgrFishCarrier.ResolveMesh({}, {}))
    assert.is_nil(MgrFishCarrier.ResolveMesh({ ModelId = '' }, {}))
  end)
end)

-- ===== 2. 引擎侧（假引擎）=====

describe('TestFishCarrierEngine', function()
  it('test_attach_destroys_the_orphan_receiver_when_controller_is_missing', function()
    -- 防御路径：受击体建出来了、但引擎没给它 Controller（EnableController 这条接缝变了）。
    -- #32 的教训是这种事不能静默；受击体还是鱼本体的子节点，留着就是个跟着鱼跑的孤儿。
    local mgr = freshManager()
    local world = newFakeWorld()
    world.SuppressController = true
    local body = world:CreateUnit('WorldUnit', { Name = 'T-body', Position = newVector3(0, 0, 0) })
    local carrier = withFakeEngine(world, function()
      return mgr:Attach(body, { MaxHealth = 50 })
    end)
    assert.is_nil(carrier)
    assert.are.equal(0, #mgr.Carriers)
    local receiver = world.Created[#world.Created]
    assert.are.equal('EggyUnit', receiver.UnitType)
    assert.is_true(receiver.Destroyed == true, '孤儿受击体必须被销毁')
  end)

  it('test_body_and_receiver_do_not_push_each_other', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local carrier = withFakeEngine(world, function()
      return mgr:Spawn(SPAWN_OPTS)
    end)
    assert.are.equal(1, #carrier.Body.NoCollidePairs)
    assert.is_true(carrier.Body.NoCollidePairs[1] == carrier.Receiver)
  end)

  it('test_business_damage_requires_hit_and_reports_actual_amount', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    withFakeEngine(world, function()
      local carrier = mgr:Spawn(SPAWN_OPTS)
      carrier.Controller.Health = 10
      assert.same(carrier, mgr:ResolveCarrier(carrier.Receiver))
      assert.is_false(mgr:Damage(carrier, 5))
      assert.are.equal(10, carrier.Controller.Health)
      local seen = {}
      mgr.DamageListener = function(target, actual, hit)
        seen[#seen + 1] = { target, actual, hit }
      end
      local hit = { id = 7, category = 'weapon' }
      local ok, actual = mgr:Damage(carrier, 25, hit)
      assert.is_true(ok)
      assert.are.equal(10, actual)
      assert.same({ { carrier, 10, hit } }, seen)
    end)
    mgr.DamageListener = nil
  end)

  it('test_damage_reports_effective_health_once_for_every_path', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local notices = {}
    mgr.DamagePublisher = function(payload) notices[#notices + 1] = payload end
    withFakeEngine(world, function()
      local carrier = mgr:Spawn(SPAWN_OPTS)
      carrier.Controller:TakeDamage(2.7)
      assert.near(2.7, notices[1].amount, 0.00001)
      assert.are.equal(carrier.Body.UnitId, notices[1].targetId)
      assert.are.equal(2, notices[1].position.y)
      mgr:Damage(carrier, 2.4, { id = 1001 })
      assert.near(2.4, notices[2].amount, 0.00001)
      carrier.Controller.Health = 4
      carrier.Controller.HealthChanged:Fire(4)
      notices = {} -- 单独观察致命一击的通知
      carrier.Controller.Health = 0
      carrier.Controller.Died:Fire() -- 引擎致死时不一定发 HealthChanged
      carrier.Controller.HealthChanged:Fire(0)
      assert.are.equal(1, #notices)
      assert.are.equal(4, notices[1].amount)
      assert.are.equal(0, carrier.Health)
    end)
    mgr.DamagePublisher = nil
  end)

  it('test_damping_options_are_forwarded_to_the_body', function()
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
    assert.are.equal(10, carrier.Body.LinearDamping)
    assert.are.equal(10, carrier.Body.AngularDamping)
  end)

  it('test_death_fired_without_health_changed_still_syncs_health', function()
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
    assert.are.equal(0, seen)
    assert.are.equal(0, carrier.Health)
    assert.is_true(carrier.Dead)
  end)

  it('test_despawn_unregisters_and_stops_notifying', function()
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

    assert.is_nil(mgr.Carriers[bodyId])
    assert.is_true(carrier.Body == nil)
    assert.are.equal(50, carrier.MaxHealth) -- 血量口径留着，M2 生成鱼获时还要读
  end)

  it('test_explicit_trajectory_target_does_not_read_stale_body_position', function()
    -- #37 失败方式：本体写后仍读到上帧坐标；显式轨迹目标被忽略，受击体持续落后。
    local mgr, world = freshManager(), newFakeWorld()
    withFakeEngine(world, function()
      local carrier = mgr:Spawn(SPAWN_OPTS)
      local target = Vector3.New(20, 15, 30)
      mgr:SyncPosition(carrier, target)
      assert.same(target + carrier.ReceiverOffset, carrier.Receiver.Position)
      assert.same({ x = 20, y = 15, z = 30 }, carrier.LastPosition)
      mgr:Update(0.03) -- pairs 顺序可在脚本写回之后跑默认同步，不能再用旧本体位置覆盖。
      assert.same(target + carrier.ReceiverOffset, carrier.Receiver.Position)
    end)
  end)

  it('test_last_known_body_position_survives_failed_position_read', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local notices = {}
    mgr.DamagePublisher = function(payload) notices[#notices + 1] = payload end
    withFakeEngine(world, function()
      local carrier = mgr:Spawn(SPAWN_OPTS)
      carrier.Body.GetPosition = function() error('unit destroyed') end
      carrier.Controller:TakeDamage(0.5)
      assert.are.equal(1, notices[1].position.x)
      assert.are.equal(0.5, notices[1].amount)
    end)
    mgr.DamagePublisher = nil
  end)

  it('test_melee_damage_reduces_health_and_death_fires_once', function()
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
      carrier.Controller:TakeDamage(25, 'attacker')
    end)
    assert.are.equal(25, carrier.Health)
    assert.are.equal(0, deaths)

    -- 归零：HealthChanged(0) 与 Died 都会来，只通知一次
    withFakeEngine(world, function()
      carrier.Controller:TakeDamage(25, 'attacker')
    end)
    assert.are.equal(0, carrier.Health)
    assert.are.equal(1, deaths)
    assert.are.equal(true, carrier.Dead)
  end)

  it('test_overkill_reports_only_remaining_health', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local notices = {}
    mgr.DamagePublisher = function(payload) notices[#notices + 1] = payload end
    withFakeEngine(world, function()
      local carrier = mgr:Spawn(SPAWN_OPTS)
      carrier.Controller.Health = 4
      carrier.Controller.HealthChanged:Fire(4)
      notices = {}
      carrier.Controller:TakeDamage(10)
      assert.are.equal(0, carrier.Controller.Health)
      assert.are.equal(1, #notices)
      assert.are.equal(4, notices[1].amount)
    end)
    mgr.DamagePublisher = nil
  end)

  it('test_receiver_is_a_controller_bearing_child_of_the_body', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local carrier = withFakeEngine(world, function()
      return mgr:Spawn(SPAWN_OPTS)
    end)

    -- #32 的接缝：受击体带 EnableController，包内 _applyDamage 才找得到 target.Controller
    assert.are.equal(true, carrier.Receiver.EnableController)
    assert.are.equal('EggyUnit', carrier.Receiver.UnitType)
    assert.is_true(carrier.Receiver.Parent == carrier.Body)
    assert.is_not.is_nil(carrier.Controller)
    assert.are.equal(50, carrier.Controller.MaxHealth)
    assert.are.equal(50, carrier.Controller.Health)
  end)

  it('test_spawn_builds_a_liftable_worldunit_body', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local carrier = withFakeEngine(world, function()
      return mgr:Spawn(SPAWN_OPTS)
    end)

    assert.is_not.is_nil(carrier)
    assert.are.equal('WorldUnit', carrier.Body.UnitType)
    assert.are.equal(4, carrier.Body.BodyType) -- Dynamic：抓举只对动态物体生效
    assert.are.equal(true, carrier.Body.Liftable)
    assert.are.equal('official://mesh/7000544', carrier.Body.RenderMeshId)
    assert.is_true(mgr.Carriers[carrier.Body.UnitId] == carrier)
  end)

  it('test_spawn_refuses_without_a_mesh', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local carrier, why = withFakeEngine(world, function()
      return mgr:Spawn({ FishId = 'T-no-mesh' })
    end)
    assert.is_nil(carrier)
    assert.are.equal('no-mesh', why)
    assert.are.equal(0, #world.Created)
  end)

  it('test_update_keeps_the_receiver_on_the_body', function()
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
    assert.are.equal(10, carrier.Receiver.Position.x)
    assert.are.equal(20, carrier.Receiver.Position.y)
    assert.are.equal(30, carrier.Receiver.Position.z)
  end)

  it('test_zero_damage_recovery_and_binding_never_report', function()
    local mgr = freshManager()
    local world = newFakeWorld()
    local notices = {}
    mgr.DamagePublisher = function(payload) notices[#notices + 1] = payload end
    withFakeEngine(world, function()
      local carrier = mgr:Spawn(SPAWN_OPTS)
      carrier.Controller.HealthChanged:Fire(50)
      carrier.Controller:TakeDamage(0)
      carrier.Controller.Health = 55
      carrier.Controller.HealthChanged:Fire(55)
      carrier.Controller:TakeDamage(0.1)
      assert.are.equal(1, #notices)
      assert.near(0.1, notices[1].amount, 0.00001)
    end)
    mgr.DamagePublisher = nil
  end)
end)

-- ===== 3. 接缝守卫（源码文本校对）=====

describe('TestFishCarrierSeam', function()
  it('test_death_is_notified_once', function()
    -- 死亡单点：Died 与 HealthChanged(<=0) 两条路都来也只能通知一次（M2 靠它生成鱼获）
    local mgr = freshManager()
    local calls = {}
    local carrier = { Dead = false }
    mgr:SubscribeDied(function(c)
      calls[#calls + 1] = c
    end)
    mgr:NotifyDied(carrier)
    mgr:NotifyDied(carrier)
    assert.are.equal(1, #calls)
    assert.is_true(carrier.Dead)
  end)

  it('test_manager_is_registered_in_the_mgr_map', function()
    -- 不进 MgrMap 就没有 Start/Update，受击体也不会跟着鱼走
    local src = readSource(MAIN_PATH)
    assert.is_true(contains(src, 'MgrFishCarrier = require("server.Mgr.MgrFishCarrier")'),
      'server/main.lua 的 MgrMap 必须注册 MgrFishCarrier')
  end)

  it('test_module_does_not_require_the_vendor_package', function()
    -- 业务层不直接 require 包内模块：接缝是双端根聚合入口（AGENTS.md「packages/」一节）
    local src = readSource(CARRIER_PATH)
    assert.is_false(contains(src, 'require("server.packages'), '不得 require 包内模块')
    assert.is_false(contains(src, 'require("client.packages'), '不得 require 包内模块')
  end)

  it('test_receiver_is_created_with_enable_controller', function()
    -- #32 的唯一接缝：没有这句，包内 _applyDamage 找不到 target.Controller，伤害静默归零
    local src = readSource(CARRIER_PATH)
    assert.is_true(contains(src, 'EnableController = true'), '受击体必须带 EnableController = true')
    assert.is_true(contains(src, 'CreateUnit("EggyUnit"'), '受击体必须是带 Controller 的单位类型')
  end)

  it('test_vendor_contract_is_still_controller_take_damage', function()
    -- 包整包 vendor 不改：这里校对包内 _applyDamage 的两条分支没变。
    -- 一旦官方改成别的接缝，本模块的实现前提就废了，必须在这里暴露。
    local src = readSource(MELEE_HIT_PATH)
    assert.is_true(contains(src, 'target.TakeDamage'), '_applyDamage 的第一条分支：target:TakeDamage')
    assert.is_true(contains(src, 'target.Controller'), '_applyDamage 的第二条分支：target.Controller')
    assert.is_true(contains(src, 'TakeDamage(damage, owner)'), '_applyDamage 的调用形状')
  end)
end)
