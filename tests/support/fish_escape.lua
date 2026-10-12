-- 逃脱共享夹具：仅提供环境方法，不注册测试案例。
local FishLift = require('tests.support.fish_lift')
local M = {}
for name, method in pairs(FishLift) do M[name] = method end

function M:prepare()
    local env = self
    self.rays = {}
    self.hits = {}
    _G.RaycastParams = { New = function() return { FilterDescendantsInstances = {} } end }
    self.physics = { Raycast = function(_, origin, direction, params)
        env.rays[#env.rays + 1] = { now = env.now, origin = origin, direction = direction, params = params }
        local excluded = {}
        for _, unit in ipairs(params and params.FilterDescendantsInstances or {}) do excluded[unit] = true end
        for _, hit in ipairs(env.hits) do
            if not excluded[hit.Instance] then return hit end
        end
    end }
    local get = _G.game.GetService
    _G.game = { GetService = function(s, name)
        if name == 'PhysicsService' then return env.physics end
        return get(s, name)
    end }
end

function M:heldFish(player, fishId, mult)
    player = player or self.player
    local fish = self:land(player, fishId, mult)
    fish.Carrier.Body.OnLiftedBegin:Fire(player.Character)
    fish.Carrier.Body.BodyType = 2
    return fish
end

return M
