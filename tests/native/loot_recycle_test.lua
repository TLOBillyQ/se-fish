-- #84 迁移：场上掉落物分区上限与 FIFO 回收（原 tests/gameplay/loot_recycle_test.lua，11 例）。
-- 接缝：MgrLoot 的分区预算与回收调度——超限顶最旧、预警闪烁与到点销毁、拾取取消回收、
-- 同区多水域共用一条 FIFO、峰值有界并可从日志观测。
-- 沿用 tests/support/fish_loot 共享夹具；本类的 Loot 配置浅拷贝与 print 采集逐例建立并还原。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local FishLoot = require('tests.support.fish_loot')
local GameCfg = require('common.GameCfg')

-- 原类内辅助改为接收 env 的本地函数
local function captureLogs(env)
    env.logs = {}
    env.realPrint = print
    local logs = env.logs
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
        logs[#logs + 1] = table.concat(parts, ' ')
    end
    return logs
end

local function restoreLogs(env)
    if env.realPrint then
        _G.print = env.realPrint
        env.realPrint = nil
    end
end

local function spawnAt(env, x, z)
    return env.loot:Spawn('shrimp', 1, { x = x, y = 5, z = z })
end

-- 第一钓鱼区（WaterCircle 中心 -11.75,-12.25）边上的一个点
local function spawnPond(env)
    return spawnAt(env, -11, -13)
end

-- 虾池统一模板水面中心 (240,-44)。
local function spawnPool(env)
    return spawnAt(env, 240, -44)
end

-- #126：池壁水条（addWaterStrip 生成）与鱼塘水圈同属一个钓鱼区，落点取第一块水条的中心
local function spawnStrip(env)
    for _, zone in ipairs(GameCfg.Water.Zones) do
        if tostring(zone.Id):find('^PondWest') then
            return spawnAt(env, zone.Center.x, zone.Center.z), zone
        end
    end
    error('未找到池壁水条水域')
end

-- 该鱼获所属区的 FIFO 队列（WaterCircle1/2 同心，归属由 MgrLoot 决定，用例不硬编区名）
local function queueOf(env, loot)
    return env.loot.ZoneQueues[loot.ZoneId]
end

local function setUp(env)
    env.savedLootCfg = GameCfg.Loot
    -- 浅拷贝原表只覆盖上限与闪烁时长，GameCfg 增字段不漂移
    local lootCfg = {}
    for k, v in pairs(env.savedLootCfg) do lootCfg[k] = v end
    lootCfg.PerZoneCap = 3
    lootCfg.FlashBeforeRecycleSec = 30
    GameCfg.Loot = lootCfg
    env:setUp()
end

local function tearDown(env)
    restoreLogs(env)
    env:tearDown()
    GameCfg.Loot = env.savedLootCfg
end

describe('TestLootRecycle', function()
    local env

    before_each(function()
        env = FishLoot.new()
        setUp(env)
    end)
    after_each(function()
        tearDown(env)
    end)

    it('test_bait_spot_loot_not_counted_in_cap', function()
        local a = spawnPond(env)
        for _ = 1, 2 do spawnPond(env) end
        -- 点位鱼饵落在同一区也不占上限
        env.loot.Spots[99] = { Cfg = { Id = 99, ItemId = 'worm', Count = 1, Position = { x = -11, y = 5, z = 27 } } }
        env.loot:SpawnBait(env.loot.Spots[99].Cfg)
        assert.is_not.is_nil(next(env.loot.Loots))
        spawnPond(env)
        -- 只有第 4 件鱼获触发 1 件待回收；鱼饵不在队列里
        assert.are.equal(3, #queueOf(env, a))
        local recycling = 0
        for _ in pairs(env.loot.Recycling) do recycling = recycling + 1 end
        assert.are.equal(1, recycling)
    end)

    it('test_bulk_spawn_keeps_active_and_pending_bounded_with_peak_logs', function()
        GameCfg.Loot.PendingCap = 2
        local logs = captureLogs(env)
        local first = spawnPond(env)
        for _ = 1, 19 do spawnPond(env) end
        restoreLogs(env)
        local active = #queueOf(env, first)
        local pending = 0
        for _ in pairs(env.loot.Recycling) do pending = pending + 1 end
        assert.are.equal(GameCfg.Loot.PerZoneCap, active)
        assert.are.equal(GameCfg.Loot.PendingCap, pending)
        assert.is_true(active + pending <= GameCfg.Loot.PerZoneCap + GameCfg.Loot.PendingCap)
        -- 生成 20 件后场上只留 3 件活跃 + 2 件预警，不随生成次数增长
        assert.are.equal(GameCfg.Loot.PerZoneCap + GameCfg.Loot.PendingCap, #env:lootUnits())
        local peak, earlyRecycle = false, false
        for _, line in ipairs(logs) do
            if line:find('[MgrLoot] 区峰值', 1, true) and line:find('active=', 1, true)
                and line:find('pending=', 1, true) then peak = true end
            if line:find('预警超限即回收', 1, true) then earlyRecycle = true end
        end
        assert.is_true(peak)
        assert.is_true(earlyRecycle)
        -- 预警到点后剩下的一并销毁，场上只剩活跃的 3 件
        env.now = GameCfg.Loot.FlashBeforeRecycleSec + 1
        env.loot:Update()
        assert.are.equal(GameCfg.Loot.PerZoneCap, #env:lootUnits())
    end)

    it('test_config_has_per_zone_cap_and_flash_seconds', function()
        local cfg = assert(loadfile('common/GameCfg.lua'))()
        assert.are.equal(200, cfg.Loot.PerZoneCap)
        assert.are.equal(30, cfg.Loot.FlashBeforeRecycleSec)
    end)

    it('test_fifo_order_recycles_next_oldest_not_newest', function()
        local spawned = {}
        for i = 1, 5 do spawned[i] = spawnPond(env) end
        -- a、b 先后待回收，新的 d、e 留在队列
        assert.is_not.is_nil(env.loot.Recycling[spawned[1].Id])
        assert.is_not.is_nil(env.loot.Recycling[spawned[2].Id])
        assert.same({ spawned[3].Id, spawned[4].Id, spawned[5].Id }, queueOf(env, spawned[1]))
        assert.is_nil(env.loot.Recycling[spawned[5].Id])
    end)

    it('test_over_cap_marks_oldest_recycling_and_count_stays_at_cap', function()
        local a = spawnPond(env)
        local b = spawnPond(env)
        local c = spawnPond(env)
        assert.are.equal(3, #queueOf(env, a))
        assert.is_nil(env.loot.Recycling[a.Id])
        local d = spawnPond(env)
        -- 最旧的 a 进入待回收（仍在场上、仍可拾取），队列计数回到上限 3
        assert.are.equal(3, #queueOf(env, a))
        assert.same({ b.Id, c.Id, d.Id }, queueOf(env, a))
        assert.is_not.is_nil(env.loot.Recycling[a.Id])
        assert.is_not.is_nil(env.loot.Loots[a.Id])
        assert.is_false(env:lootUnits()[1].Destroyed)
    end)

    it('test_picked_loot_frees_zone_count', function()
        local a = spawnPond(env)
        spawnPond(env)
        spawnPond(env)
        env.player.Character.Position = a.Position
        assert.is_true(env.loot:Pickup(env.player, a.Id))
        assert.are.equal(2, #queueOf(env, a))
        -- 再刷一件到 3 件，不触发回收
        spawnPond(env)
        assert.are.equal(3, #queueOf(env, a))
        assert.is_nil(next(env.loot.Recycling))
    end)

    it('test_pickup_of_recycling_loot_cancels_recycle', function()
        local a = spawnPond(env)
        for _ = 1, 3 do spawnPond(env) end
        assert.is_not.is_nil(env.loot.Recycling[a.Id])
        env.player.Character.Position = a.Position
        assert.is_true(env.loot:Pickup(env.player, a.Id))
        assert.is_nil(env.loot.Recycling[a.Id])
        assert.is_nil(env.loot.Loots[a.Id])
        env.now = 31
        env.loot:Update()
        -- 没有误销毁后来的鱼获
        assert.are.equal(3, #env:lootUnits())
    end)

    it('test_recycling_loot_flashes_then_is_destroyed_after_flash_seconds', function()
        for _ = 1, 4 do spawnPond(env) end
        local unit = env:lootUnits()[1]
        local id = tonumber(tostring(unit.Name):match('FishLoot_(%d+)'))
        assert.is_not.is_nil(env.loot.Recycling[id])
        -- 闪烁：可见性按节奏来回切换，30 秒未到不销毁
        env.now = 0.6
        env.loot:Update()
        assert.is_false(unit.ModelVisible)
        env.now = 1.2
        env.loot:Update()
        assert.is_true(unit.ModelVisible)
        env.now = 29.9
        env.loot:Update()
        assert.is_false(unit.Destroyed)
        assert.is_not.is_nil(env.loot.Loots[id])
        -- 到点销毁并广播
        local before = env.broadcasts
        env.now = 30.1
        env.loot:Update()
        assert.is_true(unit.Destroyed)
        assert.is_nil(env.loot.Loots[id])
        assert.is_nil(env.loot.Recycling[id])
        assert.is_true(env.broadcasts > before)
        -- 其余 3 件不受影响
        assert.are.equal(3, #env:lootUnits())
    end)

    it('test_same_zone_water_bodies_share_one_budget_and_fifo', function()
        local a = spawnPond(env) -- 鱼塘水圈
        local b = spawnPond(env)
        local c, stripZone = spawnStrip(env) -- 池壁水条
        assert.are.equal(a.ZoneId, c.ZoneId) -- 两块水域归同一个钓鱼区
        assert.are.equal(c.ZoneId, stripZone.ZoneId)
        local d = spawnStrip(env)
        -- 合计第 4 件（落水条）把全区最旧的水圈件顶进待回收：预算不是按水域各算一份
        assert.are.equal(GameCfg.Loot.PerZoneCap, #queueOf(env, a))
        assert.same({ b.Id, c.Id, d.Id }, queueOf(env, a))
        assert.is_not.is_nil(env.loot.Recycling[a.Id])
        assert.is_nil(env.loot.Recycling[c.Id])
        -- 其他钓鱼区（虾池）不受影响、也不共用这条队列
        local p = spawnPool(env)
        assert.is_nil(env.loot.Recycling[p.Id])
        assert.are.equal(1, #queueOf(env, p))
        assert.is_not.same(queueOf(env, a), queueOf(env, p))
        assert.is_not.is_nil(env.loot.Recycling[a.Id])
    end)

    it('test_warning_flag_marks_only_oldest_and_stays_pickable', function()
        local a = spawnPond(env)
        local b = spawnPond(env)
        local c = spawnPond(env)
        spawnPond(env) -- 第 4 件把 a 顶进预警
        local p = spawnPool(env)
        local warn = {}
        for _, row in ipairs(env.loot:Snapshot()) do warn[row.id] = row.warn end
        assert.is_true(warn[a.Id])
        assert.is_nil(warn[b.Id])
        assert.is_nil(warn[c.Id])
        assert.is_nil(warn[p.Id])
        -- 预警时长取配置（30 秒），不是写死的其它值
        assert.are.equal(GameCfg.Loot.FlashBeforeRecycleSec, env.loot.Recycling[a.Id].At - env.loot:Now())
        -- 预警期内仍可拾取，拾取即取消预警，且不误伤队列里的其他件
        env.player.Character.Position = a.Position
        assert.is_true(env.loot:Pickup(env.player, a.Id))
        assert.is_nil(env.loot.Recycling[a.Id])
        assert.is_nil(env.loot.Recycling[b.Id])
        assert.are.equal(3, #queueOf(env, b))
    end)

    it('test_zones_are_counted_independently', function()
        for _ = 1, 4 do spawnPond(env) end
        assert.is_not.is_nil(next(env.loot.Recycling))
        -- 虾池已有的 2 件不受影响，也不被第一钓鱼区的超限波及
        local p1 = spawnPool(env)
        local p2 = spawnPool(env)
        assert.are.equal(2, #queueOf(env, p1))
        assert.is_nil(env.loot.Recycling[p1.Id])
        assert.is_nil(env.loot.Recycling[p2.Id])
        env.now = 31
        env.loot:Update()
        assert.is_not.is_nil(env.loot.Loots[p1.Id])
        assert.is_not.is_nil(env.loot.Loots[p2.Id])
        -- 虾池自己刷满也只回收自己的
        spawnPool(env)
        spawnPool(env)
        assert.are.equal(3, #queueOf(env, p1))
        assert.is_not.is_nil(env.loot.Recycling[p1.Id])
        assert.is_nil(env.loot.Recycling[p2.Id]) -- 次旧的还在队列里
    end)
end)
