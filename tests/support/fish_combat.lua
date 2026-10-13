-- 战斗测试共享环境，不加载或注册任何测试类。
-- 复用 fish_escape 的方式：以它为 __index 原型（同族统一手法），不再逐方法拷贝。
local FishEscape = require('tests.support.fish_escape')
local M = setmetatable({}, { __index = FishEscape })

--- 建一个空世界壳；调用方随后 :setUp() 搭世界、:tearDown() 拆除
--- （与 blindbox_world / revive_world 同一构造/拆除入口名）。
function M.new()
    return setmetatable({}, { __index = M })
end

function M:setUp()
    self.savedQuaternion = rawget(_G, 'Quaternion')
    self.savedCombatRandom = math.random
    FishEscape.setUp(self)
    self.vitalsCalls = {}
    self.downed = {}
    self.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, hit, player, amount)
            self.vitalsCalls[#self.vitalsCalls + 1] = { hit, player, amount }
            player.Character.Controller:TakeDamage(amount)
            return true, amount
        end,
        CanTakeDamage = function(_, player)
            return not self.downed[player] and (player.Character.Controller.Health or 0) > 0
        end,
    }
    self.notices = {}
    local env = self
    self.mgr.PublishBite = function(_, payload) env.notices[#env.notices + 1] = payload end
end

function M:tearDown()
    if self.savedCombatRandom then math.random = self.savedCombatRandom end
    _G.Quaternion = self.savedQuaternion
    FishEscape.tearDown(self)
end

return M
