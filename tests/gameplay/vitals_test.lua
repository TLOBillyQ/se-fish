-- #53 饥饿、掉血、死亡与复活（common/Vitals.lua 纯函数 + server/Mgr/MgrVitals.lua，假玩家 / 假 Controller）。
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

TestVitals = {}

function TestVitals:setUp()
    self.cfg = require('common.GameCfg')
    self.Vitals = assert(loadfile('common/Vitals.lua'))()
    self.mgr = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    local env = self
    self.now = 1000.2
    self.mgr.Now = function() return env.now end
    self.a = newPlayer(1)
    self.b = newPlayer(2)
    self.mgr:OnPlayerAdded(self.a)
    self.mgr:OnPlayerAdded(self.b)
end

function TestVitals:tick(seconds, step)
    step = step or 0.25
    local target = self.now + seconds
    while self.now + 1e-9 < target do
        self.now = math.min(target, self.now + step)
        self.mgr:Update(step)
    end
end

function TestVitals:ctrl(p) return (p or self.a).Character.Controller end

function TestVitals:test_config_is_centralized_and_matches_design()
    local v = self.cfg.Vitals
    lu.assertEquals(v.MaxHealth, 300)
    lu.assertEquals(v.MaxHunger, 300)
    lu.assertEquals(v.HungerPerSec, 1)
    lu.assertEquals(v.StarveDamagePerSec, 5)
    lu.assertEquals(v.ReviveDelaySec, 5)
    lu.assertEquals(v.WarnText, '我要饿死了！')
    local defs = self.cfg.Items.Definitions
    local expected = { worm = 5, tilapia = 15, carp = 20, knifeFish = 20, bass = 25, catfish = 25, goldfish = 30 }
    for id, pct in pairs(expected) do lu.assertEquals(defs[id].EatPercent, pct, id) end
    lu.assertNil(defs.starterRod.EatPercent)
end

function TestVitals:test_pure_advance_whole_seconds_then_starve_next_second()
    local c = { HungerPerSec = 1, StarveDamagePerSec = 5, MaxCatchUpSec = 5 }
    local hunger, damage = self.Vitals.Advance(3, 2, c)
    lu.assertEquals({ hunger, damage }, { 1, 0 })
    hunger, damage = self.Vitals.Advance(1, 1, c)
    lu.assertEquals({ hunger, damage }, { 0, 0 }) -- 归零那一秒不掉血
    hunger, damage = self.Vitals.Advance(1, 3, c)
    lu.assertEquals({ hunger, damage }, { 0, 10 })
    hunger, damage = self.Vitals.Advance(0, 60, c) -- 卡顿补算封顶
    lu.assertEquals({ hunger, damage }, { 0, 25 })
    lu.assertEquals({ self.Vitals.Advance(10, 0, c) }, { 10, 0 })
    lu.assertEquals(self.Vitals.Restore(290, 300, 5), 300)
    lu.assertEquals(self.Vitals.Restore(100, 300, 15), 145)
end

function TestVitals:test_join_sets_full_values_and_attributes()
    local c = self:ctrl()
    lu.assertEquals(c.MaxHealth, 300)
    lu.assertEquals(c.Health, 300)
    lu.assertEquals(self.a.attrs, { Health = 300, MaxHealth = 300, Hunger = 300, MaxHunger = 300 })
end

function TestVitals:test_hunger_drops_once_per_whole_second_not_per_frame()
    local before = self.a.writes.Hunger
    self:tick(0.7, 0.05) -- 1000.2 → 1000.9：同一秒内
    lu.assertEquals(self.a.attrs.Hunger, 300)
    lu.assertEquals(self.a.writes.Hunger, before)
    self:tick(10, 0.05)
    lu.assertEquals(self.a.attrs.Hunger, 290)
    lu.assertEquals(self.a.writes.Hunger, before + 10)
    lu.assertEquals(self:ctrl().damages, {})
end

function TestVitals:test_starving_damages_through_single_entry_and_players_independent()
    local calls = {}
    local original = self.mgr.ApplyDamage
    self.mgr.ApplyDamage = function(mgr, player, amount)
        calls[#calls + 1] = { player.UserId, amount }
        return original(mgr, player, amount)
    end
    self.mgr:SetHunger(self.a, 1)
    self:tick(1) -- 1 → 0
    lu.assertEquals(calls, {})
    self:tick(3)
    lu.assertEquals(calls, { { 1, 5 }, { 1, 5 }, { 1, 5 } })
    lu.assertEquals(self:ctrl().Health, 285)
    lu.assertEquals(self.a.attrs.Health, 285)
    lu.assertEquals(self:ctrl(self.b).Health, 300)
    lu.assertEquals(self.b.attrs.Hunger, 296)
    self.mgr.ApplyDamage = original
    lu.assertFalse(self.mgr:ApplyDamage(self.a, 0))
    lu.assertFalse(self.mgr:ApplyDamage(self.a, -3))
    lu.assertEquals(self:ctrl().Health, 285)
end

function TestVitals:test_death_freezes_vitals_and_revive_resets_without_character_added()
    self.mgr:SetHunger(self.a, 0)
    self.mgr:SetHealth(self.a, 5)
    lu.assertEquals(self:ctrl().damages, { 295 }) -- 调低走 ApplyDamage
    self:tick(1.5)
    lu.assertEquals(self:ctrl().Health, 0)
    lu.assertTrue(self.mgr:IsDead(self.a))
    local damages = #self:ctrl().damages
    self:tick(3)
    lu.assertEquals(#self:ctrl().damages, damages) -- 死亡期间不再掉血
    lu.assertEquals(self.a.attrs.Hunger, 0)
    lu.assertFalse(self.mgr:Eat(self.a, 'worm'))
    lu.assertFalse(self.mgr:ApplyDamage(self.a, 5))
    -- 引擎复活：同一 Controller 血量回正，不触发 CharacterAdded
    self:ctrl().Health = 100
    self:tick(0.25)
    lu.assertFalse(self.mgr:IsDead(self.a))
    lu.assertEquals(self:ctrl().Health, 300)
    lu.assertEquals(self.a.attrs.Health, 300)
    lu.assertEquals(self.a.attrs.Hunger, 300)
    lu.assertEquals(self:ctrl().reborns, 0)
    self:tick(2)
    lu.assertEquals(self.a.attrs.Hunger, 298) -- 复活后从 300 重新计时
end

function TestVitals:test_revive_fallback_calls_reborn_once_when_engine_does_not()
    self.mgr:SetHealth(self.a, 0)
    lu.assertTrue(self.mgr:IsDead(self.a))
    local v = self.cfg.Vitals
    self:tick(v.ReviveDelaySec)
    lu.assertEquals(self:ctrl().reborns, 0)
    self:tick(v.ReviveGraceSec + 1)
    lu.assertEquals(self:ctrl().reborns, 1)
    self:tick(5)
    lu.assertEquals(self:ctrl().reborns, 1)
    self:ctrl().OnReborn:Fire(self.a.Character)
    lu.assertFalse(self.mgr:IsDead(self.a))
    lu.assertEquals(self:ctrl().Health, 300)
end

function TestVitals:test_died_signal_and_poll_record_one_death()
    local c = self:ctrl()
    c.Health = 0
    c.Died:Fire()
    local deadAt = self.mgr:GetState(self.a).deadAt
    self:tick(1)
    c.Died:Fire()
    lu.assertEquals(self.mgr:GetState(self.a).deadAt, deadAt)
end

function TestVitals:test_eat_restores_percent_of_max_and_clamps()
    self.mgr:SetHunger(self.a, 100)
    self.mgr:SetHealth(self.a, 100)
    lu.assertTrue(self.mgr:CanEat(self.a, 'worm'))
    lu.assertTrue(self.mgr:Eat(self.a, 'worm'))
    lu.assertEquals(self.a.attrs.Hunger, 115)
    lu.assertEquals(self:ctrl().Health, 115)
    lu.assertTrue(self.mgr:Eat(self.a, 'goldfish'))
    lu.assertEquals(self.a.attrs.Hunger, 205)
    self.mgr:SetHunger(self.a, 290)
    lu.assertTrue(self.mgr:Eat(self.a, 'bass'))
    lu.assertEquals(self.a.attrs.Hunger, 300)
    lu.assertFalse(self.mgr:CanEat(self.a, 'starterRod'))
    lu.assertFalse(self.mgr:Eat(self.a, 'starterRod'))
    lu.assertFalse(self.mgr:Eat(self.a, 'nope'))
    lu.assertEquals(self.b.attrs.Hunger, 300)
end

function TestVitals:test_setters_reject_out_of_range()
    for _, bad in ipairs({ -1, 301, 1.5, 'x' }) do
        lu.assertFalse(self.mgr:SetHunger(self.a, bad))
        lu.assertFalse(self.mgr:SetHealth(self.a, bad))
    end
    lu.assertEquals(self.a.attrs.Hunger, 300)
    lu.assertEquals(self:ctrl().Health, 300)
    lu.assertTrue(self.mgr:SetHealth(self.a, 300))
    lu.assertTrue(self.mgr:SetHunger(self.a, 0))
end

function TestVitals:test_remove_clears_state_and_links()
    local c = self:ctrl()
    self.mgr:OnPlayerRemoving(self.a)
    lu.assertNil(self.mgr:GetState(self.a))
    lu.assertEquals(#c.Died.handlers, 0)
    lu.assertEquals(#c.HealthChanged.handlers, 0)
    lu.assertEquals(#self.a.CharacterAdded.handlers, 0)
    self:tick(2)
    lu.assertEquals(self.b.attrs.Hunger, 298)
end

-- GM 设置血量 / 饥饿（经 MgrGM，开关关闭时拒绝）
TestVitalsGM = {}

function TestVitalsGM:setUp()
    local env = self
    self.cfg = require('common.GameCfg')
    self.savedDebug = self.cfg.Debug
    self.savedGame = rawget(_G, 'game')
    self.cfg.Debug = { Enabled = true, InitialGrants = {} }
    self.me, self.you = newPlayer(1), newPlayer(2)
    _G.game = { GetService = function(_, name)
        if name == 'Players' then return { GetPlayers = function() return { env.me, env.you } end } end
    end }
    self.vitals = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    self.vitals.Now = function() return 50 end
    self.vitals:OnPlayerAdded(self.me)
    self.vitals:OnPlayerAdded(self.you)
    self.gm = assert(loadfile('server/Mgr/MgrGM.lua'))()
    self.gm.Vitals = self.vitals
    self.gm.PlayerData = { GetDataInst = function() return {} end, SendItemBar = function() end }
    self.gm.Reply = function() end
end

function TestVitalsGM:tearDown()
    self.cfg.Debug = self.savedDebug
    _G.game = self.savedGame
end

function TestVitalsGM:test_gm_sets_target_vitals_only_when_enabled()
    lu.assertTrue(self.gm:Handle(self.me, { action = 'SetHunger', value = 10, target = 2 }))
    lu.assertEquals(self.you.attrs.Hunger, 10)
    lu.assertEquals(self.me.attrs.Hunger, 300)
    lu.assertTrue(self.gm:Handle(self.me, { action = 'SetHealth', value = 40 }))
    lu.assertEquals(self.me.Character.Controller.Health, 40)
    lu.assertFalse(self.gm:Handle(self.me, { action = 'SetHealth', value = 999 }))
    lu.assertFalse(self.gm:Handle(self.me, { action = 'SetHunger', value = 5, target = 77 }))
    self.cfg.Debug.Enabled = false
    lu.assertFalse(self.gm:Handle(self.me, { action = 'SetHunger', value = 0 }))
    lu.assertEquals(self.me.attrs.Hunger, 300)
end

-- 吃鱼获：PlayerData:EatSlot 只吃选中的有恢复百分比的格
TestEatSlot = {}

function TestEatSlot:setUp()
    self.cfg = require('common.GameCfg')
    self.savedDebug = self.cfg.Debug
    self.cfg.Debug = { Enabled = true, InitialGrants = self.savedDebug.InitialGrants }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.data = PlayerData.New({ UserId = 1, SetAttribute = function() end })
    self.data:Init()
    self.cfg.Debug = self.savedDebug
end

function TestEatSlot:test_eat_slot_only_fish_and_clears_slot()
    local d = self.data
    lu.assertEquals(d.Data.Containers.itemBar[1].itemId, 'starterRod')
    d:SelectSlot(1)
    lu.assertNil(d:EatSlot(1)) -- 鱼竿不能吃
    lu.assertTrue(d:AddItem('carp', 1.5))
    d:SelectSlot(2)
    lu.assertNil(d:EatSlot(1)) -- 不是选中格
    lu.assertEquals(d:EatSlot(2), 'carp')
    lu.assertNil(d.Data.Containers.itemBar[2])
    lu.assertNil(d.Data.SelectedSlot)
    lu.assertNil(d:EatSlot(2))
end
