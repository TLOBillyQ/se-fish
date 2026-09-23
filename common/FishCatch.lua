local FishCatch = {}

function FishCatch.Select(rows, rodLevel, baitId, random)
    local available, total = {}, 0
    for _, row in ipairs(rows or {}) do
        if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then
            total = total + row.DrawWeight
            available[#available + 1] = row
        end
    end
    if total == 0 then return nil end
    local roll = random(total)
    for _, row in ipairs(available) do
        roll = roll - row.DrawWeight
        if roll <= 0 then return row.Id end
    end
end

function FishCatch.Multiplier(random)
    return random(100, 200) / 100
end

-- 倍率按百分点取整后再乘，避免 0.1 × 1.15 这类浮点误差把 0.115 舍成 0.11
local function percent(mult)
    return math.floor(mult * 100 + 0.5)
end

-- 个体重量（kg，保留两位小数）= 基础重量 × 倍率
function FishCatch.Weight(species, mult)
    return math.floor(species.BaseWeight * percent(mult) + 0.5 + 1e-9) / 100
end

-- 出售价（整数金币，向下取整）= floor(基础出售价 × 倍率)，倍率缺省 1（#27 / #44）
function FishCatch.Price(species, mult)
    return math.floor(species.BasePrice * percent(mult or 1) / 100 + 1e-9)
end

return FishCatch
