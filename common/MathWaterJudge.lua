-- 水判定（M0-V1 转正）。语义来源：原型分支 prototype/water-judgment 的 server/ProtoWater.lua
-- 里的 MakeMathJudge（issue #12 结案结论），这里把它补成正式模块 + 配置校验。
--
-- 为什么是纯数学：本图的水是 WaterCircle1/2 两个水材质渲染 WorldUnit，
-- CanQuery=true 但没有命中几何——水中心的垂直射线先撞 TGUnitFish 触发器（顶面 y≈6.77），
-- 排掉触发器后撞的是大地板（y=2.0），全程碰不到水圈。300 次调用实测：
-- 数学 0.12ms / 射线 6.21ms / 球形重叠 2.73ms（#12 W-3），30Hz 逻辑帧下数学判定可忽略。
--
-- 判定语义（逐字沿用原型）：
--   abs(pos.x - center.x) <= halfXZ and abs(pos.z - center.z) <= halfXZ and pos.y <= surfaceY
-- 三处都含等号：正好贴在半宽线上、正好落在水面高度上都算「在水里」。
--
-- 只读 pos 的 x/y/z，不调用任何引擎 API：Vector3 与普通 table 都能直接传，
-- 所以这组纯函数能在宿主机 lua 单测里跑（tests/gameplay/water_judge_test.lua）。
--
-- 配置见 GameCfg.Water.Zones。HalfXZ 直接写运行时该水区的半边尺寸：运行时读到的 Size 已含
-- Scale，配置时再乘缩放会翻倍（#12 W-4）。取值与溯源见 issue #25 的 M0 模块线台账（评论 9862）。

local MathWaterJudge = {}

-- 中心只用到 x/z（y 留作场景溯源），HalfXZ / SurfaceY 都是米。
local function checkZone(index, zone)
    local where = "MathWaterJudge.Build: 第 " .. index .. " 个水区"

    if type(zone) ~= "table" then
        error(where .. "不是 table")
    end
    if type(zone.Id) ~= "string" or zone.Id == "" then
        error(where .. "缺 Id（判定结果要能溯源到是哪个水区）")
    end

    local center = zone.Center
    if type(center) ~= "table" or type(center.x) ~= "number" or type(center.z) ~= "number" then
        error(where .. "（" .. zone.Id .. "）的 Center 必须是含数字 x/z 的 table")
    end
    if type(zone.HalfXZ) ~= "number" or zone.HalfXZ <= 0 then
        error(where .. "（" .. zone.Id .. "）的 HalfXZ 必须是正数")
    end
    if type(zone.SurfaceY) ~= "number" then
        error(where .. "（" .. zone.Id .. "）的 SurfaceY 必须是数字")
    end
end

-- 单个水区的判定：原型 MakeMathJudge 的语义。
function MathWaterJudge.InZone(zone, pos)
    local center = zone.Center
    return math.abs(pos.x - center.x) <= zone.HalfXZ
        and math.abs(pos.z - center.z) <= zone.HalfXZ
        and pos.y <= zone.SurfaceY
end

-- 多区查询：按配置顺序返回第一个命中的水区（同心水圈时命中排在前面的那个）。
function MathWaterJudge.HitZone(zones, pos)
    for i = 1, #zones do
        if MathWaterJudge.InZone(zones[i], pos) then
            return zones[i]
        end
    end
    return nil
end

-- 装配期建判定器：配置配错在这里一次性报出来，不静默退化成「永远不在水里」。
-- 返回 function(pos) -> zone|nil，命中给水区表（zone.Id 用于日志与按水区选鱼表）。
function MathWaterJudge.Build(zones)
    if type(zones) ~= "table" or #zones == 0 then
        error("MathWaterJudge.Build: 水区配置为空")
    end
    for i = 1, #zones do
        checkZone(i, zones[i])
    end

    return function(pos)
        return MathWaterJudge.HitZone(zones, pos)
    end
end

return MathWaterJudge
