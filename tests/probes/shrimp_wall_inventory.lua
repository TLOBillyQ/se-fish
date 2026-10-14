-- #65 P0 虾池空气墙只读回读探针（重开核验：重开前后各跑一次做对照）。
-- 复跑：editor-cli exec --file <本文件绝对路径> --expect-edit-mode --json  → 取 data.result
-- 口径：只读。走 parent-scoped 查找 + 非根子树 GetChildren，不枚举 Script/PresetLink 类型，
--       不用 editor-unit 子命令（见 docs/技术难点识别.md「绕过合同」四条硬边界）。
-- 输出每行 label|Name|pos=x,y,z|size=x,y,z|canCollide|physicsActive|bodyType|climbable|assetId
local world = editor:GetService('World')
local function prop(unit, name)
    local ok, value = pcall(function() return unit:GetProperty(name) end)
    if not ok then return 'ERR' end
    if value == nil then return 'nil' end
    return tostring(value)
end
local function vec(value)
    if type(value) ~= 'table' then return tostring(value) end
    if value[1] ~= nil then return tostring(value[1]) .. ',' .. tostring(value[2]) .. ',' .. tostring(value[3]) end
    return tostring(value.x) .. ',' .. tostring(value.y) .. ',' .. tostring(value.z)
end
local function row(label, unit)
    local ok, line = pcall(function()
        return table.concat({ label, tostring(unit.Name), 'pos=' .. vec(unit.Position),
            'size=' .. vec(unit:GetProperty('Size')),
            'canCollide=' .. prop(unit, 'CanCollide'),
            'physicsActive=' .. prop(unit, 'PhysicsActive'),
            'bodyType=' .. prop(unit, 'BodyType'),
            'climbable=' .. prop(unit, 'Climbable'),
            'assetId=' .. prop(unit, 'AssetId') }, '|')
    end)
    return ok and line or (label .. '|READ_FAIL|' .. tostring(line))
end
local rows = {}
local zone = world:FindFirstChild('02 虾池', true)
if not zone then return 'FIND_FAIL|02 虾池' end
rows[#rows + 1] = 'ZONE|' .. tostring(zone.Name)
local folder = zone:FindFirstChild('空气墙', true)
if not folder then
    rows[#rows + 1] = 'FIND_FAIL|空气墙'
    return table.concat(rows, '\n')
end
rows[#rows + 1] = 'FOLDER|' .. tostring(folder.Name) .. '|assetId=' .. prop(folder, 'AssetId')
local children = folder:GetChildren()
rows[#rows + 1] = 'CHILDREN|' .. tostring(#children)
for _, child in ipairs(children) do
    rows[#rows + 1] = row('WALL', child)
end
return table.concat(rows, '\n')
