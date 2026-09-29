-- 水判定（M0-V1 转正）。语义来源：原型分支 prototype/water-judgment 的 server/ProtoWater.lua
-- 里的 MakeMathJudge（issue #12 结案结论），这里把它补成正式模块 + 配置校验。
--
-- 为什么是纯数学：本图的水是 WaterCircle1/2 两个水材质渲染 WorldUnit，
-- CanQuery=true 但没有命中几何——水中心的垂直射线先撞 TGUnitFish 触发器（顶面 y≈6.77），
-- 排掉触发器后撞的是大地板（y=2.0），全程碰不到水圈。300 次调用实测：
-- 数学 0.12ms / 射线 6.21ms / 球形重叠 2.73ms（#12 W-3），30Hz 逻辑帧下数学判定可忽略。
--
-- 现有水区沿用 HalfXZ 正方形；#125 待建长方形使用 HalfX/HalfZ（两者都必须提供）。
-- 水平边与水面高度均含等号；坐标与尺寸必须有限，Id 不得重复。
--   abs(pos.x - center.x) <= halfX and abs(pos.z - center.z) <= halfZ and pos.y <= surfaceY
--
-- 只读 pos 的 x/y/z，不调用任何引擎 API：Vector3 与普通 table 都能直接传，
-- 所以这组纯函数能在宿主机 lua 单测里跑（tests/gameplay/water_judge_test.lua）。
--
-- 配置见 GameCfg.Water.Zones。HalfXZ 直接写运行时该水区的半边尺寸：运行时读到的 Size 已含
-- Scale，配置时再乘缩放会翻倍（#12 W-4）。取值与溯源见 issue #25 的 M0 模块线台账（评论 9862）。

local MathWaterJudge = {}

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

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
    if zone.HalfX ~= nil or zone.HalfZ ~= nil then
        if type(zone.HalfX) ~= "number" or zone.HalfX <= 0
            or type(zone.HalfZ) ~= "number" or zone.HalfZ <= 0 then
            error(where .. "（" .. zone.Id .. "）的 HalfX/HalfZ 必须同时为正数")
        end
    elseif type(zone.HalfXZ) ~= "number" or zone.HalfXZ <= 0 then
        error(where .. "（" .. zone.Id .. "）的 HalfXZ 必须是正数")
    end
    if type(zone.SurfaceY) ~= "number" then
        error(where .. "（" .. zone.Id .. "）的 SurfaceY 必须是数字")
    end
    if not finite(center.x) or not finite(center.z) or not finite(zone.SurfaceY)
        or not finite(zone.HalfX or zone.HalfXZ) or not finite(zone.HalfZ or zone.HalfXZ) then
        error(where .. '（' .. zone.Id .. '）的坐标与尺寸必须是有限数字')
    end
end

-- 单个水区的判定：原型 MakeMathJudge 的语义。
function MathWaterJudge.InZone(zone, pos)
    local center = zone.Center
    return math.abs(pos.x - center.x) <= (zone.HalfX or zone.HalfXZ)
        and math.abs(pos.z - center.z) <= (zone.HalfZ or zone.HalfXZ)
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
    local ids = {}
    for i = 1, #zones do
        checkZone(i, zones[i])
        if ids[zones[i].Id] then error('MathWaterJudge.Build: 重复水域 ' .. zones[i].Id) end
        ids[zones[i].Id] = true
    end

    return function(pos)
        return MathWaterJudge.HitZone(zones, pos)
    end
end

-- 输入为只读现场快照：每项含 Name、Position={x,y,z}，不在模块内获取 Service。
-- EntitiesMatch 只说明实体名/坐标匹配；保存、sync、碰撞和试玩始终单列未验证，不提供总就绪值。
function MathWaterJudge.InspectScene(zones, snapshot)
    local byName = {}
    for _, entity in ipairs(snapshot) do
        local matches = byName[entity.Name] or {}
        matches[#matches + 1] = entity
        byName[entity.Name] = matches
    end
    local report = { EntitiesMatch = true, Issues = {}, PendingZones = {}, Verification = {
        Saved = 'unverified', Synced = 'unverified', Collision = 'unverified', Playtested = 'unverified',
    } }
    for _, zone in ipairs(zones) do
        local scene = zone.Scene
        if not scene or scene.State ~= 'verified' then
            report.PendingZones[#report.PendingZones + 1] = zone.Id
        end
        for _, expected in ipairs(scene and scene.Entities or {}) do
            local matches = byName[expected.Name] or {}
            local code
            if #matches == 0 then code = 'missing'
            elseif #matches > 1 then code = 'duplicate'
            elseif expected.Position then
                local actual = matches[1].Position
                for _, axis in ipairs({ 'x', 'y', 'z' }) do
                    if not actual or not finite(actual[axis]) or not finite(expected.Position[axis])
                        or math.abs(actual[axis] - expected.Position[axis]) > 0.1 then
                        code = 'position'
                    end
                end
            end
            if code then
                report.Issues[#report.Issues + 1] = {
                    ZoneId = zone.Id, ZoneName = zone.Name, Name = expected.Name, Code = code,
                }
            end
        end
    end
    report.EntitiesMatch = #report.Issues == 0
    return report
end

return MathWaterJudge
