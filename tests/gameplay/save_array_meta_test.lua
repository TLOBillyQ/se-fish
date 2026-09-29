-- #123 P0：平台在列表型 Lua 表跨引擎边界时附加 __count 长度键（真机证据 .scratch/125/playtest-20260929-215641/
-- 19-probe-save.txt：bar/bp 回读带 __count=2，同一回包的字典型 bait 不带），导致 Migrate 的严格键校验
-- 把所有老档判成「库存结构损坏」→ 读写屏障永久关闭。
-- 本单失败方式先列：合法存档因平台元数据被拒（本文件主测）；剥离时顺手放松校验放行真损坏档；
-- 长度以 __count 为准而非实际条数；平台元数据被带回内存并写回库；无标记的旧档受影响。
-- seam：真实 PlayerData.Migrate/CompleteLoad 与 MgrSave 公共接口；只替换 Task/DataStore 引擎边界。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')
TestSaveArrayMeta = {}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end

-- 模拟引擎边界：纯列表（键全为 ≥1 的整数）回读时带 __count，字典/混合表不带（真机 bait 不带即为字典）。
local function markLists(value)
    if type(value) ~= 'table' then return value end
    local out, count, onlyArray = {}, 0, true
    for key, child in pairs(value) do
        out[key] = markLists(child)
        if type(key) == 'number' and key >= 1 and key == math.floor(key) then
            count = count + 1
        else
            onlyArray = false
        end
    end
    if onlyArray and count > 0 then out.__count = count end
    return out
end

-- 递归找 __count，任何一层残留都算写侧不干净。
local function hasCountKey(value, seen)
    if type(value) ~= 'table' then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    if value.__count ~= nil then return true end
    for _, child in pairs(value) do
        if hasCountKey(child, seen) then return true end
    end
    return false
end

local function capturePrint(fn)
    local logs = {}
    local real = print
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        logs[#logs + 1] = table.concat(parts, ' ')
    end
    local ok, err = pcall(fn)
    print = real
    if not ok then error(err, 0) end
    return logs
end

-- 真机同形 v1 档：up=6 coin=4966 zone=fishPond1，bar/bp 各两条实例——即 21:56 那份读不回来的存档。
local function realSnapshot()
    return {
        v = 1, coin = 4966, up = 6, zone = 'fishPond1', bait = { sausage = 0, worm = 3 },
        bar = { { i = 2, id = 'garMeat', m = 1.23, n = 1 }, { i = 3, id = 'shrimpRod', n = 1 }, __count = 2 },
        bp = { { i = 2, id = 'eelMeat', m = 1.87, n = 1 }, { i = 3, id = 'tilapia', m = 1.42, n = 1 }, __count = 2 },
    }
end

local function player(id) return { UserId = id, SetAttribute = function() end } end
local function pending(id)
    local data = PlayerData.New(player(id))
    data:Init(true)
    return data
end
local function fresh(id)
    local data = PlayerData.New(player(id))
    data:Init()
    return data
end
-- 只调 Migrate 的用例不需要 Init；IsValidSave 也走同一条路径。
local function migrator(id) return PlayerData.New(player(id)) end

function TestSaveArrayMeta:test_real_cloud_snapshot_with_platform_count_marker_loads_ready()
    local data = pending(90)
    lu.assertTrue(data:CompleteLoad(realSnapshot()))
    lu.assertEquals(data.LoadState, 'ready')
    lu.assertEquals(data.Data.FishCoin, 4966)
    lu.assertEquals(data.Data.UpgradeLevel, 6)
    lu.assertEquals(data.Data.Zone, 'fishPond1')
    lu.assertEquals(data.Data.Bait.worm, 3)
    lu.assertEquals(data.Data.Bait.sausage, 0)
    local bar = data.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    lu.assertEquals(bar[2].itemId, 'garMeat')
    lu.assertEquals(bar[2].mult, 1.23)
    lu.assertEquals(bar[3].itemId, 'shrimpRod')
    lu.assertNil(bar[1])
    local bp = data.Data.Containers[GameCfg.Items.ContainerId.Backpack]
    lu.assertEquals(bp[2].itemId, 'eelMeat')
    lu.assertEquals(bp[2].mult, 1.87)
    lu.assertEquals(bp[3].itemId, 'tilapia')
    lu.assertEquals(bp[3].mult, 1.42)
    -- 平台标记不得进入内存，也不得被下一次 Serialize 写回库。
    lu.assertFalse(hasCountKey(data:Serialize()))
end

function TestSaveArrayMeta:test_empty_marker_and_mismatched_count_follow_actual_entries()
    local logs = capturePrint(function()
        local data = pending(91)
        local snapshot = realSnapshot()
        snapshot.bar = { __count = 0 }
        snapshot.bp = { { i = 2, id = 'eelMeat', n = 1 }, __count = 7 }
        lu.assertTrue(data:CompleteLoad(snapshot))
        lu.assertEquals(data:ItemCount('eelMeat'), 1)
        lu.assertNil(data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1])
    end)
    local joined = table.concat(logs, '\n')
    -- 声称 7 条、实际 1 条：以实际条数为准，并留一行痕迹。
    lu.assertNotNil(string.find(joined, '数组长度标记不一致', 1, true))
    lu.assertNotNil(string.find(joined, 'save.bp', 1, true))
end

function TestSaveArrayMeta:test_platform_marker_never_relaxes_corruption_rejection()
    local hole = realSnapshot()
    hole.bp = { [1] = { i = 2, id = 'eelMeat', n = 1 }, [3] = { i = 3, id = 'tilapia', n = 1 }, __count = 3 }
    local saved, reason = migrator(92):Migrate(hole)
    lu.assertNil(saved)
    lu.assertEquals(reason, '库存序列不连续')

    local badInstance = realSnapshot()
    badInstance.bar = { { i = 2, id = 'garMeat', n = 0 }, __count = 1 }
    saved, reason = migrator(93):Migrate(badInstance)
    lu.assertNil(saved)
    lu.assertEquals(reason, '物品实例损坏')

    local strayKey = realSnapshot()
    strayKey.bar = { { i = 2, id = 'garMeat', n = 1 }, abc = { i = 3, id = 'shrimpRod', n = 1 }, __count = 1 }
    saved, reason = migrator(94):Migrate(strayKey)
    lu.assertNil(saved)
    lu.assertEquals(reason, '库存结构损坏')

    -- 只有「恰好名为 __count 且值是非负整数」才认作平台标记，其它形态照旧当损坏拒绝。
    local bogusMarker = realSnapshot()
    bogusMarker.bar = { { i = 2, id = 'garMeat', n = 1 }, __count = 'two' }
    saved, reason = migrator(95):Migrate(bogusMarker)
    lu.assertNil(saved)
    lu.assertEquals(reason, '库存结构损坏')

    -- 标记小于实际同样不采信：长度以实际条数为准，绝不因 __count 截断物品。
    local understated = realSnapshot()
    understated.bar = { { i = 2, id = 'garMeat', n = 1 }, { i = 3, id = 'shrimpRod', n = 1 }, __count = 1 }
    local logs = capturePrint(function()
        saved = migrator(96):Migrate(understated)
    end)
    lu.assertNotNil(saved)
    lu.assertEquals(#saved.bar, 2)
    lu.assertEquals(saved.bar[2].id, 'shrimpRod')
    lu.assertNotNil(string.find(table.concat(logs, '\n'), '数组长度标记不一致', 1, true))
end

function TestSaveArrayMeta:test_markerless_old_snapshot_and_migration_output_unchanged()
    local plain = realSnapshot()
    plain.bar.__count, plain.bp.__count = nil, nil
    local saved = migrator(97):Migrate(plain)
    lu.assertNotNil(saved)
    lu.assertEquals(saved.v, 2)
    lu.assertEquals(saved.bar[1].id, 'garMeat')
    lu.assertEquals(#saved.bar, 2)
    lu.assertEquals(#saved.bp, 2)
    lu.assertFalse(hasCountKey(saved))
    -- 入参原地不被改写（迁移只作用于副本）。
    local upstream = realSnapshot()
    lu.assertNotNil(migrator(98):Migrate(upstream))
    lu.assertEquals(upstream.bar.__count, 2)
    lu.assertEquals(upstream.v, 1)
end

function TestSaveArrayMeta:test_strip_export_is_a_deep_copy_that_drops_only_the_marker()
    -- Migrate 会对副本原地改写（LegacyIdMap 改名、bait 合并），剥离必须走深拷贝、不与入参共享子表。
    local shared = { a = 1 }
    local input = { bar = { { i = 1, id = 'shrimpRod' }, __count = 1 }, p = shared, q = shared, keep = 7 }
    local out = PlayerData.StripArrayMeta(input, 'save')
    lu.assertNil(out.bar.__count)
    lu.assertEquals(out.bar[1].id, 'shrimpRod')
    lu.assertEquals(out.keep, 7)
    lu.assertFalse(rawequal(out.p, input.p))
    lu.assertFalse(rawequal(out.q, input.q))
    out.p.a = 2
    lu.assertEquals(input.p.a, 1)
    lu.assertFalse(hasCountKey(out))
end

function TestSaveArrayMeta:test_v2_meta_operations_marker_is_stripped_from_memory_and_write()
    local source = fresh(99)
    local snapshot = source:Serialize()
    snapshot.meta.sequence = 1
    snapshot.meta.operations = { { id = '99:1', sequence = 1, kind = 'probe', result = { coin = 7 } }, __count = 1 }
    snapshot.bar = { __count = 0 }
    local data = pending(99)
    lu.assertTrue(data:CompleteLoad(snapshot))
    lu.assertEquals(#data.SaveMeta.operations, 1)
    lu.assertEquals(data.SaveMeta.operations[1].id, '99:1')
    lu.assertNil(data.SaveMeta.operations.__count)
    lu.assertFalse(hasCountKey(data:Serialize()))
end

function TestSaveArrayMeta:setUp()
    self.oldGame = _G.game
    self.values, self.queue, self.attributes = {}, {}, {}
    local env = self
    self.store = {
        -- 平台每次回读都给列表补 __count；写回包同样带。
        GetAsync = function(_, key) return markLists(env.values[key]) end,
        UpdateAsync = function(_, key, transform)
            local value = transform(markLists(env.values[key]))
            if value then env.values[key] = copy(value) end
            return markLists(value)
        end,
        SetAsync = function(_, key, value) env.values[key] = copy(value) end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return 100 end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
    end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
end

function TestSaveArrayMeta:tearDown() _G.game = self.oldGame end
function TestSaveArrayMeta:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestSaveArrayMeta:test_mgr_save_joins_ready_and_stores_without_platform_metadata()
    -- 云端已有真机同形旧档：修复前这里必然走 Fail('库存结构损坏')，屏障永久关闭。
    self.values.u80 = copy(realSnapshot())
    local player = { UserId = 80, SetAttribute = function(_, key, value) self.attributes[key] = value end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.save:LoadInto(player, data)
    self:drain()
    lu.assertEquals(self.attributes.SaveState, 'ready')
    lu.assertEquals(data.LoadState, 'ready')
    lu.assertTrue(data.Inited)
    lu.assertEquals(data.Data.FishCoin, 4966)
    lu.assertEquals(data:ItemCount('garMeat'), 1)
    lu.assertEquals(data:ItemCount('eelMeat'), 1)
    lu.assertFalse(hasCountKey(data:Serialize()))
    lu.assertFalse(hasCountKey(self.values.u80))
    -- 就绪后普通写路径同样不把平台标记带进库。
    lu.assertTrue(data:AddCoin(1))
    lu.assertTrue(self.save:Save(80, data:Serialize(), 'probe'))
    self:drain()
    lu.assertEquals(self.values.u80.coin, 4967)
    lu.assertFalse(hasCountKey(self.values.u80))
end

function TestSaveArrayMeta:test_mgr_save_operation_reply_keeps_memory_clean()
    self.values.u81 = copy(realSnapshot())
    local player = { UserId = 81, SetAttribute = function() end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.save:LoadInto(player, data)
    self:drain()
    local op = self.save:NextOperation(player, 'probe')
    local result
    -- 写回包带 __count：修复前 value.meta 会把标记带进 data.SaveMeta 并写进下一次快照。
    lu.assertTrue(self.save:Execute(player, data, op, function(draft)
        draft:AddCoin(3)
        return { awarded = 3 }
    end, function(ok, value) result = { ok, value } end))
    self:drain()
    lu.assertTrue(result[1])
    lu.assertEquals(data.Data.FishCoin, 4969)
    lu.assertNil(data.SaveMeta.operations.__count)
    lu.assertFalse(hasCountKey(data:Serialize()))
    lu.assertFalse(hasCountKey(self.values.u81))
end
