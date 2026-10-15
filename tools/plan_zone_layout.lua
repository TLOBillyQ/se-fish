-- #65 P3 灰盒布局规划器（离线）。
--
-- 用途：把已拍板的口径换算成**每区一组可执行的写操作**，并在写场景之前用纯几何算出这组操作
-- 是否满足 #62 的两条空间指标。离线部分只读 `common/GameCfg.lua` 与 P2 现场基线 CSV；
-- 写操作由 `tests/probes/zone_layout_apply.lua`（本工具生成的探针）在编辑器里执行。
--
-- 已拍板口径（2026-10-14，用户委托 agent 决断）：
--   D1 主要活动地面基准 = 合同 `Scene.SafePoint.y`（后五区 6.00）。
--   D2 水陆关系 = 水塘式：水面保持数学 `SurfaceY`（后五区 3.00）留在岸下，数学水域不改；
--      地块板抬到顶面 6.00，并把水面区留成塘（不铺地），塘底封到 y=0（深 3 米）。
--   D3 边界 = A：数学范围作外沿、墙内面作有效边界，运行时不改（声明见 zone-space-contract.md）。
--   D4 `Scene.State` 待施工核对后提升（本轮不动配置字面量）。
--   D5 主题轮廓沿用现场已有件：`official://preset/1204002`（现场名 `海岛山体3`）。
--
-- 本工具**只生成与核算**，不写场景；`ops` 里每条都带名字、资产、目标父级、目标位置与缩放，
-- 可逐条复核。缩放口径按 P1 实测：`Position` 是 X/Z 中心、Y 底面，`Size = Scale × 预设基准`。
local M = {}

local audit = require('tools.zone_space_contract')

M.CSV = 'evidence/issue65/zone-baseline-rows.csv'
M.PROBE = 'tests/probes/zone_layout_apply.lua'
M.BEGIN_MARK = '-- >>> GENERATED ZONE LAYOUT OPS'
M.END_MARK = '-- <<< GENERATED ZONE LAYOUT OPS'

M.GROUND = 6 -- D1：后五区主要活动地面基准（合同 SafePoint.y）
M.POND_DEPTH = 3 -- 水面到塘底（水塘式）
M.POND_FLOOR_TOP = 0 -- 塘底顶面
M.SLAB_SIZE = { 10, 1, 10 } -- official://preset/1101661 基准盒
M.SLAB = 'official://preset/1101661'
M.MOUNT = 'official://preset/1204002' -- 现场名「海岛山体3」，基准盒 20×10×20（虾池三件 scale=1 → size 20×10×20）
M.MOUNT_SIZE = { 20, 10, 20 }
M.HEADROOM = 3
M.CORRIDOR_MIN = 8
M.SAMPLE_STEP = 0.5 -- 与 zone_space_contract 同一采样步长（设施最小 1.5 宽，步长必须更小）
-- #62 连续战斗净空间 X×Z（第一排/第二排同尺）
M.COMBAT = { { 24, 20 }, { 24, 20 }, { 32, 28 }, { 40, 36 }, { 40, 36 }, { 48, 40 }, { 48, 40 } }
M.TARGET_ZONES = { 2, 3, 4, 5, 6, 7 }

local function round(value) return math.floor(value * 1000 + 0.5) / 1000 end

--- 名字里用的整数标签（坐标取整，避免出现 `430.0` 这种随舍入变化的名字）。
local function tag(value) return string.format('%d', math.floor(value + 0.5)) end
M.tag = tag

function M.zoneLabel(GameCfg, index)
    return string.format('%02d ', index) .. tostring(GameCfg.Zones[index].Name)
end

--- 从基线行里取一个单位（同名取第一个）。
local function nodeNamed(nodes, name)
    for _, node in ipairs(nodes) do
        if node.name == name then return node end
    end
    return nil
end

--- 该区的水面实体（`Zx_Water`；虾池由合同补建，鱼塘保留水圈特例）。
local function waterUnit(nodes)
    for _, node in ipairs(nodes) do
        if node.name:match('_Water$') then return node end
    end
    return nil
end

--- 生成一个区的布局与写操作。返回 nil, 原因 表示该区不适用。
function M.layoutFor(index, GameCfg, rows)
    local label = M.zoneLabel(GameCfg, index)
    local nodes = audit.nodesOf(rows, label)
    if #nodes == 0 then return nil, '基线里没有这个区：' .. label end
    local scene = GameCfg.Zones[index].Scene
    local boundary = scene.Boundary
    local groundY = scene.SafePoint.y
    local walls = audit.boundaryFacts(boundary, nodes)
    local water = waterUnit(nodes)
    local createWater = index == 2 and not water
    if createWater then
        -- ADR 0003：虾池没有旧水面实体，由场景合同生成 80×24 新水面。
        local cfg = scene.Waters[1]
        water = { minX = cfg.Center.x - cfg.HalfX, maxX = cfg.Center.x + cfg.HalfX,
            minZ = cfg.Center.z - cfg.HalfZ, maxZ = cfg.Center.z + cfg.HalfZ, maxY = cfg.SurfaceY }
        -- 规划针对移墙后的有效边界，不能沿用旧 50 米窄墙的内面。
        walls.innerMinX, walls.innerMaxX = boundary.MinX + 1.5, boundary.MaxX - 1.5
    end
    if not water then return nil, label .. ' 现场没有水面实体' end
    if groundY ~= M.GROUND then
        return nil, ('%s 合同地面 %s 与口径 %s 不一致'):format(label, tostring(groundY), tostring(M.GROUND))
    end
    local boundaryCenterZ = (boundary.MinZ + boundary.MaxZ) / 2
    local waterCenterZ = (water.minZ + water.maxZ) / 2
    -- 水在哪一侧 → 区内方向（inland）：朝区中心那一侧为正。
    local inland = waterCenterZ >= boundaryCenterZ and -1 or 1
    local shoreZ = inland > 0 and water.maxZ or water.minZ -- 朝区内那一侧的水岸线
    local farWaterZ = inland > 0 and water.minZ or water.maxZ -- 水的另一侧（外侧）
    local innerWallZ = inland > 0 and walls.innerMaxZ or walls.innerMinZ
    local outerWallZ = inland > 0 and walls.innerMinZ or walls.innerMaxZ
    local width = boundary.MaxX - boundary.MinX
    local centerX = (boundary.MinX + boundary.MaxX) / 2
    local right = inland -- 面朝水面时，右手方向 = +x 的符号（见规划器头注推导）
    local combatX, combatZ = M.COMBAT[index][1], M.COMBAT[index][2]

    local ops = {}
    local function place(name, asset, parent, position, size, role, base)
        local scale
        if size then
            base = base or M.SLAB_SIZE
            scale = { size[1] / base[1], size[2] / base[2], size[3] / base[3] }
        end
        ops[#ops + 1] = { name = name, asset = asset, parent = parent, role = role,
            position = { round(position[1]), round(position[2]), round(position[3]) },
            scale = scale, size = size and { round(size[1]), round(size[2]), round(size[3]) } or nil }
    end
    local function slab(name, x0, x1, z0, z1, bottomY, topY, asset)
        local loX, hiX = math.min(x0, x1), math.max(x0, x1)
        local loZ, hiZ = math.min(z0, z1), math.max(z0, z1)
        place(name, asset or M.SLAB, '地块',
            { (loX + hiX) / 2, bottomY, (loZ + hiZ) / 2 },
            { hiX - loX, topY - bottomY, hiZ - loZ }, 'terrain')
    end

    -- 1) 地形：活动岛（含水面以内全部）、外侧岸、塘底、两条侧沿 —— 覆盖边界内所有水平空间，
    --    只把水面那一块留成塘；塘底顶面 y=0 → 水深 3 米（水面 3、地面 6）。
    slab('Z' .. index .. '_Land', boundary.MinX, boundary.MaxX, shoreZ, innerWallZ, 0, M.GROUND)
    slab('Z' .. index .. '_Bank', boundary.MinX, boundary.MaxX, outerWallZ, farWaterZ, 0, M.GROUND)
    slab('Z' .. index .. '_PondFloor', water.minX, water.maxX, water.minZ, water.maxZ, -6, M.POND_FLOOR_TOP)
    slab('Z' .. index .. '_LandSideX' .. tag(water.minX - (water.minX - boundary.MinX) / 2),
        boundary.MinX, water.minX, water.minZ, water.maxZ, 0, M.GROUND)
    slab('Z' .. index .. '_LandSideX' .. tag(water.maxX + (boundary.MaxX - water.maxX) / 2),
        water.maxX, boundary.MaxX, water.minZ, water.maxZ, 0, M.GROUND)

    -- 2) 主题轮廓：外侧岸上一排山体 + 内侧抵达处两座，均落在岸顶，不压水岸线。
    --    名字带 x 坐标（P2 已证「按名判方向」不可靠，坐标才可靠）。
    local bankCenterZ = (outerWallZ + farWaterZ) / 2
    for _, offset in ipairs({ -48, -20, 20, 48 }) do
        place('Z' .. index .. '_Ridge' .. tag(centerX + offset), M.MOUNT, '地块',
            { centerX + offset, M.GROUND, bankCenterZ }, { 10, 12, 10 }, 'outline', M.MOUNT_SIZE)
    end
    for _, offset in ipairs({ -45, 45 }) do
        place('Z' .. index .. '_RidgeIn' .. tag(centerX + offset), M.MOUNT, '地块',
            { centerX + offset, M.GROUND, innerWallZ - inland * 6 }, { 10, 12, 10 }, 'outline', M.MOUNT_SIZE)
    end

    -- 3) 设施动线（#62：抵达 → 补给 → 水岸 → 摆渡；左商店、右抽奖与烧烤、钓鱼佬临水但不压战斗净空间）。
    local facilityZ = {}
    local function move(name, x, z, role)
        local node = nodeNamed(nodes, name)
        if not node then return nil end
        place(name, nil, nil, { x, M.GROUND, z }, nil, role)
        facilityZ[#facilityZ + 1] = name
        return node
    end
    local edge = combatX / 2
    move(scene.FishermanName, centerX - right * (edge + 15), shoreZ + inland * 15, 'interaction')
    move(scene.ShopName, centerX - right * (edge + 12), shoreZ + inland * (combatZ + 25), 'interaction')
    move('Z' .. index .. '_Lottery', centerX + right * (edge + 6), shoreZ + inland * 14, 'collision')
    move('Z' .. index .. '_Grill', centerX + right * (edge + 6), shoreZ + inland * (combatZ + 15), 'collision')
    for n, x in ipairs({ water.minX - 12, water.maxX + 12 }) do
        local name = 'Z' .. index .. '_Bait' .. n
        if not move(name, x, shoreZ + inland * 8, 'collision') and index == 2 then
            place(name, 'official://preset/1101635', '设施',
                { x, M.GROUND, shoreZ + inland * 8 }, { 1.5, 1.5, 1.5 }, 'collision', { 3, 3, 3 })
        end
    end
    move('Z' .. index .. '_FerryOut', centerX - right * 25, innerWallZ - inland * 8, 'collision')
    move(index == 2 and 'FerryReturn' or 'Z' .. index .. '_FerryReturn',
        centerX + right * 25, innerWallZ - inland * 8, 'collision')

    -- 4) 安全落点（抵达处）：垫片压平到地面高度，顶面与地面齐平。
    local safe = nodeNamed(nodes, 'Z' .. index .. '_Safe')
    if safe then
        place('Z' .. index .. '_Safe', nil, nil,
            { centerX, M.GROUND - (safe.maxY - safe.minY), innerWallZ - inland * 18 }, nil, 'safe')
    elseif index == 2 then
        place('Z2_Safe', M.SLAB, '摆渡', { centerX, M.GROUND - 0.2, innerWallZ - inland * 18 },
            { 10, 0.2, 10 }, 'safe')
    end
    if createWater then
        -- 资产是整套旧鱼塘；显式换成 Z3_Water 实测的纯水面网格，并清掉新资产附带子件。
        place('Z2_Water', 'map://preset/u54263b69f25482dae18f9dbcfe6dc5b', '地块',
            { centerX, water.maxY - 1, waterCenterZ }, { 80, 1, 24 }, 'water', { 3, 1, 3 })
        ops[#ops].waterMesh = 'official://mesh/59269'
        -- 旧墙名字的东/西与世界坐标相反，按基线空间分类保持实体身份。
        for _, wall in ipairs(walls.xWalls) do
            place(wall.name, nil, nil,
                { wall.x < centerX and boundary.MinX or boundary.MaxX, boundary.BottomY, boundaryCenterZ },
                { 3, boundary.TopY - boundary.BottomY, boundary.MaxZ - boundary.MinZ }, 'boundary', { 3, 3, 3 })
        end
        for _, wall in ipairs(walls.zWalls) do
            place(wall.name, nil, nil,
                { centerX, boundary.BottomY, wall.z < boundaryCenterZ and boundary.MinZ or boundary.MaxZ },
                { width, boundary.TopY - boundary.BottomY, 3 }, 'boundary', { 3, 3, 3 })
        end
    end

    local layout = {
        index = index, label = label, boundary = boundary, walls = walls,
        groundY = groundY, inland = inland, right = right, shoreZ = shoreZ,
        innerWallZ = innerWallZ, outerWallZ = outerWallZ, farWaterZ = farWaterZ,
        water = { minX = water.minX, maxX = water.maxX, minZ = water.minZ, maxZ = water.maxZ,
            topY = water.maxY },
        combat = { x = combatX, z = combatZ },
        nodes = nodes, ops = ops,
    }
    return layout
end

--- 操作 → 盒体（写之前的纯几何核算用）。没有 scale 的操作沿用现场尺寸。
function M.boxOf(layout, op)
    local size = op.size
    if not size then
        local node = nodeNamed(layout.nodes, op.name)
        if not node then return nil end
        size = { node.sizeX, node.sizeY, node.sizeZ }
    end
    local p = op.position
    return { minX = p[1] - size[1] / 2, maxX = p[1] + size[1] / 2, minY = p[2], maxY = p[2] + size[2],
        minZ = p[3] - size[3] / 2, maxZ = p[3] + size[3] / 2,
        name = op.name, role = op.role, isTrigger = (nodeNamed(layout.nodes, op.name) or {}).isTrigger or false }
end

--- 设计级核算：写场景之前先算这组操作能不能满足 #62 的两条指标与「站得住」。
function M.metrics(layout)
    local boxes, blockers, floors = {}, {}, {}
    for _, op in ipairs(layout.ops) do
        local box = M.boxOf(layout, op)
        if box then
            boxes[#boxes + 1] = box
            local isFloor = box.maxY <= layout.groundY + 0.3 and box.maxY >= layout.groundY - 0.5
            if isFloor then
                floors[#floors + 1] = box
            elseif box.maxY > layout.groundY + 0.05 and box.minY < layout.groundY + M.HEADROOM then
                blockers[#blockers + 1] = box
            end
        end
    end
    -- 岸边通道：沿水岸线朝区内采样（步长与审计工具一致），量到第一个挡住通行的实体。
    local step = M.SAMPLE_STEP
    local span = layout.water.maxX - layout.water.minX
    local count = math.max(2, math.ceil(span / step))
    local function widths(onlyCollision)
        local out = {}
        for i = 0, count - 1 do
            local x = layout.water.minX + span * i / count
            local limit = layout.inland > 0 and (layout.innerWallZ - layout.shoreZ)
                or (layout.shoreZ - layout.innerWallZ)
            local best = limit
            for _, box in ipairs(blockers) do
                if (not onlyCollision) or not box.isTrigger then
                    if x >= box.minX - 1e-9 and x <= box.maxX + 1e-9 then
                        local d = layout.inland > 0 and (box.minZ - layout.shoreZ) or (layout.shoreZ - box.maxZ)
                        if d >= -1e-9 and d < best then best = d end
                    end
                end
            end
            out[#out + 1] = best
        end
        return out
    end
    local collisionWidths = widths(true)
    local allWidths = widths(false)
    local function minOf(list)
        local min = list[1]
        for _, v in ipairs(list) do if v < min then min = v end end
        return min
    end
    -- 战斗净空间：贴岸锚法，矩形紧贴水岸线、以区中心为中线。
    local centerX = (layout.boundary.MinX + layout.boundary.MaxX) / 2
    local rect = {
        minX = centerX - layout.combat.x / 2, maxX = centerX + layout.combat.x / 2,
        minZ = layout.inland > 0 and layout.shoreZ or (layout.shoreZ - layout.combat.z),
        maxZ = layout.inland > 0 and (layout.shoreZ + layout.combat.z) or layout.shoreZ,
    }
    local intrusions = {}
    for _, box in ipairs(blockers) do
        local ox = math.min(rect.maxX, box.maxX) - math.max(rect.minX, box.minX)
        local oz = math.min(rect.maxZ, box.maxZ) - math.max(rect.minZ, box.minZ)
        if ox > 0.001 and oz > 0.001 then
            intrusions[#intrusions + 1] = { name = box.name, ox = ox, oz = oz }
        end
    end
    -- 支撑：战斗净空间被顶面等于地面的地板覆盖的比例（16×16 采样）。
    local covered = 0
    for ix = 0, 15 do
        for iz = 0, 15 do
            local px = rect.minX + (rect.maxX - rect.minX) * (ix + 0.5) / 16
            local pz = rect.minZ + (rect.maxZ - rect.minZ) * (iz + 0.5) / 16
            for _, floor in ipairs(floors) do
                if math.abs(floor.maxY - layout.groundY) < 0.05
                    and px >= floor.minX and px <= floor.maxX and pz >= floor.minZ and pz <= floor.maxZ then
                    covered = covered + 1
                    break
                end
            end
        end
    end
    local landBox
    for _, box in ipairs(boxes) do
        if box.name == 'Z' .. layout.index .. '_Land' then landBox = box end
    end
    return {
        corridorCollision = minOf(collisionWidths), corridorAll = minOf(allWidths),
        combatRect = rect, intrusions = intrusions, supportPercent = covered / 256 * 100,
        floorCount = #floors, blockerCount = #blockers,
        landTop = landBox and landBox.maxY or nil,
        landWasTop = (nodeNamed(layout.nodes, 'Z' .. layout.index .. '_Land') or {}).maxY,
    }
end

--- 文本报告（稳定顺序）。
function M.report(layouts)
    local out = {}
    for _, layout in ipairs(layouts) do
        local m = M.metrics(layout)
        out[#out + 1] = string.format('== %s | 地面 %s | 水岸 z=%s（向区内 %+d）| 内侧墙内面 z=%s | 外侧墙内面 z=%s',
            layout.label, audit.fmt(layout.groundY), audit.fmt(layout.shoreZ), layout.inland,
            audit.fmt(layout.innerWallZ), audit.fmt(layout.outerWallZ))
        out[#out + 1] = string.format('   WATER|水面板 x[%s,%s] z[%s,%s] 顶 %s（数学 SurfaceY 应与此相等）',
            audit.fmt(layout.water.minX), audit.fmt(layout.water.maxX),
            audit.fmt(layout.water.minZ), audit.fmt(layout.water.maxZ), audit.fmt(layout.water.topY))
        out[#out + 1] = string.format('   METRIC|岸边通道 min：实体碰撞体 %s / 含交互范围 %s（下限 %d）|战斗净空间 %d×%d x[%s,%s] z[%s,%s] 侵占 %d|支撑 %s%%|地块顶 %s（原 %s）',
            audit.fmt(m.corridorCollision), audit.fmt(m.corridorAll), M.CORRIDOR_MIN,
            layout.combat.x, layout.combat.z, audit.fmt(m.combatRect.minX), audit.fmt(m.combatRect.maxX),
            audit.fmt(m.combatRect.minZ), audit.fmt(m.combatRect.maxZ), #m.intrusions,
            audit.fmt(m.supportPercent, 1), audit.fmt(m.landTop), audit.fmt(m.landWasTop))
        for _, hit in ipairs(m.intrusions) do
            out[#out + 1] = string.format('     侵占: %s（%s×%s）', hit.name, audit.fmt(hit.ox), audit.fmt(hit.oz))
        end
        for _, op in ipairs(layout.ops) do
            out[#out + 1] = string.format('   OP|%-8s %-22s pos=(%s,%s,%s) scale=%s parent=%s',
                op.asset and 'ensure' or 'set', op.name,
                audit.fmt(op.position[1]), audit.fmt(op.position[2]), audit.fmt(op.position[3]),
                op.scale and table.concat({ audit.fmt(op.scale[1]), audit.fmt(op.scale[2]), audit.fmt(op.scale[3]) }, ',') or '-',
                op.parent or '-')
        end
    end
    return table.concat(out, '\n')
end

--- 基线行 → 三元组（CSV 里是 "x,y,z"，可能带引号）。
local function triple(text)
    if not text then return nil end
    local values = {}
    for part in tostring(text):gsub('"', ''):gmatch('[^,]+') do
        local value = tonumber(part)
        if value == nil then return nil end
        values[#values + 1] = round(value)
    end
    if #values ~= 3 then return nil end
    return values
end

function M.posOf(node) return triple(node.pos) end
function M.scaleOf(node) return triple(node.scale) end

--- 回滚操作：把这一批碰过的单位恢复到 P2 基线位姿，并删掉本批**新建**的单位。
--- 「新建」= 规划里带资产 id、且**基线里没有**这个名字的单位（`Zi_Land` 是原地改形，不在其列 ——
--- 判据必须用基线存在性，不能用「有没有资产 id」，否则会连地块一起删掉）。
--- 只依赖「基线 CSV + 同一份规划」，所以和施工操作一样可复现、可核对。
function M.revertPlan(layouts, rows)
    local byZone = {}
    for _, row in ipairs(rows or {}) do
        local list = byZone[row.zone]
        if not list then
            list = {}
            byZone[row.zone] = list
        end
        list[#list + 1] = row
    end
    local zones = {}
    for _, layout in ipairs(layouts) do
        local baselineRows = byZone[layout.label] or {}
        local baselineNames = {}
        for _, row in ipairs(baselineRows) do baselineNames[row.name] = true end
        local ops = {}
        local restored, touched = {}, {}
        for _, op in ipairs(layout.ops) do touched[op.name] = true end
        for _, row in ipairs(baselineRows) do
            local position, scale = triple(row.pos), triple(row.scale)
            if touched[row.name] and position and scale then
                ops[#ops + 1] = { op = 'restore', name = row.name, position = position, scale = scale }
                restored[#restored + 1] = row.name
            end
        end
        table.sort(restored)
        local deleted = {}
        for _, op in ipairs(layout.ops) do
            if op.asset and not baselineNames[op.name] then deleted[#deleted + 1] = op.name end
        end
        table.sort(deleted)
        for _, name in ipairs(deleted) do ops[#ops + 1] = { op = 'delete', name = name } end
        zones[#zones + 1] = { label = layout.label, ops = ops, restored = restored, deleted = deleted }
    end
    return zones
end

--- 生成探针里的字面量块（探针沙盒没有 require/io，只能嵌数据）。
--- `rows` 是基线 CSV 行：回滚块要靠它区分「原地改形」与「本批新建」。
function M.renderOps(layouts, rows)
    local out = { M.BEGIN_MARK .. '（由 tools/gen_zone_layout_probe.lua 生成）', 'local ZONE_OPS = {' }
    for _, layout in ipairs(layouts) do
        out[#out + 1] = string.format("  { label = '%s', groundY = %s, ops = {",
            layout.label, audit.fmt(layout.groundY))
        for _, op in ipairs(layout.ops) do
            local scale = op.scale and string.format('{ %.9f, %.9f, %.9f }',
                op.scale[1], op.scale[2], op.scale[3]) or 'nil'
            out[#out + 1] = string.format(
                "    { name = '%s', asset = %s, parent = %s, position = { %s, %s, %s }, scale = %s%s },",
                op.name, op.asset and ("'" .. op.asset .. "'") or 'nil',
                op.parent and ("'" .. op.parent .. "'") or 'nil',
                audit.fmt(op.position[1]), audit.fmt(op.position[2]), audit.fmt(op.position[3]), scale,
                op.waterMesh and (", waterMesh = '" .. op.waterMesh .. "'") or '')
        end
        out[#out + 1] = '  } },'
    end
    out[#out + 1] = '}'
    -- 回滚块：把基线位姿写回去，并删掉本批新建的单位（名字都是本规划造出来的，不会误删原对象）。
    out[#out + 1] = '-- ZONE_REVERT 只在 MODE = \'revert\' 时使用：恢复基线位姿 + 删除本批新建单位。'
    out[#out + 1] = 'local ZONE_REVERT = {'
    for _, zone in ipairs(M.revertPlan(layouts, rows)) do
        out[#out + 1] = string.format("  { label = '%s', ops = {", zone.label)
        for _, op in ipairs(zone.ops) do
            if op.op == 'restore' then
                out[#out + 1] = string.format(
                    "    { op = 'restore', name = '%s', position = { %s, %s, %s }, scale = { %s, %s, %s } },",
                    op.name, audit.fmt(op.position[1]), audit.fmt(op.position[2]), audit.fmt(op.position[3]),
                    audit.fmt(op.scale[1]), audit.fmt(op.scale[2]), audit.fmt(op.scale[3]))
            else
                out[#out + 1] = string.format("    { op = 'delete', name = '%s' },", op.name)
            end
        end
        out[#out + 1] = '  } },'
    end
    out[#out + 1] = '}'
    out[#out + 1] = M.END_MARK
    return table.concat(out, '\n')
end

M.readFile = audit.readFile
M.parseCsvRows = audit.parseCsv

--- 从探针文件里抠出数据块（含两条标记行）。
function M.extractBlock(source, beginMark, endMark)
    beginMark = beginMark or M.BEGIN_MARK
    endMark = endMark or M.END_MARK
    local beginAt = source:find(beginMark, 1, true)
    if not beginAt then return nil end
    local endAt = source:find(endMark, 1, true)
    if not endAt then return nil end
    return source:sub(beginAt, endAt + #endMark - 1)
end

--- 从探针文件里取回块（供 --check 与单测）。
function M.readProbeBlock()
    local text = M.readFile(M.PROBE)
    if not text then return nil end
    return M.extractBlock(text)
end

function M.buildAll(GameCfg, rows, indexes)
    local layouts, skipped = {}, {}
    for _, index in ipairs(indexes or M.TARGET_ZONES) do
        local layout, why = M.layoutFor(index, GameCfg, rows)
        if layout then
            layouts[#layouts + 1] = layout
        else
            skipped[#skipped + 1] = why
        end
    end
    return layouts, skipped
end

--- 每区是否达标（供单测与报告）。
function M.pass(layout)
    local m = M.metrics(layout)
    return m.corridorCollision >= M.CORRIDOR_MIN and m.corridorAll >= M.CORRIDOR_MIN
        and #m.intrusions == 0 and m.supportPercent >= 99.9
end

local function main(argv)
    local indexes, check = nil, false
    for i = 1, #(argv or {}) do
        if argv[i] == '--zones' then
            indexes = {}
            for part in tostring(argv[i + 1]):gmatch('[^,]+') do indexes[#indexes + 1] = tonumber(part) end
        end
        if argv[i] == '--check' then check = true end
    end
    local rows = M.parseCsvRows(M.readFile(M.CSV))
    if not rows then
        print('读不到基线 CSV：' .. M.CSV)
        os.exit(1)
    end
    local GameCfg = require('common.GameCfg')
    local layouts, skipped = M.buildAll(GameCfg, rows, indexes)
    print(M.report(layouts))
    for _, why in ipairs(skipped) do print('SKIP|' .. why) end
    local failures = {}
    for _, layout in ipairs(layouts) do
        if not M.pass(layout) then failures[#failures + 1] = layout.label end
    end
    if #failures > 0 then
        print('未达标：' .. table.concat(failures, ', '))
    else
        print(('全部达标：%d 个区（岸边通道 ≥%d、战斗净空间无侵占、支撑 100%%、地块顶 = 地面）')
            :format(#layouts, M.CORRIDOR_MIN))
    end
    if check then
        -- 必须带 rows：回滚块靠它区分「原地改形」与「本批新建」，漏传会渲染出空回滚块，
        -- 于是 --check 永远报「不同步」（#66 修）。
        local want = M.renderOps(layouts, rows)
        local got = M.readProbeBlock()
        if want ~= got then
            print('探针数据块**不同步**：请运行 lua tools/gen_zone_layout_probe.lua')
            os.exit(1)
        end
        print('探针数据块已同步。')
    end
    os.exit(#failures > 0 and 1 or 0)
end

M.parseCsvRows = audit.parseCsv
if arg and arg[0] and arg[0]:find('plan_zone_layout', 1, true) then
    main(arg)
end

return M
