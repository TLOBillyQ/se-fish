local FishCatch = {}

function FishCatch.Select(rows, rodLevel, baitId, random)
    local available, total = {}, 0
    for _, row in ipairs(rows or {}) do
        if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then
            total = total + row.Weight
            available[#available + 1] = row
        end
    end
    if total == 0 then return nil end
    local roll = random(total)
    for _, row in ipairs(available) do
        roll = roll - row.Weight
        if roll <= 0 then return row.Id end
    end
end

function FishCatch.Multiplier(random)
    return random(100, 200) / 100
end

return FishCatch
