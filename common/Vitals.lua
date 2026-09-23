-- 饥饿与掉血节奏（#53，#40 规格），纯函数、不碰引擎对象；配置见 GameCfg.Vitals。
local Vitals = {}

-- 推进 seconds 个整秒：饥饿每秒 −HungerPerSec 直到 0；已经是 0 的那一秒掉 StarveDamagePerSec 血
-- （归零那一秒不掉，下一秒起掉）。一次最多补算 MaxCatchUpSec 秒。返回新饥饿、这次该掉的血
function Vitals.Advance(hunger, seconds, cfg)
    seconds = math.min(math.max(0, math.floor(seconds or 0)), cfg.MaxCatchUpSec or seconds)
    local damage = 0
    for _ = 1, seconds do
        if hunger > 0 then
            hunger = math.max(0, hunger - cfg.HungerPerSec)
        else
            damage = damage + cfg.StarveDamagePerSec
        end
    end
    return hunger, damage
end

-- 吃一件：恢复 floor(max × percent / 100)，不超过上限
function Vitals.Restore(value, max, percent)
    return math.min(max, value + math.floor(max * percent / 100))
end

return Vitals
