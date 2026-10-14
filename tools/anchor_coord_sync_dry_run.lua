-- #102 锚点坐标同步 dry-run（离线工具，只读）。
--
-- 问题：`common/GameCfg.lua` 的七区 `Scene.Entities` 坐标仍是 #125 时代的计划值（安全点取区中心、
-- 鱼饵取中心 ±3、设施取固定公式），而 03–07 区灰盒已按 #62 动线施工落盘，配置没跟上现场。
--
-- 本工具只算「配置要改成什么」，**不改任何东西**：对每条锚点给出
--   配置现值 / 现场实测 (x=centerX, y=minY, z=centerZ) / 需要施加的位移，
-- 供重开核验通过后套用。
--
-- 输入：
--   * 现场基线 CSV（默认 evidence/issue65/zone-baseline-rows-post-p3.csv，即施工后快照）
--   * common/GameCfg.lua（加载时已做「折返双排」刚体变换）
-- 输出：stdout 文本报告；`--json <path>` 另写机器可读结果（证据要能逐字节复现，统一 LF）。
--
-- 口径：
--   1. **pivot** 沿用 `tools/zone_space_contract.lua` 的声明（Y 底面 / XZ 中心），只有 preset 1101635
--      是实测，其余是假设 —— 所以本工具把 `minY` 与 `centerY` 都算出来，差异非零时报告里显式标注，
--      不把假设当实测。
--   2. **运行时真源**：`Scene.SafePoint`（摆渡目的地、`GroundY`）、`BaitSpots.Positions`、数学水域。
--      其余锚点是核对对象而非运行时输入；本工具把它们标出来，避免「改了没用」或「改了有副作用」被混为一谈。
--   3. **只报差值与建议位移，不判定合格**；y 是否允许变动由使用者决定（本轮结论：y 不动，只动 x/z）。
local M = {}

M.CSV = 'evidence/issue65/zone-baseline-rows-post-p3.csv'
M.EPSILON = 0.001

-- 运行时真源：改了会直接影响玩法，改前必须确认。
M.RUNTIME_CONSUMERS = {
    Safe = '摆渡目的地（PlannedRoutes Destination）与飞行 GroundY',
    Bait = 'BaitSpots.Positions（鱼饵刷新点）',
    Water = '数学水域实体名（scene.Waters[].EntityName）',
    Ferry = '摆渡落点锚点（PlannedRoutes 起终点）',
}

local contract = require('tools.zone_space_contract')

local function trim(text) return (tostring(text):gsub('^%s+', ''):gsub('%s+$', '')) end

--- 现场基线 → 名字索引（同名取第一条，与 zone_space_contract.anchorDeltas 同口径）。
function M.indexByName(rows, zoneLabel)
    local byName = {}
    for _, node in ipairs(contract.nodesOf(rows, zoneLabel)) do
        byName[node.name] = byName[node.name] or node
    end
    return byName
end

--- 逐条锚点算出现场实测位置与位移；不修改入参。
function M.resolveZone(cfgZone, zoneLabel, rows)
    local byName = M.indexByName(rows, zoneLabel)
    local entries, missing = {}, {}
    for _, entity in ipairs(cfgZone.Scene.Entities or {}) do
        local node = byName[entity.Name]
        if node then
            local dx = node.centerX - entity.Position.x
            local dy = node.minY - entity.Position.y
            local dz = node.centerZ - entity.Position.z
            local centerY = (node.minY + node.maxY) / 2
            local pivotSuspect = math.abs(centerY - node.minY) > M.EPSILON
            entries[#entries + 1] = {
                name = entity.Name, role = entity.Role, state = entity.State,
                current = { x = entity.Position.x, y = entity.Position.y, z = entity.Position.z },
                target = { x = node.centerX, y = node.minY, z = node.centerZ },
                centerY = centerY,
                delta = { x = dx, y = dy, z = dz },
                needsSync = math.abs(dx) > M.EPSILON or math.abs(dy) > M.EPSILON or math.abs(dz) > M.EPSILON,
                pivotSuspect = pivotSuspect,
                runtimeConsumer = M.RUNTIME_CONSUMERS[entity.Role],
            }
        else
            missing[#missing + 1] = { name = entity.Name, role = entity.Role, state = entity.State }
        end
    end
    table.sort(missing, function(a, b) return a.name < b.name end)
    return { label = zoneLabel, entries = entries, missing = missing }
end

function M.audit(GameCfg, rows)
    local zones = {}
    for index, cfgZone in ipairs(GameCfg.Zones) do
        local label = string.format('%02d ', index) .. tostring(cfgZone.Name)
        zones[#zones + 1] = M.resolveZone(cfgZone, label, rows)
    end
    return zones
end

local function fmt(value, digits)
    return string.format('%.' .. (digits or 2) .. 'f', value)
end

function M.report(zones)
    local lines = {}
    local totalSync, totalEntries = 0, 0
    for _, zone in ipairs(zones) do
        local sync = 0
        for _, entry in ipairs(zone.entries) do
            totalEntries = totalEntries + 1
            if entry.needsSync then
                sync = sync + 1
                totalSync = totalSync + 1
                local flags = {}
                if entry.pivotSuspect then flags[#flags + 1] = 'centerY≠minY' end
                if entry.runtimeConsumer then flags[#flags + 1] = '运行时真源' end
                lines[#lines + 1] = string.format(
                    '  SYNC|%s|%s|%s|配置 (%s, %s, %s) → 现场 (%s, %s, %s)|Δ (%s, %s, %s)%s',
                    zone.label, entry.name, entry.role,
                    fmt(entry.current.x), fmt(entry.current.y), fmt(entry.current.z),
                    fmt(entry.target.x), fmt(entry.target.y), fmt(entry.target.z),
                    fmt(entry.delta.x), fmt(entry.delta.y), fmt(entry.delta.z),
                    #flags > 0 and ('|' .. table.concat(flags, '; ')) or '')
            end
        end
        local missingNames = {}
        for _, item in ipairs(zone.missing) do
            missingNames[#missingNames + 1] = item.name .. '(' .. tostring(item.state) .. ')'
        end
        lines[#lines + 1] = string.format('  ZONE|%s|entries=%d|needsSync=%d|missing=%d|%s',
            zone.label, #zone.entries, sync, #zone.missing, table.concat(missingNames, ', '))
    end
    local header = {
        '锚点坐标同步 dry-run（基线 ' .. M.CSV .. '）',
        '口径：现场实测取 (x=centerX, y=minY, z=centerZ)，与 zone_space_contract 的 pivot 声明一致；只报差值，不判定合格。',
        '本工具不修改 GameCfg；下列 SYNC 行是重开核验通过后要套用的位移。',
    }
    lines[#lines + 1] = string.format('  TOTAL|entries=%d|needsSync=%d', totalEntries, totalSync)
    return table.concat(header, '\n') .. '\n' .. table.concat(lines, '\n')
end

local function readFile(path)
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

--- 纯 Lua 的 JSON 编码（与 zone_space_contract 同风格：不依赖外部库，键序固定）。
local function encodeJson(value)
    local out = {}
    local function esc(text)
        return '"' .. tostring(text):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
    end
    local function number(value)
        if value == math.floor(value) and math.abs(value) < 1e15 then
            return string.format('%d', value)
        end
        return string.format('%.6f', value)
    end
    local function encode(item)
        local kind = type(item)
        if kind == 'table' then
            if item[1] ~= nil then
                local parts = {}
                for _, element in ipairs(item) do parts[#parts + 1] = encode(element) end
                return '[' .. table.concat(parts, ',') .. ']'
            end
            local keys = {}
            for key in pairs(item) do keys[#keys + 1] = key end
            table.sort(keys)
            local parts = {}
            for _, key in ipairs(keys) do parts[#parts + 1] = esc(key) .. ':' .. encode(item[key]) end
            return '{' .. table.concat(parts, ',') .. '}'
        elseif kind == 'string' then
            return esc(item)
        elseif kind == 'number' then
            return number(item)
        elseif kind == 'boolean' then
            return tostring(item)
        end
        return 'null'
    end
    out[#out + 1] = encode(value)
    return table.concat(out) .. '\n'
end

M.encodeJson = encodeJson

local function main(argv)
    local jsonPath, csvPath, textPath
    for index = 1, #(argv or {}) do
        if argv[index] == '--json' then jsonPath = argv[index + 1] end
        if argv[index] == '--csv' then csvPath = argv[index + 1] end
        if argv[index] == '--text' then textPath = argv[index + 1] end
    end
    csvPath = csvPath or M.CSV
    local text = readFile(csvPath)
    if not text then
        print('读不到现场基线 CSV：' .. csvPath)
        print('先用边界探针重新生成现场快照（见 evidence/issue65/zone-geometry-facts.md §5）')
        os.exit(1)
    end
    local GameCfg = require('common.GameCfg')
    local zones = M.audit(GameCfg, contract.parseCsv(text))
    local report = M.report(zones)
    print(report)
    -- 证据自己写盘（LF），避免不同 shell 重定向带来的 CRLF 差异 —— 证据要能逐字节复现。
    if textPath and not writeFile(textPath, report .. '\n') then
        print('文本写入失败：' .. textPath)
        os.exit(1)
    end
    if jsonPath then
        if writeFile(jsonPath, encodeJson({ source = csvPath, zones = zones })) then
            print('JSON 已写入：' .. jsonPath)
        else
            print('JSON 写入失败：' .. jsonPath)
            os.exit(1)
        end
    end
end

if arg and arg[0] and arg[0]:find('anchor_coord_sync_dry_run', 1, true) then
    main(arg)
end

return M
