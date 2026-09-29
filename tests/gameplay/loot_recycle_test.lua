-- #91/#126 场上掉落物分区上限与 FIFO 回收（沿用 tests/gameplay/fish_loot_test.lua 的假引擎与真 PlayerData）。
-- 失败方式（先列后写）：
--   1. 上限与闪烁时长不走 GameCfg（写死数字 / 配置名与 issue 不符），压测无法校准；
--   2. 超限不回收，或回收的不是最旧一份（FIFO 顺序错），或场上计数把待回收的也算进去导致连锁误回收；
--   3. 待回收不闪烁、闪烁节奏乱（每帧乱闪），或 30 秒不到就提前销毁；
--   4. 待回收中的鱼获不能被拾取，或拾取后计时器残留把后来的同 id / 别的鱼获销毁；
--   5. 已拾取的鱼获仍占区计数，导致没超限也触发回收；
--   6. 各区互相串：一区刷满把另一区的鱼获回收掉；点位鱼饵（Kind='bait'）被计入上限；
--   7. #126 同区两块水域各算各的预算（合计能超 200 件），或跨水域的 FIFO 顺序错；
--   8. #126 预警期不设上限：活跃满 + 30 秒预警内继续新增，场上数量无界增长；峰值不可观测；
--   9. #126 预警标记没进快照（客户端不会闪），或把别的区 / 未预警的件也标成预警。
local lu = require('luaunit')
require('tests.gameplay.fish_loot_test')

TestLootRecycle = {}

function TestLootRecycle:setUp()
    self.cfg = require('common.GameCfg')
    self.savedLootCfg = self.cfg.Loot
    -- 浅拷贝原表只覆盖上限与闪烁时长，GameCfg 增字段不漂移
    local lootCfg = {}
    for k, v in pairs(self.savedLootCfg) do lootCfg[k] = v end
    lootCfg.PerZoneCap = 3
    lootCfg.FlashBeforeRecycleSec = 30
    self.cfg.Loot = lootCfg
    TestFishLoot.setUp(self)
end

function TestLootRecycle:tearDown()
    if self.realPrint then
        _G.print = self.realPrint
        self.realPrint = nil
    end
    TestFishLoot.tearDown(self)
    self.cfg.Loot = self.savedLootCfg
end

-- 采集 print 输出（回收/峰值日志的验收证据），用例结束务必 restoreLogs 或走 tearDown
function TestLootRecycle:captureLogs()
    self.logs = {}
    self.realPrint = print
    local logs = self.logs
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
        logs[#logs + 1] = table.concat(parts, ' ')
    end
    return logs
end

function TestLootRecycle:restoreLogs()
    if self.realPrint then
        _G.print = self.realPrint
        self.realPrint = nil
    end
end

TestLootRecycle.land = TestFishLoot.land
TestLootRecycle.kill = TestFishLoot.kill
TestLootRecycle.bar = TestFishLoot.bar
TestLootRecycle.lootUnits = TestFishLoot.lootUnits
TestLootRecycle.newPlayer = TestFishLoot.newPlayer

-- 在指定坐标直接生成一份鱼获（shrimp 无 Drops，一件就是一条记录）
function TestLootRecycle:spawnAt(x, z)
    return self.loot:Spawn('shrimp', 1, { x = x, y = 5, z = z })
end

-- 第一钓鱼区（WaterCircle 中心 -11.75,27.75）边上的一个点
function TestLootRecycle:spawnPond()
    return self:spawnAt(-11, 27)
end

-- 虾池（ShrimpPool 中心 105,106）边上的一个点
function TestLootRecycle:spawnPool()
    return self:spawnAt(105, 106)
end

-- 该鱼获所属区的 FIFO 队列（WaterCircle1/2 同心，归属由 MgrLoot 决定，用例不硬编区名）
function TestLootRecycle:queueOf(loot)
    return self.loot.ZoneQueues[loot.ZoneId]
end

function TestLootRecycle:test_config_has_per_zone_cap_and_flash_seconds()
    local cfg = assert(loadfile('common/GameCfg.lua'))()
    lu.assertEquals(cfg.Loot.PerZoneCap, 200)
    lu.assertEquals(cfg.Loot.FlashBeforeRecycleSec, 30)
end

function TestLootRecycle:test_over_cap_marks_oldest_recycling_and_count_stays_at_cap()
    local a = self:spawnPond()
    local b = self:spawnPond()
    local c = self:spawnPond()
    lu.assertEquals(#self:queueOf(a), 3)
    lu.assertEquals(self.loot.Recycling[a.Id], nil)
    local d = self:spawnPond()
    -- 最旧的 a 进入待回收（仍在场上、仍可拾取），队列计数回到上限 3
    lu.assertEquals(#self:queueOf(a), 3)
    lu.assertEquals(self:queueOf(a), { b.Id, c.Id, d.Id })
    lu.assertNotNil(self.loot.Recycling[a.Id])
    lu.assertNotNil(self.loot.Loots[a.Id])
    lu.assertFalse(self:lootUnits()[1].Destroyed)
end

function TestLootRecycle:test_recycling_loot_flashes_then_is_destroyed_after_flash_seconds()
    for _ = 1, 4 do self:spawnPond() end
    local unit = self:lootUnits()[1]
    local id = tonumber(tostring(unit.Name):match('FishLoot_(%d+)'))
    lu.assertNotNil(self.loot.Recycling[id])
    -- 闪烁：可见性按节奏来回切换，30 秒未到不销毁
    self.now = 0.6
    self.loot:Update()
    lu.assertEquals(unit.ModelVisible, false)
    self.now = 1.2
    self.loot:Update()
    lu.assertEquals(unit.ModelVisible, true)
    self.now = 29.9
    self.loot:Update()
    lu.assertFalse(unit.Destroyed)
    lu.assertNotNil(self.loot.Loots[id])
    -- 到点销毁并广播
    local before = self.broadcasts
    self.now = 30.1
    self.loot:Update()
    lu.assertTrue(unit.Destroyed)
    lu.assertNil(self.loot.Loots[id])
    lu.assertNil(self.loot.Recycling[id])
    lu.assertTrue(self.broadcasts > before)
    -- 其余 3 件不受影响
    lu.assertEquals(#self:lootUnits(), 3)
end

function TestLootRecycle:test_fifo_order_recycles_next_oldest_not_newest()
    local spawned = {}
    for i = 1, 5 do spawned[i] = self:spawnPond() end
    -- a、b 先后待回收，新的 d、e 留在队列
    lu.assertNotNil(self.loot.Recycling[spawned[1].Id])
    lu.assertNotNil(self.loot.Recycling[spawned[2].Id])
    lu.assertEquals(self:queueOf(spawned[1]), { spawned[3].Id, spawned[4].Id, spawned[5].Id })
    lu.assertNil(self.loot.Recycling[spawned[5].Id])
end

function TestLootRecycle:test_pickup_of_recycling_loot_cancels_recycle()
    local a = self:spawnPond()
    for _ = 1, 3 do self:spawnPond() end
    lu.assertNotNil(self.loot.Recycling[a.Id])
    self.player.Character.Position = a.Position
    lu.assertTrue(self.loot:Pickup(self.player, a.Id))
    lu.assertNil(self.loot.Recycling[a.Id])
    lu.assertNil(self.loot.Loots[a.Id])
    self.now = 31
    self.loot:Update()
    -- 没有误销毁后来的鱼获
    lu.assertEquals(#self:lootUnits(), 3)
end

function TestLootRecycle:test_picked_loot_frees_zone_count()
    local a = self:spawnPond()
    self:spawnPond()
    self:spawnPond()
    self.player.Character.Position = a.Position
    lu.assertTrue(self.loot:Pickup(self.player, a.Id))
    lu.assertEquals(#self:queueOf(a), 2)
    -- 再刷一件到 3 件，不触发回收
    self:spawnPond()
    lu.assertEquals(#self:queueOf(a), 3)
    lu.assertEquals(next(self.loot.Recycling), nil)
end

function TestLootRecycle:test_zones_are_counted_independently()
    for _ = 1, 4 do self:spawnPond() end
    lu.assertNotNil(next(self.loot.Recycling))
    -- 虾池已有的 2 件不受影响，也不被第一钓鱼区的超限波及
    local p1 = self:spawnPool()
    local p2 = self:spawnPool()
    lu.assertEquals(#self:queueOf(p1), 2)
    lu.assertNil(self.loot.Recycling[p1.Id])
    lu.assertNil(self.loot.Recycling[p2.Id])
    self.now = 31
    self.loot:Update()
    lu.assertNotNil(self.loot.Loots[p1.Id])
    lu.assertNotNil(self.loot.Loots[p2.Id])
    -- 虾池自己刷满也只回收自己的
    self:spawnPool()
    self:spawnPool()
    lu.assertEquals(#self:queueOf(p1), 3)
    lu.assertNotNil(self.loot.Recycling[p1.Id])
    lu.assertNil(self.loot.Recycling[p2.Id]) -- 次旧的还在队列里
end

function TestLootRecycle:test_bait_spot_loot_not_counted_in_cap()
    local a = self:spawnPond()
    for _ = 1, 2 do self:spawnPond() end
    -- 点位鱼饵落在同一区也不占上限
    self.loot.Spots[99] = { Cfg = { Id = 99, ItemId = 'worm', Count = 1, Position = { x = -11, y = 5, z = 27 } } }
    self.loot:SpawnBait(self.loot.Spots[99].Cfg)
    lu.assertNotNil(next(self.loot.Loots))
    self:spawnPond()
    -- 只有第 4 件鱼获触发 1 件待回收；鱼饵不在队列里
    lu.assertEquals(#self:queueOf(a), 3)
    local recycling = 0
    for _ in pairs(self.loot.Recycling) do recycling = recycling + 1 end
    lu.assertEquals(recycling, 1)
end

-- #126：池壁水条（addWaterStrip 生成）与鱼塘水圈同属一个钓鱼区，落点取第一块水条的中心
function TestLootRecycle:spawnStrip()
    for _, zone in ipairs(self.cfg.Water.Zones) do
        if tostring(zone.Id):find('^PondWest') then
            return self:spawnAt(zone.Center.x, zone.Center.z), zone
        end
    end
    error('未找到池壁水条水域')
end

-- #126：同一钓鱼区的两块水域共用一份预算，跨水域也是同一条 FIFO
function TestLootRecycle:test_same_zone_water_bodies_share_one_budget_and_fifo()
    local a = self:spawnPond() -- 鱼塘水圈
    local b = self:spawnPond()
    local c, stripZone = self:spawnStrip() -- 池壁水条
    lu.assertEquals(a.ZoneId, c.ZoneId) -- 两块水域归同一个钓鱼区
    lu.assertEquals(c.ZoneId, stripZone.ZoneId)
    local d = self:spawnStrip()
    -- 合计第 4 件（落水条）把全区最旧的水圈件顶进待回收：预算不是按水域各算一份
    lu.assertEquals(#self:queueOf(a), self.cfg.Loot.PerZoneCap)
    lu.assertEquals(self:queueOf(a), { b.Id, c.Id, d.Id })
    lu.assertNotNil(self.loot.Recycling[a.Id])
    lu.assertNil(self.loot.Recycling[c.Id])
    -- 其他钓鱼区（虾池）不受影响、也不共用这条队列
    local p = self:spawnPool()
    lu.assertNil(self.loot.Recycling[p.Id])
    lu.assertEquals(#self:queueOf(p), 1)
    lu.assertNotEquals(self:queueOf(a), self:queueOf(p))
    lu.assertNotNil(self.loot.Recycling[a.Id])
end

-- #126：预警只落在最旧一件上并写进快照（客户端据此闪文字泡），别的件与别的区都没有标记
function TestLootRecycle:test_warning_flag_marks_only_oldest_and_stays_pickable()
    local a = self:spawnPond()
    local b = self:spawnPond()
    local c = self:spawnPond()
    self:spawnPond() -- 第 4 件把 a 顶进预警
    local p = self:spawnPool()
    local warn = {}
    for _, row in ipairs(self.loot:Snapshot()) do warn[row.id] = row.warn end
    lu.assertEquals(warn[a.Id], true)
    lu.assertNil(warn[b.Id])
    lu.assertNil(warn[c.Id])
    lu.assertNil(warn[p.Id])
    -- 预警时长取配置（30 秒），不是写死的其它值
    lu.assertEquals(self.loot.Recycling[a.Id].At - self.loot:Now(), self.cfg.Loot.FlashBeforeRecycleSec)
    -- 预警期内仍可拾取，拾取即取消预警，且不误伤队列里的其他件
    self.player.Character.Position = a.Position
    lu.assertTrue(self.loot:Pickup(self.player, a.Id))
    lu.assertNil(self.loot.Recycling[a.Id])
    lu.assertNil(self.loot.Recycling[b.Id])
    lu.assertEquals(#self:queueOf(b), 3)
end

-- #126：预警期新增调度——超出 PendingCap 时立刻回收最旧的预警件（跳过剩余预警），
-- 单区总量恒 ≤ PerZoneCap + PendingCap，并有峰值日志可观测
function TestLootRecycle:test_bulk_spawn_keeps_active_and_pending_bounded_with_peak_logs()
    self.cfg.Loot.PendingCap = 2
    local logs = self:captureLogs()
    local first = self:spawnPond()
    for _ = 1, 19 do self:spawnPond() end
    self:restoreLogs()
    local active = #self:queueOf(first)
    local pending = 0
    for _ in pairs(self.loot.Recycling) do pending = pending + 1 end
    lu.assertEquals(active, self.cfg.Loot.PerZoneCap)
    lu.assertEquals(pending, self.cfg.Loot.PendingCap)
    lu.assertTrue(active + pending <= self.cfg.Loot.PerZoneCap + self.cfg.Loot.PendingCap)
    -- 生成 20 件后场上只留 3 件活跃 + 2 件预警，不随生成次数增长
    lu.assertEquals(#self:lootUnits(), self.cfg.Loot.PerZoneCap + self.cfg.Loot.PendingCap)
    local peak, earlyRecycle = false, false
    for _, line in ipairs(logs) do
        if line:find('区峰值') and line:find('active=') and line:find('pending=') then peak = true end
        if line:find('预警超限即回收') then earlyRecycle = true end
    end
    lu.assertTrue(peak)
    lu.assertTrue(earlyRecycle)
    -- 预警到点后剩下的一并销毁，场上只剩活跃的 3 件
    self.now = self.cfg.Loot.FlashBeforeRecycleSec + 1
    self.loot:Update()
    lu.assertEquals(#self:lootUnits(), self.cfg.Loot.PerZoneCap)
end

