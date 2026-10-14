-- #125 失败方式：长方形水域误判成正方形、无穷值、重名、缺实体、错位以及规划被当成可用。
-- 迁移自 tests/gameplay/zone_scene_125_test.lua（#83）。单类 TestZoneScene125，无 setUp/tearDown；
-- it 顺序沿用旧入口的方法名字典序，与迁移前逐条对账。
-- 断言口径：旧 assertEquals 对 table 是深比较 → assert.same；旧 assertIs 要求同一引用
-- → 用 assert.are.equal（就是 `==`，深比较的 same 会把「共享同一表」弱化成「内容相等」而漏判）。
local Judge = require('common.MathWaterJudge')
local Cfg = require('common.GameCfg')

describe("TestZoneScene125", function()
  -- 搬移失败方式：共享点被重复变换、矩形倒置、两套水域错位/错归属、摆渡与围栏留在旧址。
  it("test_folded_layout_keeps_runtime_geometry_and_shared_points_consistent", function()
    local centers = { {0,0}, {240,0}, {480,0}, {720,0}, {720,320}, {480,320}, {240,320} }
    local runtime = {}
    for _, water in ipairs(Cfg.Water.Zones) do runtime[water.Id] = water end
    for index, zone in ipairs(Cfg.Zones) do
      local scene, center = zone.Scene, centers[index]
      local b = scene.Boundary
      assert.are.equal((b.MinX + b.MaxX) / 2, center[1])
      assert.are.equal(b.MinZ, center[2] - (index == 1 and 59 or index >= 2 and index <= 4 and 70 or 50))
      assert.are.equal(b.MaxZ, center[2] + (index == 1 and 79 or index >= 2 and index <= 4 and 50 or 70))
      assert.is_true(b.MinX < b.MaxX and b.MinZ < b.MaxZ)
      assert.is_true(scene.Land.MinX < scene.Land.MaxX and scene.Land.MinZ < scene.Land.MaxZ)
      if index > 2 then
        -- #102 现场同步：03–07 区的安全点取 #65 P3 施工后的现场值「内侧墙内面内 18 米」，
        -- 折返后落在区中心靠内侧（远离水岸）那一边，不再等于区中心。
        assert.same({ x = center[1], y = 6,
          z = center[2] + (index <= 4 and 30.5 or -30.5) }, scene.SafePoint)
      elseif index == 2 then
        assert.same({ x = center[1], y = 6, z = center[2] }, scene.SafePoint)
      else
        assert.near(-0.71, scene.SafePoint.z, 1e-9)
      end
      for _, water in ipairs(scene.Waters) do
        assert.are.equal(zone.Id, water.ZoneId)
        local active = assert(runtime[water.Id])
        -- 旧 assertEquals 两侧同为 table → 深比较；注意这里不是 assertIs，
        -- 「两套水域必须是同一引用」由下面的 Safe / Water 实体 Position 断言负责。
        assert.same(water.Center, active.Center)
        assert.are.equal(active.ZoneId, zone.Id)
        assert.are.equal(active.HalfX, water.HalfX)
        assert.are.equal(active.HalfZ, water.HalfZ)
        assert.are.equal(active.HalfXZ, water.HalfXZ)
        assert.are.equal(active.SurfaceY, water.SurfaceY)
      end
      for _, entity in ipairs(scene.Entities) do
        if entity.Role == 'Safe' then assert.are.equal(scene.SafePoint, entity.Position) end
        if index >= 3 and entity.Role == 'Water' then
          assert.are.equal(scene.Waters[1].Center, entity.Position)
        end
      end
      local judge = Judge.Build(Cfg.Water.Zones)
      assert.is_nil(judge({ x = scene.SafePoint.x, y = -100, z = scene.SafePoint.z }))
      for _, point in ipairs(scene.BaitSpots.Positions) do
        assert.is_nil(judge({ x = point.x, y = -100, z = point.z }))
      end
    end
    assert.are.equal('reefIsland', Cfg.Water.ZoneIdByWater['reefIsland.water'])
    assert.are.equal('volcanoIsland', Cfg.Water.ZoneIdByWater['volcanoIsland.water'])
    assert.same({ x = 5, y = 6, z = -9 }, Cfg.BaitSpots.Spots[1].Position)
    assert.are.equal(Cfg.Zones[1].Scene.BaitSpots.Positions[1], Cfg.BaitSpots.Spots[1].Position)
    assert.are.equal(Cfg.Zones[7].Scene.Waters[1], Cfg.Zones[7].Scene.CruiseWater)
    for i, route in ipairs(Cfg.Ferry.Routes) do
      assert.are.equal(Cfg.Zones[i + 1].Scene.SafePoint, route.Outbound.Destination)
      assert.are.equal(Cfg.Zones[i].Scene.SafePoint, route.Return.Destination)
    end
  end)

  it("test_invalid_geometry_fails_before_a_judge_is_returned", function()
    for _, bad in ipairs({ math.huge, -math.huge, 0 / 0 }) do
      assert.error_matches(function()
        Judge.Build({ { Id = '坏水域', Center = { x = bad, z = 0 }, HalfXZ = 1, SurfaceY = 2 } })
      end, '有限', nil, true)
    end
    local zone = { Id = '重复', Center = { x = 0, z = 0 }, HalfXZ = 1, SurfaceY = 2 }
    assert.error_matches(function()
      Judge.Build({ zone, zone })
    end, '重复', nil, true)
  end)

  it("test_rectangular_water_preserves_dry_bank_and_inclusive_edges", function()
    local judge = Judge.Build({ {
      Id = '巡航水面', Center = { x = 10, z = 20 },
      HalfX = 30, HalfZ = 5, SurfaceY = 2,
    } })
    assert.are.equal('巡航水面', judge({ x = 40, y = 2, z = 25 }).Id)
    assert.is_nil(judge({ x = 10, y = 2, z = 25.01 }))
    assert.is_nil(judge({ x = 40.01, y = 2, z = 20 }))
    assert.is_nil(judge({ x = 10, y = 2.01, z = 20 }))
  end)

  it("test_scene_diagnostic_names_missing_duplicate_and_moved_entities", function()
    local scenes = { { Id = 'crabLake', Name = '蟹湖', Scene = { State = 'planned', Entities = {
      { Name = 'CrabWater', Position = { x = 260, y = 2, z = 140 } },
      { Name = 'CrabSafe', Position = { x = 260, y = 6, z = 100 } },
      { Name = 'CrabShop', Position = { x = 250, y = 5, z = 100 } },
    } } } }
    local report = Judge.InspectScene(scenes, {
      { Name = 'CrabSafe', Position = { x = 260, y = 6, z = 100 } },
      { Name = 'CrabSafe', Position = { x = 260, y = 6, z = 100 } },
      { Name = 'CrabShop', Position = { x = 250, y = 5, z = 110 } },
    })
    assert.is_nil(report.Ready)
    assert.same({
      { ZoneId = 'crabLake', ZoneName = '蟹湖', Name = 'CrabWater', Code = 'missing' },
      { ZoneId = 'crabLake', ZoneName = '蟹湖', Name = 'CrabSafe', Code = 'duplicate' },
      { ZoneId = 'crabLake', ZoneName = '蟹湖', Name = 'CrabShop', Code = 'position' },
    }, report.Issues)
    local complete = {}
    for _, e in ipairs(scenes[1].Scene.Entities) do complete[#complete + 1] = e end
    report = Judge.InspectScene(scenes, complete)
    assert.is_true(report.EntitiesMatch)
    assert.is_nil(report.Ready) -- 名称和位置匹配不等于碰撞、保存或试玩通过。
    assert.same({ 'crabLake' }, report.PendingZones)
    scenes[1].Scene.State = 'verified'
    report = Judge.InspectScene(scenes, complete)
    assert.is_nil(report.Ready)
    assert.same({
      Saved = 'unverified', Synced = 'unverified', Collision = 'unverified', Playtested = 'unverified',
    }, report.Verification)
  end)

  it("test_seven_zone_plan_keeps_unbuilt_entities_out_of_active_water", function()
    assert.are.equal(7, #Cfg.Zones)
    for index, zone in ipairs(Cfg.Zones) do
      local scene = zone.Scene
      assert.are.equal('planned', scene.State)
      assert.are.equal(15, scene.BaitSpots.RespawnSec)
      assert.are.equal(zone.BaitItemId, scene.BaitSpots.ItemId)
      assert.is_nil(Cfg.Casting.BossBaitCatalog[scene.BaitSpots.ItemId])
      assert.is_not_nil(scene.LotteryName)
      assert.are.equal(index >= 3, scene.GrillName ~= nil)
      assert.is_true(scene.Boundary.TopY > scene.SafePoint.y + 20)
      local water = Judge.Build(scene.Waters)
      assert.is_nil(water(scene.SafePoint), zone.Name .. '落点不得入水')
      assert.is_true(scene.SafePoint.x > scene.Land.MinX and scene.SafePoint.x < scene.Land.MaxX)
      assert.is_true(scene.SafePoint.z > scene.Land.MinZ and scene.SafePoint.z < scene.Land.MaxZ)
      for _, point in ipairs(scene.BaitSpots.Positions) do
        assert.is_nil(water({ x = point.x, y = -100, z = point.z }))
      end
      local fallback = false
      for _, row in ipairs(Cfg.Casting.Catalog[zone.Id]) do
        fallback = fallback or (row.Bait == 0 and row.RodLevel == 1)
      end
      assert.is_true(fallback, zone.Name .. '缺无饵保底')
      if index >= 3 then
        -- #136 蟹湖（第三区）、#141 树林岛（第四区）、#142 沙滩岛（第五区）水域已实测接入：
        -- 其余未建区仍不得接入活跃抽鱼池
        if index >= 3 and index <= 7 then
          assert.is_not_nil(Cfg.Casting.Zones[zone.WaterId])
        else
          assert.is_nil(Cfg.Casting.Zones[zone.WaterId])
        end
        local bankZ = index <= 4 and scene.Land.MinZ + 1 - Cfg.Casting.Distance
          or scene.Land.MaxZ - 1 + Cfg.Casting.Distance
        assert.is_not_nil(water({ x = scene.SafePoint.x, y = scene.Waters[1].SurfaceY,
          z = bankZ }), zone.Name .. '岸边必须可抛入水')
      end
      for other = 1, index - 1 do
        local a, b = scene.Boundary, Cfg.Zones[other].Scene.Boundary
        assert.is_true(a.MinX > b.MaxX or b.MinX > a.MaxX or a.MinZ > b.MaxZ or b.MinZ > a.MaxZ,
          zone.Name .. '围栏不得与其他钓鱼区重叠')
      end
    end
    assert.is_not_nil(Cfg.Zones[6].Scene.AirCombat)
    assert.is_not_nil(Cfg.Zones[7].Scene.CruiseWater)
    assert.is_not_nil(Cfg.Zones[7].Scene.BossArena)
  end)

  it("test_six_route_pairs_target_dry_same_zone_safe_points", function()
    assert.are.equal(6, #Cfg.Ferry.PlannedRoutes)
    local prices = { 10, 30, 90, 270, 810, 2430 }
    for i, route in ipairs(Cfg.Ferry.PlannedRoutes) do
      assert.are.equal('planned', route.State)
      assert.are.equal(Cfg.Zones[i].Id, route.FromZoneId)
      assert.are.equal(Cfg.Zones[i + 1].Id, route.ToZoneId)
      assert.are.equal(Cfg.Content.Exchanges[i].Result, route.Outbound.Ticket)
      assert.are.equal(5, route.Outbound.CountdownSec)
      assert.are.equal(prices[i], route.Return.Price)
      assert.are.equal(Cfg.Zones[i + 1].Scene.SafePoint, route.Outbound.Destination)
      assert.are.equal(Cfg.Zones[i].Scene.SafePoint, route.Return.Destination)
    end
    assert.are.equal('FerryBoat', Cfg.Ferry.Outbound.AnchorName)
    for _, water in ipairs(Cfg.Water.Zones) do
      assert.are.equal(Cfg.Water.ZoneIdByWater[water.Id], water.ZoneId)
    end
  end)
end)
