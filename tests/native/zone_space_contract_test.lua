-- #65 P3：空间合同核对工具的用例（fast 车道）。
-- 覆盖两件事：
--   1. 纯几何/解析函数的语义（CSV 引号、pivot 盒体、地板与障碍的区分、岸线采样、净宽量法、
--      边界内面与差值、JSON 编码）——这些是「声明与核对」的判据来源，错了会把结论带偏；
--   2. 提交的证据 JSON 与「当前基线 CSV + 当前 GameCfg」重新算出来的一致：
--      场景基线更新（重新生成 CSV）后忘了重算证据，就会在这里红。
local audit = require('tools.zone_space_contract')

local HEADER = 'zone,depth,path,name,type,spatial,pos,rot,scale,size,canCollide,canQuery,physicsActive,bodyType,assetId'

local function csvLine(zone, depth, path, name, unitType, spatial, pos, size, canCollide, canQuery)
    return table.concat({ zone, depth, path, name, unitType, spatial, '"' .. pos .. '"',
        '"Quaternion(0,0,0,1)"', '"1.000,1.000,1.000"', '"' .. size .. '"',
        canCollide and 'true' or 'false', canQuery and 'true' or 'false', 'true', '2', 'official://preset/1' }, ',')
end

local function csvOf(rows)
    return table.concat({ HEADER, table.concat(rows, '\n') }, '\n')
end

--- 合成一个区：四面墙压中线 + 可选附加对象。
local function zoneCsv(label, centerX, centerZ)
    local rows = {}
    local function wall(path, name, pos, size)
        rows[#rows + 1] = csvLine(label, 2, path, name, 'WorldUnit', 1, pos, size, true, true)
    end
    wall(label .. '/空气墙/East', 'East', string.format('%d,-30,%d', centerX - 60, centerZ - 10), '3,70,120')
    wall(label .. '/空气墙/West', 'West', string.format('%d,-30,%d', centerX + 60, centerZ - 10), '3,70,120')
    wall(label .. '/空气墙/North', 'North', string.format('%d,-30,%d', centerX, centerZ - 60), '120,70,3')
    wall(label .. '/空气墙/South', 'South', string.format('%d,-30,%d', centerX, centerZ + 60), '120,70,3')
    return rows
end

describe('#65 P3 空间合同核对工具', function()
    it('CSV 解析：引号字段里的逗号不当分隔符', function()
        local fields = audit.splitCsvLine('a,"90.000,2.000,60.000",b')
        assert.are.equal(3, #fields)
        assert.are.equal('90.000,2.000,60.000', fields[2])
    end)

    it('CSV 解析：表头映射与空行跳过', function()
        local rows = audit.parseCsv('name,pos\n甲,"1,2,3"\n\n乙,"4,5,6"\n')
        assert.are.equal(2, #rows)
        assert.are.equal('甲', rows[1].name)
        assert.are.equal('1,2,3', rows[1].pos)
    end)

    it('盒体口径：Y 轴 Position 是底面、X/Z 以 Position 为中心', function()
        local box = audit.box({ pos = '"10.000,5.000,-2.000"', size = '"4.000,2.000,6.000"' })
        assert.are.equal(5, box.minY)
        assert.are.equal(7, box.maxY, '顶面应是 5 + 2，不是 5 + 1')
        assert.are.equal(8, box.minX)
        assert.are.equal(12, box.maxX)
        assert.are.equal(-5, box.minZ)
        assert.are.equal(1, box.maxZ)
    end)

    it('盒体口径：坐标字段不合法时返回 nil，不静默当 0', function()
        assert.is_nil(audit.box({ pos = '', size = '"1,1,1"' }))
        assert.is_nil(audit.box({ pos = '"1,2,3"', size = '"1,1"' }))
        assert.is_nil(audit.parseTriple('1,x,3'))
    end)

    it('地板与障碍：贴地垫片是地板，高出地面 0.5 的设施块是障碍', function()
        local groundY = 6
        local pad = { canCollide = true, minY = 6.0, maxY = 6.2 }
        local cube = { canCollide = true, minY = 5.0, maxY = 6.5 }
        assert.is_true(audit.isWalkableSurface(pad, groundY))
        assert.is_false(audit.isWalkableSurface(cube, groundY))
        assert.is_false(audit.isBlocker(pad, groundY, 3, 'all'), '地板不算障碍')
        assert.is_true(audit.isBlocker(cube, groundY, 3, 'collision'))
        local high = { canCollide = true, minY = 40, maxY = 43 }
        assert.is_false(audit.isBlocker(high, groundY, 3, 'all'), '行走高度带之外的遮挡不算侵占')
    end)

    it('障碍口径：TriggerUnit 只算交互范围，不算实体碰撞体', function()
        local trigger = { canCollide = false, isTrigger = true, minY = 5, maxY = 14 }
        assert.is_false(audit.isBlocker(trigger, 6, 3, 'collision'))
        assert.is_true(audit.isBlocker(trigger, 6, 3, 'all'))
    end)

    it('水岸：同心的两个水圈取外圈 WaterCircle2', function()
        local zone = { Scene = { Boundary = { MinX = -69, MaxX = 69, MinZ = -59, MaxZ = 79 }, Waters = {} } }
        local nodes = audit.nodesOf(audit.parseCsv(csvOf({
            csvLine('01 鱼塘', 2, '01 鱼塘/地块/WaterCircle1', 'WaterCircle1', 'WorldUnit', 1, '-11.75,1.05,-12.25', '6,1,6', false, true),
            csvLine('01 鱼塘', 2, '01 鱼塘/地块/WaterCircle2', 'WaterCircle2', 'WorldUnit', 1, '-11.75,1.05,-12.25', '12,1,12', false, true),
        })), '01 鱼塘')
        local shore = audit.shoreFacts(zone, nodes)
        assert.are.equal('WaterCircle2', shore.name)
        assert.are.equal('circle', shore.kind)
        assert.are.equal(6, shore.radius)
    end)

    it('水岸：无现场水面实体时退回配置水域，并给出内侧方向', function()
        local zone = { Scene = {
            Boundary = { MinX = 420, MaxX = 540, MinZ = -70, MaxZ = 50 },
            Waters = { { Center = { x = 480, y = 2, z = -44 }, HalfX = 40, HalfZ = 12, SurfaceY = 3 } },
        } }
        local shore = audit.shoreFacts(zone, {})
        assert.are.equal('config', shore.source)
        assert.are.equal('rect', shore.kind)
        assert.are.equal(1, shore.inland, '水域在 −Z 侧时内侧朝 +Z')
        assert.are.equal(-32, shore.edgeZ)
        assert.are.equal(440, shore.spanMin)
        assert.are.equal(520, shore.spanMax)
    end)

    it('岸边通道：净宽量到第一个碰撞体，交互范围另算一套', function()
        local boundary = { MinX = 420, MaxX = 540, MinZ = -70, MaxZ = 50 }
        local shore = { kind = 'rect', inland = 1, edgeZ = -32, spanMin = 440, spanMax = 520 }
        local nodes = {
            { name = 'Block', canCollide = true, isTrigger = false, minX = 470, maxX = 490,
              minZ = -22, maxZ = -20, minY = 6, maxY = 7.5 },
            { name = 'Trigger', canCollide = false, isTrigger = true, minX = 440, maxX = 520,
              minZ = -32, maxZ = -28, minY = 6, maxY = 14 },
        }
        local corridor = audit.corridor(shore, nodes, boundary, 6)
        assert.are.equal(10, corridor.collision.minWidth, '岸线 −32 到碰撞体近面 −22 是 10')
        assert.are.equal(0, corridor.all.minWidth, '交互范围压在岸线上')
        local blocked = false
        for _, name in ipairs(corridor.collision.blockers) do
            if name == 'Block' then blocked = true end
        end
        assert.is_true(blocked, '挡路的实体应被记进 blockers')
        assert.is_true(corridor.collision.longestRunLength > 0)
        assert.is_true(corridor.all.longestRunLength < corridor.collision.longestRunLength,
            '交互范围压在岸线上时，含交互口径的连续段应更短')
    end)

    it('战斗净空间：紧贴水岸与退让通道两种锚法相差通道宽度', function()
        local boundary = { MinX = 420, MaxX = 540, MinZ = -70, MaxZ = 50 }
        local shore = { kind = 'rect', inland = 1, edgeZ = -32, spanMin = 440, spanMax = 520 }
        local rects = audit.combatRects(shore, boundary, 32, 28, 8)
        assert.are.equal(2, #rects)
        assert.are.equal(-32, rects[1].minZ)
        assert.are.equal(-4, rects[1].maxZ)
        assert.are.equal(8, rects[2].minZ - rects[1].minZ)
        assert.are.equal(464, rects[1].minX)
        assert.are.equal(496, rects[1].maxX)
    end)

    it('战斗净空间：水岸宽度不足时按比例收缩并暴露缩放值', function()
        local boundary = { MinX = 215, MaxX = 265, MinZ = -70, MaxZ = 50 }
        local shore = { kind = 'rect', inland = -1, edgeZ = -9, spanMin = 232, spanMax = 238 }
        local rects = audit.combatRects(shore, boundary, 24, 20, 8)
        assert.are.equal(0.25, rects[1].scale)
    end)

    it('战斗净空间：圆岸改用水域包围盒四条边做候选，贴盒不重叠', function()
        local shore = { kind = 'circle', centerX = -11.75, centerZ = -12.25, radius = 6,
            minX = -17.75, maxX = -5.75, minZ = -18.25, maxZ = -6.25 }
        local rects = audit.combatRects(shore, {}, 24, 20, 8)
        assert.are.equal(4, #rects)
        local plusX = rects[1]
        assert.are.equal(-5.75, plusX.minX, '近边贴水域包围盒的 +X 边')
        assert.are.equal(18.25, plusX.maxX)
        assert.are.equal(-22.25, plusX.minZ)
        assert.are.equal(-2.25, plusX.maxZ)
    end)

    it('段与盒相交：正前方命中、侧向不命中、射程外不命中', function()
        local box = { minX = 10, maxX = 12, minZ = -1, maxZ = 1 }
        assert.are.equal(10, audit.segmentEnterT(0, 0, 1, 0, box, 100))
        assert.is_nil(audit.segmentEnterT(0, 50, 1, 0, box, 100))
        assert.is_nil(audit.segmentEnterT(0, 0, 1, 0, box, 5))
    end)

    it('边界声明：墙压中线时内面比数学范围各进来半个墙厚', function()
        local boundary = { MinX = 420, MaxX = 540, MinZ = -70, MaxZ = 50 }
        local nodes = audit.nodesOf(audit.parseCsv(csvOf(zoneCsv('03 蟹湖', 480, -10))), '03 蟹湖')
        local walls = audit.boundaryFacts(boundary, nodes)
        assert.are.equal(4, walls.wallCount)
        assert.are.equal(421.5, walls.innerMinX)
        assert.are.equal(538.5, walls.innerMaxX)
        assert.are.equal(-68.5, walls.innerMinZ)
        assert.are.equal(48.5, walls.innerMaxZ)
    end)

    it('锚点坐标差：同名对象给出 x/y/z 差，缺对象按配置状态归档', function()
        local zone = { Scene = { Entities = {
            { Name = 'Z3_Lottery', Role = 'Lottery', Position = { x = 485, y = 5, z = -5 }, State = 'planned' },
            { Name = 'Z3_Safe', Role = 'Safe', Position = { x = 480, y = 6, z = 0 }, State = 'planned' },
        } } }
        local nodes = audit.nodesOf(audit.parseCsv(csvOf({
            csvLine('03 蟹湖', 2, '03 蟹湖/设施/Z3_Lottery', 'Z3_Lottery', 'WorldUnit', 1, '486,5,-5', '1.5,1.5,1.5', true, true),
        })), '03 蟹湖')
        local deltas = audit.anchorDeltas(zone, nodes)
        assert.are.equal(2, deltas.entries)
        assert.are.equal(1, deltas.resolved)
        assert.are.equal(1, deltas.nonzero)
        assert.are.equal(1, deltas.maxDx)
        assert.are.equal('Z3_Safe', deltas.missing[1].name)
    end)

    it('JSON 编码：对象键排序、数组保序、非法数字写 null', function()
        local text = audit.encodeJson({ { b = 1, a = 2 }, 0 / 0 })
        assert.is_truthy(text:find('"a"', 1, true) < text:find('"b"', 1, true))
        assert.is_truthy(text:find('null', 1, true))
        assert.is_truthy(text:find('[\n', 1, true))
    end)

    it('证据 JSON 与「当前基线 CSV + 当前 GameCfg」重算一致', function()
        local text = audit.readFile(audit.EVIDENCE_JSON)
        assert.is_truthy(text, '读不到证据 ' .. audit.EVIDENCE_JSON ..
            '：跑 lua tools/zone_space_contract.lua --json ' .. audit.EVIDENCE_JSON)
        local csv = audit.readFile(audit.CSV)
        assert.is_truthy(csv, '读不到基线 CSV ' .. audit.CSV)
        local zones = audit.audit(require('common.GameCfg'), audit.parseCsv(csv))
        local payload = { source = audit.CSV, corridorMin = audit.CORRIDOR_MIN, headroom = audit.HEADROOM,
            combat = audit.COMBAT, zones = zones }
        audit.stripBoxes(payload)
        assert.are.equal(audit.encodeJson(payload), text,
            '证据已过时：请重跑 lua tools/zone_space_contract.lua --json ' .. audit.EVIDENCE_JSON)
    end)
end)
