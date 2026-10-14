-- #65 P1 七区空气墙真实顶底范围（运行时射线口径，server 平台）。
-- 复跑（验收槽隔离，不动正式存档）：
--   lua tools/cli.lua acceptance-slot new && lua tools/cli.lua deploy
--   editor-cli play start --wait-ready --json
--   editor-cli exec --platform server --file <本文件绝对路径> --timeout 60 --json
--   editor-cli log grep AIRWALLBOUNDS65 --play-session <session> --json
--   editor-cli play stop && lua tools/cli.lua acceptance-slot off && lua tools/cli.lua deploy
--
-- 为什么是运行时：编辑器 eval 上下文只暴露 World/Task/Environment/Asset，没有 PhysicsService
--   （2026-10-14 实测），编辑模式无法打射线；沿用 2026-10-12 鱼塘施工时验证过的运行时射线口径。
--
-- 只读：不移动、不改属性、不写地图。走 parent-scoped 查找 + 非根子树 GetChildren。
--
-- 取点口径（关键）：每面墙打六条轴对齐射线，取点固定在「墙自身尺寸的 1/4 偏移」处：
--   Y 向射线取 (px + sx/4, pz + sz/4)；X 向取 (py + sy/4, pz + sz/4)；Z 向取 (px + sx/4, py + sy/4)。
--   这样无论 pivot 是「中心」还是「底/起点」，取点都落在墙体内，且都不贴边（避免擦射）。
--   射线自外向内：起点在墙外一个身位以上（+size+10），方向长度 2*size+40。
-- 判定：命中点即为该面的世界坐标；minY == py → Y 为底部，minY == py - sy/2 → Y 为中心。
-- 过滤：优先用 RaycastParams(FilterType=Include, FilterDescendantsInstances={本墙})，
--   并输出实际命中的 Instance 名，便于识别「过滤没生效、打到了别的东西」。
local MARK = 'AIRWALLBOUNDS65V2'
local world = game:GetService('World')
local physics = game:GetService('PhysicsService')
local function emit(line) print(MARK .. '|' .. line) end

if not physics then
    emit('ABORT|无 PhysicsService')
    return
end
local includeType = 1
local okEnums = pcall(function() includeType = Enums.RaycastFilterType.Include end)
if not okEnums then includeType = 1 end
emit('ENV|world=' .. tostring(world ~= nil) .. '|physics=' .. tostring(physics ~= nil)
    .. '|enums=' .. tostring(okEnums) .. '|includeType=' .. tostring(includeType))

local function abs(v)
    if v < 0 then return -v end
    return v
end
local function num(v)
    if type(v) ~= 'number' then return tostring(v) end
    local ok, s = pcall(string.format, '%.3f', v)
    if ok then return s end
    return tostring(v)
end
-- 兼容运行时 userdata 式（.x 可取，tostring 为 Vector3(x,y,z)）
-- 与编辑器数组式（[1]=x）两种向量：先试字段，取不到再试下标。
local function comp(v, i)
    if v == nil then return nil end
    local ok, c = pcall(function()
        if i == 1 then return v.x elseif i == 2 then return v.y else return v.z end
    end)
    if ok and c ~= nil then return c end
    return v[i]
end
local function vec(v)
    if type(v) ~= 'table' then return tostring(v) end
    return num(comp(v, 1)) .. ',' .. num(comp(v, 2)) .. ',' .. num(comp(v, 3))
end

local function cast(unit, origin, direction)
    local ok, hit = pcall(function()
        local params = RaycastParams.New()
        params.FilterDescendantsInstances = { unit }
        params.FilterType = includeType
        return physics:Raycast(origin, direction, params)
    end)
    if not ok then return nil, 'RAY_ERR:' .. tostring(hit) end
    if not hit then return nil, 'MISS' end
    local p = hit.Position
    return { x = comp(p, 1), y = comp(p, 2), z = comp(p, 3),
        name = tostring(hit.Instance and hit.Instance.Name) }
end

local zones = { '01 鱼塘', '02 虾池', '03 蟹湖', '04 树林岛', '05 沙滩岛', '06 礁石岛', '07 火山岛' }

local function measure(zoneLabel, unit)
    local p = unit.Position
    local size = unit.Size
    local px, py, pz = comp(p, 1), comp(p, 2), comp(p, 3)
    local sx, sy, sz = comp(size, 1), comp(size, 2), comp(size, 3)
    if not (px and py and pz and sx and sy and sz) then
        emit('BOX|' .. zoneLabel .. '|' .. tostring(unit.Name) .. '|SHAPE_ERR|pos=' .. vec(p)
            .. '|size=' .. vec(size))
        return false
    end
    local qx, qy, qz = px + sx / 4, py + sy / 4, pz + sz / 4
    local top = cast(unit, Vector3.New(qx, py + sy + 10, qz), Vector3.New(0, -(2 * sy + 40), 0))
    local bot = cast(unit, Vector3.New(qx, py - sy - 10, qz), Vector3.New(0, (2 * sy + 40), 0))
    local maxX = cast(unit, Vector3.New(px + sx + 10, qy, qz), Vector3.New(-(2 * sx + 40), 0, 0))
    local minX = cast(unit, Vector3.New(px - sx - 10, qy, qz), Vector3.New((2 * sx + 40), 0, 0))
    local maxZ = cast(unit, Vector3.New(qx, qy, pz + sz + 10), Vector3.New(0, 0, -(2 * sz + 40)))
    local minZ = cast(unit, Vector3.New(qx, qy, pz - sz - 10), Vector3.New(0, 0, (2 * sz + 40)))

    local name = tostring(unit.Name)
    local hits, others = 0, 0
    for _, h in ipairs({ top, bot, maxX, minX, maxZ, minZ }) do
        if h then
            hits = hits + 1
            if h.name ~= name then others = others + 1 end
        end
    end
    local minY, maxY = bot and bot.y, top and top.y
    local loX, hiX = minX and minX.x, maxX and maxX.x
    local loZ, hiZ = minZ and minZ.z, maxZ and maxZ.z
    local function span(a, b)
        if a and b then return num(b - a) end
        return 'nil'
    end
    local pivot = 'undetermined'
    if minY and maxY then
        if abs(minY - py) <= 0.05 then
            pivot = 'Y=bottom'
        elseif abs(minY - (py - sy / 2)) <= 0.05 then
            pivot = 'Y=center'
        else
            pivot = 'Y=offset' .. num(minY - py)
        end
    end
    local pivotX = 'undetermined'
    if loX and hiX then
        if abs(loX - px) <= 0.05 then
            pivotX = 'X=min'
        elseif abs(loX - (px - sx / 2)) <= 0.05 then
            pivotX = 'X=center'
        else
            pivotX = 'X=offset' .. num(loX - px)
        end
    end
    emit(table.concat({ 'BOX', zoneLabel, name,
        'pos=' .. vec(p), 'size=' .. vec(size),
        'Y=[' .. tostring(minY) .. ',' .. tostring(maxY) .. ']', 'Yspan=' .. span(minY, maxY),
        'X=[' .. tostring(loX) .. ',' .. tostring(hiX) .. ']', 'Xspan=' .. span(loX, hiX),
        'Z=[' .. tostring(loZ) .. ',' .. tostring(hiZ) .. ']', 'Zspan=' .. span(loZ, hiZ),
        'pivot' .. pivot .. '/' .. pivotX, 'hits=' .. tostring(hits) .. '/6',
        'otherHits=' .. tostring(others) }, '|'))
    return true
end

local total = 0
for _, label in ipairs(zones) do
    local ok, node = pcall(function() return world:FindFirstChild(label, true) end)
    if not ok or not node then
        emit('ZONE|' .. label .. '|MISS')
    else
        local folder = node:FindFirstChild('空气墙', true)
        if not folder then
            emit('ZONE|' .. label .. '|' .. tostring(node.Name) .. '|FOLDER_MISS')
        else
            local children = folder:GetChildren()
            emit('ZONE|' .. label .. '|' .. tostring(node.Name) .. '|空气墙=' .. tostring(folder.Name)
                .. '|walls=' .. tostring(#children))
            for _, child in ipairs(children) do
                total = total + 1
                local okRow, err = pcall(measure, label, child)
                if not okRow then
                    emit('BOX|' .. label .. '|' .. tostring(child.Name) .. '|MEASURE_FAIL|' .. tostring(err))
                end
            end
        end
    end
end
emit('SUMMARY|walls=' .. tostring(total))
