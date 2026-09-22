-- 纯模块单测：水判定 common/MathWaterJudge.lua（M0-V1）。
-- 判定只读 pos 的 x/y/z、不碰引擎，所以这里能用普通 table 当坐标（试玩里传 Vector3 是同一套字段）。
-- 六个边界用例（#12 的验收：中心 / 水下 / 空中 / 贴边 ±0.1m / 远处陆地）+ 配置口径，
-- 用的就是 GameCfg.Water.Zones 的真值，改配置把边界改错了这里先红。
local lu = require("luaunit")
local GameCfg = require("common.GameCfg")
local MathWaterJudge = require("common.MathWaterJudge")

-- 本图实测值（#12，宿主目录 log.txt 2026-09-22 11:46:49 的 PROTO_WATER INSPECT 行）：
--   WaterCircle1 Position(-11.75, 1.05, 27.75) Size(3, 1, 3) Scale(1, 1, 1)
--   WaterCircle2 Position(-11.75, 1.05, 27.75) Size(6, 1, 6) Scale(2, 1, 2)
local CENTER_X = -11.75
local CENTER_Z = 27.75
local SURFACE_Y = 1.55 -- 1.05 + Size.y / 2
local OUTER_HALF = 3.0 -- WaterCircle2 的 Size.x / 2（Size 已含 Scale，不再乘 Scale）
local UNDER_WATER_Y = 1.45
local AIR_Y = 2.55
local FLOOR_Y = 2.0 -- 大地板的表面高度（射线实测命中 2.0）

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

-- 水面 y≈1.55 低于大地板表面 y=2.0（下凹池塘）：站在地板高度上的点不算在水里。
-- 这条是 W-7 那个实测关系的操作化——水面高度配高了，岸上会被误判成水里。
function TestWaterJudgeSemantics:test_point_at_floor_height_is_not_in_water()
  lu.assertTrue(FLOOR_Y > zoneById("WaterCircle2").SurfaceY)
  lu.assertFalse(inWater(at(CENTER_X, FLOOR_Y, CENTER_Z)))
end

-- 两圈同心但半宽不同：外圈 3.0 / 内圈 1.5，所以 dx=2.5 的点只在外圈里。
function TestWaterJudgeSemantics:test_inner_circle_has_its_own_half_width()
  local outer = zoneById("WaterCircle2")
  local inner = zoneById("WaterCircle1")
  local pos = at(CENTER_X + 2.5, UNDER_WATER_Y, CENTER_Z)

  lu.assertTrue(MathWaterJudge.InZone(outer, pos))
  lu.assertFalse(MathWaterJudge.InZone(inner, pos))
end

-- 同心时按配置顺序命中排在前的那个（Build 的行为契约，M1 按水区选鱼表要看这个）。
function TestWaterJudgeSemantics:test_build_returns_the_first_matching_zone()
  local judge = MathWaterJudge.Build(zones())
  local hit = judge(at(CENTER_X, UNDER_WATER_Y, CENTER_Z))

  lu.assertEquals(hit.Id, "WaterCircle2")
  lu.assertIs(judge(at(CENTER_X, FLOOR_Y, CENTER_Z)), nil)
end

TestWaterJudgeConfig = {}

-- 配置口径：HalfXZ 直接写运行时半边尺寸，不再乘 Scale（WaterCircle2 的 Scale.x=2 已经算进 Size.x=6）。
-- 谁「顺手」把 3.0 改成 6.0（乘了缩放），这条先红。
function TestWaterJudgeConfig:test_half_width_does_not_multiply_scale()
  lu.assertEquals(zoneById("WaterCircle2").HalfXZ, OUTER_HALF)
  lu.assertEquals(zoneById("WaterCircle1").HalfXZ, 1.5)
end

function TestWaterJudgeConfig:test_center_and_surface_come_from_measured_values()
  for _, zone in ipairs(zones()) do
    lu.assertEquals(zone.Center.x, CENTER_X)
    lu.assertEquals(zone.Center.z, CENTER_Z)
    lu.assertEquals(zone.SurfaceY, SURFACE_Y)
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
