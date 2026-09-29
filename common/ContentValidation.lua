-- 纯配置检查；不依赖引擎服务。返回的每项错误都带原始表行或规则来源。
local Validate = {}

local function positive(value) return type(value) == 'number' and value > 0 end
local function nonnegative(value) return type(value) == 'number' and value >= 0 end
local function integer(value) return type(value) == 'number' and value % 1 == 0 end
local function count(map) local n = 0; for _ in pairs(map or {}) do n = n + 1 end; return n end

function Validate.Check(cfg)
    local errors = {}
    local function fail(source, message) errors[#errors + 1] = tostring(source or '配置') .. ': ' .. message end
    local zones, waters, zoneSeen = {}, {}, {}
    for _, zone in ipairs(cfg.Zones or {}) do
        if zones[zone.Id] then fail(zone.source, '钓鱼区 ID 重复 ' .. tostring(zone.Id)) end
        zones[zone.Id], waters[zone.WaterId] = zone, zone
        if not cfg.Items.Definitions[zone.BaitItemId] then fail(zone.source, '普通鱼饵不存在 ' .. tostring(zone.BaitItemId)) end
    end
    local items, fish = cfg.Items.Definitions, cfg.Fish
    local itemNumbers = {}
    for key, item in pairs(items) do
        local source = item.source
        if key ~= item.Id then fail(source, '物品键与 ID 不同 ' .. tostring(key)) end
        if itemNumbers[item.SourceId] then fail(source, '物品编号重复 ' .. tostring(item.SourceId) .. '（' .. itemNumbers[item.SourceId] .. '）') end
        itemNumbers[item.SourceId] = source
        if cfg.Items.SourceIdMap[item.SourceId] ~= key then fail(source, '物品编号映射失效 ' .. tostring(item.SourceId)) end
        if not nonnegative(item.BasePrice) then fail(source, '出售价格无效') end
        if item.implemented ~= true and item.implemented ~= false then fail(source, '未标记可用状态') end
    end
    local fishNumbers = {}
    for key, species in pairs(fish) do
        local source = species.source
        if key ~= species.Id then fail(source, '鱼种键与 ID 不同 ' .. tostring(key)) end
        local sourceKey = tostring(species.SourceId) .. ':' .. tostring(species.Grade)
        if fishNumbers[sourceKey] then fail(source, '鱼种编号和品级重复 ' .. sourceKey .. '（' .. fishNumbers[sourceKey] .. '）') end
        fishNumbers[sourceKey] = source
        if cfg.FishSourceIdMap[sourceKey] ~= key then fail(source, '鱼种编号映射失效 ' .. sourceKey) end
        if not zones[species.ZoneId] or not waters[species.WaterId] or waters[species.WaterId].Id ~= species.ZoneId then
            fail(source, '钓鱼区或水域 ID 无效 ' .. tostring(species.ZoneId) .. '/' .. tostring(species.WaterId))
        end
        if not positive(species.Health) or not positive(species.BaseWeight) or not positive(species.DrawWeight)
            or not integer(species.RodLevel) or species.RodLevel < 1 or species.RodLevel > 7
            or not nonnegative(species.BasePrice) then fail(source, '血量/重量/抽签权重/竿级/价格无效') end
        if species.Bait ~= 0 and not items[species.Bait] then fail(source, '鱼饵不存在 ' .. tostring(species.Bait)) end
        if type(species.Drops) ~= 'table' or #species.Drops == 0 then fail(source, '缺少掉落')
        else
            for _, drop in ipairs(species.Drops) do
                if not items[drop.ItemId] then fail(source, '掉落物不存在 ' .. tostring(drop.ItemId)) end
                if not integer(drop.Count) or drop.Count < 1 then fail(source, '掉落数量无效') end
            end
        end
        if species.implemented ~= true and species.implemented ~= false then fail(source, '未标记可用状态') end
        if species.Grade ~= 'boss' then zoneSeen[species.ZoneId] = true end
    end
    for _, zone in ipairs(cfg.Zones or {}) do
        if not zoneSeen[zone.Id] then fail(zone.source, '缺少普通抽鱼表 ' .. zone.Id) end
    end
    local goods, lottery, blindbox = cfg.Content.Shop.Goods, cfg.Content.Lottery.Patterns, cfg.Content.Blindbox.Entries
    local shopNumbers, activeGoods = {}, {}
    for _, row in ipairs(cfg.Shop.Goods or {}) do activeGoods[row.Number] = row end
    for _, row in ipairs(goods) do
        if shopNumbers[row.number] then fail(row.source, '商品编号重复 ' .. tostring(row.number) .. '（' .. shopNumbers[row.number] .. '）') end
        shopNumbers[row.number] = row.source
        if row.number == 27 or row.itemName == '夜明珠' then fail(row.source, '作废或禁止售卖商品') end
        if row.itemKey and not items[row.itemKey] then fail(row.source, '商品物品不存在 ' .. row.itemKey) end
        if row.itemKey and items[row.itemKey] and row.itemName ~= items[row.itemKey].Name then
            fail(row.source, '商品名称与物品表不一致 ' .. row.itemName)
        end
        if not positive(row.price) or not integer(row.minShopLevel) or row.minShopLevel < 1 or row.minShopLevel > 7
            or not nonnegative(row.purchaseLimit) or not integer(row.purchaseLimit) then fail(row.source, '商品价格/商店等级/限购无效') end
        if row.implemented ~= true and row.implemented ~= false then fail(row.source, '未标记可用状态') end
        if row.implemented == true then
            local active = activeGoods[row.number]
            if not active or active.Price ~= row.price or active.MinShopLevel ~= row.minShopLevel then
                fail(row.source, '标为可用但现有商店未上架该商品或价格/等级不同')
            end
        end
    end
    local lotteryWeight = 0
    for _, row in ipairs(lottery) do
        lotteryWeight = lotteryWeight + (row.weight or 0)
        if not positive(row.weight) or not positive(row.pairMultiplier) then fail(row.source, '抽奖图案权重/两同倍率无效') end
        local reward = row.tripleReward or {}
        if reward.kind == 'weaponChoice' then
            if #reward.itemKeys ~= 5 then fail(row.source, '三同武器组须五件') end
            for _, key in ipairs(reward.itemKeys) do if not items[key] then fail(row.source, '大奖武器不存在 ' .. tostring(key)) end end
        elseif reward.kind == 'item' then
            if not items[reward.itemKey] then fail(row.source, '三同物品不存在 ' .. tostring(reward.itemKey)) end
        else fail(row.source, '三同奖项无效') end
        if row.implemented ~= false then fail(row.source, '未实现抽奖不能标可用') end
    end
    local blindboxWeight, jackpotCount, blindboxKeys = 0, 0, {}
    for _, row in ipairs(blindbox) do
        blindboxWeight = blindboxWeight + (row.weight or 0)
        if row.jackpot then jackpotCount = jackpotCount + 1 end
        if blindboxKeys[row.itemKey] then fail(row.source, '盲盒物品重复 ' .. tostring(row.itemKey)) end
        blindboxKeys[row.itemKey] = true
        local item = items[row.itemKey]
        if not item then fail(row.source, '盲盒物品不存在 ' .. tostring(row.itemKey))
        elseif item.Name ~= row.itemName or item.Type ~= '极品食物' or item.BasePrice ~= row.basePrice then
            fail(row.source, '盲盒物品名称/类别/基础价与物品表不符') end
        if not positive(row.weight) or row.multiplier ~= 1 then fail(row.source, '盲盒权重或固定倍率无效') end
        if row.implemented ~= false then fail(row.source, '未接入平台盲盒不能标可用') end
    end
    local blind = cfg.Content.Blindbox
    if blind.Currency ~= '金豆' or blind.SinglePrice ~= 10 or blind.TenPrice ~= 90
        or blind.Pity.afterMisses ~= 49 or blind.Pity.guaranteedDraw ~= 50
        or jackpotCount ~= 2 then fail('GameSpec.md#15', '盲盒价格/保底大奖规则无效') end
    for _, key in ipairs(blind.Pity.prizeItemKeys) do
        if not blindboxKeys[key] then fail('GameSpec.md#15', '保底物品不在奖池 ' .. tostring(key)) end
    end
    local chains = cfg.Content.Exchanges or {}
    for _, chain in ipairs(chains) do
        local source = chain.source
        local elite, boss = fish[chain.EliteFish], fish[chain.BossFish]
        if not elite or elite.Grade ~= 'elite' or elite.ZoneId ~= chain.ZoneId then fail(source, '精英鱼不存在或钓鱼区不匹配 ' .. tostring(chain.EliteFish)) end
        if not boss or boss.Grade ~= 'boss' or boss.ZoneId ~= chain.ZoneId then fail(source, '首领不存在或钓鱼区不匹配 ' .. tostring(chain.BossFish)) end
        if not items[chain.EliteToken] then fail(source, '精英信物不存在 ' .. tostring(chain.EliteToken)) end
        if not items[chain.BossBait] or not items[chain.BossBait].BossBait then fail(source, '首领饵不存在 ' .. tostring(chain.BossBait)) end
        if not items[chain.BossToken] then fail(source, '首领信物不存在 ' .. tostring(chain.BossToken)) end
        if chain.Result ~= 'achievement.final' and not items[chain.Result] then fail(source, '兑换物品不存在 ' .. tostring(chain.Result)) end
        if elite and elite.Drops[2] and elite.Drops[2].ItemId ~= chain.EliteToken then fail(source, '精英信物与掉落不匹配') end
        if boss and (boss.Bait ~= chain.BossBait or not boss.Drops[2] or boss.Drops[2].ItemId ~= chain.BossToken) then
            fail(source, '首领饵或首领信物与鱼种不匹配') end
    end
    if #chains ~= 7 then fail('GameSpec.md#8.1', '信物兑换链不是七组') end
    local counts = { zones = #(cfg.Zones or {}), fish = count(fish), items = count(items), shop = #goods,
        lottery = #lottery, blindbox = #blindbox, lotteryWeight = lotteryWeight, blindboxWeight = blindboxWeight }
    for field, expected in pairs({ zones = 7, fish = 98, items = 171, shop = 50, lottery = 7,
        blindbox = 42, lotteryWeight = 100, blindboxWeight = 1000 }) do
        if counts[field] ~= expected then fail('GameSpec.md#19', field .. ' 数量/权重应为 ' .. expected .. '，实际 ' .. counts[field]) end
    end
    table.sort(errors)
    return { errors = errors, counts = counts }
end

return Validate
