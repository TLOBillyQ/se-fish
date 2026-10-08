-- #49 专属离线测试：公开探针接缝；失败方式见仓库外 notes.txt。
local lu = require('luaunit')
TestModifierProbe = {}
function TestModifierProbe:test_mapping_preserves_refresh_only_and_legacy_remaining()
    local probe = require('tools.probes.modifier_system_probe')
    local cfg = require('common.GameCfg')
    local mappings = probe.BuildMappings(cfg)
    lu.assertEquals(mappings.poison.maxStackCount, 5)
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

function TestModifierProbe:test_run_rejects_unowned_targets_without_api_calls()
    local probe = require('tools.probes.modifier_system_probe')
    lu.assertErrorMsgContains('隔离', function() probe.Run({}) end)
end
