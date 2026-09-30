-- #139 T18 大奖成长切片 4：MgrVitals 按玩家血量上限 + 行动闸门（麻痹统一封锁）。
-- 失败方式（先列后写）：
--   1. MaxHealth 仍是全局 300：变大后绑定/进食/复活/写属性/GM 设血都被 300 截断（统一规格 §2 上限 900）；
--   2. 上限提升没有刷新口：喝变大药水后控制器上限与 HUD 属性不跟进，当前血可超上限；
--   3. 麻痹没有统一闸门：麻痹中仍能攻击/投掷/钓鱼/进食（统一规格 §6.3「麻痹无法行动」）；
--   4. 无 provider 注入时行为漂移（缺省必须保持全局 300 的旧行为，#53/#131 用例不动）。
-- 接缝：MgrVitals.MaxHealthProvider（main.lua 注入 MgrAbility:MaxHealth）与
--   MgrVitals.ActGuard（注入「非麻痹」）；loadfile 取全新实例，假玩家/假 Controller。
local lu = require('luaunit')

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        local handlers = self.handlers
        handlers[#handlers + 1] = fn
        return { Disconnect = function()
            for i, h in ipairs(handlers) do if h == fn then table.remove(handlers, i) return end end
        end }
    end
    function s:Fire(...) for _, h in ipairs({ table.unpack(self.handlers) }) do h(...) end end
    return s
end

local function newController()
    local c = { Health = 100, MaxHealth = 100, HealthChanged = signal(), Died = signal(), OnReborn = signal() }
    function c:TakeDamage(amount)
        self.Health = math.max(0, self.Health - amount)
        self.HealthChanged:Fire(self.Health)
        if self.Health <= 0 then self.Died:Fire() end
    end
    return c
end

local function newPlayer(id)
    local p = { UserId = id, attrs = {}, CharacterAdded = signal() }
    p.Character = { Controller = newController() }
    function p:SetAttribute(k, v) self.attrs[k] = v end
    return p
end

TestVitalsGrowth = {}

function TestVitalsGrowth:setUp()
    self.mgr = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    local env = self
    self.now = 1000.2
    self.mgr.Now = function() return env.now end
    self.maxHealth = 300 -- 假 provider 读这个值（模拟变大药水成长）
    self.mgr.MaxHealthProvider = function() return env.maxHealth end
    self.player = newPlayer(13911)
    self.mgr:OnPlayerAdded(self.player)
end

function TestVitalsGrowth:ctrl()
    return self.player.Character.Controller
end

-- 绑定即按 provider 上限：控制器 MaxHealth 与初次回满都用 900，HUD 属性同步
function TestVitalsGrowth:test_bind_uses_per_player_max_health()
    self.maxHealth = 900
    self.mgr:OnPlayerRemoving(self.player)
    self.player = newPlayer(13912)
    self.mgr:OnPlayerAdded(self.player)
    lu.assertEquals(self:ctrl().MaxHealth, 900)
    lu.assertEquals(self:ctrl().Health, 900, '首次绑定回满到玩家上限')
    lu.assertEquals(self.player.attrs.MaxHealth, 900)
end

-- 进食按玩家上限恢复：金鱼 30% × 900 = +270（不是 ×300）
function TestVitalsGrowth:test_eat_restores_percent_of_per_player_max()
    self.maxHealth = 900
    self.mgr:RefreshMaxHealth(self.player)
    self:ctrl().Health = 300
    lu.assertTrue(self.mgr:Eat(self.player, 'goldfish'))
    lu.assertEquals(self:ctrl().Health, 300 + 270)
end

-- 负食用（核废料桶 EatPercent=-99）按玩家上限结算伤害：99% × 900 = 891
function TestVitalsGrowth:test_negative_eat_damage_scales_with_per_player_max()
    self.maxHealth = 900
    self.mgr:RefreshMaxHealth(self.player)
    self:ctrl().Health = 900
    lu.assertTrue(self.mgr:Eat(self.player, 'item126'))
    lu.assertEquals(self:ctrl().Health, 900 - 891)
end

-- 复活（引擎路径）回满到玩家上限；ApplyRevive 的上界校验也按玩家上限
function TestVitalsGrowth:test_revive_paths_use_per_player_max()
    self.maxHealth = 900
    self.mgr:RefreshMaxHealth(self.player)
    local state = self.mgr:GetState(self.player)
    state.dead = true
    state.deadAt = self.now
    self.mgr:Revive(state, 'poll')
    lu.assertEquals(self:ctrl().Health, 900)
    -- ApplyRevive：900 以内合法、超 900 拒绝
    lu.assertTrue(self.mgr:ApplyRevive(state, 90, 30))
    lu.assertFalse(self.mgr:ApplyRevive(state, 901, 0))
    -- provider 回落 300 后，901/301 都拒绝
    self.maxHealth = 300
    lu.assertFalse(self.mgr:ApplyRevive(state, 301, 0))
end

-- GM 设血的上界按玩家上限
function TestVitalsGrowth:test_set_health_bound_is_per_player()
    self.maxHealth = 900
    self.mgr:RefreshMaxHealth(self.player)
    lu.assertTrue(self.mgr:SetHealth(self.player, 900))
    lu.assertFalse(self.mgr:SetHealth(self.player, 901))
end

-- 刷新口：提上限不回血、降上限夹当前血、HUD 属性始终写玩家上限
function TestVitalsGrowth:test_refresh_max_health_clamps_and_writes_attribute()
    self.mgr:RefreshMaxHealth(self.player) -- 300：无变化
    lu.assertEquals(self:ctrl().MaxHealth, 300)
    self.maxHealth = 900
    local ok, max = self.mgr:RefreshMaxHealth(self.player)
    lu.assertTrue(ok)
    lu.assertEquals(max, 900)
    lu.assertEquals(self:ctrl().MaxHealth, 900)
    lu.assertEquals(self:ctrl().Health, 300, '提上限不自动回血')
    lu.assertEquals(self.player.attrs.MaxHealth, 900)
    -- 降上限（理论路径：数据修正）：当前血 800 夹到 300
    self:ctrl().Health = 800
    self.maxHealth = 300
    self.mgr:RefreshMaxHealth(self.player)
    lu.assertEquals(self:ctrl().MaxHealth, 300)
    lu.assertEquals(self:ctrl().Health, 300)
    lu.assertEquals(self.player.attrs.MaxHealth, 300)
end

-- 行动闸门：ActGuard 拒绝时 CanAct/CanEat 全封；闸门抛错 fail-open 并记日志（与生命接缝同策略）
function TestVitalsGrowth:test_act_guard_blocks_actions_when_paralyzed()
    local paralyzed = false
    self.mgr.ActGuard = function() return not paralyzed end
    lu.assertTrue(self.mgr:CanAct(self.player))
    lu.assertTrue(self.mgr:CanEat(self.player, 'goldfish'))
    paralyzed = true
    lu.assertFalse(self.mgr:CanAct(self.player))
    lu.assertFalse(self.mgr:CanEat(self.player, 'goldfish'))
    self.mgr.ActGuard = function() error('闸故障') end
    lu.assertTrue(self.mgr:CanAct(self.player), '闸门故障 fail-open，不把全服锁死')
end

-- 缺省行为不变：无 provider/无闸门时一切按全局 300
function TestVitalsGrowth:test_default_behavior_without_injections()
    local plain = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    local env = self
    plain.Now = function() return env.now end
    local p = newPlayer(13913)
    plain:OnPlayerAdded(p)
    lu.assertEquals(plain:MaxHealthOf(p), 300)
    lu.assertEquals(p.Character.Controller.MaxHealth, 300)
    lu.assertTrue(plain:CanAct(p))
    lu.assertFalse(plain:ApplyRevive(plain:GetState(p), 301, 0))
end

-- 审查边界：控制器写上限抛错时不能继续报告成功；可在下一次刷新重试。
function TestVitalsGrowth:test_refresh_max_health_write_error_is_reported_and_retryable()
    local controller = self:ctrl()
    controller.MaxHealth = nil
    setmetatable(controller, { __newindex = function(_, key) error('拒绝写属性:' .. key) end })
    local ok, err = self.mgr:RefreshMaxHealth(self.player)
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), 'MaxHealth')
    setmetatable(controller, nil)
    lu.assertTrue(self.mgr:RefreshMaxHealth(self.player))
end
