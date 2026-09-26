-- 纯模块单测：水判定 common/MathWaterJudge.lua（M0-V1）。
-- 判定只读 pos 的 x/y/z、不碰引擎，所以这里能用普通 table 当坐标（试玩里传 Vector3 是同一套字段）。
-- 六个边界用例（#12 的验收：中心 / 水下 / 空中 / 贴边 ±0.1m / 远处陆地）+ 配置口径，
-- 用的就是 GameCfg.Water.Zones 的真值，改配置把边界改错了这里先红。
-- 末尾还钉住 GameCfg.FishCarrier 的 mesh id 写法与模型号号段（M0-V3 / #31）——那是 GameCfg 的另一处
-- 实测配置真值，写错鱼建不出来（F-7 的 [未查证] 已消除，见 common/GameCfg.lua 该段注释）。
local lu = require("luaunit")
local GameCfg = require("common.GameCfg")
local MathWaterJudge = require("common.MathWaterJudge")

-- 本图 2026-09-24 水平扩建两倍后的编辑器回读值：
--   WaterCircle1 Position(-11.75, 1.05, 27.75) Size(6, 1, 6) Scale(2, 1, 2)
--   WaterCircle2 Position(-11.75, 1.05, 27.75) Size(12, 1, 12) Scale(4, 1, 4)
local CENTER_X = -11.75
local CENTER_Z = 27.75
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

TestWaterJudgeBoundary = {}

-- 1) 中心：水圈正中心、水面下 0.1m。
function TestWaterJudgeBoundary:test_center_below_surface_is_in_water()
  lu.assertTrue(inWater(at(CENTER_X, UNDER_WATER_Y, CENTER_Z)))
end

-- 2) 水下：再深 1m 仍在水里（判定只要 y ≤ 水面，不设下限）。
function TestWaterJudgeBoundary:test_deep_underwater_is_in_water()
  lu.assertTrue(inWater(at(CENTER_X, SURFACE_Y - 1.0, CENTER_Z)))
end

-- 3) 空中：水面上 1m 不在水里。
function TestWaterJudgeBoundary:test_air_above_surface_is_not_in_water()
  lu.assertFalse(inWater(at(CENTER_X, AIR_Y, CENTER_Z)))
end

-- 4) 贴边 +0.1m：超出半宽 0.1m 不算在水里。
function TestWaterJudgeBoundary:test_edge_outside_by_point_one_meter_is_not_in_water()
  lu.assertFalse(inWater(at(CENTER_X + OUTER_HALF + 0.1, UNDER_WATER_Y, CENTER_Z)))
end

-- 5) 贴边 −0.1m：还在半宽以内，算在水里。
function TestWaterJudgeBoundary:test_edge_inside_by_point_one_meter_is_in_water()
  lu.assertTrue(inWater(at(CENTER_X + OUTER_HALF - 0.1, UNDER_WATER_Y, CENTER_Z)))
end

-- 6) 远处陆地：本图原点附近的岸上点，不在水里。
function TestWaterJudgeBoundary:test_far_land_is_not_in_water()
  lu.assertFalse(inWater(at(0, FLOOR_Y, 0)))
end

TestWaterJudgeSemantics = {}

-- 边界含等号：正好贴在半宽线上、正好落在水面高度上都算在水里。
function TestWaterJudgeSemantics:test_boundary_is_inclusive()
  lu.assertTrue(inWater(at(CENTER_X + OUTER_HALF, SURFACE_Y, CENTER_Z)))
  lu.assertTrue(inWater(at(CENTER_X, SURFACE_Y, CENTER_Z + OUTER_HALF)))
end

-- Z 轴与 X 轴对称（判定是「水平方框」不是圆）。
function TestWaterJudgeSemantics:test_z_axis_edge_matches_x_axis()
  lu.assertTrue(inWater(at(CENTER_X, UNDER_WATER_Y, CENTER_Z + OUTER_HALF - 0.1)))
  lu.assertFalse(inWater(at(CENTER_X, UNDER_WATER_Y, CENTER_Z + OUTER_HALF + 0.1)))
end

-- 水面 y≈2.183 高于大地板表面 y=2.0（#31 改正：Position.y 是底面、Size.y 是包围盒半长）：
-- 水区矩形内、站在地板高度上的点算在水里（那块地板就是池塘底），水面之上的点不算。
-- 这条是 W-7 那个实测关系的操作化——水面高度配低了，水里的点会被误判成岸上。
function TestWaterJudgeSemantics:test_point_at_floor_height_inside_pond_is_in_water()
  lu.assertTrue(zoneById("WaterCircle2").SurfaceY > FLOOR_Y)
  lu.assertTrue(inWater(at(CENTER_X, FLOOR_Y, CENTER_Z)))
  lu.assertFalse(inWater(at(CENTER_X, FLOOR_Y + 0.5, CENTER_Z)))
end

-- 两圈同心但半宽不同：外圈 6.0 / 内圈 3.0，所以 dx=5.0 的点只在外圈里。
function TestWaterJudgeSemantics:test_inner_circle_has_its_own_half_width()
  local outer = zoneById("WaterCircle2")
  local inner = zoneById("WaterCircle1")
  local pos = at(CENTER_X + 5.0, UNDER_WATER_Y, CENTER_Z)

  lu.assertTrue(MathWaterJudge.InZone(outer, pos))
  lu.assertFalse(MathWaterJudge.InZone(inner, pos))
end

-- 同心时按配置顺序命中排在前的那个（Build 的行为契约，M1 按水区选鱼表要看这个）。
function TestWaterJudgeSemantics:test_build_returns_the_first_matching_zone()
  local judge = MathWaterJudge.Build(zones())
  local hit = judge(at(CENTER_X, UNDER_WATER_Y, CENTER_Z))

  lu.assertEquals(hit.Id, "WaterCircle2")
  lu.assertIs(judge(at(CENTER_X, AIR_Y, CENTER_Z)), nil)
end

TestWaterJudgeConfig = {}

-- 配置口径：HalfXZ 直接写运行时半边尺寸，不再乘 Scale（WaterCircle2 的 Scale.x=4 已经算进 Size.x=12）。
-- 谁「顺手」把 3.0 改成 6.0（乘了缩放），这条先红。
function TestWaterJudgeConfig:test_half_width_does_not_multiply_scale()
  lu.assertEquals(zoneById("WaterCircle2").HalfXZ, OUTER_HALF)
  lu.assertEquals(zoneById("WaterCircle1").HalfXZ, 3.0)
end

function TestWaterJudgeConfig:test_center_and_surface_come_from_measured_values()
  for _, zone in ipairs(zones()) do
    if zone.Id == "WaterCircle1" or zone.Id == "WaterCircle2" then
      lu.assertEquals(zone.Center.x, CENTER_X)
      lu.assertEquals(zone.Center.z, CENTER_Z)
      lu.assertEquals(zone.SurfaceY, SURFACE_Y)
    end
  end
end

-- 配错要当场报错，不能静默退化成「永远不在水里」。
function TestWaterJudgeConfig:test_build_rejects_missing_field()
  lu.assertErrorMsgContains("SurfaceY", MathWaterJudge.Build, {
    { Id = "Bad", Center = { x = 0, z = 0 }, HalfXZ = 1.0 },
  })
end

function TestWaterJudgeConfig:test_build_rejects_non_positive_half_width()
  lu.assertErrorMsgContains("HalfXZ", MathWaterJudge.Build, {
    { Id = "Bad", Center = { x = 0, z = 0 }, HalfXZ = 0, SurfaceY = 1.0 },
  })
end

function TestWaterJudgeConfig:test_build_rejects_empty_zones()
  lu.assertErrorMsgContains("水区配置为空", MathWaterJudge.Build, {})
end

TestFishCarrierConfig = {}

-- mesh id 的写法守卫（M0-V3 / #31）：写进 RenderMeshId 的必须是 official://mesh/<模型号>。
-- 台账 §2.1 实测：official://preset/... 也能建出来但只是空壳（Size=(1,1,1)、无几何），
-- 所以谁把预设号写进 Mesh，这条先红。
function TestFishCarrierConfig:test_mesh_id_follows_the_official_uri_convention()
  local models, ids = carrierModels()

  for _, id in ipairs(ids) do
    local row = models[id]
    lu.assertEquals(row.Mesh, "official://mesh/" .. id)
    lu.assertNotEquals(row.Mesh, row.Preset)
    lu.assertEquals(row.Preset:sub(1, #PRESET_PREFIX), PRESET_PREFIX)
  end
end

-- 官方鱼模型库是 7000544–7000563 共 20 条、模型号连续，官方预设号一一对应且不重复。
-- 号段抄错、漏一条、或者把预设号错位挪一行，这条先红。
function TestFishCarrierConfig:test_official_fish_model_range_is_complete()
  local models, ids = carrierModels()
  local presets = {}

  lu.assertEquals(#ids, 20)
  for i, id in ipairs(ids) do
    lu.assertEquals(id, tostring(7000543 + i))
    lu.assertTrue(models[id].Name ~= nil and models[id].Name ~= "", id .. " 缺名称")

    local preset = models[id].Preset
    lu.assertTrue(presets[preset] == nil, "官方预设号重复：" .. preset)
    presets[preset] = true
  end
end
