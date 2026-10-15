-- #65 P3 七区灰盒布局施工探针（编辑器侧，**会写场景**）。
--
-- 复跑：
--   lua tools/gen_zone_layout_probe.lua                       # 按 tools/plan_zone_layout.lua 重生成数据块
--   editor-cli exec --file tests/probes/zone_layout_apply.lua --expect-edit-mode --timeout 180 --json
--   editor-cli log grep P3LAYOUT65 --platform editor --context 0 --max-matches 400 --json
--
-- 口径（已拍板，见 tools/plan_zone_layout.lua 头注）：
--   * 地面基准 = 合同 `Scene.SafePoint.y`（后五区 6.00）；水塘式：水面保持数学 `SurfaceY` 留在岸下。
--   * pivot 按 P1 实测：`Position` 是 X/Z 中心、Y 底面；`Size = Scale × 预设基准盒`。
--   * 数据块由 `tools/gen_zone_layout_probe.lua` 从 `tools/plan_zone_layout.lua` 生成，**不要手改**；
--     fast 车道的 tests/native/zone_layout_plan_test.lua 会逐字节校验它与规划器同步。
--
-- 安全与幂等：
--   * `APPLY = false` 时只查找 + 回读，不写任何东西（可用于先核对目标是否存在）。
--   * 幂等：先按名字找；找到就只改位姿/父级，找不到且该条带资产才创建。重复运行不会堆单位。
--   * 只碰数据块里点名的单位与它创建的单位；不动别的东西。写完必须 `map save` 并重开核验。
local MARK = 'P3LAYOUT65'
-- 'apply' = 按规划施工；'revert' = 恢复 P2 基线位姿并删除本批新建单位；APPLY = false 时只读。
local MODE = 'apply'
local APPLY = true

-- >>> GENERATED ZONE LAYOUT OPS（由 tools/gen_zone_layout_probe.lua 生成）
local ZONE_OPS = {
  { label = '02 虾池', groundY = 6.00, ops = {
    { name = 'Z2_Land', asset = 'official://preset/1101661', parent = '地块', position = { 240.00, 0.00, 8.25 }, scale = { 12.000000000, 6.000000000, 8.050000000 } },
    { name = 'Z2_Bank', asset = 'official://preset/1101661', parent = '地块', position = { 240.00, 0.00, -62.25 }, scale = { 12.000000000, 6.000000000, 1.250000000 } },
    { name = 'Z2_PondFloor', asset = 'official://preset/1101661', parent = '地块', position = { 240.00, -6.00, -44.00 }, scale = { 8.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z2_LandSideX190', asset = 'official://preset/1101661', parent = '地块', position = { 190.00, 0.00, -44.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z2_LandSideX290', asset = 'official://preset/1101661', parent = '地块', position = { 290.00, 0.00, -44.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z2_Ridge192', asset = 'official://preset/1204002', parent = '地块', position = { 192.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z2_Ridge220', asset = 'official://preset/1204002', parent = '地块', position = { 220.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z2_Ridge260', asset = 'official://preset/1204002', parent = '地块', position = { 260.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z2_Ridge288', asset = 'official://preset/1204002', parent = '地块', position = { 288.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z2_RidgeIn195', asset = 'official://preset/1204002', parent = '地块', position = { 195.00, 6.00, 42.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z2_RidgeIn285', asset = 'official://preset/1204002', parent = '地块', position = { 285.00, 6.00, 42.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'TGUnitFishShrimp', asset = nil, parent = nil, position = { 213.00, 6.00, -17.00 }, scale = nil },
    { name = 'TGUnitShopShrimp', asset = nil, parent = nil, position = { 216.00, 6.00, 13.00 }, scale = nil },
    { name = 'Z2_Lottery', asset = nil, parent = nil, position = { 258.00, 6.00, -18.00 }, scale = nil },
    { name = 'Z2_Bait1', asset = 'official://preset/1101635', parent = '设施', position = { 188.00, 6.00, -24.00 }, scale = { 0.500000000, 0.500000000, 0.500000000 } },
    { name = 'Z2_Bait2', asset = 'official://preset/1101635', parent = '设施', position = { 292.00, 6.00, -24.00 }, scale = { 0.500000000, 0.500000000, 0.500000000 } },
    { name = 'Z2_FerryOut', asset = nil, parent = nil, position = { 215.00, 6.00, 40.50 }, scale = nil },
    { name = 'FerryReturn', asset = nil, parent = nil, position = { 265.00, 6.00, 40.50 }, scale = nil },
    { name = 'Z2_Safe', asset = 'official://preset/1101661', parent = '摆渡', position = { 240.00, 5.80, 30.50 }, scale = { 1.000000000, 0.200000000, 1.000000000 } },
    { name = 'Z2_Water', asset = 'map://preset/u54263b69f25482dae18f9dbcfe6dc5b', parent = '地块', position = { 240.00, 2.00, -44.00 }, scale = { 26.666666667, 1.000000000, 8.000000000 }, waterMesh = 'official://mesh/59269' },
    { name = 'Z2_BoundaryEast', asset = nil, parent = nil, position = { 180.00, -30.00, -10.00 }, scale = { 1.000000000, 23.333333333, 40.000000000 } },
    { name = 'Z2_BoundaryWest', asset = nil, parent = nil, position = { 300.00, -30.00, -10.00 }, scale = { 1.000000000, 23.333333333, 40.000000000 } },
    { name = 'Z2_BoundaryNorth', asset = nil, parent = nil, position = { 240.00, -30.00, -70.00 }, scale = { 40.000000000, 23.333333333, 1.000000000 } },
    { name = 'Z2_BoundarySouth', asset = nil, parent = nil, position = { 240.00, -30.00, 50.00 }, scale = { 40.000000000, 23.333333333, 1.000000000 } },
  } },
  { label = '03 蟹湖', groundY = 6.00, ops = {
    { name = 'Z3_Land', asset = 'official://preset/1101661', parent = '地块', position = { 480.00, 0.00, 8.25 }, scale = { 12.000000000, 6.000000000, 8.050000000 } },
    { name = 'Z3_Bank', asset = 'official://preset/1101661', parent = '地块', position = { 480.00, 0.00, -62.25 }, scale = { 12.000000000, 6.000000000, 1.250000000 } },
    { name = 'Z3_PondFloor', asset = 'official://preset/1101661', parent = '地块', position = { 480.00, -6.00, -44.00 }, scale = { 8.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z3_LandSideX430', asset = 'official://preset/1101661', parent = '地块', position = { 430.00, 0.00, -44.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z3_LandSideX530', asset = 'official://preset/1101661', parent = '地块', position = { 530.00, 0.00, -44.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z3_Ridge432', asset = 'official://preset/1204002', parent = '地块', position = { 432.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z3_Ridge460', asset = 'official://preset/1204002', parent = '地块', position = { 460.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z3_Ridge500', asset = 'official://preset/1204002', parent = '地块', position = { 500.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z3_Ridge528', asset = 'official://preset/1204002', parent = '地块', position = { 528.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z3_RidgeIn435', asset = 'official://preset/1204002', parent = '地块', position = { 435.00, 6.00, 42.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z3_RidgeIn525', asset = 'official://preset/1204002', parent = '地块', position = { 525.00, 6.00, 42.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z3_Fisherman', asset = nil, parent = nil, position = { 449.00, 6.00, -17.00 }, scale = nil },
    { name = 'Z3_Shop', asset = nil, parent = nil, position = { 452.00, 6.00, 21.00 }, scale = nil },
    { name = 'Z3_Lottery', asset = nil, parent = nil, position = { 502.00, 6.00, -18.00 }, scale = nil },
    { name = 'Z3_Grill', asset = nil, parent = nil, position = { 502.00, 6.00, 11.00 }, scale = nil },
    { name = 'Z3_Bait1', asset = nil, parent = nil, position = { 428.00, 6.00, -24.00 }, scale = nil },
    { name = 'Z3_Bait2', asset = nil, parent = nil, position = { 532.00, 6.00, -24.00 }, scale = nil },
    { name = 'Z3_FerryOut', asset = nil, parent = nil, position = { 455.00, 6.00, 40.50 }, scale = nil },
    { name = 'Z3_FerryReturn', asset = nil, parent = nil, position = { 505.00, 6.00, 40.50 }, scale = nil },
    { name = 'Z3_Safe', asset = nil, parent = nil, position = { 480.00, 5.80, 30.50 }, scale = nil },
  } },
  { label = '04 树林岛', groundY = 6.00, ops = {
    { name = 'Z4_Land', asset = 'official://preset/1101661', parent = '地块', position = { 720.00, 0.00, 8.25 }, scale = { 12.000000000, 6.000000000, 8.050000000 } },
    { name = 'Z4_Bank', asset = 'official://preset/1101661', parent = '地块', position = { 720.00, 0.00, -62.25 }, scale = { 12.000000000, 6.000000000, 1.250000000 } },
    { name = 'Z4_PondFloor', asset = 'official://preset/1101661', parent = '地块', position = { 720.00, -6.00, -44.00 }, scale = { 8.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z4_LandSideX670', asset = 'official://preset/1101661', parent = '地块', position = { 670.00, 0.00, -44.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z4_LandSideX770', asset = 'official://preset/1101661', parent = '地块', position = { 770.00, 0.00, -44.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z4_Ridge672', asset = 'official://preset/1204002', parent = '地块', position = { 672.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z4_Ridge700', asset = 'official://preset/1204002', parent = '地块', position = { 700.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z4_Ridge740', asset = 'official://preset/1204002', parent = '地块', position = { 740.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z4_Ridge768', asset = 'official://preset/1204002', parent = '地块', position = { 768.00, 6.00, -62.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z4_RidgeIn675', asset = 'official://preset/1204002', parent = '地块', position = { 675.00, 6.00, 42.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z4_RidgeIn765', asset = 'official://preset/1204002', parent = '地块', position = { 765.00, 6.00, 42.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z4_Fisherman', asset = nil, parent = nil, position = { 685.00, 6.00, -17.00 }, scale = nil },
    { name = 'Z4_Shop', asset = nil, parent = nil, position = { 688.00, 6.00, 29.00 }, scale = nil },
    { name = 'Z4_Lottery', asset = nil, parent = nil, position = { 746.00, 6.00, -18.00 }, scale = nil },
    { name = 'Z4_Grill', asset = nil, parent = nil, position = { 746.00, 6.00, 19.00 }, scale = nil },
    { name = 'Z4_Bait1', asset = nil, parent = nil, position = { 668.00, 6.00, -24.00 }, scale = nil },
    { name = 'Z4_Bait2', asset = nil, parent = nil, position = { 772.00, 6.00, -24.00 }, scale = nil },
    { name = 'Z4_FerryOut', asset = nil, parent = nil, position = { 695.00, 6.00, 40.50 }, scale = nil },
    { name = 'Z4_FerryReturn', asset = nil, parent = nil, position = { 745.00, 6.00, 40.50 }, scale = nil },
    { name = 'Z4_Safe', asset = nil, parent = nil, position = { 720.00, 5.80, 30.50 }, scale = nil },
  } },
  { label = '05 沙滩岛', groundY = 6.00, ops = {
    { name = 'Z5_Land', asset = 'official://preset/1101661', parent = '地块', position = { 720.00, 0.00, 311.75 }, scale = { 12.000000000, 6.000000000, 8.050000000 } },
    { name = 'Z5_Bank', asset = 'official://preset/1101661', parent = '地块', position = { 720.00, 0.00, 382.25 }, scale = { 12.000000000, 6.000000000, 1.250000000 } },
    { name = 'Z5_PondFloor', asset = 'official://preset/1101661', parent = '地块', position = { 720.00, -6.00, 364.00 }, scale = { 8.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z5_LandSideX670', asset = 'official://preset/1101661', parent = '地块', position = { 670.00, 0.00, 364.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z5_LandSideX770', asset = 'official://preset/1101661', parent = '地块', position = { 770.00, 0.00, 364.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z5_Ridge672', asset = 'official://preset/1204002', parent = '地块', position = { 672.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z5_Ridge700', asset = 'official://preset/1204002', parent = '地块', position = { 700.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z5_Ridge740', asset = 'official://preset/1204002', parent = '地块', position = { 740.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z5_Ridge768', asset = 'official://preset/1204002', parent = '地块', position = { 768.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z5_RidgeIn675', asset = 'official://preset/1204002', parent = '地块', position = { 675.00, 6.00, 277.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z5_RidgeIn765', asset = 'official://preset/1204002', parent = '地块', position = { 765.00, 6.00, 277.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z5_Fisherman', asset = nil, parent = nil, position = { 755.00, 6.00, 337.00 }, scale = nil },
    { name = 'Z5_Shop', asset = nil, parent = nil, position = { 752.00, 6.00, 291.00 }, scale = nil },
    { name = 'Z5_Lottery', asset = nil, parent = nil, position = { 694.00, 6.00, 338.00 }, scale = nil },
    { name = 'Z5_Grill', asset = nil, parent = nil, position = { 694.00, 6.00, 301.00 }, scale = nil },
    { name = 'Z5_Bait1', asset = nil, parent = nil, position = { 668.00, 6.00, 344.00 }, scale = nil },
    { name = 'Z5_Bait2', asset = nil, parent = nil, position = { 772.00, 6.00, 344.00 }, scale = nil },
    { name = 'Z5_FerryOut', asset = nil, parent = nil, position = { 745.00, 6.00, 279.50 }, scale = nil },
    { name = 'Z5_FerryReturn', asset = nil, parent = nil, position = { 695.00, 6.00, 279.50 }, scale = nil },
    { name = 'Z5_Safe', asset = nil, parent = nil, position = { 720.00, 5.80, 289.50 }, scale = nil },
  } },
  { label = '06 礁石岛', groundY = 6.00, ops = {
    { name = 'Z6_Land', asset = 'official://preset/1101661', parent = '地块', position = { 480.00, 0.00, 311.75 }, scale = { 12.000000000, 6.000000000, 8.050000000 } },
    { name = 'Z6_Bank', asset = 'official://preset/1101661', parent = '地块', position = { 480.00, 0.00, 382.25 }, scale = { 12.000000000, 6.000000000, 1.250000000 } },
    { name = 'Z6_PondFloor', asset = 'official://preset/1101661', parent = '地块', position = { 480.00, -6.00, 364.00 }, scale = { 8.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z6_LandSideX430', asset = 'official://preset/1101661', parent = '地块', position = { 430.00, 0.00, 364.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z6_LandSideX530', asset = 'official://preset/1101661', parent = '地块', position = { 530.00, 0.00, 364.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z6_Ridge432', asset = 'official://preset/1204002', parent = '地块', position = { 432.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z6_Ridge460', asset = 'official://preset/1204002', parent = '地块', position = { 460.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z6_Ridge500', asset = 'official://preset/1204002', parent = '地块', position = { 500.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z6_Ridge528', asset = 'official://preset/1204002', parent = '地块', position = { 528.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z6_RidgeIn435', asset = 'official://preset/1204002', parent = '地块', position = { 435.00, 6.00, 277.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z6_RidgeIn525', asset = 'official://preset/1204002', parent = '地块', position = { 525.00, 6.00, 277.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z6_Fisherman', asset = nil, parent = nil, position = { 519.00, 6.00, 337.00 }, scale = nil },
    { name = 'Z6_Shop', asset = nil, parent = nil, position = { 516.00, 6.00, 287.00 }, scale = nil },
    { name = 'Z6_Lottery', asset = nil, parent = nil, position = { 450.00, 6.00, 338.00 }, scale = nil },
    { name = 'Z6_Grill', asset = nil, parent = nil, position = { 450.00, 6.00, 297.00 }, scale = nil },
    { name = 'Z6_Bait1', asset = nil, parent = nil, position = { 428.00, 6.00, 344.00 }, scale = nil },
    { name = 'Z6_Bait2', asset = nil, parent = nil, position = { 532.00, 6.00, 344.00 }, scale = nil },
    { name = 'Z6_FerryOut', asset = nil, parent = nil, position = { 505.00, 6.00, 279.50 }, scale = nil },
    { name = 'Z6_FerryReturn', asset = nil, parent = nil, position = { 455.00, 6.00, 279.50 }, scale = nil },
    { name = 'Z6_Safe', asset = nil, parent = nil, position = { 480.00, 5.80, 289.50 }, scale = nil },
  } },
  { label = '07 火山岛', groundY = 6.00, ops = {
    { name = 'Z7_Land', asset = 'official://preset/1101661', parent = '地块', position = { 240.00, 0.00, 311.75 }, scale = { 12.000000000, 6.000000000, 8.050000000 } },
    { name = 'Z7_Bank', asset = 'official://preset/1101661', parent = '地块', position = { 240.00, 0.00, 382.25 }, scale = { 12.000000000, 6.000000000, 1.250000000 } },
    { name = 'Z7_PondFloor', asset = 'official://preset/1101661', parent = '地块', position = { 240.00, -6.00, 364.00 }, scale = { 8.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z7_LandSideX190', asset = 'official://preset/1101661', parent = '地块', position = { 190.00, 0.00, 364.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z7_LandSideX290', asset = 'official://preset/1101661', parent = '地块', position = { 290.00, 0.00, 364.00 }, scale = { 2.000000000, 6.000000000, 2.400000000 } },
    { name = 'Z7_Ridge192', asset = 'official://preset/1204002', parent = '地块', position = { 192.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z7_Ridge220', asset = 'official://preset/1204002', parent = '地块', position = { 220.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z7_Ridge260', asset = 'official://preset/1204002', parent = '地块', position = { 260.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z7_Ridge288', asset = 'official://preset/1204002', parent = '地块', position = { 288.00, 6.00, 382.25 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z7_RidgeIn195', asset = 'official://preset/1204002', parent = '地块', position = { 195.00, 6.00, 277.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z7_RidgeIn285', asset = 'official://preset/1204002', parent = '地块', position = { 285.00, 6.00, 277.50 }, scale = { 0.500000000, 1.200000000, 0.500000000 } },
    { name = 'Z7_Fisherman', asset = nil, parent = nil, position = { 279.00, 6.00, 337.00 }, scale = nil },
    { name = 'Z7_Shop', asset = nil, parent = nil, position = { 276.00, 6.00, 287.00 }, scale = nil },
    { name = 'Z7_Lottery', asset = nil, parent = nil, position = { 210.00, 6.00, 338.00 }, scale = nil },
    { name = 'Z7_Grill', asset = nil, parent = nil, position = { 210.00, 6.00, 297.00 }, scale = nil },
    { name = 'Z7_Bait1', asset = nil, parent = nil, position = { 188.00, 6.00, 344.00 }, scale = nil },
    { name = 'Z7_Bait2', asset = nil, parent = nil, position = { 292.00, 6.00, 344.00 }, scale = nil },
    { name = 'Z7_FerryReturn', asset = nil, parent = nil, position = { 215.00, 6.00, 279.50 }, scale = nil },
    { name = 'Z7_Safe', asset = nil, parent = nil, position = { 240.00, 5.80, 289.50 }, scale = nil },
  } },
}
-- ZONE_REVERT 只在 MODE = 'revert' 时使用：恢复基线位姿 + 删除本批新建单位。
local ZONE_REVERT = {
  { label = '02 虾池', ops = {
    { op = 'restore', name = 'FerryReturn', position = { 240.00, 5.00, -3.00 }, scale = { 0.20, 0.20, 0.20 } },
    { op = 'restore', name = 'Z2_FerryOut', position = { 225.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z2_BoundaryEast', position = { 215.00, -30.00, -10.00 }, scale = { 1.00, 23.33, 40.00 } },
    { op = 'restore', name = 'Z2_BoundaryNorth', position = { 240.00, -30.00, -70.00 }, scale = { 16.67, 23.33, 1.00 } },
    { op = 'restore', name = 'Z2_BoundarySouth', position = { 240.00, -30.00, 50.00 }, scale = { 16.67, 23.33, 1.00 } },
    { op = 'restore', name = 'Z2_BoundaryWest', position = { 265.00, -30.00, -10.00 }, scale = { 1.00, 23.33, 40.00 } },
    { op = 'restore', name = 'TGUnitFishShrimp', position = { 246.00, -4.00, 0.00 }, scale = { 3.00, 3.00, 3.00 } },
    { op = 'restore', name = 'TGUnitShopShrimp', position = { 234.00, -0.50, 3.00 }, scale = { 2.00, 2.00, 2.00 } },
    { op = 'restore', name = 'Z2_Lottery', position = { 235.00, 5.00, -5.00 }, scale = { 1.50, 1.50, 1.50 } },
    { op = 'delete', name = 'Z2_Bait1' },
    { op = 'delete', name = 'Z2_Bait2' },
    { op = 'delete', name = 'Z2_Bank' },
    { op = 'delete', name = 'Z2_Land' },
    { op = 'delete', name = 'Z2_LandSideX190' },
    { op = 'delete', name = 'Z2_LandSideX290' },
    { op = 'delete', name = 'Z2_PondFloor' },
    { op = 'delete', name = 'Z2_Ridge192' },
    { op = 'delete', name = 'Z2_Ridge220' },
    { op = 'delete', name = 'Z2_Ridge260' },
    { op = 'delete', name = 'Z2_Ridge288' },
    { op = 'delete', name = 'Z2_RidgeIn195' },
    { op = 'delete', name = 'Z2_RidgeIn285' },
    { op = 'delete', name = 'Z2_Safe' },
    { op = 'delete', name = 'Z2_Water' },
  } },
  { label = '03 蟹湖', ops = {
    { op = 'restore', name = 'Z3_Land', position = { 480.00, 0.00, 0.00 }, scale = { 12.00, 2.00, 14.00 } },
    { op = 'restore', name = 'Z3_FerryOut', position = { 465.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z3_FerryReturn', position = { 495.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z3_Safe', position = { 480.00, 6.00, 0.00 }, scale = { 1.00, 0.20, 1.00 } },
    { op = 'restore', name = 'Z3_Bait1', position = { 483.00, 6.00, 3.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z3_Bait2', position = { 477.00, 6.00, 3.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z3_Fisherman', position = { 500.00, 5.00, 0.00 }, scale = { 3.00, 3.00, 3.00 } },
    { op = 'restore', name = 'Z3_Grill', position = { 490.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z3_Lottery', position = { 475.00, 5.00, -5.00 }, scale = { 1.50, 1.50, 1.50 } },
    { op = 'restore', name = 'Z3_Shop', position = { 460.00, 5.00, 0.00 }, scale = { 2.00, 2.00, 2.00 } },
    { op = 'delete', name = 'Z3_Bank' },
    { op = 'delete', name = 'Z3_LandSideX430' },
    { op = 'delete', name = 'Z3_LandSideX530' },
    { op = 'delete', name = 'Z3_PondFloor' },
    { op = 'delete', name = 'Z3_Ridge432' },
    { op = 'delete', name = 'Z3_Ridge460' },
    { op = 'delete', name = 'Z3_Ridge500' },
    { op = 'delete', name = 'Z3_Ridge528' },
    { op = 'delete', name = 'Z3_RidgeIn435' },
    { op = 'delete', name = 'Z3_RidgeIn525' },
  } },
  { label = '04 树林岛', ops = {
    { op = 'restore', name = 'Z4_Land', position = { 720.00, 0.00, 0.00 }, scale = { 12.00, 2.00, 14.00 } },
    { op = 'restore', name = 'Z4_FerryOut', position = { 705.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z4_FerryReturn', position = { 735.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z4_Safe', position = { 720.00, 6.00, 0.00 }, scale = { 1.00, 0.20, 1.00 } },
    { op = 'restore', name = 'Z4_Bait1', position = { 723.00, 6.00, 3.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z4_Bait2', position = { 717.00, 6.00, 3.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z4_Fisherman', position = { 740.00, 5.00, 0.00 }, scale = { 3.00, 3.00, 3.00 } },
    { op = 'restore', name = 'Z4_Grill', position = { 730.00, 5.00, 10.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z4_Lottery', position = { 715.00, 5.00, -5.00 }, scale = { 1.50, 1.50, 1.50 } },
    { op = 'restore', name = 'Z4_Shop', position = { 700.00, 5.00, 0.00 }, scale = { 2.00, 2.00, 2.00 } },
    { op = 'delete', name = 'Z4_Bank' },
    { op = 'delete', name = 'Z4_LandSideX670' },
    { op = 'delete', name = 'Z4_LandSideX770' },
    { op = 'delete', name = 'Z4_PondFloor' },
    { op = 'delete', name = 'Z4_Ridge672' },
    { op = 'delete', name = 'Z4_Ridge700' },
    { op = 'delete', name = 'Z4_Ridge740' },
    { op = 'delete', name = 'Z4_Ridge768' },
    { op = 'delete', name = 'Z4_RidgeIn675' },
    { op = 'delete', name = 'Z4_RidgeIn765' },
  } },
  { label = '05 沙滩岛', ops = {
    { op = 'restore', name = 'Z5_Land', position = { 720.00, 0.00, 320.00 }, scale = { 12.00, 2.00, 14.00 } },
    { op = 'restore', name = 'Z5_FerryOut', position = { 735.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z5_FerryReturn', position = { 705.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z5_Safe', position = { 720.00, 6.00, 320.00 }, scale = { 1.00, 0.20, 1.00 } },
    { op = 'restore', name = 'Z5_Bait1', position = { 717.00, 6.00, 317.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z5_Bait2', position = { 723.00, 6.00, 317.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z5_Fisherman', position = { 700.00, 5.00, 320.00 }, scale = { 3.00, 3.00, 3.00 } },
    { op = 'restore', name = 'Z5_Grill', position = { 710.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z5_Lottery', position = { 725.00, 5.00, 325.00 }, scale = { 1.50, 1.50, 1.50 } },
    { op = 'restore', name = 'Z5_Shop', position = { 740.00, 5.00, 320.00 }, scale = { 2.00, 2.00, 2.00 } },
    { op = 'delete', name = 'Z5_Bank' },
    { op = 'delete', name = 'Z5_LandSideX670' },
    { op = 'delete', name = 'Z5_LandSideX770' },
    { op = 'delete', name = 'Z5_PondFloor' },
    { op = 'delete', name = 'Z5_Ridge672' },
    { op = 'delete', name = 'Z5_Ridge700' },
    { op = 'delete', name = 'Z5_Ridge740' },
    { op = 'delete', name = 'Z5_Ridge768' },
    { op = 'delete', name = 'Z5_RidgeIn675' },
    { op = 'delete', name = 'Z5_RidgeIn765' },
  } },
  { label = '06 礁石岛', ops = {
    { op = 'restore', name = 'Z6_Land', position = { 480.00, 0.00, 320.00 }, scale = { 12.00, 2.00, 14.00 } },
    { op = 'restore', name = 'Z6_FerryOut', position = { 495.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z6_FerryReturn', position = { 465.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z6_Safe', position = { 480.00, 6.00, 320.00 }, scale = { 1.00, 0.20, 1.00 } },
    { op = 'restore', name = 'Z6_Bait1', position = { 477.00, 6.00, 317.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z6_Bait2', position = { 483.00, 6.00, 317.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z6_Fisherman', position = { 460.00, 5.00, 320.00 }, scale = { 3.00, 3.00, 3.00 } },
    { op = 'restore', name = 'Z6_Grill', position = { 470.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z6_Lottery', position = { 485.00, 5.00, 325.00 }, scale = { 1.50, 1.50, 1.50 } },
    { op = 'restore', name = 'Z6_Shop', position = { 500.00, 5.00, 320.00 }, scale = { 2.00, 2.00, 2.00 } },
    { op = 'delete', name = 'Z6_Bank' },
    { op = 'delete', name = 'Z6_LandSideX430' },
    { op = 'delete', name = 'Z6_LandSideX530' },
    { op = 'delete', name = 'Z6_PondFloor' },
    { op = 'delete', name = 'Z6_Ridge432' },
    { op = 'delete', name = 'Z6_Ridge460' },
    { op = 'delete', name = 'Z6_Ridge500' },
    { op = 'delete', name = 'Z6_Ridge528' },
    { op = 'delete', name = 'Z6_RidgeIn435' },
    { op = 'delete', name = 'Z6_RidgeIn525' },
  } },
  { label = '07 火山岛', ops = {
    { op = 'restore', name = 'Z7_Land', position = { 240.00, 0.00, 320.00 }, scale = { 12.00, 2.00, 14.00 } },
    { op = 'restore', name = 'Z7_FerryReturn', position = { 225.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z7_Safe', position = { 240.00, 6.00, 320.00 }, scale = { 1.00, 0.20, 1.00 } },
    { op = 'restore', name = 'Z7_Bait1', position = { 237.00, 6.00, 317.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z7_Bait2', position = { 243.00, 6.00, 317.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z7_Fisherman', position = { 220.00, 5.00, 320.00 }, scale = { 3.00, 3.00, 3.00 } },
    { op = 'restore', name = 'Z7_Grill', position = { 230.00, 5.00, 310.00 }, scale = { 0.50, 0.50, 0.50 } },
    { op = 'restore', name = 'Z7_Lottery', position = { 245.00, 5.00, 325.00 }, scale = { 1.50, 1.50, 1.50 } },
    { op = 'restore', name = 'Z7_Shop', position = { 260.00, 5.00, 320.00 }, scale = { 2.00, 2.00, 2.00 } },
    { op = 'delete', name = 'Z7_Bank' },
    { op = 'delete', name = 'Z7_LandSideX190' },
    { op = 'delete', name = 'Z7_LandSideX290' },
    { op = 'delete', name = 'Z7_PondFloor' },
    { op = 'delete', name = 'Z7_Ridge192' },
    { op = 'delete', name = 'Z7_Ridge220' },
    { op = 'delete', name = 'Z7_Ridge260' },
    { op = 'delete', name = 'Z7_Ridge288' },
    { op = 'delete', name = 'Z7_RidgeIn195' },
    { op = 'delete', name = 'Z7_RidgeIn285' },
  } },
}
-- <<< GENERATED ZONE LAYOUT OPS

local world = editor:GetService('World')
local function emit(line) print(MARK .. '|' .. line) end
local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if not ok then return fallback end
    return value
end
local function num(value)
    if type(value) ~= 'number' then return '-' end
    -- 沙盒里没有 math.huge（实测为 nil），NaN/inf 用字面量兜：不能写 math.huge。
    if value ~= value or value > 1e30 or value < -1e30 then return '-' end
    return string.format('%.3f', value)
end
local function comp(v, i)
    if type(v) ~= 'table' then return nil end
    if v.x ~= nil then
        if i == 1 then return v.x elseif i == 2 then return v.y else return v.z end
    end
    return v[i]
end
local function vec(v)
    if type(v) ~= 'table' then return '-' end
    return num(comp(v, 1)) .. ',' .. num(comp(v, 2)) .. ',' .. num(comp(v, 3))
end
local function unitName(unit)
    return tostring(safe(function() return unit:GetName() end, safe(function() return unit.Name end, '?')))
end

local counters = { ops = 0, created = 0, moved = 0, miss = 0, failed = 0, deleted = 0 }

if MODE == 'revert' then
    -- 回滚：把基线位姿写回去，并删掉本批新建的单位（只删规划里造出来的名字）。
    for _, zone in ipairs(ZONE_REVERT) do
        emit(('ZONE|%s|mode=revert|ops=%d'):format(zone.label, #zone.ops))
        for _, op in ipairs(zone.ops) do
            counters.ops = counters.ops + 1
            local unit = safe(function() return world:FindFirstChild(op.name) end, nil)
            if unit == nil then
                counters.miss = counters.miss + 1
                emit(('OP|%s|%s|%s|MISS'):format(zone.label, op.op, op.name))
            else
                local ok = true
                if APPLY then
                    if op.op == 'restore' then
                        ok = pcall(function() return unit:SetPosition(Vector3.New(op.position[1], op.position[2], op.position[3])) end)
                        ok = pcall(function() return unit:SetScale(Vector3.New(op.scale[1], op.scale[2], op.scale[3])) end) and ok
                    else
                        ok = pcall(function() return unit:Destroy() end)
                        counters.deleted = counters.deleted + 1
                    end
                end
                if not ok then counters.failed = counters.failed + 1 end
                local pos = safe(function() return unit:GetPosition() end, nil)
                local size = safe(function() return unit:GetProperty('Size') end, nil)
                emit(('OP|%s|%s|%s|write=%s|pos=%s|size=%s'):format(zone.label, op.op, op.name,
                    tostring(ok), vec(pos), vec(size)))
            end
        end
    end
    emit(('SUMMARY|mode=revert|ops=%d|restored=%d|deleted=%d|miss=%d|failed=%d|apply=%s'):format(
        counters.ops, counters.ops - counters.deleted - counters.miss, counters.deleted,
        counters.miss, counters.failed, tostring(APPLY)))
    return MARK .. ' done mode=revert apply=' .. tostring(APPLY) .. ' ops=' .. tostring(counters.ops)
end

for _, zone in ipairs(ZONE_OPS) do
    local zoneUnit = safe(function() return world:FindFirstChild(zone.label) end, nil)
    local folders = {}
    local function parentFor(name)
        if not name or not zoneUnit then return nil end
        if folders[name] then return folders[name] end
        local folder = zoneUnit:FindFirstChild(name)
        if not folder then error('目标分组不存在：' .. zone.label .. '/' .. name) end
        folders[name] = folder
        return folder
    end
    emit(('ZONE|%s|found=%s|ops=%d'):format(zone.label, tostring(zoneUnit ~= nil), #zone.ops))
    for _, op in ipairs(zone.ops) do
        counters.ops = counters.ops + 1
        local unit = safe(function() return world:FindFirstChild(op.name) end, nil)
        local created = false
        if unit == nil and op.asset and APPLY then
            local ok, list = pcall(function()
                return world:CreateAsset(op.asset,
                    Vector3.New(op.position[1], op.position[2], op.position[3]),
                    { scale = Vector3.New(op.scale[1], op.scale[2], op.scale[3]) })
            end)
            if not ok then
                emit('ERROR|' .. zone.label .. '|' .. op.name .. '|CreateAsset|' .. tostring(list))
                error('创建失败：' .. op.name)
            end
            if type(list) == 'table' and list[1] ~= nil then
                unit = list[1]
                created = true
            end
        end
        if unit == nil then
            counters.miss = counters.miss + 1
            emit(('OP|%s|%s|MISS|asset=%s'):format(zone.label, op.name, tostring(op.asset)))
        else
            local ok = true
            if APPLY then
                local writeError
                ok, writeError = pcall(function()
                    if created then unit:SetName(op.name) end
                    if op.waterMesh then
                        unit:DestroyChildren()
                        unit:SetProperty('RenderMeshId', op.waterMesh)
                        unit:SetProperty('PhysicsMeshId', op.waterMesh)
                        unit:SetProperty('CanCollide', false)
                    end
                    unit:SetPosition(Vector3.New(op.position[1], op.position[2], op.position[3]))
                    if op.scale then unit:SetScale(Vector3.New(op.scale[1], op.scale[2], op.scale[3])) end
                    if op.parent then unit:SetParent(parentFor(op.parent)) end
                end)
                if not ok then
                    counters.failed = counters.failed + 1
                    emit('ERROR|' .. zone.label .. '|' .. op.name .. '|write|' .. tostring(writeError))
                    if created then
                        local cleaned, cleanupError = pcall(function() unit:Destroy() end)
                        emit('CLEANUP|' .. op.name .. '|ok=' .. tostring(cleaned) .. '|error=' .. tostring(cleanupError))
                    end
                    error('施工中止：' .. op.name .. '；此前已成功操作保留，可用 revert 回滚')
                end
            end
            if created then
                counters.created = counters.created + 1
            else
                counters.moved = counters.moved + 1
            end
            if not ok then counters.failed = counters.failed + 1 end
            local pos = safe(function() return unit:GetPosition() end, nil)
            local scale = safe(function() return unit:GetScale() end, nil)
            local size = safe(function() return unit:GetProperty('Size') end, nil)
            local parent = safe(function() return unit:GetParent() end, nil)
            local parentName = parent and unitName(parent) or '-'
            emit(('OP|%s|%s|created=%s|write=%s|pos=%s|scale=%s|size=%s|parent=%s'):format(
                zone.label, op.name, tostring(created), tostring(ok), vec(pos), vec(scale), vec(size), parentName))
        end
    end
end

emit(('SUMMARY|ops=%d|created=%d|moved=%d|miss=%d|failed=%d|apply=%s'):format(
    counters.ops, counters.created, counters.moved, counters.miss, counters.failed, tostring(APPLY)))
return MARK .. ' done apply=' .. tostring(APPLY) .. ' ops=' .. tostring(counters.ops)
