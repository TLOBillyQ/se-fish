-- #88 迁移：存档列表元数据标记（原 tests/gameplay/save_array_meta_test.lua，8 例）。
-- #123 P0：平台在列表型 Lua 表跨引擎边界时附加 __count 长度键（真机证据 .scratch/125/playtest-20260929-215641/
-- 19-probe-save.txt：bar/bp 回读带 __count=2，同一回包的字典型 bait 不带），导致 Migrate 的严格键校验
-- 把所有老档判成「库存结构损坏」→ 读写屏障永久关闭。
-- 本单失败方式先列：合法存档因平台元数据被拒（本文件主测）；剥离时顺手放松校验放行真损坏档；
-- 长度以 __count 为准而非实际条数；平台元数据被带回内存并写回库；无标记的旧档受影响。
-- seam：真实 PlayerData.Migrate/CompleteLoad 与 MgrSave 公共接口；只替换 Task/DataStore 引擎边界。
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- 断言映射：assertEquals 的 table 深比较由 assert.same 承接；assertFalse 是严格 false（rawequal / hasCountKey
-- 都只返回布尔，语义不变）。
-- 注意：capturePrint 必须改写真实全局 `_G.print`。Busted 对案例文件套逐文件沙箱，
-- 裸赋值 `print = fn` 只改沙箱副本，被测模块（其 _ENV 是真实 _G）看不到，日志会全部漏捕获。
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

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

-- 保留旧语义：失败也要把 print 还回去再重新抛出，不让捕获器泄漏到后续案例。
local function capturePrint(fn)
    local logs = {}
    local real = _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        logs[#logs + 1] = table.concat(parts, ' ')
    end
    local ok, err = pcall(fn)
    _G.print = real
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

describe('TestSaveArrayMeta', function()
    local env, savedGame

    -- 逐例夹具：旧 LuaUnit 对每个方法都跑 setUp/tearDown，这里同样用 before_each/after_each，
    -- 因此只调 Migrate 的案例也一样会建立引擎边界替身（与旧套件一致）。
    -- before_each 第一步保存 _G.game，夹具中途抛错时 after_each 仍能恢复全局。
    before_each(function()
        savedGame = rawget(_G, 'game')
        env = { values = {}, queue = {}, attributes = {} }
        env.store = {
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
        env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    end)
    after_each(function()
        _G.game = savedGame
        savedGame = nil
        env = nil
    end)

    local function drain()
        while #env.queue > 0 do table.remove(env.queue, 1)() end
    end

    it('test_empty_marker_and_mismatched_count_follow_actual_entries', function()
        local logs = capturePrint(function()
            local data = pending(91)
            local snapshot = realSnapshot()
            snapshot.bar = { __count = 0 }
            snapshot.bp = { { i = 2, id = 'eelMeat', n = 1 }, __count = 7 }
            assert.is_true(data:CompleteLoad(snapshot))
            assert.same(1, data:ItemCount('eelMeat'))
            assert.is_nil(data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1])
        end)
        local joined = table.concat(logs, '\n')
        -- 声称 7 条、实际 1 条：以实际条数为准，并留一行痕迹。
        assert.is_not_nil(string.find(joined, '数组长度标记不一致', 1, true))
        assert.is_not_nil(string.find(joined, 'save.bp', 1, true))
    end)

    it('test_markerless_old_snapshot_and_migration_output_unchanged', function()
        local plain = realSnapshot()
        plain.bar.__count, plain.bp.__count = nil, nil
        local saved = migrator(97):Migrate(plain)
        assert.is_not_nil(saved)
        assert.same(2, saved.v)
        assert.same('garMeat', saved.bar[1].id)
        assert.same(2, #saved.bar)
        assert.same(2, #saved.bp)
        assert.is_false(hasCountKey(saved))
        -- 入参原地不被改写（迁移只作用于副本）。
        local upstream = realSnapshot()
        assert.is_not_nil(migrator(98):Migrate(upstream))
        assert.same(2, upstream.bar.__count)
        assert.same(1, upstream.v)
    end)

    it('test_mgr_save_joins_ready_and_stores_without_platform_metadata', function()
        -- 云端已有真机同形旧档：修复前这里必然走 Fail('库存结构损坏')，屏障永久关闭。
        env.values.u80 = copy(realSnapshot())
        local p = { UserId = 80, SetAttribute = function(_, key, value) env.attributes[key] = value end }
        local data = PlayerData.New(p)
        data:Init(true)
        env.save:LoadInto(p, data)
        drain()
        assert.same('ready', env.attributes.SaveState)
        assert.same('ready', data.LoadState)
        assert.is_true(data.Inited)
        assert.same(4966, data.Data.FishCoin)
        assert.same(1, data:ItemCount('garMeat'))
        assert.same(1, data:ItemCount('eelMeat'))
        assert.is_false(hasCountKey(data:Serialize()))
        assert.is_false(hasCountKey(env.values.u80))
        -- 就绪后普通写路径同样不把平台标记带进库。
        assert.is_true(data:AddCoin(1))
        assert.is_true(env.save:Save(80, data:Serialize(), 'probe'))
        drain()
        assert.same(4967, env.values.u80.coin)
        assert.is_false(hasCountKey(env.values.u80))
    end)

    it('test_mgr_save_operation_reply_keeps_memory_clean', function()
        env.values.u81 = copy(realSnapshot())
        local p = { UserId = 81, SetAttribute = function() end }
        local data = PlayerData.New(p)
        data:Init(true)
        env.save:LoadInto(p, data)
        drain()
        local op = env.save:NextOperation(p, 'probe')
        local result
        -- 写回包带 __count：修复前 value.meta 会把标记带进 data.SaveMeta 并写进下一次快照。
        assert.is_true(env.save:Execute(p, data, op, function(draft)
            draft:AddCoin(3)
            return { awarded = 3 }
        end, function(ok, value) result = { ok, value } end))
        drain()
        assert.is_true(result[1])
        assert.same(4969, data.Data.FishCoin)
        assert.is_nil(data.SaveMeta.operations.__count)
        assert.is_false(hasCountKey(data:Serialize()))
        assert.is_false(hasCountKey(env.values.u81))
    end)

    it('test_platform_marker_never_relaxes_corruption_rejection', function()
        local hole = realSnapshot()
        hole.bp = { [1] = { i = 2, id = 'eelMeat', n = 1 }, [3] = { i = 3, id = 'tilapia', n = 1 }, __count = 3 }
        local saved, reason = migrator(92):Migrate(hole)
        assert.is_nil(saved)
        assert.same('库存序列不连续', reason)

        local badInstance = realSnapshot()
        badInstance.bar = { { i = 2, id = 'garMeat', n = 0 }, __count = 1 }
        saved, reason = migrator(93):Migrate(badInstance)
        assert.is_nil(saved)
        assert.same('物品实例损坏', reason)

        local strayKey = realSnapshot()
        strayKey.bar = { { i = 2, id = 'garMeat', n = 1 }, abc = { i = 3, id = 'shrimpRod', n = 1 }, __count = 1 }
        saved, reason = migrator(94):Migrate(strayKey)
        assert.is_nil(saved)
        assert.same('库存结构损坏', reason)

        -- 只有「恰好名为 __count 且值是非负整数」才认作平台标记，其它形态照旧当损坏拒绝。
        local bogusMarker = realSnapshot()
        bogusMarker.bar = { { i = 2, id = 'garMeat', n = 1 }, __count = 'two' }
        saved, reason = migrator(95):Migrate(bogusMarker)
        assert.is_nil(saved)
        assert.same('库存结构损坏', reason)

        -- 标记小于实际同样不采信：长度以实际条数为准，绝不因 __count 截断物品。
        local understated = realSnapshot()
        understated.bar = { { i = 2, id = 'garMeat', n = 1 }, { i = 3, id = 'shrimpRod', n = 1 }, __count = 1 }
        local logs = capturePrint(function()
            saved = migrator(96):Migrate(understated)
        end)
        assert.is_not_nil(saved)
        assert.same(2, #saved.bar)
        assert.same('shrimpRod', saved.bar[2].id)
        assert.is_not_nil(string.find(table.concat(logs, '\n'), '数组长度标记不一致', 1, true))
    end)

    it('test_real_cloud_snapshot_with_platform_count_marker_loads_ready', function()
        local data = pending(90)
        assert.is_true(data:CompleteLoad(realSnapshot()))
        assert.same('ready', data.LoadState)
        assert.same(4966, data.Data.FishCoin)
        assert.same(6, data.Data.UpgradeLevel)
        assert.same('fishPond1', data.Data.Zone)
        assert.same(3, data.Data.Bait.worm)
        assert.same(0, data.Data.Bait.sausage)
        local bar = data.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
        assert.same('garMeat', bar[2].itemId)
        assert.same(1.23, bar[2].mult)
        assert.same('shrimpRod', bar[3].itemId)
        assert.is_nil(bar[1])
        local bp = data.Data.Containers[GameCfg.Items.ContainerId.Backpack]
        assert.same('eelMeat', bp[2].itemId)
        assert.same(1.87, bp[2].mult)
        assert.same('tilapia', bp[3].itemId)
        assert.same(1.42, bp[3].mult)
        -- 平台标记不得进入内存，也不得被下一次 Serialize 写回库。
        assert.is_false(hasCountKey(data:Serialize()))
    end)

    it('test_strip_export_is_a_deep_copy_that_drops_only_the_marker', function()
        -- Migrate 会对副本原地改写（LegacyIdMap 改名、bait 合并），剥离必须走深拷贝、不与入参共享子表。
        local shared = { a = 1 }
        local input = { bar = { { i = 1, id = 'shrimpRod' }, __count = 1 }, p = shared, q = shared, keep = 7 }
        local out = PlayerData.StripArrayMeta(input, 'save')
        assert.is_nil(out.bar.__count)
        assert.same('shrimpRod', out.bar[1].id)
        assert.same(7, out.keep)
        assert.is_false(rawequal(out.p, input.p))
        assert.is_false(rawequal(out.q, input.q))
        out.p.a = 2
        assert.same(1, input.p.a)
        assert.is_false(hasCountKey(out))
    end)

    it('test_v2_meta_operations_marker_is_stripped_from_memory_and_write', function()
        local source = fresh(99)
        local snapshot = source:Serialize()
        snapshot.meta.sequence = 1
        snapshot.meta.operations = { { id = '99:1', sequence = 1, kind = 'probe', result = { coin = 7 } }, __count = 1 }
        snapshot.bar = { __count = 0 }
        local data = pending(99)
        assert.is_true(data:CompleteLoad(snapshot))
        assert.same(1, #data.SaveMeta.operations)
        assert.same('99:1', data.SaveMeta.operations[1].id)
        assert.is_nil(data.SaveMeta.operations.__count)
        assert.is_false(hasCountKey(data:Serialize()))
    end)
end)
