-- #102 虾池施工前置：拓宽后的虾池范围内现场有哪些单位（编辑器侧，edit mode，只读）。
-- 复跑：
--   editor-cli exec --file tests/probes/shrimp_pond_area_inventory.lua --expect-edit-mode --timeout 120 --json
--   editor-cli log grep SHRIMPAREA102 --platform editor --context 0 --max-matches 400 --json
--
-- 用途：回答 ADR 0003 施工前置第 1 条 —— 旧虾池是否仍有水面实体（配置注释称有一块 pos.y=4.2 的
--   深水预设，#65 基线说 02 区子树里没有）。基线探针只走区根子树，这里改按类型全量枚举，
--   不管单位挂在哪个父级，只要位置落进拓宽后的范围（外扩 10 米）就列出来，并给出完整父级路径。
-- 口径同 zone_baseline_inventory.lua：只读；不枚举 Script / PresetLink；不用 World:GetDescendants()。
local MARK = 'SHRIMPAREA102'
local AREA = { minX = 170, maxX = 310, minZ = -80, maxZ = 60 } -- x 180..300 / z −70..50 外扩 10 米
local world = editor:GetService('World')
local function emit(line) print(MARK .. '|' .. line) end
local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if not ok then return fallback end
    return value
end
local function num(v)
    if type(v) ~= 'number' then return tostring(v) end
    return string.format('%.3f', v)
end
local function comp(v, i)
    if type(v) ~= 'table' then return nil end
    if v.x ~= nil then
        if i == 1 then return v.x elseif i == 2 then return v.y else return v.z end
    end
    return v[i]
end
local function vec(v)
    if type(v) ~= 'table' then return '-' end
    return num(comp(v, 1)) .. ',' .. num(comp(v, 2)) .. ',' .. num(comp(v, 3))
end
local function prop(unit, name)
    local ok, value = pcall(function() return unit:GetProperty(name) end)
    if not ok then return 'ERR' end
    if value == nil then return 'nil' end
    return tostring(value)
end
local function pathOf(unit)
    local parts, node = { tostring(unit.Name) }, unit
    for _ = 1, 16 do
        local parent = safe(function() return node:GetParent() end, nil)
        if parent == nil then break end
        if tostring(safe(function() return parent:GetUnitType() end, '?')) == 'World' then break end
        table.insert(parts, 1, tostring(safe(function() return parent.Name end, '?')))
        node = parent
    end
    return table.concat(parts, '/')
end

local typeList = { 'WorldUnit', 'TriggerUnit', 'EffectUnit', 'SpawnLocationUnit', 'RenderUnit',
    'SoundUnit', 'TextUnit', 'SimpleLight', 'FoliageUnit', 'ModelUnit', 'GroupUnit', 'TeleportUnit',
    'PhysicsUnit', 'AnimatedUnit', 'SeatUnit', 'AttachmentUnit', 'WaterUnit', 'TerrainUnit',
    'EggyUnit', 'HumanUnit', 'SkinUnit', 'AdBoardUnit' }
local seen, rows = {}, {}
for _, t in ipairs(typeList) do
    local list = safe(function() return world:GetUnitsByUnitType(t, false) end, nil)
    if list == nil then
        emit('ENUM|' .. t .. '|ERR')
    else
        for _, unit in ipairs(list) do
            local key = tostring(safe(function() return unit:GetUnitId() end, '?')) .. '#' .. tostring(unit.Name)
            if not seen[key] then
                seen[key] = true
                local pos = safe(function() return unit:GetPosition() end, nil)
                local x, z = comp(pos, 1), comp(pos, 3)
                if type(x) == 'number' and type(z) == 'number'
                    and x >= AREA.minX and x <= AREA.maxX and z >= AREA.minZ and z <= AREA.maxZ then
                    local utype = tostring(safe(function() return unit:GetUnitType() end, '?'))
                    rows[#rows + 1] = table.concat({ 'U', pathOf(unit), utype, 'pos=' .. vec(pos),
                        'scale=' .. vec(safe(function() return unit:GetScale() end, nil)),
                        'size=' .. vec(safe(function() return unit:GetProperty('Size') end, nil)),
                        'cc=' .. prop(unit, 'CanCollide'), 'asset=' .. prop(unit, 'AssetId') }, '|')
                end
            end
        end
    end
end
table.sort(rows)
for _, row in ipairs(rows) do emit(row) end
emit('SUMMARY|units=' .. tostring(#rows))
return MARK .. ' units=' .. tostring(#rows)
