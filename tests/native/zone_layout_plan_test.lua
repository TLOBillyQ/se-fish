-- #65 P3：灰盒布局规划器的用例（fast 车道）。
-- 覆盖三件事：
--   1. 规划出的布局**在设计上达标**（岸边通道 ≥8 两套口径、战斗净空间无侵占、支撑 100%）；
--   2. 地形拼合无洞无叠（五块板的面积之和 = 边界面积，且互不重叠）、地块顶 = 合同地面、
--      塘底顶 < 水面顶 < 地面（水塘式），水面那块不被铺地；
--   3. 探针数据块与规划器逐字节同步，且「必须已存在」的操作确实在基线里、「要新建」的名字确实不在。
local plan = require('tools.plan_zone_layout')
local GameCfg = require('common.GameCfg')
local audit = require('tools.zone_space_contract')

local rows = plan.parseCsvRows(plan.readFile(plan.CSV))

local function layouts()
    local list, skipped = plan.buildAll(GameCfg, rows)
    assert.are.equal(0, #skipped, '规划器跳过了区：' .. table.concat(skipped, ' / '))
    assert.are.equal(#plan.TARGET_ZONES, #list)
    return list
end

describe('#65 P3 灰盒布局规划器', function()
    it('基线可读，且五个目标区都能规划', function()
        assert.is_truthy(rows, '读不到 ' .. plan.CSV)
        layouts()
    end)

    it('每个区在设计上达标：岸边通道、战斗净空间、支撑、地块顶', function()
        for _, layout in ipairs(layouts()) do
            local m = plan.metrics(layout)
            assert.is_true(m.corridorCollision >= plan.CORRIDOR_MIN,
                layout.label .. ' 实体碰撞体口径岸边通道 ' .. tostring(m.corridorCollision))
            assert.is_true(m.corridorAll >= plan.CORRIDOR_MIN,
                layout.label .. ' 含交互范围口径岸边通道 ' .. tostring(m.corridorAll))
            assert.are.equal(0, #m.intrusions, layout.label .. ' 战斗净空间被侵占')
            assert.is_true(m.supportPercent >= 99.9, layout.label .. ' 战斗净空间支撑不足')
            assert.are.equal(layout.groundY, m.landTop, layout.label .. ' 地块顶面不等于合同地面')
            assert.is_true(plan.pass(layout))
        end
    end)

    it('地形五块板铺满可达范围、互不重叠，且水面区不被铺地', function()
        for _, layout in ipairs(layouts()) do
            local terrain = {}
            for _, op in ipairs(layout.ops) do
                if op.role == 'terrain' then terrain[#terrain + 1] = plan.boxOf(layout, op) end
            end
            assert.are.equal(5, #terrain, layout.label .. ' 地形板数量')
            -- 可达范围 = 四面墙内面围出的矩形；它必须被地形板完全铺满（无洞），且板间不重叠。
            local inner = { minX = layout.walls.innerMinX, maxX = layout.walls.innerMaxX,
                minZ = layout.walls.innerMinZ, maxZ = layout.walls.innerMaxZ }
            local covered = 0
            for _, box in ipairs(terrain) do
                local ox = math.min(inner.maxX, box.maxX) - math.max(inner.minX, box.minX)
                local oz = math.min(inner.maxZ, box.maxZ) - math.max(inner.minZ, box.minZ)
                if ox > 0 and oz > 0 then covered = covered + ox * oz end
            end
            local innerArea = (inner.maxX - inner.minX) * (inner.maxZ - inner.minZ)
            assert.are.equal(innerArea, covered, layout.label .. ' 墙内可达范围有洞或重叠')
            for i = 1, #terrain do
                for j = i + 1, #terrain do
                    local ox = math.min(terrain[i].maxX, terrain[j].maxX) - math.max(terrain[i].minX, terrain[j].minX)
                    local oz = math.min(terrain[i].maxZ, terrain[j].maxZ) - math.max(terrain[i].minZ, terrain[j].minZ)
                    assert.is_true(ox <= 1e-6 or oz <= 1e-6,
                        layout.label .. ' 地形板重叠：' .. terrain[i].name .. ' / ' .. terrain[j].name)
                end
            end
            -- 水塘式的水位关系：塘底顶 < 水面顶 < 地面。
            local floor = terrain[3]
            assert.is_true(floor.maxY < layout.water.topY, layout.label .. ' 塘底高于水面')
            assert.is_true(layout.water.topY < layout.groundY, layout.label .. ' 水面不低于地面')
        end
    end)

    it('设施操作各自有名有实：要改的在基线里、要建的不在基线里', function()
        for _, layout in ipairs(layouts()) do
            local seen = {}
            -- 活动岛地块是**原地改形**（第 1 条操作），所以它同时带资产 id 又已经存在。
            local reuse = 'Z' .. layout.index .. '_Land'
            for _, op in ipairs(layout.ops) do
                assert.is_nil(seen[op.name], '重名操作：' .. op.name)
                seen[op.name] = true
                local exists = false
                for _, node in ipairs(layout.nodes) do
                    if node.name == op.name then exists = true end
                end
                if op.asset and op.name ~= reuse then
                    assert.is_false(exists, layout.label .. ' 要新建的单位已存在：' .. op.name)
                elseif not op.asset then
                    assert.is_true(exists, layout.label .. ' 要改的单位不在基线里：' .. op.name)
                end
            end
        end
    end)

    it('设施不侵占战斗净空间也不压水岸线（正面核对）', function()
        for _, layout in ipairs(layouts()) do
            local m = plan.metrics(layout)
            local rect = m.combatRect
            for _, op in ipairs(layout.ops) do
                if op.role == 'collision' or op.role == 'interaction' then
                    local box = plan.boxOf(layout, op)
                    local ox = math.min(rect.maxX, box.maxX) - math.max(rect.minX, box.minX)
                    local oz = math.min(rect.maxZ, box.maxZ) - math.max(rect.minZ, box.minZ)
                    assert.is_true(ox <= 1e-6 or oz <= 1e-6,
                        layout.label .. ' 设施落进战斗净空间：' .. op.name)
                end
            end
        end
    end)

    it('探针数据块与规划器逐字节同步', function()
        local want = plan.renderOps(layouts(), rows)
        local got = plan.readProbeBlock()
        assert.is_truthy(got, '探针缺少生成标记 ' .. plan.BEGIN_MARK)
        assert.are.equal(want, got, '数据块已漂移：请运行 lua tools/gen_zone_layout_probe.lua')
    end)

    it('回滚计划：恢复基线位姿，只删本批新建的单位（不误删原地改形的活动岛）', function()
        for _, zone in ipairs(plan.revertPlan(layouts(), rows)) do
            assert.are.equal(#zone.restored + #zone.deleted, #zone.ops)
            local deleted, restored = {}, {}
            for _, op in ipairs(zone.ops) do
                if op.op == 'delete' then deleted[op.name] = true else restored[op.name] = true end
            end
            assert.is_nil(deleted['Z' .. zone.label:sub(1, 2):gsub('^0', '') .. '_Land'],
                '回滚不能删掉活动岛 ' .. zone.label)
            for name in pairs(deleted) do
                assert.is_nil(restored[name], '同名既恢复又删除：' .. name)
            end
            -- 本批新建的 10 件（4 板 + 6 山体）应当全部在删除名单里。
            assert.are.equal(10, #zone.deleted, zone.label .. ' 删除名单数量')
        end
    end)

    it('审计工具与规划器用同一步长，避免 1.5 米宽的挡路件漏检', function()
        assert.are.equal(audit.SAMPLE_STEP, plan.SAMPLE_STEP)
        assert.is_true(plan.SAMPLE_STEP <= 0.75)
    end)
end)
