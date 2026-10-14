-- #65 P2 配置锚点清单生成器：把 common/GameCfg.lua 里被运行时**按名查找**的锚点名，
-- 离线解析成字面量数据块，写进 tests/probes/config_anchor_resolution.lua 的两条标记之间。
--
-- 为什么离线生成：编辑器 exec 沙盒（edit mode）里 require 不可用
-- （sdk.common.lua:830: attempt to call a nil value (field 'require')），且没有 io/os，
-- 探针既不能自己加载 common/GameCfg.lua，也不能读外部数据文件。
--
-- 用法（仓库根执行）：
--   lua tools/gen_config_anchor_probe.lua           # 重写数据块
--   lua tools/gen_config_anchor_probe.lua --check   # 只校验是否同步，不同步退出码 1
-- 同步守卫同时由 tests/native/config_anchor_baseline_sync_test.lua 在 fast 车道执行。
local M = {}
M.PROBE = 'tests/probes/config_anchor_resolution.lua'
M.BEGIN_MARK = '-- >>> GENERATED ANCHOR DATA'
M.END_MARK = '-- <<< GENERATED ANCHOR DATA'

-- 收集：锚点名 + 来源 + 预期区 + 状态（observed / planned / '-'）
function M.collect(GameCfg)
    local labels, labelByZoneId = {}, {}
    for index, zone in ipairs(GameCfg.Zones) do
        labels[index] = string.format('%02d ', index) .. tostring(zone.Name)
        labelByZoneId[zone.Id] = labels[index]
    end
    local entries = {}
    local function add(source, zoneLabel, name, state)
        if name == nil or name == '' then return end
        entries[#entries + 1] = { source = source, zone = zoneLabel or '-',
            name = tostring(name), state = state or '-' }
    end
    -- 1. #125 场景合同实体（Land / Safe / Fisherman / Shop / Lottery / Grill / Water / Boundary / Bait / Ferry）
    for index, zone in ipairs(GameCfg.Zones) do
        local scene = zone.Scene
        if scene then
            for _, entity in ipairs(scene.Entities or {}) do
                add('Scene.' .. tostring(entity.Role), labels[index], entity.Name, entity.State)
            end
        end
    end
    -- 2. 钓鱼佬锚点（MgrInteract.FindAnchor 的名字来源）
    for index, fisherman in ipairs(GameCfg.Interact.Fishermen or {}) do
        for _, name in ipairs(fisherman.AnchorNames or {}) do
            add('Interact.Fishermen', labels[index], name, '-')
        end
    end
    -- 3. 商店锚点（GameCfg.Shop.Stands 是硬编码字符串，不从 Scene 派生）
    for index, stand in ipairs((GameCfg.Shop or {}).Stands or {}) do
        add('Shop.Stands', labels[index], stand.AnchorName, '-')
    end
    -- 4. 烧烤锚点（MgrGrill.FindAnchor）
    for _, point in ipairs((GameCfg.Grill or {}).Points or {}) do
        add('Grill.Points', labelByZoneId[point.ZoneId], point.AnchorName, '-')
    end
    -- 5. 抽奖机锚点（GameCfg.Lottery.MachineAnchors）
    local okAnchors, anchors = pcall(function() return GameCfg.Lottery.MachineAnchors() end)
    if okAnchors then
        for index, name in ipairs(anchors) do add('Lottery', labels[index], name, '-') end
    end
    -- 6. 摆渡锚点（MgrFerry）：去程锚点在出发区，返程锚点在到达区
    local okRoutes, routes = pcall(function() return GameCfg.Ferry.Routes end)
    if okRoutes and routes then
        for index, route in ipairs(routes) do
            add('Ferry.Outbound', labels[index], route.Outbound and route.Outbound.AnchorName, '-')
            add('Ferry.Return', labels[index + 1], route.Return and route.Return.AnchorName, '-')
        end
    end
    table.sort(entries, function(a, b)
        if a.source ~= b.source then return a.source < b.source end
        if a.zone ~= b.zone then return a.zone < b.zone end
        if a.name ~= b.name then return a.name < b.name end
        return a.state < b.state
    end)
    return entries, labels
end

-- 渲染数据块（含两条标记之间的全部文本，便于 --check 与测试逐字节比对）
function M.renderBlock(entries, labels)
    local out = { M.BEGIN_MARK .. '（由 tools/gen_config_anchor_probe.lua 生成）' }
    local zoneParts = {}
    for _, label in ipairs(labels) do zoneParts[#zoneParts + 1] = "'" .. label .. "'" end
    out[#out + 1] = 'local ZONES = { ' .. table.concat(zoneParts, ', ') .. ' }'
    out[#out + 1] = '-- 每行：来源|预期区|锚点名|配置状态'
    out[#out + 1] = 'local ANCHOR_DATA = [['
    for _, entry in ipairs(entries) do
        out[#out + 1] = table.concat({ entry.source, entry.zone, entry.name, entry.state }, '|')
    end
    out[#out + 1] = ']]'
    out[#out + 1] = M.END_MARK
    return table.concat(out, '\n')
end

-- 从探针文件里抠出数据块（含标记行）
function M.extractBlock(source)
    local beginAt = source:find(M.BEGIN_MARK, 1, true)
    if not beginAt then return nil end
    local endAt = source:find(M.END_MARK, 1, true)
    if not endAt then return nil end
    return source:sub(beginAt, endAt + #M.END_MARK - 1)
end

function M.readProbe()
    local file = io.open(M.PROBE, 'rb')
    if not file then return nil end
    local text = file:read('*a')
    file:close()
    return text
end

local function main(argv)
    local check = argv and argv[1] == '--check'
    local GameCfg = require('common.GameCfg')
    local entries, labels = M.collect(GameCfg)
    local want = M.renderBlock(entries, labels)
    local text = M.readProbe()
    if not text then
        print('探针文件读不到：' .. M.PROBE)
        os.exit(1)
    end
    local got = M.extractBlock(text)
    if check then
        if got == want then
            print(('配置锚点数据块已同步：%d 条锚点、%d 个区'):format(#entries, #labels))
            return
        end
        print('配置锚点数据块**不同步**：请运行 lua tools/gen_config_anchor_probe.lua')
        os.exit(1)
    end
    if not got then
        print('探针文件缺少生成标记：' .. M.BEGIN_MARK)
        os.exit(1)
    end
    local updated = text:sub(1, (text:find(M.BEGIN_MARK, 1, true)) - 1) .. want
        .. text:sub((text:find(M.END_MARK, 1, true)) + #M.END_MARK)
    local file = io.open(M.PROBE, 'wb')
    file:write(updated)
    file:close()
    print(('已生成数据块：%d 条锚点、%d 个区 → %s'):format(#entries, #labels, M.PROBE))
end

if arg and arg[0] and arg[0]:find('gen_config_anchor_probe', 1, true) then
    main(arg)
end

return M
