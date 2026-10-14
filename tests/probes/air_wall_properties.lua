-- #65 P1 七区空气墙属性基线（编辑器侧，edit mode，只读）。
-- 复跑：
--   editor-cli exec --file <本文件绝对路径> --expect-edit-mode --timeout 60 --json
--   editor-cli log grep AIRWALLPROP65 --platform editor --context 0 --max-matches 500 --json
-- （exec 的返回值会被 CLI 截断，所以逐行 print，用 log grep 取全量。）
--
-- 口径：只读。走 parent-scoped 查找 + 非根子树 GetChildren，不枚举 Script/PresetLink 类型，
--       不用 editor-unit 子命令（见 docs/技术难点识别.md「绕过合同」四条硬边界）。
-- 本探针只回读**属性**，不测几何：真实顶底由 tests/probes/air_wall_bounds_runtime.lua
--   在运行时用射线测量（编辑器 eval 上下文没有 PhysicsService，打不了射线）。
-- 声明：属性回读不等于运行时角色碰撞行为（归 P8）。
local MARK = 'AIRWALLPROP65'
local world = editor:GetService('World')
local function emit(line) print(MARK .. '|' .. line) end
local function num(v)
    if type(v) ~= 'number' then return tostring(v) end
    return string.format('%.3f', v)
end
-- 兼容字段式与数组式向量的分量读取
local function comp(v, i)
    if type(v) ~= 'table' then return nil end
    if v.x ~= nil then
        if i == 1 then return v.x elseif i == 2 then return v.y else return v.z end
    end
    return v[i]
end
local function vec(v)
    if type(v) ~= 'table' then return tostring(v) end
    return num(comp(v, 1)) .. ',' .. num(comp(v, 2)) .. ',' .. num(comp(v, 3))
end
local function prop(unit, name)
    local ok, value = pcall(function() return unit:GetProperty(name) end)
    if not ok then return 'ERR' end
    if value == nil then return 'nil' end
    return tostring(value)
end

local zones = { '01 鱼塘', '02 虾池', '03 蟹湖', '04 树林岛', '05 沙滩岛', '06 礁石岛', '07 火山岛' }
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
                local okRow, line = pcall(function()
                    return table.concat({ 'WALL', label, tostring(child.Name),
                        'pos=' .. vec(child.Position), 'size=' .. vec(child:GetProperty('Size')),
                        'canCollide=' .. prop(child, 'CanCollide'),
                        'canQuery=' .. prop(child, 'CanQuery'),
                        'physicsActive=' .. prop(child, 'PhysicsActive'),
                        'climbable=' .. prop(child, 'Climbable'),
                        'assetId=' .. prop(child, 'AssetId') }, '|')
                end)
                if okRow then
                    emit(line)
                else
                    emit('WALL|' .. label .. '|' .. tostring(child.Name) .. '|READ_FAIL|' .. tostring(line))
                end
            end
        end
    end
end
emit('SUMMARY|walls=' .. tostring(total))
return MARK .. ' emitted walls=' .. tostring(total)
