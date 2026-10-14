-- #65 P3 布局数据块生成器：把 tools/plan_zone_layout.lua 算出的写操作渲染成字面量，
-- 写进 tests/probes/zone_layout_apply.lua 的两条标记之间。
--
-- 为什么嵌字面量：编辑器 exec 沙盒里 require/io 都不可用（见 config_anchor_probe 的同款注释），
-- 探针不能自己加载规划器，只能带数据。同步守卫在 fast 车道
-- tests/native/zone_layout_plan_test.lua，规划器改了而没重生成就会红。
--
-- 用法（仓库根执行）：
--   lua tools/gen_zone_layout_probe.lua           # 重写数据块
--   lua tools/gen_zone_layout_probe.lua --check   # 只校验同步，不同步退出码 1
local M = {}

local plan = require('tools.plan_zone_layout')

local function readProbe()
    return plan.readFile(plan.PROBE)
end

local function main(argv)
    local check = argv and argv[1] == '--check'
    local rows = plan.parseCsvRows(plan.readFile(plan.CSV))
    if not rows then
        print('读不到基线 CSV：' .. plan.CSV)
        os.exit(1)
    end
    local GameCfg = require('common.GameCfg')
    local layouts, skipped = plan.buildAll(GameCfg, rows)
    for _, why in ipairs(skipped) do print('SKIP|' .. why) end
    local want = plan.renderOps(layouts, rows)
    local text = readProbe()
    if not text then
        print('探针文件读不到：' .. plan.PROBE)
        os.exit(1)
    end
    local got = plan.extractBlock(text)
    if check then
        if got == want then
            print(('布局数据块已同步：%d 个区、%d 条操作'):format(#layouts,
                (function()
                    local total = 0
                    for _, layout in ipairs(layouts) do total = total + #layout.ops end
                    return total
                end)()))
            return
        end
        print('布局数据块**不同步**：请运行 lua tools/gen_zone_layout_probe.lua')
        os.exit(1)
    end
    local updated = text:sub(1, (text:find(plan.BEGIN_MARK, 1, true)) - 1) .. want
        .. text:sub((text:find(plan.END_MARK, 1, true)) + #plan.END_MARK)
    local file = assert(io.open(plan.PROBE, 'wb'))
    file:write(updated)
    file:close()
    print(('已生成布局数据块：%d 个区 → %s'):format(#layouts, plan.PROBE))
end

if arg and arg[0] and arg[0]:find('gen_zone_layout_probe', 1, true) then
    main(arg)
end

return M
