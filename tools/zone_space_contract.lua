-- #65 P3 空间合同核对（离线工具，只读）。
--
-- 输入：
--   * evidence/issue65/zone-baseline-rows.csv —— P2 现场基线（探针 tests/probes/zone_baseline_inventory.lua 生成）
--   * common/GameCfg.lua                      —— #125 七区场景合同（加载时已做「折返双排」刚体变换）
-- 输出：stdout 文本报告；`--json <path>` 另写机器可读结果。
--
-- 口径（逐条显式声明，避免把推断当实测）：
--   1. **pivot**：沿用 P1 在 preset `1101635`（30 面空气墙）上的运行时射线结论 —— Y 轴 `Position.y`
--      是**底面**、X/Z 以 `Position.x/z` 为**中心**。对非 1101635 的对象这是假设，不是实测
--      （P2 §0 已声明），所以本工具把墙的内面同时给出，便于与 P1 实测表交叉核对。
--   2. **边界**：「数学允许范围」取 `zone.Scene.Boundary`（变换后）；「实体碰撞边界」取该区空气墙
--      按上述 pivot 算出的内面。只报差值（墙厚偏移），**不判定**以哪一面为准 —— 那是 P3 的声明项。
--   3. **岸边通道**：#62「岸边连续通道至少 8 单位净宽」。沿水岸线采样，量到第一个挡住通行的实体的
--      水平距离。挡住 = （`CanCollide=true` 或 `TriggerUnit` 交互范围）且 Y 跨度与
--      `[groundY, groundY + Headroom]` 相交（`Headroom=3`，三倍体型线性净空的行走带）。
--      可站立薄面（顶面在 `groundY ± 0.5` 内）算地板，不算障碍。
--   4. **战斗净空间**：#62 逐区 X×Z。锚法有两种解释，两种都算，供 P3 选定：
--      A「紧贴水岸」= 一条边压在水岸线上；B「退让通道」= 先让出 `CorridorMin` 宽的岸边通道，
--      再紧贴通道内沿。侵占判定同 §3。
--   5. **只报事实与差值，不下合格/不合格结论**：施工未做时这些数字是现状快照，不是验收。
local M = {}

M.CSV = 'evidence/issue65/zone-baseline-rows.csv'
M.EVIDENCE_JSON = 'evidence/issue65/zone-space-contract.json'
M.CORRIDOR_MIN = 8 -- #62 岸边连续通道净宽下限（米）
M.HEADROOM = 3     -- 判定高度带：地面 → 地面 + 3（三倍体型线性净空）
M.SAMPLES = 32     -- 水岸线采样数
-- #62 决议的连续战斗净空间 X×Z（按区序 1..7）
M.COMBAT = { { 24, 20 }, { 24, 20 }, { 32, 28 }, { 40, 36 }, { 40, 36 }, { 48, 40 }, { 48, 40 } }

local function trim(text) return (tostring(text):gsub('^%s+', ''):gsub('%s+$', '')) end

--- 拆一行 CSV，支持双引号包裹（尺寸/位置字段里带逗号）。
function M.splitCsvLine(line)
    local fields, buf, inQuote, i = {}, {}, false, 1
    while i <= #line do
        local c = line:sub(i, i)
        if inQuote then
            if c == '"' then
                if line:sub(i + 1, i + 1) == '"' then
                    buf[#buf + 1] = '"'
                    i = i + 1
                else
                    inQuote = false
                end
            else
                buf[#buf + 1] = c
            end
        elseif c == '"' then
            inQuote = true
        elseif c == ',' then
            fields[#fields + 1] = table.concat(buf)
            buf = {}
        else
            buf[#buf + 1] = c
        end
        i = i + 1
    end
    fields[#fields + 1] = table.concat(buf)
    return fields
end

--- 解析基线 CSV → { { 字段名 = 值 }, ... }。
function M.parseCsv(text)
    local rows, header = {}, nil
    for line in tostring(text):gmatch('[^\r\n]+') do
        if line:match('%S') then
            local fields = M.splitCsvLine(line)
            if not header then
                header = fields
            else
                local row = {}
                for index, key in ipairs(header) do row[key] = fields[index] or '' end
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end

--- 解析 "1.000,2.000,3.000" → { 1, 2, 3 }（容忍外层引号，便于直接喂原始字段）。
function M.parseTriple(text)
    local values = {}
    for part in tostring(text):gsub('"', ''):gmatch('[^,]+') do
        local value = tonumber(trim(part))
        if value == nil then return nil end
        values[#values + 1] = value
    end
    if #values ~= 3 then return nil end
    return values
end

--- 基线行 → 轴对齐盒。pivot 口径见文件头 §1（Y 底面、X/Z 中心）。
function M.box(row)
    local pos, size = M.parseTriple(row.pos), M.parseTriple(row.size)
    if not pos or not size then return nil end
    return {
        minX = pos[1] - size[1] / 2, maxX = pos[1] + size[1] / 2,
        minY = pos[2], maxY = pos[2] + size[2],
        minZ = pos[3] - size[3] / 2, maxZ = pos[3] + size[3] / 2,
        centerX = pos[1], centerZ = pos[3], sizeX = size[1], sizeY = size[2], sizeZ = size[3],
    }
end

--- 该区所有能从基线算出盒体的行（去掉 Folder / PresetLink 这类没有空间属性的）。
function M.nodesOf(rows, zoneLabel)
    local nodes = {}
    for _, row in ipairs(rows) do
        if row.zone == zoneLabel and row.spatial == '1' then
            local box = M.box(row)
            if box then
                box.name, box.path, box.type = row.name, row.path, row.type
                box.canCollide = row.canCollide == 'true'
                box.isTrigger = row.type == 'TriggerUnit'
                nodes[#nodes + 1] = box
            end
        end
    end
    return nodes
end

local function zoneCenterX(boundary) return (boundary.MinX + boundary.MaxX) / 2 end
local function zoneCenterZ(boundary) return (boundary.MinZ + boundary.MaxZ) / 2 end

--- 空气墙按取向分类：侧墙按薄轴分 x/z，另外单独识别水平盖板（顶盖/底板）。
function M.classifyWalls(nodes)
    local xWalls, zWalls, caps = {}, {}, {}
    for _, node in ipairs(nodes) do
        if node.path:find('/空气墙/', 1, true) then
            if node.sizeY < node.sizeX and node.sizeY < node.sizeZ then
                caps[#caps + 1] = node
            elseif node.sizeX <= node.sizeZ then
                xWalls[#xWalls + 1] = node
            else
                zWalls[#zWalls + 1] = node
            end
        end
    end
    return xWalls, zWalls, caps
end

--- 实体碰撞边界：按 pivot 口径从侧墙算出的内面，以及与数学范围的差值。
function M.boundaryFacts(boundary, nodes)
    local xWalls, zWalls, caps = M.classifyWalls(nodes)
    local cx, cz = zoneCenterX(boundary), zoneCenterZ(boundary)
    local facts = { wallCount = #xWalls + #zWalls + #caps, xWalls = {}, zWalls = {}, caps = {} }
    for _, wall in ipairs(xWalls) do
        facts.xWalls[#facts.xWalls + 1] = { name = wall.name, x = wall.centerX,
            inner = wall.centerX <= cx and wall.maxX or wall.minX, box = wall }
    end
    table.sort(facts.xWalls, function(a, b) return a.x < b.x end)
    if #facts.xWalls >= 2 then
        facts.innerMinX = facts.xWalls[1].inner
        facts.innerMaxX = facts.xWalls[#facts.xWalls].inner
    end
    for _, wall in ipairs(zWalls) do
        facts.zWalls[#facts.zWalls + 1] = { name = wall.name, z = wall.centerZ,
            inner = wall.centerZ <= cz and wall.maxZ or wall.minZ, box = wall }
    end
    table.sort(facts.zWalls, function(a, b) return a.z < b.z end)
    if #facts.zWalls >= 2 then
        facts.innerMinZ = facts.zWalls[1].inner
        facts.innerMaxZ = facts.zWalls[#facts.zWalls].inner
    end
    for _, cap in ipairs(caps) do facts.caps[#facts.caps + 1] = cap end
    return facts
end

--- 水岸：优先现场水面实体（圆或矩形），退化到配置数学水域（矩形）。返回岸边线/内侧方向。
function M.shoreFacts(cfgZone, nodes)
    local sceneWater, circle
    for _, node in ipairs(nodes) do
        if node.name == 'WaterCircle2' then
            circle = node -- 外圈优先：同心时先命中的是 WaterCircle2
        elseif node.name == 'WaterCircle1' and not circle then
            circle = node
        end
        if node.name:match('_Water$') or node.name:match('_Water%d') then sceneWater = node end
    end
    local mathWater = (cfgZone.Scene.Waters or {})[1]
    local body
    if sceneWater then
        body = { source = 'scene', name = sceneWater.name, kind = 'rect', box = sceneWater }
    elseif circle then
        body = { source = 'scene', name = circle.name, kind = 'circle', box = circle,
            radius = math.min(circle.sizeX, circle.sizeZ) / 2 }
    elseif mathWater then
        local halfX = mathWater.HalfX or mathWater.HalfXZ or 0
        local halfZ = mathWater.HalfZ or mathWater.HalfXZ or 0
        body = { source = 'config', name = mathWater.EntityName or mathWater.Id, kind = 'rect',
            centerX = mathWater.Center.x, centerZ = mathWater.Center.z,
            minX = mathWater.Center.x - halfX, maxX = mathWater.Center.x + halfX,
            minZ = mathWater.Center.z - halfZ, maxZ = mathWater.Center.z + halfZ,
            surfaceY = mathWater.SurfaceY }
    end
    if not body then return nil end
    if body.box then
        body.minX, body.maxX = body.box.minX, body.box.maxX
        body.minZ, body.maxZ = body.box.minZ, body.box.maxZ
        body.topY = body.box.maxY
        body.centerX, body.centerZ = body.box.centerX, body.box.centerZ
        -- 现场水面实体来自场景；合同水面高度仍从配置取，便于核对两者是否同一口径。
        local contractWater = (cfgZone.Scene.Waters or {})[1]
        if contractWater then body.surfaceY = contractWater.SurfaceY end
    end
    if body.kind == 'rect' then
        local boundary = cfgZone.Scene.Boundary
        local centerZ = zoneCenterZ(boundary)
        -- 内侧 = 朝向区中心的一侧；#62 已定前四区水岸朝 −Z、后三区朝 +Z。
        body.inland = (body.centerZ >= centerZ) and -1 or 1
        body.edgeZ = body.inland > 0 and body.maxZ or body.minZ
        body.spanMin, body.spanMax = body.minX, body.maxX
        body.side = body.inland > 0 and '-Z' or '+Z'
    end
    return body
end

--- 可站立面（地板）：顶面在当前地面高度或略高一点（0.3 以内）的碰撞体。
--- 这个阈值把 0.2 厚的安全点垫片当地板，把 1.5 立方的设施块当障碍（后者的顶面高出地面 0.5）。
function M.isWalkableSurface(box, groundY)
    return box.canCollide and box.maxY <= groundY + 0.3 and box.maxY >= groundY - 0.5
end

--- 障碍：碰撞体或交互范围，且与行走高度带相交；落地薄面不算障碍。
--- kind: 'collision' 只算实体碰撞体；'all' 另算 TriggerUnit 交互范围。
function M.isBlocker(box, groundY, headroom, kind)
    if kind == 'collision' and not box.canCollide then return false end
    if not (box.canCollide or box.isTrigger) then return false end
    if M.isWalkableSurface(box, groundY) then return false end
    return box.maxY > groundY + 0.05 and box.minY < groundY + headroom
end

--- 二维线段与轴对齐盒的进入参数（slab 法）。返回 tEnter（≥0）或 nil。
function M.segmentEnterT(fromX, fromZ, dirX, dirZ, box, maxT)
    local tMin, tMax = 0, maxT
    local function slab(origin, dir, lo, hi)
        if math.abs(dir) < 1e-9 then
            if origin < lo or origin > hi then return false end
            return true
        end
        local t1, t2 = (lo - origin) / dir, (hi - origin) / dir
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tMin then tMin = t1 end
        if t2 < tMax then tMax = t2 end
        return tMin <= tMax
    end
    if not slab(fromX, dirX, box.minX, box.maxX) then return nil end
    if not slab(fromZ, dirZ, box.minZ, box.maxZ) then return nil end
    if tMin <= tMax and tMin <= maxT then return math.max(tMin, 0) end
    return nil
end

--- 水上岸线采样点：{ x, z, dirX, dirZ }。
function M.shoreSamples(shore, count)
    count = count or M.SAMPLES
    local samples = {}
    if shore.kind == 'circle' then
        for index = 0, count - 1 do
            local angle = 2 * math.pi * index / count
            local dx, dz = math.cos(angle), math.sin(angle)
            samples[#samples + 1] = {
                x = shore.centerX + shore.radius * dx,
                z = shore.centerZ + shore.radius * dz,
                dirX = dx, dirZ = dz,
            }
        end
    else
        for index = 0, count - 1 do
            local ratio = index / count
            local x = shore.spanMin + (shore.spanMax - shore.spanMin) * ratio
            samples[#samples + 1] = { x = x, z = shore.edgeZ,
                dirX = 0, dirZ = shore.inland }
        end
    end
    return samples
end

--- 岸边通道：逐采样点量净宽，返回最小净宽与最长「≥8」连续段长度。
--- 同时给出两种口径：只算实体碰撞体（collision）与另算交互范围（all）。
function M.corridor(shore, nodes, boundary, groundY, corridorMin)
    corridorMin = corridorMin or M.CORRIDOR_MIN
    local samples = M.shoreSamples(shore)
    -- 量程上限：朝区内的数学范围边界（否则会把区外空间算成通道）。
    local function widthsFor(kind)
        local widths, blockers = {}, {}
        for _, sample in ipairs(samples) do
            local maxT
            if sample.dirZ > 0 then maxT = boundary.MaxZ - sample.z
            elseif sample.dirZ < 0 then maxT = sample.z - boundary.MinZ
            elseif sample.dirX > 0 then maxT = boundary.MaxX - sample.x
            else maxT = sample.x - boundary.MinX end
            if maxT < 0 then maxT = 0 end
            local best, bestName = maxT, nil
            for _, node in ipairs(nodes) do
                if M.isBlocker(node, groundY, M.HEADROOM, kind) then
                    local t = M.segmentEnterT(sample.x, sample.z, sample.dirX, sample.dirZ, node, maxT)
                    if t and t < best then best, bestName = t, node.name end
                end
            end
            widths[#widths + 1] = best
            if bestName then blockers[#blockers + 1] = bestName end
        end
        return widths, blockers
    end
    local step = 0
    if shore.kind == 'circle' then
        step = 2 * math.pi * shore.radius / #samples
    else
        step = (shore.spanMax - shore.spanMin) / #samples
    end
    local function summarise(widths, blockers)
        local minWidth, minAt = math.huge, nil
        for index, width in ipairs(widths) do
            if width < minWidth then minWidth, minAt = width, index end
        end
        local run, bestRun = 0, 0
        for _, width in ipairs(widths) do
            if width >= corridorMin then
                run = run + 1
                if run > bestRun then bestRun = run end
            else
                run = 0
            end
        end
        return { minWidth = minWidth, minAt = minAt, longestRun = bestRun,
            longestRunLength = bestRun * step, sampleStep = step, widths = widths, blockers = blockers }
    end
    local collisionWidths, collisionBlockers = widthsFor('collision')
    local allWidths, allBlockers = widthsFor('all')
    local collision = summarise(collisionWidths, collisionBlockers)
    local all = summarise(allWidths, allBlockers)
    return { collision = collision, all = all, sampleStep = step,
        minWidth = collision.minWidth, minAt = collision.minAt }
end

--- 战斗净空间：两种锚法（A 紧贴水岸 / B 退让通道），各自算侵占对象与重叠尺寸。
--- 水岸宽度不足战斗宽度时按比例收缩，`scale` 会出现在标签里（不掩盖退化）。
function M.combatRects(shore, boundary, combatX, combatZ, corridorMin)
    local rects = {}
    local function push(label, minX, maxX, minZ, maxZ)
        rects[#rects + 1] = { label = label, scale = 1, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
    end
    if shore.kind == 'circle' then
        -- 圆岸（鱼塘）：矩形战斗场地没有唯一的「贴岸」锚法，改为以水域包围盒的四条边为近边，
        -- 各给一个候选；哪一侧有没有整块空地由审计结果说话。
        local centerX = (shore.minX + shore.maxX) / 2
        local centerZ = (shore.minZ + shore.maxZ) / 2
        local halfX, halfZ = combatX / 2, combatZ / 2
        push('圆岸 +X 侧', shore.maxX, shore.maxX + combatX, centerZ - halfZ, centerZ + halfZ)
        push('圆岸 −X 侧', shore.minX - combatX, shore.minX, centerZ - halfZ, centerZ + halfZ)
        push('圆岸 +Z 侧', centerX - halfX, centerX + halfX, shore.maxZ, shore.maxZ + combatZ)
        push('圆岸 −Z 侧', centerX - halfX, centerX + halfX, shore.minZ - combatZ, shore.minZ)
        return rects
    end
    local centerX = zoneCenterX(boundary)
    local scale = math.min(1, (shore.spanMax - shore.spanMin) / combatX)
    local halfX = combatX * scale / 2
    local function make(label, nearZ)
        rects[#rects + 1] = { label = label, scale = scale,
            minX = centerX - halfX, maxX = centerX + halfX,
            minZ = math.min(nearZ, nearZ + shore.inland * combatZ),
            maxZ = math.max(nearZ, nearZ + shore.inland * combatZ) }
    end
    make('A|紧贴水岸', shore.edgeZ)
    make('B|退让通道后', shore.edgeZ + shore.inland * corridorMin)
    return rects
end

--- 无侵占窗口扫描：不预设「战斗场地锚在哪」，直接在区内扫 W×H 轴对齐矩形的位置，
--- 报出「完全无侵占」的位置数与最优位置（侵占面积最小）。这样圆岸（鱼塘）也能给数，
--- 而且把「锚法口径」从结论里剔除出去 —— 锚法只影响 COMBAT 那两行，不影响这一行。
function M.combatWindow(boundary, nodes, groundY, width, height, step)
    step = step or 2
    local result = { width = width, height = height, step = step, candidates = 0,
        freeCollision = 0, freeAll = 0, best = nil }
    local x = boundary.MinX
    while x <= boundary.MaxX do
        local z = boundary.MinZ
        while z <= boundary.MaxZ do
            local rect = { minX = x - width / 2, maxX = x + width / 2,
                minZ = z - height / 2, maxZ = z + height / 2 }
            local intrusion = { collision = 0, all = 0 }
            for _, node in ipairs(nodes) do
                if M.isBlocker(node, groundY, M.HEADROOM, 'all') then
                    local overlapX = math.min(rect.maxX, node.maxX) - math.max(rect.minX, node.minX)
                    local overlapZ = math.min(rect.maxZ, node.maxZ) - math.max(rect.minZ, node.minZ)
                    if overlapX > 0.001 and overlapZ > 0.001 then
                        intrusion.all = intrusion.all + overlapX * overlapZ
                        if node.canCollide then
                            intrusion.collision = intrusion.collision + overlapX * overlapZ
                        end
                    end
                end
            end
            result.candidates = result.candidates + 1
            if intrusion.collision <= 0.0001 then result.freeCollision = result.freeCollision + 1 end
            if intrusion.all <= 0.0001 then result.freeAll = result.freeAll + 1 end
            if result.best == nil or intrusion.all < result.best.intrudedAll then
                result.best = { centerX = x, centerZ = z, intrudedAll = intrusion.all,
                    intrudedCollision = intrusion.collision }
            end
            z = z + step
        end
        x = x + step
    end
    return result
end

--- 一个矩形里被哪些障碍侵占（含重叠尺寸与 Y 跨度），按实体碰撞体 / 交互范围分开列。
function M.intrusionsIn(rect, nodes, groundY, kind)
    local hits = {}
    for _, node in ipairs(nodes) do
        if M.isBlocker(node, groundY, M.HEADROOM, kind) then
            local overlapX = math.min(rect.maxX, node.maxX) - math.max(rect.minX, node.minX)
            local overlapZ = math.min(rect.maxZ, node.maxZ) - math.max(rect.minZ, node.minZ)
            if overlapX > 0.001 and overlapZ > 0.001 then
                hits[#hits + 1] = { name = node.name, path = node.path,
                    overlapX = overlapX, overlapZ = overlapZ,
                    minY = node.minY, maxY = node.maxY }
            end
        end
    end
    table.sort(hits, function(a, b)
        local areaA, areaB = a.overlapX * a.overlapZ, b.overlapX * b.overlapZ
        if areaA ~= areaB then return areaA > areaB end
        return a.path < b.path
    end)
    return hits
end

--- 落地支撑：合同地面附近的可站立面，以及它们对给定矩形的覆盖比例。
function M.supportFacts(nodes, boundary, groundY, rects)
    local surfaces = {}
    for _, node in ipairs(nodes) do
        if M.isWalkableSurface(node, groundY) then
            surfaces[#surfaces + 1] = { name = node.name, path = node.path, topY = node.maxY,
                minX = node.minX, maxX = node.maxX, minZ = node.minZ, maxZ = node.maxZ }
        end
    end
    table.sort(surfaces, function(a, b) return a.path < b.path end)
    -- 地面高度参考：地块板（Land 实体名）与最高的可站立面。
    local landTop, highest = nil, nil
    for _, node in ipairs(nodes) do
        if node.name:match('_Land$') or node.name == '大地板' or node.name == '星光地板' then
            if landTop == nil or node.maxY > landTop then landTop = node.maxY end
        end
        if node.canCollide and node.sizeY <= 2.5 then
            if highest == nil or node.maxY > highest then highest = node.maxY end
        end
    end
    local coverage = {}
    for _, rect in ipairs(rects or {}) do
        local area, covered = (rect.maxX - rect.minX) * (rect.maxZ - rect.minZ), 0
        -- 采样法估覆盖（够用即可；薄面相交面积不是关键量）。
        for ix = 0, 15 do
            for iz = 0, 15 do
                local px = rect.minX + (rect.maxX - rect.minX) * (ix + 0.5) / 16
                local pz = rect.minZ + (rect.maxZ - rect.minZ) * (iz + 0.5) / 16
                for _, surface in ipairs(surfaces) do
                    if px >= surface.minX and px <= surface.maxX and pz >= surface.minZ and pz <= surface.maxZ then
                        covered = covered + 1
                        break
                    end
                end
            end
        end
        coverage[rect.label] = covered / (16 * 16) * 100
    end
    return { surfaces = surfaces, landTop = landTop, highestSurface = highest, coverage = coverage }
end

--- 锚点坐标差：配置 Scene.Entities 的坐标（变换后）与现场同名单位坐标。
function M.anchorDeltas(cfgZone, nodes)
    local byName = {}
    for _, node in ipairs(nodes) do byName[node.name] = byName[node.name] or node end
    local result = { entries = 0, resolved = 0, maxDx = 0, maxDy = 0, maxDz = 0,
        nonzero = 0, missing = {}, deltas = {} }
    for _, entity in ipairs(cfgZone.Scene.Entities or {}) do
        result.entries = result.entries + 1
        local node = byName[entity.Name]
        if node then
            result.resolved = result.resolved + 1
            local dx = node.centerX - entity.Position.x
            local dz = node.centerZ - entity.Position.z
            local dy = node.minY - entity.Position.y
            result.maxDx = math.max(result.maxDx, math.abs(dx))
            result.maxDy = math.max(result.maxDy, math.abs(dy))
            result.maxDz = math.max(result.maxDz, math.abs(dz))
            if math.abs(dx) > 0.001 or math.abs(dy) > 0.001 or math.abs(dz) > 0.001 then
                result.nonzero = result.nonzero + 1
                result.deltas[#result.deltas + 1] = { name = entity.Name, role = entity.Role,
                    dx = dx, dy = dy, dz = dz }
            end
        else
            result.missing[#result.missing + 1] = { name = entity.Name, role = entity.Role,
                state = entity.State }
        end
    end
    table.sort(result.missing, function(a, b) return a.name < b.name end)
    return result
end

local function fmt(value, digits)
    if value == nil then return '-' end
    return string.format('%.' .. (digits or 2) .. 'f', value)
end
M.fmt = fmt

--- 逐区核对，返回结构化结果（供报告与 JSON 复用）。
function M.audit(GameCfg, rows)
    local zones = {}
    for index, cfgZone in ipairs(GameCfg.Zones) do
        local label = string.format('%02d ', index) .. tostring(cfgZone.Name)
        local boundary = cfgZone.Scene.Boundary
        local nodes = M.nodesOf(rows, label)
        local groundY = cfgZone.Scene.SafePoint.y
        local combat = M.COMBAT[index] or { 0, 0 }
        local walls = M.boundaryFacts(boundary, nodes)
        local shore = M.shoreFacts(cfgZone, nodes)
        local rects = shore and M.combatRects(shore, boundary, combat[1], combat[2], M.CORRIDOR_MIN) or nil
        local entry = {
            label = label, index = index, zoneId = cfgZone.Id,
            math = { minX = boundary.MinX, maxX = boundary.MaxX, minZ = boundary.MinZ,
                maxZ = boundary.MaxZ, bottomY = boundary.BottomY, topY = boundary.TopY,
                maxFlightHeight = boundary.MaxFlightHeight },
            groundY = groundY, ceilingY = groundY + (boundary.MaxFlightHeight or 0),
            walls = walls, nodes = #nodes, shore = shore,
            support = M.supportFacts(nodes, boundary, groundY, rects),
            window = M.combatWindow(boundary, nodes, groundY, combat[1], combat[2]),
            anchors = M.anchorDeltas(cfgZone, nodes),
            sceneState = cfgZone.Scene.State,
        }
        if walls.innerMinX and boundary.MinX then
            entry.inset = { minX = walls.innerMinX - boundary.MinX, maxX = boundary.MaxX - walls.innerMaxX,
                minZ = walls.innerMinZ - boundary.MinZ, maxZ = boundary.MaxZ - walls.innerMaxZ }
        end
        if shore then
            entry.corridor = M.corridor(shore, nodes, boundary, groundY)
            entry.waterDrop = (shore.topY and groundY) and (groundY - shore.topY) or nil
            local combatFacts = {}
            for _, rect in ipairs(rects or {}) do
                rect.collisionHits = M.intrusionsIn(rect, nodes, groundY, 'collision')
                local all = M.intrusionsIn(rect, nodes, groundY, 'all')
                local collisionNames = {}
                for _, hit in ipairs(rect.collisionHits) do collisionNames[hit.path] = true end
                rect.interactionHits = {}
                for _, hit in ipairs(all) do
                    if not collisionNames[hit.path] then rect.interactionHits[#rect.interactionHits + 1] = hit end
                end
                rect.hits = all
                combatFacts[#combatFacts + 1] = rect
            end
            entry.combat = combatFacts
        end
        zones[#zones + 1] = entry
    end
    return zones
end

--- 文本报告（稳定顺序：区序 → 区段内固定字段序）。
function M.report(zones)
    local out = {}
    for _, zone in ipairs(zones) do
        local head = string.format('== %s | 数学 x[%s,%s] z[%s,%s] y[%s,%s] | 地面 %s | 顶限 %s',
            zone.label, fmt(zone.math.minX), fmt(zone.math.maxX), fmt(zone.math.minZ),
            fmt(zone.math.maxZ), fmt(zone.math.bottomY), fmt(zone.math.topY),
            fmt(zone.groundY), fmt(zone.ceilingY))
        out[#out + 1] = head
        local walls = zone.walls
        out[#out + 1] = string.format('  WALLS|count=%d|innerX=[%s,%s]|innerZ=[%s,%s]|inset=%s/%s/%s/%s|caps=%d',
            walls.wallCount, fmt(walls.innerMinX), fmt(walls.innerMaxX),
            fmt(walls.innerMinZ), fmt(walls.innerMaxZ),
            fmt(zone.inset and zone.inset.minX), fmt(zone.inset and zone.inset.maxX),
            fmt(zone.inset and zone.inset.minZ), fmt(zone.inset and zone.inset.maxZ), #walls.caps)
        if zone.shore then
            local shore = zone.shore
            out[#out + 1] = string.format('  SHORE|%s|%s|kind=%s|center=(%s,%s)|x[%s,%s] z[%s,%s]|topY=%s|side=%s|合同SurfaceY=%s|水面在地面下 %s',
                shore.source, shore.name, shore.kind, fmt(shore.centerX), fmt(shore.centerZ),
                fmt(shore.minX), fmt(shore.maxX), fmt(shore.minZ), fmt(shore.maxZ),
                fmt(shore.topY), shore.side or '-', fmt(shore.surfaceY), fmt(zone.waterDrop))
            local corridor = zone.corridor
            out[#out + 1] = string.format('  CORRIDOR|实体碰撞体 min=%s|含交互范围 min=%s|最长连续≥%d: 碰撞体 %s 米 / 含交互 %s 米|采样步长=%s',
                fmt(corridor.collision.minWidth), fmt(corridor.all.minWidth), M.CORRIDOR_MIN,
                fmt(corridor.collision.longestRunLength, 1), fmt(corridor.all.longestRunLength, 1),
                fmt(corridor.sampleStep))
            for _, rect in ipairs(zone.combat or {}) do
                local function describe(hits)
                    local parts = {}
                    for _, hit in ipairs(hits) do
                        parts[#parts + 1] = string.format('%s(%s×%s, y=%s..%s)', hit.name,
                            fmt(hit.overlapX), fmt(hit.overlapZ), fmt(hit.minY), fmt(hit.maxY))
                    end
                    return #parts > 0 and table.concat(parts, '; ') or '无'
                end
                out[#out + 1] = string.format('  COMBAT|%s|缩放=%s|x[%s,%s] z[%s,%s]|实体碰撞体侵占=%d: %s|交互范围侵占=%d: %s',
                    rect.label, fmt(rect.scale), fmt(rect.minX), fmt(rect.maxX), fmt(rect.minZ), fmt(rect.maxZ),
                    #rect.collisionHits, describe(rect.collisionHits),
                    #rect.interactionHits, describe(rect.interactionHits))
            end
        else
            out[#out + 1] = '  SHORE|无现场水面实体，且配置水域不可用'
        end
        local support = zone.support
        local window = zone.window
        out[#out + 1] = string.format('  WINDOW|%d×%d 无侵占位置：实体碰撞体 %d / 含交互范围 %d（候选 %d，步长 %s）|最优位置=(%s,%s) 侵占 %s 平方米',
            window.width, window.height, window.freeCollision, window.freeAll, window.candidates,
            fmt(window.step), fmt(window.best.centerX), fmt(window.best.centerZ), fmt(window.best.intrudedAll))
        local surfaces = {}
        for _, surface in ipairs(support.surfaces) do
            surfaces[#surfaces + 1] = string.format('%s(顶 %s)', surface.path:gsub('^.-/', ''), fmt(surface.topY))
        end
        local coverage = {}
        for label, percent in pairs(support.coverage or {}) do
            coverage[#coverage + 1] = string.format('%s=%s%%', label, fmt(percent, 1))
        end
        table.sort(coverage)
        out[#out + 1] = string.format('  SUPPORT|地块板顶=%s (合同地面差 %s)|可站立面=%d|%s|战斗空间覆盖: %s',
            fmt(support.landTop), fmt(support.landTop and (support.landTop - zone.groundY)),
            #support.surfaces, (#surfaces > 0 and table.concat(surfaces, ', ') or '无'),
            (#coverage > 0 and table.concat(coverage, ' ') or '-'))
        local anchors = zone.anchors
        local missing = {}
        for _, item in ipairs(anchors.missing) do missing[#missing + 1] = item.name .. '(' .. tostring(item.state) .. ')' end
        out[#out + 1] = string.format('  ANCHOR|entries=%d|resolved=%d|nonzero=%d|maxDelta=%s/%s/%s|missing=%d|%s',
            anchors.entries, anchors.resolved, anchors.nonzero,
            fmt(anchors.maxDx, 3), fmt(anchors.maxDy, 3), fmt(anchors.maxDz, 3),
            #anchors.missing, table.concat(missing, ', '))
    end
    return table.concat(out, '\n')
end

local function jsonEscape(text)
    return (tostring(text):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        if c == '\n' then return '\\n' end
        if c == '\t' then return '\\t' end
        return string.format('\\u%04x', c:byte())
    end))
end

--- 极简 JSON 编码（够本项目证据用；键序按插入序，Lua 5.4 的 pairs 不保证序）。
function M.encodeJson(value, indent)
    indent = indent or ''
    local t = type(value)
    if value == nil then return 'null' end
    if t == 'boolean' then return value and 'true' or 'false' end
    if t == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        return string.format('%.6g', value)
    end
    if t == 'string' then return '"' .. jsonEscape(value) .. '"' end
    if t == 'table' then
        local isArray = true
        for key in pairs(value) do
            if type(key) ~= 'number' then isArray = false end
        end
        if isArray then
            local parts = {}
            for _, item in ipairs(value) do parts[#parts + 1] = M.encodeJson(item, indent .. '  ') end
            if #parts == 0 then return '[]' end
            return '[\n' .. indent .. '  ' .. table.concat(parts, ',\n' .. indent .. '  ') .. '\n' .. indent .. ']'
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        if #keys == 0 then return '{}' end
        local parts = {}
        for _, key in ipairs(keys) do
            parts[#parts + 1] = string.format('%s"%s": %s', indent .. '  ', jsonEscape(key),
                M.encodeJson(value[key], indent .. '  '))
        end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
    end
    return 'null'
end

--- 去掉盒体引用，避免把整棵基线塞进 JSON（体积与可读性）。报告与证据共用同一步。
function M.stripBoxes(payload)
    for _, zone in ipairs(payload.zones) do
        for _, wall in ipairs(zone.walls.xWalls or {}) do wall.box = nil end
        for _, wall in ipairs(zone.walls.zWalls or {}) do wall.box = nil end
        zone.walls.caps = nil
        if zone.shore then zone.shore.box = nil end
    end
    return payload
end

function M.readFile(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local text = file:read('*a')
    file:close()
    return text
end

local function writeFile(path, text)
    local file = io.open(path, 'wb')
    if not file then return false end
    file:write(text)
    file:close()
    return true
end

local function main(argv)
    local jsonPath, csvPath, textPath
    for index = 1, #(argv or {}) do
        if argv[index] == '--json' then jsonPath = argv[index + 1] end
        if argv[index] == '--csv' then csvPath = argv[index + 1] end
        if argv[index] == '--text' then textPath = argv[index + 1] end
    end
    csvPath = csvPath or M.CSV
    local text = M.readFile(csvPath)
    if not text then
        print('读不到基线 CSV：' .. csvPath)
        print('先在编辑器里跑 tests/probes/zone_baseline_inventory.lua 重新生成（见 evidence/issue65/zone-geometry-facts.md §5）')
        os.exit(1)
    end
    local GameCfg = require('common.GameCfg')
    local zones = M.audit(GameCfg, M.parseCsv(text))
    local lines = {
        ('空间合同核对（基线 %s，%d 个区）'):format(csvPath, #zones),
        '口径：pivot=Y 底面/XZ 中心（仅 preset 1101635 已实测）；只报事实与差值，不判定合格。',
        M.report(zones),
    }
    print(lines[1])
    print(lines[2])
    print(lines[3])
    -- 文本证据自己写盘（LF），避免不同 shell 重定向带来的 CRLF 差异 —— 证据要能逐字节复现。
    if textPath and not writeFile(textPath, table.concat(lines, '\n') .. '\n') then
        print('文本写入失败：' .. textPath)
        os.exit(1)
    end
    if jsonPath then
        local payload = { source = csvPath, corridorMin = M.CORRIDOR_MIN, headroom = M.HEADROOM,
            combat = M.COMBAT, zones = zones }
        M.stripBoxes(payload)
        if writeFile(jsonPath, M.encodeJson(payload)) then
            print('JSON 已写入：' .. jsonPath)
        else
            print('JSON 写入失败：' .. jsonPath)
            os.exit(1)
        end
    end
end

if arg and arg[0] and arg[0]:find('zone_space_contract', 1, true) then
    main(arg)
end

return M
