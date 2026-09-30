-- #125 失败方式：长方形水域误判成正方形、无穷值、重名、缺实体、错位以及规划被当成可用。
local lu = require('luaunit')
local Judge = require('common.MathWaterJudge')
local Cfg = require('common.GameCfg')

TestZoneScene125 = {}

function TestZoneScene125:test_rectangular_water_preserves_dry_bank_and_inclusive_edges()
    local judge = Judge.Build({ {
        Id = '巡航水面', Center = { x = 10, z = 20 },
        HalfX = 30, HalfZ = 5, SurfaceY = 2,
    } })
    lu.assertEquals(judge({ x = 40, y = 2, z = 25 }).Id, '巡航水面')
    lu.assertNil(judge({ x = 10, y = 2, z = 25.01 }))
    lu.assertNil(judge({ x = 40.01, y = 2, z = 20 }))
    lu.assertNil(judge({ x = 10, y = 2.01, z = 20 }))
end

function TestZoneScene125:test_invalid_geometry_fails_before_a_judge_is_returned()
    for _,bad in ipairs({ math.huge, -math.huge, 0/0 }) do
        lu.assertErrorMsgContains('有限', Judge.Build, {
            { Id = '坏水域', Center = { x = bad, z = 0 }, HalfXZ = 1, SurfaceY = 2 },
        })
    end
    local zone = { Id = '重复', Center = { x = 0, z = 0 }, HalfXZ = 1, SurfaceY = 2 }
    lu.assertErrorMsgContains('重复', Judge.Build, { zone, zone })
end

function TestZoneScene125:test_scene_diagnostic_names_missing_duplicate_and_moved_entities()
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
    lu.assertNil(report.Ready)
    lu.assertEquals(report.Issues, {
        { ZoneId = 'crabLake', ZoneName = '蟹湖', Name = 'CrabWater', Code = 'missing' },
        { ZoneId = 'crabLake', ZoneName = '蟹湖', Name = 'CrabSafe', Code = 'duplicate' },
        { ZoneId = 'crabLake', ZoneName = '蟹湖', Name = 'CrabShop', Code = 'position' },
    })
    local complete = {}
    for _,e in ipairs(scenes[1].Scene.Entities) do complete[#complete + 1] = e end
    report = Judge.InspectScene(scenes, complete)
    lu.assertTrue(report.EntitiesMatch)
    lu.assertNil(report.Ready) -- 名称和位置匹配不等于碰撞、保存或试玩通过。
    lu.assertEquals(report.PendingZones, { 'crabLake' })
    scenes[1].Scene.State = 'verified'
    report = Judge.InspectScene(scenes, complete)
    lu.assertNil(report.Ready)
    lu.assertEquals(report.Verification, {
        Saved = 'unverified', Synced = 'unverified', Collision = 'unverified', Playtested = 'unverified',
    })
end

function TestZoneScene125:test_seven_zone_plan_keeps_unbuilt_entities_out_of_active_water()
    lu.assertEquals(#Cfg.Zones, 7)
    for index,zone in ipairs(Cfg.Zones) do
        local scene = zone.Scene
        lu.assertEquals(scene.State, 'planned')
        lu.assertEquals(scene.BaitSpots.RespawnSec, 15)
        lu.assertEquals(scene.BaitSpots.ItemId, zone.BaitItemId)
        lu.assertNil(Cfg.Casting.BossBaitCatalog[scene.BaitSpots.ItemId])
        lu.assertNotNil(scene.LotteryName)
        lu.assertEquals(scene.GrillName ~= nil, index >= 3)
        lu.assertTrue(scene.Boundary.TopY > scene.SafePoint.y + 20)
        local water = Judge.Build(scene.Waters)
        lu.assertNil(water(scene.SafePoint), zone.Name .. '落点不得入水')
        lu.assertTrue(scene.SafePoint.x > scene.Land.MinX and scene.SafePoint.x < scene.Land.MaxX)
        lu.assertTrue(scene.SafePoint.z > scene.Land.MinZ and scene.SafePoint.z < scene.Land.MaxZ)
        for _,point in ipairs(scene.BaitSpots.Positions) do
            lu.assertNil(water({ x = point.x, y = -100, z = point.z }))
        end
        local fallback = false
        for _,row in ipairs(Cfg.Casting.Catalog[zone.Id]) do
            fallback = fallback or (row.Bait == 0 and row.RodLevel == 1)
        end
        lu.assertTrue(fallback, zone.Name .. '缺无饵保底')
        if index >= 3 then
            -- #136 蟹湖（第三区）水域已实测接入：其余未建区仍不得接入活跃抽鱼池
            if index == 3 then
                lu.assertNotNil(Cfg.Casting.Zones[zone.WaterId])
            else
                lu.assertNil(Cfg.Casting.Zones[zone.WaterId])
            end
            lu.assertNotNil(water({ x = scene.SafePoint.x, y = scene.Waters[1].SurfaceY,
                z = scene.Land.MaxZ - 1 + Cfg.Casting.Distance }), zone.Name .. '岸边必须可抛入水')
        end
        for other = 1,index - 1 do
            local a,b = scene.Boundary,Cfg.Zones[other].Scene.Boundary
            lu.assertTrue(a.MinX > b.MaxX or b.MinX > a.MaxX or a.MinZ > b.MaxZ or b.MinZ > a.MaxZ,
                zone.Name .. '围栏不得与其他钓鱼区重叠')
        end
    end
    lu.assertNotNil(Cfg.Zones[6].Scene.AirCombat)
    lu.assertNotNil(Cfg.Zones[7].Scene.CruiseWater)
    lu.assertNotNil(Cfg.Zones[7].Scene.BossArena)
end

function TestZoneScene125:test_six_route_pairs_target_dry_same_zone_safe_points()
    lu.assertEquals(#Cfg.Ferry.PlannedRoutes, 6)
    local prices = {10,30,90,270,810,2430}
    for i,route in ipairs(Cfg.Ferry.PlannedRoutes) do
        lu.assertEquals(route.State, 'planned')
        lu.assertEquals(route.FromZoneId, Cfg.Zones[i].Id)
        lu.assertEquals(route.ToZoneId, Cfg.Zones[i+1].Id)
        lu.assertEquals(route.Outbound.Ticket, Cfg.Content.Exchanges[i].Result)
        lu.assertEquals(route.Outbound.CountdownSec, 5)
        lu.assertEquals(route.Return.Price, prices[i])
        lu.assertEquals(route.Outbound.Destination, Cfg.Zones[i+1].Scene.SafePoint)
        lu.assertEquals(route.Return.Destination, Cfg.Zones[i].Scene.SafePoint)
    end
    lu.assertEquals(Cfg.Ferry.Outbound.AnchorName, 'FerryBoat')
    for _,water in ipairs(Cfg.Water.Zones) do
        lu.assertEquals(water.ZoneId, Cfg.Water.ZoneIdByWater[water.Id])
    end
end

