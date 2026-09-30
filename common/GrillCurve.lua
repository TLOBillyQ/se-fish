-- 烧烤倍率曲线（#137 T16，策划案烧烤段）：纯函数，只由「投入时长」一次算出倍率，
-- 不按帧累加——客户端快慢帧不改变收益（服务端以 World:GetServerTime() 之差为投入时长）。
-- 0-RiseSec 秒线性 1→MaxRate，保持 HoldSec 秒，随后 FallSec 秒线性 MaxRate→0；
-- 投入时长达到 BurnSec 即烤糊（物品损毁，见 MgrGrill），IsBurnt 与 Rate 共用同一份配置。
local GrillCurve = {}

-- 取出倍率：elapsed 为投入秒数；非法输入返回 nil，烤糊（elapsed >= BurnSec）恒 0
function GrillCurve.Rate(elapsed, cfg)
    if type(elapsed) ~= 'number' or elapsed ~= elapsed or elapsed >= math.huge then return nil end
    if elapsed < 0 then elapsed = 0 end
    if elapsed >= cfg.BurnSec then return 0 end
    if elapsed < cfg.RiseSec then
        return 1 + (cfg.MaxRate - 1) * (elapsed / cfg.RiseSec)
    end
    if elapsed < cfg.RiseSec + cfg.HoldSec then return cfg.MaxRate end
    local falling = (elapsed - cfg.RiseSec - cfg.HoldSec) / cfg.FallSec
    return cfg.MaxRate * (1 - falling)
end

-- 是否烤糊：投入时长到达 BurnSec 即糊（边界含 4.5 秒整，验收：4.5 秒取出结果是烤糊）
function GrillCurve.IsBurnt(elapsed, cfg)
    return type(elapsed) == 'number' and elapsed >= cfg.BurnSec
end

-- 界面显示（策划案：两位小数）
function GrillCurve.Format(rate)
    return string.format('%.2f', rate)
end

return GrillCurve
