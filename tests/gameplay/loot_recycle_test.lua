-- #91 场上掉落物分区上限与 FIFO 回收（沿用 tests/gameplay/fish_loot_test.lua 的假引擎与真 PlayerData）。
-- 失败方式（先列后写）：
--   1. 上限与闪烁时长不走 GameCfg（写死数字 / 配置名与 issue 不符），压测无法校准；
--   2. 超限不回收，或回收的不是最旧一份（FIFO 顺序错），或场上计数把待回收的也算进去导致连锁误回收；
--   3. 待回收不闪烁、闪烁节奏乱（每帧乱闪），或 30 秒不到就提前销毁；
--   4. 待回收中的鱼获不能被拾取，或拾取后计时器残留把后来的同 id / 别的鱼获销毁；
--   5. 已拾取的鱼获仍占区计数，导致没超限也触发回收；
--   6. 各区互相串：一区刷满把另一区的鱼获回收掉；点位鱼饵（Kind='bait'）被计入上限。
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
    TestFishLoot.tearDown(self)
    self.cfg.Loot = self.savedLootCfg
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
