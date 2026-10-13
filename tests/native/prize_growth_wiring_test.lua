-- #89 迁移（原 tests/gameplay/prize_growth_wiring_test.lua，#139 T18 大奖成长切片 6）：
-- 成长与持续效果的生产接线。
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
-- 旧套件的逐例 setUp/tearDown 映射为 before_each/after_each；被替换的全局（game / Vector3 / REUtil）、
-- 模块缓存（package.loaded 的 MgrFishUnit 与 common.REUtil）与配置（GameCfg.Debug）逐例恢复，
-- after_each 对未完成的 before_each 幂等。describe 顺序沿用旧执行序（类名字典序）。
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

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- ===== 5. 鱼的霜冻减速与麻痹闸门 =====
describe('TestFishStatusGate', function()
    local ctx

    before_each(function()
        ctx = { saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
            unit = package.loaded['server.Mgr.MgrFishUnit'] } }
        ctx.now = 10
        local state = ctx
        _G.Vector3 = { New = vec }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return state.now end } end
            if name == 'Players' then return { GetPlayers = function() return {} end } end
            return {}
        end }
        package.loaded['server.Mgr.MgrFishUnit'] = nil
        ctx.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
        ctx.factor, ctx.paralyzed = 1, false
        ctx.mgr.Ability = {
            FishSpeedFactor = function() return state.factor end,
            FishParalyzed = function() return state.paralyzed end,
            RemoveFish = function() end,
        }
    end)

    after_each(function()
        if ctx and ctx.saved then
            _G.game = ctx.saved.game
            _G.Vector3 = ctx.saved.Vector3
            package.loaded['server.Mgr.MgrFishUnit'] = ctx.saved.unit
        end
    end)

    -- 麻痹的鱼不追咬、不施法、就地停住
    it('test_paralyzed_fish_skips_combat_actions', function()
        local dispatched = {}
        for _, name in ipairs({ 'UpdateChase', 'UpdateEel', 'UpdateBossPhase', 'UpdateShrimpCombat',
            'UpdateKingCrabCombat', 'UpdateCrabBossCombat', 'StunFish' }) do
            ctx.mgr[name] = function() dispatched[#dispatched + 1] = name end
        end
        ctx.mgr.RefreshMovingCombat = function() end
        ctx.mgr.BossPhaseEnabled = function() return false end
        local body = { Position = vec(9999, 500, 9999) } -- 远离任何水域，不触发入水逃脱
        local fish = { Id = 2, FishId = 'alligatorGar', State = 'combat', FleeAt = ctx.now + 100,
            Carrier = { Body = body } }
        ctx.paralyzed = true
        ctx.mgr:UpdateCombat(fish, ctx.now)
        assert.message('麻痹期间不追咬/不施法').same({}, dispatched)
        assert.same(vec(0, 0, 0), body.LinearVelocity)
        ctx.paralyzed = false
        ctx.mgr:UpdateCombat(fish, ctx.now)
        assert.same({ 'UpdateChase' }, dispatched)
    end)

    -- 鱼的移速 = 基础 × 状态因子；效果口故障不拖垮移动
    it('test_speed_multiplies_status_factor', function()
        local fish = { Id = 1, FishId = 'alligatorGar' }
        local base = GameCfg.Fish.alligatorGar.Speed
        assert.same(base, ctx.mgr:Speed(fish))
        ctx.factor = 0.7 -- 霜冻
        assert.near(base * 0.7, ctx.mgr:Speed(fish), 1e-9)
        ctx.factor = 0 -- 麻痹
        assert.same(0, ctx.mgr:Speed(fish))
        -- 效果口故障不拖垮移动：按 1 处理
        ctx.mgr.Ability.FishSpeedFactor = function() error('boom') end
        assert.same(base, ctx.mgr:Speed(fish))
        ctx.mgr.Ability = nil
        assert.same(base, ctx.mgr:Speed(fish))
    end)

    -- 直线逃跑每帧刷新状态速度：不等 TurnSec 转向
    it('test_straight_escape_refreshes_status_velocity_each_frame', function()
        local body = { Position = vec(9999, 500, 9999) }
        local fish = { Id = 3, FishId = 'alligatorGar', StraightEscape = true,
            Heading = { x = 1, z = 0 }, Carrier = { Body = body } }
        ctx.factor = 0
        ctx.mgr:UpdateEscaping(fish, ctx.now)
        assert.same(vec(0, 0, 0), body.LinearVelocity)
        ctx.now, ctx.factor = ctx.now + 0.5, 0.7
        ctx.mgr:UpdateEscaping(fish, ctx.now)
        assert.near(GameCfg.Fish.alligatorGar.Speed * 0.7, body.LinearVelocity.x, 1e-9)
        ctx.now, ctx.factor = ctx.now + 2.5, 1
        ctx.mgr:UpdateEscaping(fish, ctx.now)
        assert.same(GameCfg.Fish.alligatorGar.Speed, body.LinearVelocity.x)
    end)
end)

-- ===== 1–3. 喝药成长应用、上限、重进保留 =====
describe('TestPrizeGrowthPotion', function()
    local ctx

    before_each(function()
        ctx = { debug = GameCfg.Debug, oldREUtil = _G.REUtil, events = {}, growth = {}, bodyOnly = {} }
        local state = ctx
        ctx.mgr = require('server.Mgr.MgrPlayerData')
        GameCfg.Debug = { Enabled = false }
        _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
            if not state.events[name] then
                state.events[name] = {
                    OnServerEvent = signal(),
                    FireClient = function(_, player, payload) player.lastResult = payload end,
                }
            end
            return state.events[name]
        end }
        local player = { UserId = 13961, Character = { Name = 'Eggy' },
            CharacterAdded = signal(), CharacterRemoving = signal() }
        function player:SetAttribute() end
        ctx.player = player
        ctx.mgr.Vitals = { CanEat = function() return true end, Eat = function() end }
        ctx.mgr.Save = nil
        ctx.mgr.Ability = {
            ApplyGrowth = function(_, p) state.growth[#state.growth + 1] = p; return { Ok = true } end,
            ApplyBodyScale = function(_, p) state.bodyOnly[#state.bodyOnly + 1] = p; return { Ok = true } end,
        }
        ctx.mgr:Start()
        ctx.mgr:OnPlayerAdded(player)
        ctx.data = ctx.mgr:GetDataInst(player)
    end)

    -- before_each 中途失败也要拆掉注入的假管理器与全局
    after_each(function()
        if not ctx then return end
        if ctx.player then ctx.mgr:OnPlayerRemoving(ctx.player) end
        ctx.mgr.Vitals, ctx.mgr.Save, ctx.mgr.Ability = nil, nil, nil
        _G.REUtil = ctx.oldREUtil
        GameCfg.Debug = ctx.debug
    end)

    local function drink(itemId)
        assert.is_true(ctx.data:AddItem(itemId, 1))
        local function operate()
            ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player, { action = 'Operate', op = 'eat', slot = 1 })
            return ctx.player.lastResult
        end
        operate() -- 第一下拿起
        return operate()
    end

    -- 变大最多 10 个：第 10 个生效，第 11 个拒绝
    it('test_body_potion_10th_applies_growth_11th_rejected', function()
        ctx.data.Extra.growth.potions.item168 = 9
        assert.is_true(drink('item168').ok)
        assert.same(10, ctx.data:PotionCount('item168'))
        assert.same(1, #ctx.growth)
        assert.same('potion-capped', drink('item168').reason)
        assert.same(10, ctx.data:PotionCount('item168'))
        assert.same(1, #ctx.growth)
    end)

    -- 重进：药水次数与抽奖武器随存档往返
    it('test_rejoin_keeps_potion_counts_and_prize_weapons', function()
        ctx.data.Extra.growth.potions.item167 = 19
        assert.is_true(drink('item167').ok)
        ctx.data.Extra.growth.potions.item168 = 9
        assert.is_true(drink('item168').ok)
        assert.is_true(ctx.data:GrantWeapon('item165', 1)) -- 黄金AK47
        assert.is_true(ctx.data:GrantWeapon('item152', 1)) -- 淬毒匕首
        local snapshot = ctx.data:Serialize()
        local PlayerData = require('server.Data.PlayerData')
        local again = PlayerData.New({ UserId = 13961, SetAttribute = function() end })
        again:Init()
        assert.is_true(again:ApplySave(snapshot))
        assert.same(20, again:PotionCount('item167'))
        assert.same(10, again:PotionCount('item168'))
        assert.same(1, again:WeaponCount('item165'))
        assert.same(1, again:WeaponCount('item152'))
    end)

    -- 统一规格 §2：加速最多 20 个；第 20 个生效，第 21 个拒绝且不扣格、不触发成长应用
    it('test_speed_potion_20th_applies_growth_21st_rejected', function()
        ctx.data.Extra.growth.potions.item167 = 19
        local twentieth = drink('item167')
        assert.is_true(twentieth.ok)
        assert.same(20, ctx.data:PotionCount('item167'))
        assert.message('喝药后走整体成长应用（体型+血量上限+移速），不只是体型').same(1, #ctx.growth)
        assert.same(ctx.player, ctx.growth[1])
        assert.same(0, #ctx.bodyOnly)
        local capped = drink('item167')
        assert.same({ ok = false, op = 'eat', reason = 'potion-capped' }, capped)
        assert.same(20, ctx.data:PotionCount('item167'))
        assert.message('超限不扣格').same('item167', ctx.data:GetItemBarSnapshot().slots[1].itemId)
        assert.message('超限不再触发成长应用').same(1, #ctx.growth)
    end)
end)

-- ===== 6. server/main.lua 接线 =====
describe('TestPrizeGrowthWiring', function()
    -- 只读源码断言，不改全局，无需 before_each/after_each
    it('test_server_main_wires_growth_and_effects', function()
        local file = assert(io.open('server/main.lua', 'r'))
        local src = file:read('*a')
        file:close()
        assert.matches('MgrMap.MgrAbility.PlayerData = MgrMap.MgrPlayerData', src, nil, true)
        assert.matches('MgrMap.MgrAbility.Survival = MgrMap.MgrSurvival', src, nil, true)
        assert.matches('MgrMap.MgrSurvival.SpeedWriter = MgrMap.MgrAbility', src, nil, true)
        assert.matches('MgrMap.MgrWeapon.Ability = MgrMap.MgrAbility', src, nil, true)
        assert.matches('MgrMap.MgrVitals.ActGuard = function(player)', src, nil, true)
        assert.matches('not MgrMap.MgrAbility:IsParalyzed(player)', src, nil, true)
        assert.matches('MgrMap.MgrVitals.MaxHealthProvider = function(player)', src, nil, true)
        assert.matches('MgrMap.MgrAttr:MaxHealth(player)', src, nil, true)
    end)
end)

-- 公共客户端输入：连发火箭筒按住按1秒间隔持续请求，不进入长按换弹。
describe('TestPrizeRocketInput', function()
    local ctx

    -- 旧案例在测试体末尾手工还原 game/REUtil；断言失败会跳过还原。
    -- 逐例 before_each/after_each 后，替换的全局无论成败都恢复。
    before_each(function()
        ctx = { oldGame = _G.game, oldRE = _G.REUtil, now = 0, requests = {} }
        local state = ctx
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return state.now end } end
            if name == 'Players' then return { LocalPlayer = { Character = {} } } end
        end }
        _G.REUtil = { GetRE = function() return { FireServer = function(_, p)
            state.requests[#state.requests + 1] = p.action end } end }
        ctx.button = assert(loadfile('client/LocalAttackButton.lua'))()
        ctx.button.Gesture = require('client.PressGesture').New({ LongPressSec = 0.5 })
        ctx.button.Root, ctx.button.Container, ctx.button.IsOpen = { Visible = true }, { Visible = true }, true
        ctx.button:SetEquipped({ selectedWeapon = 'item166', weapons = { item166 = 1 } })
    end)

    after_each(function()
        if ctx then
            _G.game, _G.REUtil = ctx.oldGame, ctx.oldRE
        end
    end)

    it('test_long_press_rocket_requests_repeated_attacks', function()
        ctx.button:OnPressBegin()
        ctx.button:Tick()
        ctx.now = 0.9; ctx.button:Tick()
        ctx.now = 1; ctx.button:Tick()
        ctx.now = 2; ctx.button:Tick()
        ctx.button:OnPressEnd()
        assert.same({ 'attack', 'attack', 'attack' }, ctx.requests)
    end)
end)

-- ===== 4. 虚弱进出经唯一移速计算口 =====
describe('TestWeakSpeedRouting', function()
    local ctx

    before_each(function()
        ctx = { savedGame = rawget(_G, 'game'), now = 50, refreshes = {} }
        local state = ctx
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return state.now end } end
            return {}
        end }
        -- REUtil 顶层按 RunService 注册服务端事件；单独跑本文件时用最小桩，不依赖其他用例先加载
        ctx.savedRE = package.loaded['common.REUtil']
        package.loaded['common.REUtil'] = ctx.savedRE or { GetRE = function()
            return { OnServerEvent = signal(), FireClient = function() end } end,
            CheckRECD = function() return false end }
        ctx.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
        require('tests.support.modifier_runtime').AttachSurvival(ctx.s, function() return state.now end)
        ctx.controller = { WalkSpeed = 21 } -- 已吃 20 个加速
        ctx.player = { UserId = 13962, Character = { Controller = ctx.controller } }
        ctx.state = { player = ctx.player, phase = 'alive' }
        ctx.s.States[ctx.player.UserId] = ctx.state
        ctx.s.SpeedWriter = { RefreshMoveSpeed = function(_, player)
            local st = state.s:GetState(player)
            state.refreshes[#state.refreshes + 1] = { player = player, weak = state.s.Modifier:GetRemaining(player, 'weak') > 0 }
        end }
    end)

    after_each(function()
        if ctx then
            _G.game = ctx.savedGame
            package.loaded['common.REUtil'] = ctx.savedRE
        end
    end)

    -- 虚弱进出都走唯一写口，且退出时先清标记再重算
    it('test_weak_enter_and_exit_route_to_single_writer', function()
        ctx.s:ApplyWeak(ctx.state, 60)
        assert.same({ { player = ctx.player, weak = true } }, ctx.refreshes)
        assert.message('Survival 不再私写 WalkSpeed').same(21, ctx.controller.WalkSpeed)
        ctx.s:ClearWeak(ctx.state)
        assert.same(3, #ctx.refreshes)
        assert.message('退出虚弱先清标记再重算，否则唯一计算口仍按虚弱算').is_false(ctx.refreshes[2].weak)
        assert.same(21, ctx.controller.WalkSpeed)
        assert.is_nil(ctx.state.weakUntil)
    end)

    -- 缺速度写口仍只创建官方效果；不启用旧半速兜底。
    it('test_without_writer_keeps_modifier_as_single_state_owner', function()
        ctx.s.SpeedWriter = nil
        ctx.s.Modifier.Ability = nil
        ctx.s:ApplyWeak(ctx.state, 60)
        assert.same(60, ctx.s.Modifier:GetRemaining(ctx.player, 'weak'))
        assert.same(21, ctx.controller.WalkSpeed)
        ctx.s:ClearWeak(ctx.state)
        assert.same(0, ctx.s.Modifier:GetRemaining(ctx.player, 'weak'))
        assert.same(21, ctx.controller.WalkSpeed)
    end)
end)
