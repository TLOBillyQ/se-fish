-- #139 T18 大奖成长切片 6：成长与持续效果的生产接线。
-- 失败方式（先列后写）：
--   1. 喝药后只重算体型（#132 的 ApplyBodyScale），移速与血量上限不跟着成长；
--   2. 第 21 个加速 / 第 11 个变大被接受或扣格；第 20 / 10 个被拒；超限仍触发成长应用；
--   3. 重进（Serialize → ApplySave）丢药水次数或抽奖武器；
--   4. 虚弱进出由 MgrSurvival 私写 WalkSpeed：退虚弱恢复「进虚弱前」的旧值，虚弱期喝的加速丢失；
--      或退出时先写速度后清 weakUntil，唯一计算口仍按虚弱算；
--   5. 鱼被霜冻/麻痹后移速不变；麻痹的鱼仍追咬/施法；
--   6. server/main.lua 漏接 MgrAbility.PlayerData / Survival、Vitals.ActGuard / MaxHealthProvider、
--      Survival.SpeedWriter、MgrWeapon.Ability（单测注入了、生产没接 = 生产里药水数恒 0）。
-- 接缝：MgrPlayerData:Handle（ItemBarAction 通道）、PlayerData 存档往返、MgrSurvival:ApplyWeak/ClearWeak、
--   MgrFishUnit:Speed / UpdateCombat、MgrAbility:CastFish、server/main.lua 源码接线断言。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            callbacks[#callbacks + 1] = fn
            return { Disconnect = function() for i, cb in ipairs(callbacks) do
                if cb == fn then callbacks[i] = nil end
            end end }
        end,
        Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
    }
end

-- ===== 1–3. 喝药成长应用、上限、重进保留 =====
TestPrizeGrowthPotion = {}

function TestPrizeGrowthPotion:setUp()
    self.mgr = require('server.Mgr.MgrPlayerData')
    self.debug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false }
    self.oldREUtil = _G.REUtil
    self.events = {}
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = {
                OnServerEvent = signal(),
                FireClient = function(_, player, payload) player.lastResult = payload end,
            }
        end
        return self.events[name]
    end }
    self.player = { UserId = 13961, Character = { Name = 'Eggy' },
        CharacterAdded = signal(), CharacterRemoving = signal() }
    function self.player:SetAttribute() end
    self.growth, self.bodyOnly = {}, {}
    local env = self
    self.mgr.Vitals = { CanEat = function() return true end, Eat = function() end }
    self.mgr.Save = nil
    self.mgr.Ability = {
        ApplyGrowth = function(_, player) env.growth[#env.growth + 1] = player; return { Ok = true } end,
        ApplyBodyScale = function(_, player) env.bodyOnly[#env.bodyOnly + 1] = player; return { Ok = true } end,
    }
    self.mgr:Start()
    self.mgr:OnPlayerAdded(self.player)
    self.data = self.mgr:GetDataInst(self.player)
end

function TestPrizeGrowthPotion:tearDown()
    self.mgr:OnPlayerRemoving(self.player)
    self.mgr.Vitals, self.mgr.Save, self.mgr.Ability = nil, nil, nil
    _G.REUtil = self.oldREUtil
    GameCfg.Debug = self.debug
end

function TestPrizeGrowthPotion:drink(itemId)
    lu.assertTrue(self.data:AddItem(itemId, 1))
    local function operate()
        self.events.ItemBarAction.OnServerEvent:Fire(self.player, { action = 'Operate', op = 'eat', slot = 1 })
        return self.player.lastResult
    end
    operate() -- 第一下拿起
    return operate()
end

-- 统一规格 §2：加速最多 20 个；第 20 个生效，第 21 个拒绝且不扣格、不触发成长应用
function TestPrizeGrowthPotion:test_speed_potion_20th_applies_growth_21st_rejected()
    self.data.Extra.growth.potions.item167 = 19
    local twentieth = self:drink('item167')
    lu.assertTrue(twentieth.ok)
    lu.assertEquals(self.data:PotionCount('item167'), 20)
    lu.assertEquals(#self.growth, 1, '喝药后走整体成长应用（体型+血量上限+移速），不只是体型')
    lu.assertEquals(self.growth[1], self.player)
    lu.assertEquals(#self.bodyOnly, 0)
    local capped = self:drink('item167')
    lu.assertEquals(capped, { ok = false, op = 'eat', reason = 'potion-capped' })
    lu.assertEquals(self.data:PotionCount('item167'), 20)
    lu.assertEquals(self.data:GetItemBarSnapshot().slots[1].itemId, 'item167', '超限不扣格')
    lu.assertEquals(#self.growth, 1, '超限不再触发成长应用')
end

-- 变大最多 10 个：第 10 个生效，第 11 个拒绝
function TestPrizeGrowthPotion:test_body_potion_10th_applies_growth_11th_rejected()
    self.data.Extra.growth.potions.item168 = 9
    lu.assertTrue(self:drink('item168').ok)
    lu.assertEquals(self.data:PotionCount('item168'), 10)
    lu.assertEquals(#self.growth, 1)
    lu.assertEquals(self:drink('item168').reason, 'potion-capped')
    lu.assertEquals(self.data:PotionCount('item168'), 10)
    lu.assertEquals(#self.growth, 1)
end

-- 重进：药水次数与抽奖武器随存档往返
function TestPrizeGrowthPotion:test_rejoin_keeps_potion_counts_and_prize_weapons()
    self.data.Extra.growth.potions.item167 = 19
    lu.assertTrue(self:drink('item167').ok)
    self.data.Extra.growth.potions.item168 = 9
    lu.assertTrue(self:drink('item168').ok)
    lu.assertTrue(self.data:GrantWeapon('item165', 1)) -- 黄金AK47
    lu.assertTrue(self.data:GrantWeapon('item152', 1)) -- 淬毒匕首
    local snapshot = self.data:Serialize()
    local PlayerData = require('server.Data.PlayerData')
    local again = PlayerData.New({ UserId = 13961, SetAttribute = function() end })
    again:Init()
    lu.assertTrue(again:ApplySave(snapshot))
    lu.assertEquals(again:PotionCount('item167'), 20)
    lu.assertEquals(again:PotionCount('item168'), 10)
    lu.assertEquals(again:WeaponCount('item165'), 1)
    lu.assertEquals(again:WeaponCount('item152'), 1)
end

-- ===== 4. 虚弱进出经唯一移速计算口 =====
TestWeakSpeedRouting = {}

function TestWeakSpeedRouting:setUp()
    self.savedGame = rawget(_G, 'game')
    self.now = 50
    local env = self
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        return {}
    end }
    -- REUtil 顶层按 RunService 注册服务端事件；单独跑本文件时用最小桩，不依赖其他用例先加载
    self.savedRE = package.loaded['common.REUtil']
    package.loaded['common.REUtil'] = self.savedRE or { GetRE = function()
        return { OnServerEvent = signal(), FireClient = function() end } end,
        CheckRECD = function() return false end }
    self.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
    self.controller = { WalkSpeed = 21 } -- 已吃 20 个加速
    self.player = { UserId = 13962, Character = { Controller = self.controller } }
    self.state = { player = self.player, phase = 'alive' }
    self.s.States[self.player.UserId] = self.state
    self.refreshes = {}
    self.s.SpeedWriter = { RefreshMoveSpeed = function(_, player)
        local st = env.s:GetState(player)
        env.refreshes[#env.refreshes + 1] = { player = player, weak = st ~= nil and st.weakUntil ~= nil }
    end }
end

function TestWeakSpeedRouting:tearDown()
    _G.game = self.savedGame
    package.loaded['common.REUtil'] = self.savedRE
end

function TestWeakSpeedRouting:test_weak_enter_and_exit_route_to_single_writer()
    self.s:ApplyWeak(self.state, 60)
    lu.assertEquals(self.refreshes, { { player = self.player, weak = true } })
    lu.assertEquals(self.controller.WalkSpeed, 21, 'Survival 不再私写 WalkSpeed')
    self.s:ClearWeak(self.state)
    lu.assertEquals(#self.refreshes, 2)
    lu.assertFalse(self.refreshes[2].weak, '退出虚弱先清标记再重算，否则唯一计算口仍按虚弱算')
    lu.assertEquals(self.controller.WalkSpeed, 21)
    lu.assertNil(self.state.weakUntil)
end

-- 未注入写口时保持 #131 旧行为（单测与降级兜底）
function TestWeakSpeedRouting:test_without_writer_keeps_legacy_halving()
    self.s.SpeedWriter = nil
    self.s:ApplyWeak(self.state, 60)
    lu.assertEquals(self.controller.WalkSpeed, 21 * GameCfg.Survival.WeakSpeedScale)
    self.s:ClearWeak(self.state)
    lu.assertEquals(self.controller.WalkSpeed, 21)
end

-- ===== 5. 鱼的霜冻减速与麻痹闸门 =====
TestFishStatusGate = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

function TestFishStatusGate:setUp()
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        unit = package.loaded['server.Mgr.MgrFishUnit'] }
    self.now = 10
    local env = self
    _G.Vector3 = { New = vec }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
        return {}
    end }
    package.loaded['server.Mgr.MgrFishUnit'] = nil
    self.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    self.factor, self.paralyzed = 1, false
    self.mgr.Ability = {
        FishSpeedFactor = function() return env.factor end,
        FishParalyzed = function() return env.paralyzed end,
        RemoveFish = function() end,
    }
end

function TestFishStatusGate:tearDown()
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    package.loaded['server.Mgr.MgrFishUnit'] = self.saved.unit
end

function TestFishStatusGate:test_speed_multiplies_status_factor()
    local fish = { Id = 1, FishId = 'alligatorGar' }
    local base = GameCfg.Fish.alligatorGar.Speed
    lu.assertEquals(self.mgr:Speed(fish), base)
    self.factor = 0.7 -- 霜冻
    lu.assertAlmostEquals(self.mgr:Speed(fish), base * 0.7, 1e-9)
    self.factor = 0 -- 麻痹
    lu.assertEquals(self.mgr:Speed(fish), 0)
    -- 效果口故障不拖垮移动：按 1 处理
    self.mgr.Ability.FishSpeedFactor = function() error('boom') end
    lu.assertEquals(self.mgr:Speed(fish), base)
    self.mgr.Ability = nil
    lu.assertEquals(self.mgr:Speed(fish), base)
end

function TestFishStatusGate:test_paralyzed_fish_skips_combat_actions()
    local dispatched = {}
    for _, name in ipairs({ 'UpdateChase', 'UpdateEel', 'UpdateBossPhase', 'UpdateShrimpCombat',
        'UpdateKingCrabCombat', 'UpdateCrabBossCombat', 'StunFish' }) do
        self.mgr[name] = function() dispatched[#dispatched + 1] = name end
    end
    self.mgr.RefreshMovingCombat = function() end
    self.mgr.BossPhaseEnabled = function() return false end
    local body = { Position = vec(9999, 500, 9999) } -- 远离任何水域，不触发入水逃脱
    local fish = { Id = 2, FishId = 'alligatorGar', State = 'combat', FleeAt = self.now + 100,
        Carrier = { Body = body } }
    self.paralyzed = true
    self.mgr:UpdateCombat(fish, self.now)
    lu.assertEquals(dispatched, {}, '麻痹期间不追咬/不施法')
    lu.assertEquals(body.LinearVelocity, vec(0, 0, 0), '麻痹期间就地停住')
    self.paralyzed = false
    self.mgr:UpdateCombat(fish, self.now)
    lu.assertEquals(dispatched, { 'UpdateChase' })
end

-- ===== 6. server/main.lua 接线 =====
TestPrizeGrowthWiring = {}

function TestPrizeGrowthWiring:test_server_main_wires_growth_and_effects()
    local file = assert(io.open('server/main.lua', 'r'))
    local src = file:read('*a')
    file:close()
    lu.assertStrContains(src, 'MgrMap.MgrAbility.PlayerData = MgrMap.MgrPlayerData')
    lu.assertStrContains(src, 'MgrMap.MgrAbility.Survival = MgrMap.MgrSurvival')
    lu.assertStrContains(src, 'MgrMap.MgrSurvival.SpeedWriter = MgrMap.MgrAbility')
    lu.assertStrContains(src, 'MgrMap.MgrWeapon.Ability = MgrMap.MgrAbility')
    lu.assertStrContains(src, 'MgrMap.MgrVitals.ActGuard = function(player)')
    lu.assertStrContains(src, 'not MgrMap.MgrAbility:IsParalyzed(player)')
    lu.assertStrContains(src, 'MgrMap.MgrVitals.MaxHealthProvider = function(player)')
    lu.assertStrContains(src, 'MgrMap.MgrAbility:MaxHealth(player)')
end
