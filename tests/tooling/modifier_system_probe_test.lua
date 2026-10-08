-- #49 专属离线测试：公开探针接缝；失败方式见仓库外 notes.txt。
local lu = require('luaunit')
TestModifierProbe = {}
function TestModifierProbe:test_mapping_preserves_refresh_only_and_legacy_remaining()
    local probe = require('tools.probes.modifier_system_probe')
    local cfg = require('common.GameCfg')
    local mappings = probe.BuildMappings(cfg)
    lu.assertEquals(mappings.poison.maxStackCount, 5)
    lu.assertEquals(mappings.poison.TickSec, cfg.Ability.StatusEffects.poison.TickSec)
    lu.assertEquals(mappings.poison.DamagePerStack, cfg.Ability.StatusEffects.poison.DamagePerStack)
    lu.assertEquals(mappings.poison.DotOwner, '业务调度器 → MgrVitals:NewHit/ApplyHit')
    lu.assertEquals(mappings.poison.SourcePolicy, '末次命中来源；独立于vendor首来源')
    lu.assertEquals(mappings.burn.duration, 3)
    lu.assertEquals(mappings.frost.stackCountMode, 0)
    lu.assertTrue(mappings.frost.stackable)
    lu.assertEquals(mappings.paralyze.duration, 0.5)
    lu.assertEquals(probe.WeakRemaining({ Extra = { survival = { weakRemaining = 17 } } }, 60), 17)
    lu.assertEquals(probe.WeakRemaining({ Extra = { survival = { weakRemaining = 999 } } }, 60), 60)
    lu.assertEquals(probe.WeakRemaining({ Extra = { survival = { weakUntil = 999 } } }, 60), 0)
end

-- 引擎边界模拟，完整执行真实根 ModifierAPI / vendor；不模拟包内算法。
local function engine()
    local e = { now = 100, timers = {}, units = {}, logs = {} }
    local function signal()
        local callbacks = {}
        return {
            Connect = function(_, fn)
                local token = { fn = fn, active = true }
                callbacks[#callbacks + 1] = token
                return { Disconnect = function() token.active = false end }
            end,
            Fire = function(_, ...) for _, token in ipairs(callbacks) do
                if token.active then token.fn(...) end
            end end,
        }
    end
    function e.unit(name)
        local u = { Name = name, UnitId = #e.units + 1, attrs = {}, Destroying = signal() }
        e.units[#e.units + 1] = u
        function u:GetAttribute(k) return self.attrs[k] end
        function u:SetAttribute(k, v) self.attrs[k] = v end
        function u:GetComponent() return nil end
        function u:IsA(kind) return kind == 'BindableEvent' and name == 'BindableEvent' end
        function u:FindFirstChild(childName)
            for _, child in ipairs(e.units) do
                if child.Parent == self and child.Name == childName and not child.destroyed then return child end
            end
        end
        function u:Destroy()
            if self.destroyed then return end
            self.destroyed = true
            self.Destroying:Fire()
            for _, child in ipairs(e.units) do if child.Parent == self then child:Destroy() end end
        end
        local event = signal()
        function u:Connect(fn) return event:Connect(fn) end
        function u:Fire(...) event:Fire(...) end
        return u
    end
    local world = {
        GetServerTime = function() return e.now end,
        CreateAsset = function(_, key) return { e.unit(key) } end,
    }
    local timerService = { CreateTimer = function(_, _, duration, _, callback)
        local timer = { due = e.now + duration, callback = callback }
        function timer:Cancel() self.cancelled = true end
        e.timers[#e.timers + 1] = timer
        return timer
    end }
    e.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'TimerService' then return timerService end
        if name == 'RunService' then return { IsServer = function() return true end } end
        return {}
    end, CreateUnit = function(_, _, props)
        local u = e.unit('BindableEvent'); u.Name = props.Name; return u
    end }
    e.remote = { New = function() return { OnServerEvent = signal(), FireAllClients = function() end } end }
    function e.wait(seconds)
        local target = e.now + seconds
        while true do
            local nextTimer
            for _, timer in ipairs(e.timers) do
                if not timer.cancelled and timer.due <= target and (not nextTimer or timer.due < nextTimer.due) then
                    nextTimer = timer
                end
            end
            if not nextTimer then break end
            e.now = nextTimer.due; nextTimer.cancelled = true; nextTimer.callback()
        end
        e.now = target
    end
    return e
end

function TestModifierProbe:test_real_vendor_public_api_reruns_and_cleans_isolated_objects()
    local savedGame, savedRemote = _G.game, _G.RemoteEvent
    local saved = {}
    for name, value in pairs(package.loaded) do
        if name:find('modifier_system', 1, true) or name == 'server.ModifierAPI' then
            saved[name] = value; package.loaded[name] = nil
        end
    end
    local e = engine()
    _G.game, _G.RemoteEvent = e.game, e.remote
    local ok, err = pcall(function()
        local api = require('server.ModifierAPI')
        for _ = 1, 2 do
            local owner, source, source2 = e.unit('owner'), e.unit('source'), e.unit('source2')
            local report = require('tools.probes.modifier_system_probe').Run({
                isolated = true, isIsolated = function(u) return u == owner or u == source or u == source2 end,
                owner = owner, source = source, source2 = source2,
                api = api, cfg = require('common.GameCfg'), evidence = 'offline', wait = e.wait,
                assets = { poison = 'test:poison', burn = 'test:burn', frost = 'test:frost',
                    paralyze = 'test:paralyze', weak = 'test:weak' },
                log = function(line) e.logs[#e.logs + 1] = line end,
                dispose = function() owner:Destroy(); source:Destroy(); source2:Destroy() end,
            })
            lu.assertEquals(report.errors, {})
            lu.assertTrue(report.ok)
            lu.assertTrue(owner.destroyed and source.destroyed and source2.destroyed)
            for _, timer in ipairs(e.timers) do lu.assertTrue(timer.cancelled) end
        end
    end)
    _G.game, _G.RemoteEvent = savedGame, savedRemote
    for name in pairs(package.loaded) do
        if name:find('modifier_system', 1, true) or name == 'server.ModifierAPI' then package.loaded[name] = nil end
    end
    for name, value in pairs(saved) do package.loaded[name] = value end
    if not ok then error(err) end
end

function TestModifierProbe:test_business_dot_uses_real_manager_phase_final_tick_and_latest_source()
    local clock, hits = 100, {}
    local env = setmetatable({ game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return clock end } end
        if name == 'Players' then return { GetPlayerFromCharacter = function() end } end
        return {}
    end } }, { __index = _G })
    env.require = function(name)
        if name == 'server.AbilityAPI' then return {} end
        return require(name)
    end
    local mgr = assert(loadfile('server/Mgr/MgrAbility.lua', 't', env))()
    local target = { UserId = 49001, Character = { Controller = {} } }
    mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, hit, ref, amount)
            hits[#hits + 1] = { source = hit.source, category = hit.category, target = ref, amount = amount, at = clock }
        end,
    }
    local runtime = require('tests.tooling.modifier_runtime').New(clock)
    target.Character = runtime.unit('target')
    mgr.Modifier = runtime.loadModifier()
    mgr.Modifier.Vitals = mgr.Vitals
    local source, source2 = {}, {}
    local report = require('tools.probes.modifier_system_probe').VerifyBusinessDot({
        cfg = require('common.GameCfg'), source = source, source2 = source2, dotTarget = target,
        now = function() return clock end,
        wait = function(s) runtime.wait(s); clock = runtime.now; mgr:UpdateEffects() end,
        businessDot = {
            apply = function(src, ref, kind) return mgr:ApplyWeaponEffect(src, ref, { Kind = kind }) end,
            hits = function() return hits end,
            clear = function() mgr.Modifier:ClearTarget(target) end,
        },
    })
    lu.assertEquals(report.owner, 'business')
    lu.assertTrue(report.ok)
    lu.assertEquals(report.kinds.poison.count, 3)
    lu.assertEquals(report.kinds.burn.count, 3)
    lu.assertEquals(next(mgr.Effects), nil)
end

-- #52：业务入口使用真实根 API；替身只提供单位、时钟与伤害边界。
local function business(run)
    local e = engine()
    local savedGame, savedRemote = _G.game, _G.RemoteEvent
    local saved = {}
    for name, value in pairs(package.loaded) do
        if name:find('modifier_system', 1, true) or name == 'server.ModifierAPI' then
            saved[name] = value; package.loaded[name] = nil
        end
    end
    _G.game, _G.RemoteEvent = e.game, e.remote
    local ok, err = pcall(function()
        local env = setmetatable({}, { __index = _G })
        local modifier = assert(loadfile('server/Mgr/MgrModifier.lua', 't', env))()
        modifier.Presets = { poison = 'test:poison', burn = 'test:burn', frost = 'test:frost',
            paralyze = 'test:paralyze', weak = 'test:weak' }
        local player = { UserId = 52001, Character = e.unit('character') }
        local hits = {}
        modifier.Vitals = {
            NewHit = function(_, source, category) return { source = source, category = category } end,
            ApplyHit = function(_, hit, target, amount)
                hits[#hits + 1] = { source = hit.source, target = target, amount = amount, category = hit.category }
            end,
        }
        run(e, modifier, player, hits)
    end)
    _G.game, _G.RemoteEvent = savedGame, savedRemote
    for name in pairs(package.loaded) do
        if name:find('modifier_system', 1, true) or name == 'server.ModifierAPI' then package.loaded[name] = nil end
    end
    for name, value in pairs(saved) do package.loaded[name] = value end
    if not ok then error(err, 0) end
end

function TestModifierProbe:test_business_death_rebuild_and_source_leave_do_not_keep_old_dot()
    business(function(e, mgr, player, hits)
        local source = { UserId = 2, Character = e.unit('source') }
        lu.assertTrue(mgr:ApplyWeaponEffect(source, player, { Kind = 'burn' }))
        mgr:OnCharacterAdded(player)
        e.wait(4); mgr:Update()
        lu.assertEquals(#hits, 0)
        lu.assertEquals(#mgr.ModifierAPI.GetUnitModifiers(player.Character), 0)
        lu.assertTrue(mgr:ApplyWeaponEffect(source, player, { Kind = 'poison' }))
        mgr:OnPlayerRemoving(source)
        e.wait(4); mgr:Update()
        lu.assertEquals(#hits, 0)
    end)
end

function TestModifierProbe:test_business_refresh_controls_and_weak_remaining_are_vendor_driven()
    business(function(e, mgr, player)
        lu.assertTrue(mgr:Apply(nil, player, 'weak', 17))
        lu.assertTrue(mgr:Apply(nil, player, 'frost'))
        lu.assertEquals(mgr:GetMoveMultiplier(player), 0.35)
        e.wait(1)
        lu.assertTrue(mgr:Apply(nil, player, 'frost'))
        local entity = mgr.ModifierAPI.GetUnitModifiers(player.Character, 'test:frost')[1]
        lu.assertEquals(entity:GetAttribute('CurrCount'), 1)
        lu.assertEquals(mgr:GetRemaining(player, 'frost'), 3)
        lu.assertTrue(mgr:Apply(nil, player, 'paralyze'))
        lu.assertTrue(mgr:IsControlled(player))
        lu.assertEquals(mgr:GetMoveMultiplier(player), 0)
        e.wait(0.5)
        lu.assertFalse(mgr:IsControlled(player))
        lu.assertEquals(mgr:GetMoveMultiplier(player), 0.35)
        e.wait(3)
        lu.assertEquals(mgr:GetMoveMultiplier(player), 0.5)
        local remaining = mgr:GetRemaining(player, 'weak')
        mgr:OnPlayerRemoving(player)
        e.wait(300)
        lu.assertTrue(mgr:Apply(nil, player, 'weak', remaining))
        lu.assertEquals(mgr:GetRemaining(player, 'weak'), 12.5)
    end)
end

function TestModifierProbe:test_business_modifier_stacks_uses_latest_source_and_retains_dot_phase()
    business(function(e, mgr, player, hits)
        local first, latest = { UserId = 1, Character = e.unit('first') }, { UserId = 2, Character = e.unit('latest') }
        lu.assertTrue(mgr:ApplyWeaponEffect(first, player, { Kind = 'poison' }))
        e.wait(0.5)
        lu.assertTrue(mgr:ApplyWeaponEffect(latest, player, { Kind = 'poison' }))
        e.wait(0.5); mgr:Update()
        lu.assertEquals(#hits, 1)
        lu.assertEquals(hits[1], { source = latest, target = player, amount = 2, category = 'dot' })
        e.wait(3)
        mgr:Update()
        lu.assertEquals(#hits, 3)
        lu.assertEquals(mgr:GetRemaining(player, 'poison'), 0)
        lu.assertEquals(#mgr.ModifierAPI.GetUnitModifiers(player.Character), 0)
    end)
end

function TestModifierProbe:test_run_rejects_unowned_targets_without_api_calls()
    local probe = require('tools.probes.modifier_system_probe')
    lu.assertErrorMsgContains('隔离', function() probe.Run({}) end)
end
