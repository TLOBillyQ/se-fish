-- 仓库根执行 lua tools/validate_content.lua；单行输出数量并逐行列出来源与错误。
local cfg = require('common.GameCfg')
local result = require('common.ContentValidation').Check(cfg)
local counts = result.counts
print(('内容基线：钓鱼区 %d、鱼种 %d、物品 %d、商店 %d、抽奖图案 %d（权重 %d）、盲盒 %d（权重 %d）')
    :format(counts.zones, counts.fish, counts.items, counts.shop,
        counts.lottery, counts.lotteryWeight, counts.blindbox, counts.blindboxWeight))
for _, issue in ipairs(result.errors) do io.stderr:write(issue .. '\n') end
if #result.errors > 0 then os.exit(1) end
print('内容引用校验通过')
