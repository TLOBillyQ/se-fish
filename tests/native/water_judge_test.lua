-- 纯模块单测：水判定 common/MathWaterJudge.lua（M0-V1）。
-- 判定只读 pos 的 x/y/z、不碰引擎，所以这里能用普通 table 当坐标（试玩里传 Vector3 是同一套字段）。
-- 六个边界用例（#12 的验收：中心 / 水下 / 空中 / 贴边 ±0.1m / 远处陆地）+ 配置口径，
-- 用的就是 GameCfg.Water.Zones 的真值，改配置把边界改错了这里先红。
-- 末尾还钉住 GameCfg.FishCarrier 的 mesh id 写法与模型号号段（M0-V3 / #31）——那是 GameCfg 的另一处
-- 实测配置真值，写错鱼建不出来（F-7 的 [未查证] 已消除，见 common/GameCfg.lua 该段注释）。
-- 迁移自 tests/gameplay/water_judge_test.lua（#83）。旧入口有 5 个 LuaUnit 类，按「类名字典序 +
-- 类内方法名字典序」展开（等价于旧入口对 ClassName.method 全名的排序）；本文件无 setUp/tearDown，
-- 因此不额外注册钩子。it 顺序与迁移前逐条对账。
local GameCfg = require("common.GameCfg")
local MathWaterJudge = require("common.MathWaterJudge")

-- 本图 2026-09-24 水平扩建两倍后的编辑器回读值：
--   WaterCircle1 Position(-11.75, 1.05, 27.75) Size(6, 1, 6) Scale(2, 1, 2)
--   WaterCircle2 Position(-11.75, 1.05, 27.75) Size(12, 1, 12) Scale(4, 1, 4)
local CENTER_X = -11.75
local CENTER_Z = -12.25 -- 原测量中心 27.75 随鱼塘整体平移 -40
-- 水面高度（#31 改正）：Position.y 是底面、Size.y 是包围盒半长 ⇒ 水圈顶面 = 1.18 + 1 ≈ 2.183。
-- 来源 issue #25 的 M0 试玩验证台账（评论 9865；M15 试玩里水圈会漂移，1.18 是 16:24 那次的高点）。
local SURFACE_Y = 2.183
local OUTER_HALF = 6.0 -- WaterCircle2 的 Size.x / 2（Size 已含 Scale，不再乘 Scale）
local UNDER_WATER_Y = 2.08 -- 水面下 ≈0.1m
local AIR_Y = 3.18 -- 水面上 ≈1m
local FLOOR_Y = 2.0 -- 大地板的表面高度（射线实测命中 2.0；现在低于水面，见下面 W-7 那条）

local function zones()
  return GameCfg.Water.Zones
end

local function zoneById(id)
  for _, zone in ipairs(zones()) do
    if zone.Id == id then
      return zone
    end
  end
  error("GameCfg.Water.Zones 里没有 " .. id)
end

local function at(x, y, z)
  return { x = x, y = y, z = z }
end

-- 落到水圈的判定统一用装配出来的判定器（与业务同一条路径），不直接调 InZone。
local function inWater(pos)
  return MathWaterJudge.Build(zones())(pos) ~= nil
end

local PRESET_PREFIX = "official://preset/"

-- GameCfg.FishCarrier 的 20 条模型：把模型号排好序返回，让「号段连续」这类断言不受 pairs 顺序影响。
local function carrierModels()
  local models = GameCfg.FishCarrier.Models
  local ids = {}
  for id in pairs(models) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return models, ids
end

describe("TestFishCarrierConfig", function()
  -- mesh id 的写法守卫（M0-V3 / #31）：写进 RenderMeshId 的必须是 official://mesh/<模型号>。
  -- 台账 §2.1 实测：official://preset/... 也能建出来但只是空壳（Size=(1,1,1)、无几何），
  -- 所以谁把预设号写进 Mesh，这条先红。
  it("test_mesh_id_follows_the_official_uri_convention", function()
    local models, ids = carrierModels()
    for _, id in ipairs(ids) do
      local row = models[id]
      assert.are.equal("official://mesh/" .. id, row.Mesh)
      -- 旧 assertNotEquals 对字符串就是 ~=，这里都是字符串，are_not.equal 等价
      assert.are_not.equal(row.Mesh, row.Preset)
      assert.are.equal(PRESET_PREFIX, row.Preset:sub(1, #PRESET_PREFIX))
    end
  end)

  -- 官方鱼模型库是 7000544–7000563 共 20 条、模型号连续，官方预设号一一对应且不重复。
  -- 号段抄错、漏一条、或者把预设号错位挪一行，这条先红。
  it("test_official_fish_model_range_is_complete", function()
    local models, ids = carrierModels()
    local presets = {}
    assert.are.equal(20, #ids)
    for i, id in ipairs(ids) do
      assert.are.equal(tostring(7000543 + i), id)
      assert.is_true(models[id].Name ~= nil and models[id].Name ~= "", id .. " 缺名称")
      local preset = models[id].Preset
      assert.is_true(presets[preset] == nil, "官方预设号重复：" .. preset)
      presets[preset] = true
    end
  end)
end)

describe("TestWallWater", function()
  -- 失败方式：墙内误判、墙外漏判、凹角或拼接接缝漏判、新水区没有鱼表。
  it("test_every_added_zone_has_a_fish_pool", function()
    for i = 3, #zones() do
      assert.is_not_nil(GameCfg.Casting.Zones[zones()[i].Id])
    end
  end)

  it("test_land_and_bait_positions_stay_dry", function()
    for _, p in ipairs({ {5,-9}, {5,0}, {10,-12}, {15,-6}, {10,5}, {-15,5} }) do
      assert.is_false(inWater(at(p[1], FLOOR_Y, p[2])))
    end
  end)

  it("test_outside_walls_and_notch_are_water", function()
    for _, p in ipairs({ {-40,5}, {28,0}, {0,-28}, {0,28}, {-15,-10}, {-10,-6} }) do
      assert.is_true(inWater(at(p[1], FLOOR_Y, p[2])))
    end
  end)

  it("test_tiling_has_no_holes_or_land_overlap", function()
    for x = -58, 31 do
      for z = -29, 30 do
        local outside = x < -24.25 or x > 21.75 or z < -23.75 or z > 21.25
          or (x < -4.982 and z < -4.732)
        assert.are.equal(outside, inWater(at(x, FLOOR_Y, z)), 'x=' .. x .. ', z=' .. z)
      end
    end
  end)
end)

describe("TestWaterJudgeBoundary", function()
  -- 1) 中心：水圈正中心、水面下 0.1m。
  it("test_air_above_surface_is_not_in_water", function()
    assert.is_false(inWater(at(CENTER_X, AIR_Y, CENTER_Z)))
  end)

  -- 2) 中心：水圈正中心、水面下 0.1m。
  it("test_center_below_surface_is_in_water", function()
    assert.is_true(inWater(at(CENTER_X, UNDER_WATER_Y, CENTER_Z)))
  end)

  -- 3) 水下：再深 1m 仍在水里（判定只要 y ≤ 水面，不设下限）。
  it("test_deep_underwater_is_in_water", function()
    assert.is_true(inWater(at(CENTER_X, SURFACE_Y - 1.0, CENTER_Z)))
  end)

  -- 4) 贴边 −0.1m：还在半宽以内，算在水里。
  it("test_edge_inside_by_point_one_meter_is_in_water", function()
    assert.is_true(inWater(at(CENTER_X + OUTER_HALF - 0.1, UNDER_WATER_Y, CENTER_Z)))
  end)

  -- 5) 贴边 +0.1m：超出半宽 0.1m 不算在水里。
  it("test_edge_outside_by_point_one_meter_is_not_in_water", function()
    assert.is_false(MathWaterJudge.InZone(zoneById("WaterCircle2"),
      at(CENTER_X + OUTER_HALF + 0.1, UNDER_WATER_Y, CENTER_Z)))
  end)

  -- 6) 远处陆地：本图原点附近的岸上点，不在水里。
  it("test_far_land_is_not_in_water", function()
    assert.is_false(inWater(at(0, FLOOR_Y, 0)))
  end)
end)

describe("TestWaterJudgeConfig", function()
  -- 配错要当场报错，不能静默退化成「永远不在水里」。
  it("test_build_rejects_empty_zones", function()
    assert.error_matches(function() MathWaterJudge.Build({}) end, "水区配置为空", nil, true)
  end)

  it("test_build_rejects_missing_field", function()
    assert.error_matches(function()
      MathWaterJudge.Build({ { Id = "Bad", Center = { x = 0, z = 0 }, HalfXZ = 1.0 } })
    end, "SurfaceY", nil, true)
  end)

  it("test_build_rejects_non_positive_half_width", function()
    assert.error_matches(function()
      MathWaterJudge.Build({ { Id = "Bad", Center = { x = 0, z = 0 }, HalfXZ = 0, SurfaceY = 1.0 } })
    end, "HalfXZ", nil, true)
  end)

  it("test_center_and_surface_come_from_measured_values", function()
    for _, zone in ipairs({ zoneById("WaterCircle2"), zoneById("WaterCircle1") }) do
      assert.are.equal(CENTER_X, zone.Center.x)
      assert.are.equal(CENTER_Z, zone.Center.z)
      assert.are.equal(SURFACE_Y, zone.SurfaceY)
    end
  end)

  -- 配置口径：HalfXZ 直接写运行时半边尺寸，不再乘 Scale（WaterCircle2 的 Scale.x=4 已经算进 Size.x=12）。
  -- 谁「顺手」把 3.0 改成 6.0（乘了缩放），这条先红。
  it("test_half_width_does_not_multiply_scale", function()
    assert.are.equal(OUTER_HALF, zoneById("WaterCircle2").HalfXZ)
    assert.are.equal(3.0, zoneById("WaterCircle1").HalfXZ)
  end)
end)

describe("TestWaterJudgeSemantics", function()
  -- 边界含等号：正好贴在半宽线上、正好落在水面高度上都算在水里。
  it("test_boundary_is_inclusive", function()
    assert.is_true(inWater(at(CENTER_X + OUTER_HALF, SURFACE_Y, CENTER_Z)))
    assert.is_true(inWater(at(CENTER_X, SURFACE_Y, CENTER_Z + OUTER_HALF)))
  end)

  -- 同心时按配置顺序命中排在前的那个（Build 的行为契约，M1 按水区选鱼表要看这个）。
  it("test_build_returns_the_first_matching_zone", function()
    local judge = MathWaterJudge.Build(zones())
    local hit = judge(at(CENTER_X, UNDER_WATER_Y, CENTER_Z))
    assert.are.equal("WaterCircle2", hit.Id)
    assert.is_nil(judge(at(CENTER_X, AIR_Y, CENTER_Z)))
  end)

  -- 两圈同心但半宽不同：外圈 6.0 / 内圈 3.0，所以 dx=5.0 的点只在外圈里。
  it("test_inner_circle_has_its_own_half_width", function()
    local outer = zoneById("WaterCircle2")
    local inner = zoneById("WaterCircle1")
    local pos = at(CENTER_X + 5.0, UNDER_WATER_Y, CENTER_Z)
    assert.is_true(MathWaterJudge.InZone(outer, pos))
    assert.is_false(MathWaterJudge.InZone(inner, pos))
  end)

  -- 水面 y≈2.183 高于大地板表面 y=2.0（#31 改正：Position.y 是底面、Size.y 是包围盒半长）：
  -- 水区矩形内、站在地板高度上的点算在水里（那块地板就是池塘底），水面之上的点不算。
  -- 这条是 W-7 那个实测关系的操作化——水面高度配低了，水里的点会被误判成岸上。
  it("test_point_at_floor_height_inside_pond_is_in_water", function()
    assert.is_true(zoneById("WaterCircle2").SurfaceY > FLOOR_Y)
    assert.is_true(inWater(at(CENTER_X, FLOOR_Y, CENTER_Z)))
    assert.is_false(inWater(at(CENTER_X, FLOOR_Y + 0.5, CENTER_Z)))
  end)

  -- Z 轴与 X 轴对称（判定是「水平方框」不是圆）。
  it("test_z_axis_edge_matches_x_axis", function()
    assert.is_true(inWater(at(CENTER_X, UNDER_WATER_Y, CENTER_Z + OUTER_HALF - 0.1)))
    assert.is_false(MathWaterJudge.InZone(zoneById("WaterCircle2"),
      at(CENTER_X, UNDER_WATER_Y, CENTER_Z + OUTER_HALF + 0.1)))
  end)
end)
