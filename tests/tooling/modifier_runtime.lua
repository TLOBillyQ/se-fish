-- modifier_system 离线边界：单位、事件与 Timer；不替代官方效果算法。
local Runtime = {}
function Runtime.New(clock)
    local e = { now = clock or 100, units = {}, timers = {} }
    local function signal()
        local tokens = {}
        return {
            Connect = function(_, fn)
                local token = { fn = fn, active = true }; tokens[#tokens + 1] = token
                return { Disconnect = function() token.active = false end }
            end,
            Fire = function(_, ...) for _, token in ipairs(tokens) do if token.active then token.fn(...) end end end,
        }
    end
    function e.unit(name)
        local u = { Name = name, UnitId = #e.units + 1, attrs = {}, Destroying = signal() }
        e.units[#e.units + 1] = u
        function u:GetAttribute(k) return self.attrs[k] end
        function u:SetAttribute(k, v) self.attrs[k] = v end
        function u:GetComponent() return nil end
        function u:IsA(kind) return kind == 'BindableEvent' end
        function u:GetChildren()
            local result = {}
            for _, child in ipairs(e.units) do if child.Parent == self and not child.destroyed then result[#result + 1] = child end end
            return result
        end
        function u:FindFirstChild(name)
            for _, child in ipairs(self:GetChildren()) do if child.Name == name then return child end end
        end
        function u:Destroy()
            if self.destroyed then return end
            self.destroyed = true; self.Destroying:Fire()
            for _, child in ipairs(self:GetChildren()) do child:Destroy() end
        end
        local event = signal()
        function u:Connect(fn) return event:Connect(fn) end
        function u:Fire(...) event:Fire(...) end
        return u
    end
    e.world = { GetServerTime = function() return e.now end,
        CreateAsset = function(_, key) return { e.unit(key) } end }
    e.timerService = { CreateTimer = function(_, _, duration, _, callback)
        local t = { due = e.now + duration, callback = callback }
        function t:Cancel() self.cancelled = true end
        e.timers[#e.timers + 1] = t
        return t
    end }
    e.game = { GetService = function(_, name)
        if name == 'World' then return e.world end
        if name == 'TimerService' then return e.timerService end
        if name == 'RunService' then return { IsServer = function() return true end } end
        return {}
    end, CreateUnit = function(_, _, props) local u = e.unit(props.Name); return u end }
    e.remote = { New = function() return { OnServerEvent = signal(), FireAllClients = function() end } end }
    function e.wait(seconds)
        local target = e.now + seconds
        while true do
            local nextTimer
            for _, t in ipairs(e.timers) do
                if not t.cancelled and t.due <= target and (not nextTimer or t.due < nextTimer.due) then nextTimer = t end
            end
            if not nextTimer then break end
            e.now = nextTimer.due; nextTimer.cancelled = true; nextTimer.callback()
        end
        e.now = target
    end
    function e.loadModifier()
        local loaded = {}
        local env = setmetatable({ game = e.game, RemoteEvent = e.remote }, { __index = _G })
        env.require = function(name)
            if name:find('modifier_system', 1, true) or name == 'server.ModifierAPI' or name == 'common.ModifierAPIBase' then
                if not loaded[name] then loaded[name] = assert(loadfile(name:gsub('%.', '/') .. '.lua', 't', env))() end
                return loaded[name]
            end
            return require(name)
        end
        local mgr = assert(loadfile('server/Mgr/MgrModifier.lua', 't', env))()
        mgr.Presets = { poison = 'test:poison', burn = 'test:burn', frost = 'test:frost', paralyze = 'test:paralyze', weak = 'test:weak' }
        return mgr
    end
    return e
end
-- 旧生存测试接入真实 vendor 时钟；速度投影是可观测边界，不复制效果计时。
function Runtime.AttachSurvival(survival, now)
    local e = Runtime.New(now())
    local modifier = e.loadModifier()
    local function sync(player)
        e.wait(math.max(0, now() - e.now))
        if player and player.Character and not player.Character.GetAttribute then
            local unit = e.unit('character')
            for k, v in pairs(unit) do if player.Character[k] == nil then player.Character[k] = v end end
        end
    end
    local apply, left = modifier.Apply, modifier.GetRemaining
    function modifier:Apply(source, target, kind, seconds) sync(target); return apply(self, source, target, kind, seconds) end
    function modifier:GetRemaining(target, kind) sync(target); return left(self, target, kind) end
    local bases = {}
    survival.Modifier = modifier
    survival.SpeedWriter = { RefreshMoveSpeed = function(_, player)
        local controller = player.Character and player.Character.Controller
        if not controller then return false end
        bases[player.UserId] = bases[player.UserId] or controller.WalkSpeed
        controller.WalkSpeed = bases[player.UserId] * modifier:GetMoveMultiplier(player)
        return true
    end }
    modifier.Ability = survival.SpeedWriter
    return modifier
end
return Runtime
