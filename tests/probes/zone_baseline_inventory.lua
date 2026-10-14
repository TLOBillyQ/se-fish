-- #65 P2 七区场景基线盘点（编辑器侧，edit mode，只读）。
-- 复跑：
--   editor-cli exec --file <本文件绝对路径> --expect-edit-mode --timeout 120 --json
--   editor-cli log grep P2BASE65 --platform editor --context 0 --max-matches 1500 --json
-- （exec 的返回值会被 CLI 截断，所以逐行 print，用 log grep 取全量。）
--
-- 用途：为 P3–P7 各修改批次留一份**可恢复基线**——名称、类型、层级、当前变换、
--   尺寸与碰撞属性。派生几何事实见 evidence/issue65/zone-geometry-facts.md。
--
-- 口径（与 docs/技术难点识别.md「绕过合同」一致，另有几条本轮实测口径）：
--   1. 只读；不用 editor-unit 子命令；不枚举 Script / PresetLink 类型本身。
--   2. 不用 World:GetDescendants()（World 服务没有 GetChildren）。
--   3. **Unit:FindFirstChild(name) 只匹配直接子级**——meta 只有 name 一个参数，
--      多传的 true 被静默忽略（实测：zone:FindFirstChild('大地板', true) → nil，
--      而 zone:FindFirstChild('地块'):FindFirstChild('大地板') → 命中）。
--      需要递归时用本文件的手工栈遍历，不要指望第二个参数。
--   4. World 服务（editor:GetService('World')）的 FindFirstChild(name) **是递归的**
--      （实测深度 5 的 '铁艺弯钩' 直接命中），与 Unit 的语义不同，不能混用。
--   5. 属性回读口径：Position/Scale 在编辑器 SDK 里是数组式（[1]=x,[2]=y,[3]=z），
--      Rotation 的 tostring 形如 Quaternion(w,x,y,z)。属性回读**不等于**运行时角色
--      碰撞行为（胶囊、体型、游泳/飞行状态），后者归 P8。
--   6. 不输出 UnitId：本轮加载的临时 ID 不能当跨加载稳定标识（见场景清理经验），
--      基线身份用「区/路径/类型/名称」表达。
local MARK = 'P2BASE65V2'
local world = editor:GetService('World')
local function emit(line) print(MARK .. '|' .. line) end
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
local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if not ok then return fallback end
    return value
end
local function unitType(unit)
    return tostring(safe(function() return unit:GetUnitType() end, '?'))
end
local function geometry(unit, unitTypeName)
    if unitTypeName == 'Folder' or unitTypeName == 'PresetLink'
        or unitTypeName:find('Script') then
        return 'spatial=0'
    end
    local pos = safe(function() return unit:GetPosition() end, nil)
    local rot = safe(function() return unit:GetRotation() end, nil)
    local scale = safe(function() return unit:GetScale() end, nil)
    local size = safe(function() return unit:GetProperty('Size') end, nil)
    return table.concat({ 'spatial=1', 'pos=' .. vec(pos),
        'rot=' .. (rot ~= nil and tostring(rot) or '-'),
        'scale=' .. vec(scale), 'size=' .. vec(size),
        'cc=' .. prop(unit, 'CanCollide'), 'cq=' .. prop(unit, 'CanQuery'),
        'pa=' .. prop(unit, 'PhysicsActive'), 'bt=' .. prop(unit, 'BodyType'),
        'asset=' .. prop(unit, 'AssetId') }, '|')
end
local function sortKey(unit)
    local pos = safe(function() return unit:GetPosition() end, nil)
    return tostring(unit.Name) .. '#' .. vec(pos)
end

local zones = { '01 鱼塘', '02 虾池', '03 蟹湖', '04 树林岛', '05 沙滩岛', '06 礁石岛', '07 火山岛' }
local zoneNameSet = {}
for _, label in ipairs(zones) do zoneNameSet[label] = true end

local grandTotal = 0
for _, label in ipairs(zones) do
    -- World 服务的 FindFirstChild 是递归的。
    local zone = safe(function() return world:FindFirstChild(label) end, nil)
    if not zone then
        emit('ZONE|' .. label .. '|MISS')
    else
        local rows, total = {}, 0
        local stack = { { zone, label, 1 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local unit, path, depth = item[1], item[2], item[3]
            local kids = safe(function() return unit:GetChildren() end, {})
            local ordered = {}
            for _, k in ipairs(kids) do ordered[#ordered + 1] = k end
            table.sort(ordered, function(a, b) return sortKey(a) < sortKey(b) end)
            for _, child in ipairs(ordered) do
                local cname = tostring(child.Name)
                local ctype = unitType(child)
                local cpath = path .. '/' .. cname
                total = total + 1
                rows[#rows + 1] = table.concat({ 'N', label, tostring(depth), cpath, ctype,
                    geometry(child, ctype) }, '|')
                if depth < 8 then stack[#stack + 1] = { child, cpath, depth + 1 } end
            end
        end
        table.sort(rows)
        emit('ZONE|' .. label .. '|nodes=' .. tostring(total))
        for _, row in ipairs(rows) do emit(row) end
        grandTotal = grandTotal + total
    end
end

-- 根级（不属于任何区根）盘点。
-- 注意：Script / PresetLink 类型不可枚举（硬边界 3），所以下面按类型的部分**不覆盖**
-- 这两类根级残留；另外补两条按名探测，并声明它非穷尽。
-- 实测：根级单位的父级是 World 服务包装对象，它 **能** 应答 GetUnitType() → 'World'
-- （Unit:GetParent() 不会返回 nil，也不能用 `parent == world` 比较，那个比较会报错）。
local function isRootLevel(unit)
    local node = unit
    for _ = 1, 16 do
        local parent = safe(function() return node:GetParent() end, nil)
        if parent == nil then return false end
        local ptype = tostring(safe(function() return parent:GetUnitType() end, '?'))
        if ptype == 'World' then return true end
        if zoneNameSet[tostring(safe(function() return parent.Name end, '?'))] then return false end
        node = parent
    end
    return false
end
local typeList = { 'WorldUnit', 'Folder', 'TriggerUnit', 'EffectUnit', 'SpawnLocationUnit',
    'RenderUnit', 'SoundUnit', 'TextUnit', 'SimpleLight', 'FoliageUnit', 'ModelUnit', 'GroupUnit',
    'TeleportUnit', 'PhysicsUnit', 'AnimatedUnit', 'SeatUnit', 'AttachmentUnit', 'WaterUnit',
    'TerrainUnit', 'EggyUnit', 'HumanUnit', 'SkinUnit', 'ClickDetector', 'AdBoardUnit',
    'SkeletalSocketMount' }
local seen, roots = {}, {}
for _, t in ipairs(typeList) do
    -- exact=false 让子类一并命中（实测 WorldUnit exact=true 118 / false 119）。
    local list = safe(function() return world:GetUnitsByUnitType(t, false) end, nil)
    if list == nil then
        emit('ROOTENUM|' .. t .. '|ERR')
    else
        for _, unit in ipairs(list) do
            local id = tostring(safe(function() return unit:GetUnitId() end, '?'))
            local key = id .. '#' .. tostring(unit.Name)
            if not seen[key] then
                seen[key] = true
                if isRootLevel(unit) then
                    local utype = unitType(unit)
                    roots[#roots + 1] = table.concat({ 'ROOT', tostring(unit.Name), utype,
                        geometry(unit, utype) }, '|')
                end
            end
        end
    end
end
table.sort(roots)
emit('ROOTS|count=' .. tostring(#roots))
for _, row in ipairs(roots) do emit(row) end
-- 按名探测已知根级残留（非穷尽）：'预设链接' / 'Link' / '加速锚点' / '名称1'
for _, name in ipairs({ '预设链接', '加速锚点', '名称1' }) do
    local hit = safe(function() return world:FindFirstChild(name) end, nil)
    emit('ROOTNAME|' .. name .. '|' .. (hit and unitType(hit) or 'nil'))
end
emit('SUMMARY|zoneNodes=' .. tostring(grandTotal) .. '|rootObjects=' .. tostring(#roots))
return MARK .. ' emitted zoneNodes=' .. tostring(grandTotal)
