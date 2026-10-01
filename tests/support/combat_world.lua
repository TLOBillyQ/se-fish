-- 战斗岛（#141 树林岛 / #142 沙滩岛）探针与验收步骤共用的假引擎战斗世界。
-- 复用 fish_escape 测试夹具：真实 MgrFishUnit + 假载体 / Vitals / RE；双人各 5000 血，
-- 预警 payload 记入 env.notices，结算伤害记入 env.hits。在仓库根运行（require 路径以根为准）。
require('tests.gameplay.fish_escape_test')

local M = {}

function M.new()
    local env = setmetatable({}, { __index = TestFishEscape })
    TestFishEscape.setUp(env)
    TestFishEscape.prepare(env)
    env.hits, env.notices = {}, {}
    for _, p in ipairs({ env.player, env.other }) do
        p.Character.Controller.Health = 5000
        p.Character.Controller.TakeDamage = function(c, d) c.Health = c.Health - d end
    end
    -- 第二名玩家默认远离战斗点，避免落点范围 / 翻滚 / 突击判定的无关命中（需要贴身时由调用方显式摆位）
    env.other.Character.Position = Vector3.New(500, 2, 500)
    env.mgr.PublishBite = function(_, payload) env.notices[#env.notices + 1] = payload end
    env.mgr.CombatPublisher = function() end
    env.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, _, player, amount)
            env.hits[#env.hits + 1] = { player = player, amount = amount }
            return true, amount
        end,
        CanTakeDamage = function() return true end,
    }
    return env
end

-- 恢复 pinRandom 替换的全局随机并拆除夹具
function M.close(env)
    if env.savedRandom then math.random = env.savedRandom end
    TestFishEscape.tearDown(env)
end

-- 推进到服务器时刻 now 并跑一帧
function M.at(env, now) env.now = now env.mgr:Update() end

-- 固定随机方向：高跃 / 鲸跃落点朝 +x（表现细化，只钉距离与范围）；close 时恢复
function M.pinRandom(env)
    env.savedRandom = math.random
    math.random = function() return 0 end
end

-- 放下一条战斗鱼并把目标玩家摆到鱼身 (0, dz) 处
function M.drop(env, fishId, dz)
    local p = env.player.Character.Position
    local fish = env.mgr:SpawnLanded(env.player, { fishId = fishId, mult = 1 }, Vector3.New(p.x, 2, p.z + 2))
    fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
    env.mgr:Drop(env.player)
    local bp = fish.Carrier.Body.Position
    env.player.Character.Position = Vector3.New(bp.x, 2, bp.z + (dz or 2))
    return fish
end

return M
