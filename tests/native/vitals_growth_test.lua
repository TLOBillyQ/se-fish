-- #89 迁移（原 tests/gameplay/vitals_growth_test.lua，#139 T18 大奖成长切片 4）：
-- MgrVitals 按玩家血量上限 + 行动闸门（麻痹统一封锁）。
-- 失败方式（先列后写）：
--   1. MaxHealth 仍是全局 300：变大后绑定/进食/复活/写属性/GM 设血都被 300 截断（统一规格 §2 上限 900）；
--   2. 上限提升没有刷新口：喝变大药水后控制器上限与 HUD 属性不跟进，当前血可超上限；
--   3. 麻痹没有统一闸门：麻痹中仍能攻击/投掷/钓鱼/进食（统一规格 §6.3「麻痹无法行动」）；
--   4. 无 provider 注入时行为漂移（缺省必须保持全局 300 的旧行为，#53/#131 用例不动）。
-- 接缝：MgrVitals.MaxHealthProvider（main.lua 注入 MgrAbility:MaxHealth）与
--   MgrVitals.ActGuard（注入「非麻痹」）；loadfile 取全新实例，假玩家/假 Controller。
-- 旧 setUp 是逐例的，因此映射为 before_each；实例由 loadfile 新建、不写全局与 package.loaded，
-- 无需 after_each 恢复（与旧套件同口径：旧套件也没有 tearDown）。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
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

describe('TestVitalsGrowth', function()
    local ctx

    before_each(function()
        ctx = { mgr = assert(loadfile('server/Mgr/MgrVitals.lua'))(), now = 1000.2, maxHealth = 300 }
        local state = ctx
        ctx.mgr.Now = function() return state.now end
        ctx.mgr.MaxHealthProvider = function() return state.maxHealth end -- 假 provider（模拟变大药水成长）
        ctx.player = newPlayer(13911)
        ctx.mgr:OnPlayerAdded(ctx.player)
    end)

    local function ctrl() return ctx.player.Character.Controller end

    -- 行动闸门：ActGuard 拒绝时 CanAct/CanEat 全封；闸门抛错 fail-open 并记日志（与生命接缝同策略）
    it('test_act_guard_blocks_actions_when_paralyzed', function()
        local paralyzed = false
        ctx.mgr.ActGuard = function() return not paralyzed end
        assert.is_true(ctx.mgr:CanAct(ctx.player))
        assert.is_true(ctx.mgr:CanEat(ctx.player, 'goldfish'))
        paralyzed = true
        assert.is_false(ctx.mgr:CanAct(ctx.player))
        assert.is_false(ctx.mgr:CanEat(ctx.player, 'goldfish'))
        ctx.mgr.ActGuard = function() error('闸故障') end
        assert.message('闸门故障 fail-open，不把全服锁死').is_true(ctx.mgr:CanAct(ctx.player))
    end)

    -- 绑定即按 provider 上限：控制器 MaxHealth 与初次回满都用 900，HUD 属性同步
    it('test_bind_uses_per_player_max_health', function()
        ctx.maxHealth = 900
        ctx.mgr:OnPlayerRemoving(ctx.player)
        ctx.player = newPlayer(13912)
        ctx.mgr:OnPlayerAdded(ctx.player)
        assert.same(900, ctrl().MaxHealth)
        assert.message('首次绑定回满到玩家上限').same(900, ctrl().Health)
        assert.same(900, ctx.player.attrs.MaxHealth)
    end)

    -- 缺省行为不变：无 provider/无闸门时一切按全局 300
    it('test_default_behavior_without_injections', function()
        local plain = assert(loadfile('server/Mgr/MgrVitals.lua'))()
        plain.Now = function() return ctx.now end
        local p = newPlayer(13913)
        plain:OnPlayerAdded(p)
        assert.same(300, plain:MaxHealthOf(p))
        assert.same(300, p.Character.Controller.MaxHealth)
        assert.is_true(plain:CanAct(p))
        assert.is_false(plain:ApplyRevive(plain:GetState(p), 301, 0))
    end)

    -- 进食按玩家上限恢复：金鱼 30% × 900 = +270（不是 ×300）
    it('test_eat_restores_percent_of_per_player_max', function()
        ctx.maxHealth = 900
        ctx.mgr:RefreshMaxHealth(ctx.player)
        ctrl().Health = 300
        assert.is_true(ctx.mgr:Eat(ctx.player, 'goldfish'))
        assert.same(300 + 270, ctrl().Health)
    end)

    -- 负食用（核废料桶 EatPercent=-99）按玩家上限结算伤害：99% × 900 = 891
    it('test_negative_eat_damage_scales_with_per_player_max', function()
        ctx.maxHealth = 900
        ctx.mgr:RefreshMaxHealth(ctx.player)
        ctrl().Health = 900
        assert.is_true(ctx.mgr:Eat(ctx.player, 'item126'))
        assert.same(900 - 891, ctrl().Health)
    end)

    -- 刷新口：提上限不回血、降上限夹当前血、HUD 属性始终写玩家上限
    it('test_refresh_max_health_clamps_and_writes_attribute', function()
        ctx.mgr:RefreshMaxHealth(ctx.player) -- 300：无变化
        assert.same(300, ctrl().MaxHealth)
        ctx.maxHealth = 900
        local ok, max = ctx.mgr:RefreshMaxHealth(ctx.player)
        assert.is_true(ok)
        assert.same(900, max)
        assert.same(900, ctrl().MaxHealth)
        assert.message('提上限不自动回血').same(300, ctrl().Health)
        assert.same(900, ctx.player.attrs.MaxHealth)
        -- 降上限（理论路径：数据修正）：当前血 800 夹到 300
        ctrl().Health = 800
        ctx.maxHealth = 300
        ctx.mgr:RefreshMaxHealth(ctx.player)
        assert.same(300, ctrl().MaxHealth)
        assert.same(300, ctrl().Health)
        assert.same(300, ctx.player.attrs.MaxHealth)
    end)

    -- 审查边界：控制器写上限抛错时不能继续报告成功；可在下一次刷新重试。
    it('test_refresh_max_health_write_error_is_reported_and_retryable', function()
        local controller = ctrl()
        controller.MaxHealth = nil
        setmetatable(controller, { __newindex = function(_, key) error('拒绝写属性:' .. key) end })
        local ok, err = ctx.mgr:RefreshMaxHealth(ctx.player)
        assert.is_false(ok)
        assert.matches('MaxHealth', tostring(err), nil, true)
        setmetatable(controller, nil)
        assert.is_true(ctx.mgr:RefreshMaxHealth(ctx.player))
    end)

    -- 复活（引擎路径）回满到玩家上限；ApplyRevive 的上界校验也按玩家上限
    it('test_revive_paths_use_per_player_max', function()
        ctx.maxHealth = 900
        ctx.mgr:RefreshMaxHealth(ctx.player)
        local state = ctx.mgr:GetState(ctx.player)
        state.dead = true
        state.deadAt = ctx.now
        ctx.mgr:Revive(state, 'poll')
        assert.same(900, ctrl().Health)
        -- ApplyRevive：900 以内合法、超 900 拒绝
        assert.is_true(ctx.mgr:ApplyRevive(state, 90, 30))
        assert.is_false(ctx.mgr:ApplyRevive(state, 901, 0))
        -- provider 回落 300 后，901/301 都拒绝
        ctx.maxHealth = 300
        assert.is_false(ctx.mgr:ApplyRevive(state, 301, 0))
    end)

    -- GM 设血的上界按玩家上限
    it('test_set_health_bound_is_per_player', function()
        ctx.maxHealth = 900
        ctx.mgr:RefreshMaxHealth(ctx.player)
        assert.is_true(ctx.mgr:SetHealth(ctx.player, 900))
        assert.is_false(ctx.mgr:SetHealth(ctx.player, 901))
    end)
end)
