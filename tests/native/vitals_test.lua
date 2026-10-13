-- #89 迁移（原 tests/gameplay/vitals_test.lua，#53 饥饿、掉血、死亡与复活 + #118 受伤跳字）：
-- common/Vitals.lua 纯函数 + server/Mgr/MgrVitals.lua（假玩家 / 假 Controller）。
-- 失败方式（先列后写）：
--   1. 饥饿按帧推进（同一秒内多次 Update 多扣），或跨多秒只扣一次；服务端卡顿后一次性补扣到暴毙；
--   2. 饥饿扣到负数；饥饿还没归零就开始掉血，或归零那一秒同时掉血（设计：归零后下一秒起每秒 −5）；
--   3. 掉血绕过 ApplyDamage 单点（直接改 Health）；ApplyDamage 接受非正数 / 死亡期间还在扣；
--   4. 死亡期间饥饿继续推进或继续掉血；Died 与轮询两条路重复记死亡；
--   5. 复活挂在 CharacterAdded 上（引擎复活不换角色、不触发它）；复活后血量或饥饿没回满 300；
--      引擎没按时复活时没有兜底，玩家永远躺着；兜底重复调用 Reborn；
--   6. 吃的恢复量不是「食用恢复百分比 × 300」、超过上限、没有恢复百分比的物品也能吃、死亡期间能吃；
--   7. 属性不写或写错：Health / MaxHealth / Hunger / MaxHunger 由服务端写，饥饿只在整秒变化时写；
--   8. GM 设置越界值（负数、超上限、小数）也生效；把血量设低时不走 ApplyDamage；调试开关关着也能设；
--   9. 两名玩家的饥饿 / 血量互相影响；玩家离开后状态与信号连接残留；
--  10. 吃鱼获：选中格不是鱼获（鱼竿）也能吃；吃掉后格子没清空、选中没取消。
-- 旧套件按类分 4 组：TestVitals / TestDamageNotice 只有逐例 setUp（loadfile 取全新实例，不写全局），
-- TestVitalsGM 与 TestEatSlot 还会换 GameCfg.Debug / _G.game，因此各自成对 before_each/after_each，
-- after_each 对未完成的 before_each 幂等。describe/it 名沿用旧类名与方法名，顺序沿用旧执行序。
local GameCfg = require('common.GameCfg')

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        local handlers = self.handlers
        handlers[#handlers + 1] = fn
        return { Disconnect = function()
            for i, h in ipairs(handlers) do if h == fn then table.remove(handlers, i) return end end
        end }
    end
    function s:Fire(...)
        for _, h in ipairs({ table.unpack(self.handlers) }) do h(...) end
    end
    return s
end

local function newController()
    local c = { Health = 100, MaxHealth = 100, HealthChanged = signal(), Died = signal(), OnReborn = signal(),
        damages = {}, reborns = 0 }
    function c:TakeDamage(amount)
        self.damages[#self.damages + 1] = amount
        self.Health = math.max(0, self.Health - amount)
        self.HealthChanged:Fire(self.Health)
        if self.Health <= 0 then self.Died:Fire() end
    end
    function c:Reborn() self.reborns = self.reborns + 1 end
    return c
end

local function newPlayer(id)
    local p = { UserId = id, Name = 'p' .. id, attrs = {}, writes = {}, CharacterAdded = signal() }
    p.Character = { Controller = newController() }
    function p:SetAttribute(k, v)
        self.attrs[k] = v
        self.writes[k] = (self.writes[k] or 0) + 1
    end
    return p
end

local function newCharacter(x, y, z)
    return { Controller = newController(), Position = { x = x, y = y, z = z }, Size = { y = 2 } }
end

local function newDamagePlayer(id, x, y, z)
    local p = { UserId = id, Name = 'p' .. id, attrs = {}, writes = {}, CharacterAdded = signal() }
    p.Character = newCharacter(x, y, z)
    function p:SetAttribute(k, v)
        self.attrs[k] = v
        self.writes[k] = (self.writes[k] or 0) + 1
    end
    return p
end

-- #118 玩家受伤跳字通知：HealthChanged / Died 双路观察基线差额，只在正扣血时各发一条。
-- 失败方式：只在 ApplyDamage 接入漏掉直接 Controller 扣血；致命一击只发 Died 漏报；
-- 两路重复上报；初始化 / 绑定 / 复活 / 治疗误报；目标位置读取失败时用失效对象。
describe('TestDamageNotice', function()
    local ctx

    before_each(function()
        ctx = { mgr = assert(loadfile('server/Mgr/MgrVitals.lua'))(), notices = {} }
        ctx.mgr.Now = function() return 100 end
        local notices = ctx.notices
        ctx.mgr.DamagePublisher = function(payload) notices[#notices + 1] = payload end
        ctx.a = newDamagePlayer(1, 3, 4, 5)
        ctx.mgr:OnPlayerAdded(ctx.a)
    end)

    local function ctrlDirect(damage)
        local c = ctx.a.Character.Controller
        if damage then
            c.Health = math.max(0, c.Health - damage)
            c.HealthChanged:Fire(c.Health)
        end
        return c
    end

    -- ApplyDamage 与直接走 Controller 两条路各报一次
    it('test_apply_damage_and_direct_controller_paths_both_report_once', function()
        ctx.mgr:ApplyDamage(ctx.a, 2.7)
        ctrlDirect(2.4) -- 电鳗 / 首领直接走 Controller
        assert.same(2, #ctx.notices)
        assert.near(2.7, ctx.notices[1].amount, 0.00001)
        assert.near(2.4, ctx.notices[2].amount, 0.00001)
        assert.same('player', ctx.notices[1].targetType)
        assert.same(1, ctx.notices[1].targetId)
        assert.same({ x = 3, y = 4, z = 5 }, ctx.notices[1].position)
        assert.same(2, ctx.notices[1].height)
    end)

    -- 绑定与治疗方向不报
    it('test_binding_and_healing_never_report', function()
        assert.same({}, ctx.notices) -- 绑定回满 300 不报
        ctx.mgr:SetHealth(ctx.a, 200)
        assert.same(1, #ctx.notices)
        ctx.mgr:SetHealth(ctx.a, 300) -- 调高不报
        assert.same(1, #ctx.notices)
        ctx.mgr:Eat(ctx.a, 'goldfish') -- 已在满血，治疗方向不报
        assert.same(1, #ctx.notices)
    end)

    -- 时序一：只发 Died 的致命一击也只报一次
    it('test_lethal_hit_reported_once_when_only_died_fires', function()
        ctx.mgr:SetHealth(ctx.a, 4)
        while #ctx.notices > 0 do table.remove(ctx.notices) end
        local c = ctrlDirect()
        c.Health = 0
        c.Died:Fire() -- 引擎致死不一定发 HealthChanged
        c.HealthChanged:Fire(0) -- 即使补发也不重复
        assert.same(1, #ctx.notices)
        assert.same(4, ctx.notices[1].amount)
        assert.is_true(ctx.mgr:IsDead(ctx.a))
    end)

    -- 时序二：HealthChanged 先到、Died 随后，同样只报一次
    it('test_lethal_hit_reported_once_when_health_changed_comes_first', function()
        ctx.mgr:SetHealth(ctx.a, 4)
        while #ctx.notices > 0 do table.remove(ctx.notices) end
        local c = ctrlDirect()
        c.Health = 0
        c.HealthChanged:Fire(0)
        c.Died:Fire()
        assert.same(1, #ctx.notices)
        assert.same(4, ctx.notices[1].amount)
        assert.is_true(ctx.mgr:IsDead(ctx.a))
    end)

    -- 过量伤害只报剩余血量
    it('test_overkill_reports_only_remaining_health', function()
        ctx.mgr:SetHealth(ctx.a, 4)
        while #ctx.notices > 0 do table.remove(ctx.notices) end
        ctrlDirect(10)
        assert.same(1, #ctx.notices)
        assert.same(4, ctx.notices[1].amount)
    end)

    -- 位置读不到时用上一次已知定位；首次就没有定位则不报
    it('test_position_read_failure_uses_last_known_position', function()
        ctx.a.Character.Position = nil
        ctrlDirect(3)
        assert.same(0, #ctx.notices) -- 首次受伤且读不到位置，缺定位不报
        ctx.a.Character.Position = { x = 7, y = 8, z = 9 }
        ctrlDirect(3)
        assert.same(1, #ctx.notices)
        ctx.a.Character.Position = nil
        ctrlDirect(3)
        assert.same(2, #ctx.notices)
        assert.same({ x = 7, y = 8, z = 9 }, ctx.notices[2].position) -- 用上一次的定位
    end)

    -- 复活回满不误报
    it('test_revive_refills_without_notice', function()
        ctx.mgr:SetHealth(ctx.a, 0)
        while #ctx.notices > 0 do table.remove(ctx.notices) end
        ctrlDirect().Health = 100 -- 引擎复活
        ctx.mgr:Update()
        assert.same({}, ctx.notices) -- 复活回满不误报
        assert.is_false(ctx.mgr:IsDead(ctx.a))
    end)

    -- 饥饿掉血每个结算秒各自成一条
    it('test_starving_reports_each_settled_tick', function()
        ctx.mgr:SetHunger(ctx.a, 0)
        while #ctx.notices > 0 do table.remove(ctx.notices) end
        local now = 100
        ctx.mgr.Now = function() return now end
        now = 101.5
        ctx.mgr:Update() -- 跨一秒：饥饿 0，结算一次 5 点
        assert.same(1, #ctx.notices)
        assert.same(5, ctx.notices[1].amount)
        now = 102.5
        ctx.mgr:Update()
        assert.same(2, #ctx.notices)
        assert.same(5, ctx.notices[2].amount) -- 每秒实际扣血各自成一条
    end)
end)

-- 吃鱼获：PlayerData:EatSlot 只吃选中的有恢复百分比的格
describe('TestEatSlot', function()
    local ctx

    before_each(function()
        ctx = { savedDebug = GameCfg.Debug }
        GameCfg.Debug = { Enabled = true, InitialGrants = ctx.savedDebug.InitialGrants }
        local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
        ctx.data = PlayerData.New({ UserId = 1, SetAttribute = function() end })
        ctx.data:Init()
        GameCfg.Debug = ctx.savedDebug
    end)

    -- before_each 中途失败也要恢复调试开关
    after_each(function()
        if ctx and ctx.savedDebug ~= nil then
            GameCfg.Debug = ctx.savedDebug
        end
    end)

    it('test_eat_slot_only_fish_and_clears_slot', function()
        local d = ctx.data
        assert.same('starterRod', d.Data.Containers.itemBar[1].itemId)
        d:SelectSlot(1)
        assert.is_nil(d:EatSlot(1)) -- 鱼竿不能吃
        assert.is_true(d:AddItem('carp', 1.5))
        d:SelectSlot(2)
        assert.is_nil(d:EatSlot(1)) -- 不是选中格
        assert.same('carp', d:EatSlot(2))
        assert.is_nil(d.Data.Containers.itemBar[2])
        assert.is_nil(d.Data.SelectedSlot)
        assert.is_nil(d:EatSlot(2))
    end)
end)

describe('TestVitals', function()
    local ctx

    before_each(function()
        ctx = { Vitals = assert(loadfile('common/Vitals.lua'))(), mgr = assert(loadfile('server/Mgr/MgrVitals.lua'))(), now = 1000.2 }
        local state = ctx
        ctx.mgr.Now = function() return state.now end
        ctx.a = newPlayer(1)
        ctx.b = newPlayer(2)
        ctx.mgr:OnPlayerAdded(ctx.a)
        ctx.mgr:OnPlayerAdded(ctx.b)
    end)

    local function tick(seconds, step)
        step = step or 0.25
        local target = ctx.now + seconds
        while ctx.now + 1e-9 < target do
            ctx.now = math.min(target, ctx.now + step)
            ctx.mgr:Update(step)
        end
    end

    local function ctrl(p) return (p or ctx.a).Character.Controller end

    -- 核废料桶：只检查选中格、移入背包不伤、转移后仍伤旧持有人、濒死绕过锁血（#38）。
    -- 接缝：真实 PlayerData 库存与 MgrVitals.Update / Controller。
    it('test_confirmed_held_damage_continues_while_inventory_is_saving', function()
        local PD = assert(loadfile('server/Data/PlayerData.lua'))()
        local data = PD.New(ctx.a, function() end)
        data:Init()
        ctx.mgr.PlayerData = { GetDataInst = function() if data.Inited then return data end end }
        data.Data.Containers.backpack[1] = { itemId = 'item126', count = 1 }
        tick(1)
        data.Inited = false
        tick(2)
        assert.same(297, ctrl().Health)
        data.Inited = true
        data.Data.Containers.backpack[1] = nil
        tick(1)
        assert.same(297, ctrl().Health)
    end)

    -- 数值集中在 GameCfg.Vitals，且与策划案一致
    it('test_config_is_centralized_and_matches_design', function()
        local v = GameCfg.Vitals
        assert.same(300, v.MaxHealth)
        assert.same(300, v.MaxHunger)
        assert.same(1, v.HungerPerSec)
        assert.same(5, v.StarveDamagePerSec)
        assert.same(5, v.ReviveDelaySec)
        assert.same('我要饿死了！', v.WarnText)
        local defs = GameCfg.Items.Definitions
        local expected = { worm = 5, tilapia = 15, carp = 20, knifeFish = 20, bass = 25, catfish = 25, goldfish = 30 }
        for id, pct in pairs(expected) do assert.message(id).same(pct, defs[id].EatPercent) end
        assert.is_nil(defs.starterRod.EatPercent)
    end)

    -- 死亡冻结生命数值；复活不靠 CharacterAdded 也能重置
    it('test_death_freezes_vitals_and_revive_resets_without_character_added', function()
        ctx.mgr:SetHunger(ctx.a, 0)
        ctx.mgr:SetHealth(ctx.a, 5)
        assert.same({ 295 }, ctrl().damages) -- 调低走 ApplyDamage
        tick(1.5)
        assert.same(0, ctrl().Health)
        assert.is_true(ctx.mgr:IsDead(ctx.a))
        local damages = #ctrl().damages
        tick(3)
        assert.same(damages, #ctrl().damages) -- 死亡期间不再掉血
        assert.same(0, ctx.a.attrs.Hunger)
        assert.is_false(ctx.mgr:Eat(ctx.a, 'worm'))
        assert.is_false(ctx.mgr:ApplyDamage(ctx.a, 5))
        -- 引擎复活：同一 Controller 血量回正，不触发 CharacterAdded
        ctrl().Health = 100
        tick(0.25)
        assert.is_false(ctx.mgr:IsDead(ctx.a))
        assert.same(300, ctrl().Health)
        assert.same(300, ctx.a.attrs.Health)
        assert.same(300, ctx.a.attrs.Hunger)
        assert.same(0, ctrl().reborns)
        tick(2)
        assert.same(298, ctx.a.attrs.Hunger) -- 复活后从 300 重新计时
    end)

    -- 引擎死亡信号与轮询只记一次死亡
    it('test_died_signal_and_poll_record_one_death', function()
        local c = ctrl()
        c.Health = 0
        c.Died:Fire()
        local deadAt = ctx.mgr:GetState(ctx.a).deadAt
        tick(1)
        c.Died:Fire()
        assert.same(deadAt, ctx.mgr:GetState(ctx.a).deadAt)
    end)

    -- 进食按上限百分比恢复并夹住
    it('test_eat_restores_percent_of_max_and_clamps', function()
        ctx.mgr:SetHunger(ctx.a, 100)
        ctx.mgr:SetHealth(ctx.a, 100)
        assert.is_true(ctx.mgr:CanEat(ctx.a, 'worm'))
        assert.is_true(ctx.mgr:Eat(ctx.a, 'worm'))
        assert.same(115, ctx.a.attrs.Hunger)
        assert.same(115, ctrl().Health)
        assert.is_true(ctx.mgr:Eat(ctx.a, 'goldfish'))
        assert.same(205, ctx.a.attrs.Hunger)
        ctx.mgr:SetHunger(ctx.a, 290)
        assert.is_true(ctx.mgr:Eat(ctx.a, 'bass'))
        assert.same(300, ctx.a.attrs.Hunger)
        assert.is_false(ctx.mgr:CanEat(ctx.a, 'starterRod'))
        assert.is_false(ctx.mgr:Eat(ctx.a, 'starterRod'))
        assert.is_false(ctx.mgr:Eat(ctx.a, 'nope'))
        assert.same(300, ctx.b.attrs.Hunger)
    end)

    -- 加入即回满并写 HUD 属性
    it('test_join_sets_full_values_and_attributes', function()
        local c = ctrl()
        assert.same(300, c.MaxHealth)
        assert.same(300, c.Health)
        assert.same({ Health = 300, MaxHealth = 300, Hunger = 300, MaxHunger = 300 }, ctx.a.attrs)
    end)

    -- 加入时存档里已有桶：首帧之前就应有已确认持有快照
    it('test_loaded_holder_is_known_before_the_first_update', function()
        local PD = assert(loadfile('server/Data/PlayerData.lua'))()
        local data = PD.New(ctx.a, function() end)
        data:Init()
        data.Data.Containers.itemBar[1] = { itemId = 'item126', count = 1 }
        ctx.mgr.PlayerData = { GetDataInst = function() if data.Inited then return data end end }
        ctx.mgr:OnPlayerRemoving(ctx.a)
        ctx.mgr:OnPlayerAdded(ctx.a)
        data.Inited = false
        tick(1)
        assert.same(299, ctrl().Health)
    end)

    -- 核废料桶伤害跟随当前持有人（道具栏或背包），每秒一次
    it('test_nuclear_bait_damages_current_holder_in_bar_or_backpack_once_per_second', function()
        local PD = assert(loadfile('server/Data/PlayerData.lua'))()
        local a, b = PD.New(ctx.a, function() end), PD.New(ctx.b, function() end)
        a:Init(); b:Init()
        local entries = { [ctx.a] = a, [ctx.b] = b }
        ctx.mgr.PlayerData = { GetDataInst = function(_, p) return entries[p] end }
        ctrl(ctx.a).Health = 300
        ctrl(ctx.b).Health = 300
        a.Data.Containers.backpack[1] = { itemId = 'item126', count = 1 }
        tick(1)
        assert.same(299, ctrl(ctx.a).Health)
        assert.same(300, ctrl(ctx.b).Health)
        a.Data.Containers.backpack[1] = nil
        b.Data.Containers.itemBar[1] = { itemId = 'item126', count = 1 }
        tick(1)
        assert.same(299, ctrl(ctx.a).Health)
        assert.same(299, ctrl(ctx.b).Health)
        ctx.mgr:SetLifeHooks({ LifeStatus = function() return 'downed' end,
            CanTakeDamage = function() return false end })
        tick(2)
        assert.same(299, ctrl(ctx.b).Health)
    end)

    -- 纯函数：整秒推进、归零那一秒不掉血、卡顿补算封顶
    it('test_pure_advance_whole_seconds_then_starve_next_second', function()
        local c = { HungerPerSec = 1, StarveDamagePerSec = 5, MaxCatchUpSec = 5 }
        local hunger, damage = ctx.Vitals.Advance(3, 2, c)
        assert.same({ hunger, damage }, { 1, 0 })
        hunger, damage = ctx.Vitals.Advance(1, 1, c)
        assert.same({ hunger, damage }, { 0, 0 }) -- 归零那一秒不掉血
        hunger, damage = ctx.Vitals.Advance(1, 3, c)
        assert.same({ hunger, damage }, { 0, 10 })
        hunger, damage = ctx.Vitals.Advance(0, 60, c) -- 卡顿补算封顶
        assert.same({ hunger, damage }, { 0, 25 })
        assert.same({ ctx.Vitals.Advance(10, 0, c) }, { 10, 0 })
        assert.same(300, ctx.Vitals.Restore(290, 300, 5))
        assert.same(145, ctx.Vitals.Restore(100, 300, 15))
    end)

    -- 离开清理状态与信号连接
    it('test_remove_clears_state_and_links', function()
        local c = ctrl()
        ctx.mgr:OnPlayerRemoving(ctx.a)
        assert.is_nil(ctx.mgr:GetState(ctx.a))
        assert.same(0, #c.Died.handlers)
        assert.same(0, #c.HealthChanged.handlers)
        assert.same(0, #ctx.a.CharacterAdded.handlers)
        tick(2)
        assert.same(298, ctx.b.attrs.Hunger)
    end)

    -- 引擎没按时复活时兜底只调一次 Reborn
    it('test_revive_fallback_calls_reborn_once_when_engine_does_not', function()
        ctx.mgr:SetHealth(ctx.a, 0)
        assert.is_true(ctx.mgr:IsDead(ctx.a))
        local v = GameCfg.Vitals
        tick(v.ReviveDelaySec)
        assert.same(0, ctrl().reborns)
        tick(v.ReviveGraceSec + 1)
        assert.same(1, ctrl().reborns)
        tick(5)
        assert.same(1, ctrl().reborns)
        ctrl().OnReborn:Fire(ctx.a.Character)
        assert.is_false(ctx.mgr:IsDead(ctx.a))
        assert.same(300, ctrl().Health)
    end)

    -- 越界值一律拒绝
    it('test_setters_reject_out_of_range', function()
        for _, bad in ipairs({ -1, 301, 1.5, 'x' }) do
            assert.is_false(ctx.mgr:SetHunger(ctx.a, bad))
            assert.is_false(ctx.mgr:SetHealth(ctx.a, bad))
        end
        assert.same(300, ctx.a.attrs.Hunger)
        assert.same(300, ctrl().Health)
        assert.is_true(ctx.mgr:SetHealth(ctx.a, 300))
        assert.is_true(ctx.mgr:SetHunger(ctx.a, 0))
    end)

    -- 饥饿只按整秒推进，不随帧扣
    it('test_hunger_drops_once_per_whole_second_not_per_frame', function()
        local before = ctx.a.writes.Hunger
        tick(0.7, 0.05) -- 1000.2 → 1000.9：同一秒内
        assert.same(300, ctx.a.attrs.Hunger)
        assert.same(before, ctx.a.writes.Hunger)
        tick(10, 0.05)
        assert.same(290, ctx.a.attrs.Hunger)
        assert.same(before + 10, ctx.a.writes.Hunger)
        assert.same({}, ctrl().damages)
    end)

    -- 饿死掉血只走 ApplyDamage 单点，两名玩家互不影响
    it('test_starving_damages_through_single_entry_and_players_independent', function()
        local calls = {}
        local original = ctx.mgr.ApplyDamage
        ctx.mgr.ApplyDamage = function(mgr, player, amount)
            calls[#calls + 1] = { player.UserId, amount }
            return original(mgr, player, amount)
        end
        ctx.mgr:SetHunger(ctx.a, 1)
        tick(1) -- 1 → 0
        assert.same({}, calls)
        tick(3)
        assert.same({ { 1, 5 }, { 1, 5 }, { 1, 5 } }, calls)
        assert.same(285, ctrl().Health)
        assert.same(285, ctx.a.attrs.Health)
        assert.same(300, ctrl(ctx.b).Health)
        assert.same(296, ctx.b.attrs.Hunger)
        ctx.mgr.ApplyDamage = original
        assert.is_false(ctx.mgr:ApplyDamage(ctx.a, 0))
        assert.is_false(ctx.mgr:ApplyDamage(ctx.a, -3))
        assert.same(285, ctrl().Health)
    end)
end)

-- GM 设置血量 / 饥饿（经 MgrGM，开关关闭时拒绝）
describe('TestVitalsGM', function()
    local ctx

    before_each(function()
        ctx = { savedDebug = GameCfg.Debug, savedGame = rawget(_G, 'game') }
        GameCfg.Debug = { Enabled = true, InitialGrants = {} }
        local me, you = newPlayer(1), newPlayer(2)
        ctx.me, ctx.you = me, you
        _G.game = { GetService = function(_, name)
            if name == 'Players' then return { GetPlayers = function() return { me, you } end } end
        end }
        ctx.vitals = assert(loadfile('server/Mgr/MgrVitals.lua'))()
        ctx.vitals.Now = function() return 50 end
        ctx.vitals:OnPlayerAdded(me)
        ctx.vitals:OnPlayerAdded(you)
        ctx.gm = assert(loadfile('server/Mgr/MgrGM.lua'))()
        ctx.gm.Vitals = ctx.vitals
        ctx.gm.PlayerData = { GetDataInst = function() return {} end, SendItemBar = function() end }
        ctx.gm.Reply = function() end
    end)

    -- before_each 中途失败也要把全局与配置放回原样
    after_each(function()
        if ctx then
            if ctx.savedDebug ~= nil then GameCfg.Debug = ctx.savedDebug end
            _G.game = ctx.savedGame
        end
    end)

    it('test_gm_sets_target_vitals_only_when_enabled', function()
        assert.is_true(ctx.gm:Handle(ctx.me, { action = 'SetHunger', value = 10, target = 2 }))
        assert.same(10, ctx.you.attrs.Hunger)
        assert.same(300, ctx.me.attrs.Hunger)
        assert.is_true(ctx.gm:Handle(ctx.me, { action = 'SetHealth', value = 40 }))
        assert.same(40, ctx.me.Character.Controller.Health)
        assert.is_false(ctx.gm:Handle(ctx.me, { action = 'SetHealth', value = 999 }))
        assert.is_false(ctx.gm:Handle(ctx.me, { action = 'SetHunger', value = 5, target = 77 }))
        GameCfg.Debug.Enabled = false
        assert.is_false(ctx.gm:Handle(ctx.me, { action = 'SetHunger', value = 0 }))
        assert.same(300, ctx.me.attrs.Hunger)
    end)
end)
