-- #102 锚点坐标同步 dry-run 的用例（fast 车道）。
-- 覆盖两件事：
--   1. 解析语义：现场实测位置取 (x=centerX, y=minY, z=centerZ)、位移方向、pivot 疑点标记、
--      运行时真源标记 —— 这些决定了「配置要改成什么」，错了会把同步带到错坐标；
--   2. 提交的施工后基线 + 当前 GameCfg 重算出的分布：同步完成后 **x/z 全为 0**，只剩 Safe 的
--      Δy=−0.20（配置 6.00 是地面基准 GroundY、现场 5.80 是安全垫片的底面）—— 场景快照或
--      GameCfg 变了就会在这里红，重算再更新期望。
local sync = require('tools.anchor_coord_sync_dry_run')
local contract = require('tools.zone_space_contract')

local HEADER = 'zone,depth,path,name,type,spatial,pos,rot,scale,size,canCollide,canQuery,physicsActive,bodyType,assetId'

local function csvLine(zone, depth, path, name, pos, size)
    return table.concat({ zone, depth, path, name, 'WorldUnit', '1', '"' .. pos .. '"',
        '"Quaternion(0,0,0,1)"', '"1.000,1.000,1.000"', '"' .. size .. '"',
        'true', 'true', 'true', '2', 'official://preset/1' }, ',')
end

local function rowsOf(lines)
    return contract.parseCsv(table.concat({ HEADER, table.concat(lines, '\n') }, '\n'))
end

--- 合成一个 facility：位置 10,5,-5，尺寸 2×2×2（minY=5、centerY=6，故意让 centerY≠minY）。
local FACILITY = csvLine('03 蟹湖', 2, '03 蟹湖/设施/Z3_Lottery', 'Z3_Lottery', '509.000,5.000,-5.000', '2.000,2.000,2.000')

describe('#102 锚点坐标同步 dry-run', function()
    it('现场实测位置：x/z 取中心、y 取底面，配置一致时不算需要同步', function()
        local zone = { Scene = { Entities = {
            { Name = 'Z3_Lottery', Role = 'Lottery', Position = { x = 509, y = 5, z = -5 }, State = 'planned' },
        } } }
        local result = sync.resolveZone(zone, '03 蟹湖', rowsOf({ FACILITY }))
        local entry = result.entries[1]
        assert.are.equal(509, entry.target.x)
        assert.are.equal(5, entry.target.y, 'y 取底面 minY，不是中心')
        assert.are.equal(-5, entry.target.z)
        assert.is_false(entry.needsSync)
    end)

    it('位移方向：现场减配置，且中心≠底面时标记 pivot 疑点', function()
        local zone = { Scene = { Entities = {
            { Name = 'Z3_Lottery', Role = 'Lottery', Position = { x = 500, y = 6, z = 0 }, State = 'planned' },
        } } }
        local entry = sync.resolveZone(zone, '03 蟹湖', rowsOf({ FACILITY })).entries[1]
        assert.are.equal(9, entry.delta.x)
        assert.are.equal(-1, entry.delta.y)
        assert.are.equal(-5, entry.delta.z)
        assert.is_true(entry.needsSync)
        assert.is_true(entry.pivotSuspect, '尺寸 2 的方块 centerY=6 ≠ minY=5，必须标出来')
    end)

    it('运行时真源：Safe/Ferry/Bait/Water 标出，其余角色不标', function()
        local entity = { Name = 'Z3_Lottery', Role = 'Lottery', Position = { x = 0, y = 0, z = 0 }, State = 'planned' }
        local consumed = {}
        for role in pairs(sync.RUNTIME_CONSUMERS) do consumed[role] = true end
        assert.is_true(consumed.Safe)
        assert.is_true(consumed.Ferry)
        assert.is_true(consumed.Bait)
        assert.is_true(consumed.Water)
        assert.is_nil(consumed.Lottery, '设施锚点不是运行时输入')
        local zone = { Scene = { Entities = { entity } } }
        local entry = sync.resolveZone(zone, '03 蟹湖', rowsOf({ FACILITY })).entries[1]
        assert.are.equal('Lottery', entry.role, '角色未改，still 不是运行时真源')
        assert.is_nil(entry.runtimeConsumer, '设施锚点不是运行时真源，不该被标记')
    end)

    it('匿名标记：现场没有同名对象时进 missing，不按坐标凑', function()
        local zone = { Scene = { Entities = {
            { Name = 'Z3_Ghost', Role = 'Shop', Position = { x = 1, y = 2, z = 3 }, State = 'planned' },
        } } }
        local result = sync.resolveZone(zone, '03 蟹湖', rowsOf({ FACILITY }))
        assert.are.equal(0, #result.entries)
        assert.are.equal(1, #result.missing)
        assert.are.equal('Z3_Ghost', result.missing[1].name)
    end)

    it('JSON 编码：对象键排序、数组保序', function()
        local text = sync.encodeJson({ { b = 1, a = 2 }, 3 })
        assert.is_truthy(text:find('"a"', 1, true) < text:find('"b"', 1, true))
        assert.is_truthy(text:find('3', 1, true))
    end)

    it('施工后基线 + 当前 GameCfg：90 条锚点全部与现场一致', function()
        local text = assert(contract.readFile(sync.CSV), '读不到施工后基线 ' .. sync.CSV)
        local zones = sync.audit(require('common.GameCfg'), contract.parseCsv(text))
        local counts, total = {}, 0
        for _, zone in ipairs(zones) do
            local syncCount = 0
            for _, entry in ipairs(zone.entries) do
                if entry.needsSync then syncCount = syncCount + 1 end
            end
            counts[zone.label] = string.format('%d/%d', syncCount, #zone.entries)
            total = total + syncCount
        end
        assert.are.equal('0/15', counts['03 蟹湖'])
        assert.are.equal('0/15', counts['04 树林岛'])
        assert.are.equal('0/15', counts['05 沙滩岛'])
        assert.are.equal('0/15', counts['06 礁石岛'])
        assert.are.equal('0/14', counts['07 火山岛'])
        assert.are.equal('0/6', counts['01 鱼塘'])
        assert.are.equal('0/10', counts['02 虾池'])
        assert.are.equal(0, total, '配置与施工后现场不一致：跑 lua tools/anchor_coord_sync_dry_run.lua 看具体是哪几条')
    end)

    it('y 口径：Safe 取现场顶面（地面高度），位置类单位取底面（pivot）', function()
        local rows = rowsOf({ csvLine('03 蟹湖', 2, '03 蟹湖/摆渡/Z3_Safe', 'Z3_Safe', '480.000,5.800,30.500', '10.000,0.200,10.000') })
        local zone = { Scene = { Entities = {
            { Name = 'Z3_Safe', Role = 'Safe', Position = { x = 480, y = 6, z = 30.5 }, State = 'planned' },
        } } }
        local entry = sync.resolveZone(zone, '03 蟹湖', rows).entries[1]
        assert.are.equal('top', entry.yReference)
        assert.are.equal(6, entry.target.y, 'Safe 的 y 目标是可站立面顶面 6.00，不是垫片底面 5.80')
        assert.is_false(entry.needsSync, '配置写地面高度时不该报需要同步')
        assert.are.equal('bottom', sync.yReference('Lottery'), '设施锚点是位置类单位，仍取底面')
        local facility = sync.resolveZone({ Scene = { Entities = {
            { Name = 'Z3_Lottery', Role = 'Lottery', Position = { x = 509, y = 5, z = -5 }, State = 'planned' },
        } } }, '03 蟹湖', rowsOf({ FACILITY })).entries[1]
        assert.are.equal('bottom', facility.yReference)
        assert.are.equal(5, facility.target.y, '设施取底面 minY')
    end)
end)
