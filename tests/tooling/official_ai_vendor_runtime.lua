-- 加载未修改 vendor 的最小运行环境；game/Task/World/Players 与单位是显式引擎边界。
local Probe = require('tools.probes.official_ai_probe')

local Loader = {}

local MODULE_PATHS = {
    ['common.AbilityAPIBase'] = 'common/AbilityAPIBase.lua',
    ['common.AiAPIBase'] = 'common/AiAPIBase.lua',
    ['server.packages.official_ai_feature.api'] = 'server/packages/official_ai_feature/api.lua',
    ['common.packages.official_ai_feature.configs'] = 'common/packages/official_ai_feature/configs.lua',
    ['server.packages.official_ai_feature.official_ai_feature'] = 'server/packages/official_ai_feature/official_ai_feature.lua',
    ['common.packages.official_ai_feature.utils'] = 'common/packages/official_ai_feature/utils.lua',
    ['server.packages.official_ai_feature.ability_bridge'] = 'server/packages/official_ai_feature/ability_bridge.lua',
    ['server.packages.official_ai_feature.behavior_runtime'] = 'server/packages/official_ai_feature/behavior_runtime.lua',
    ['server.packages.ability_system.api'] = 'server/packages/ability_system/api.lua',
    ['common.packages.ability_system.constants'] = 'common/packages/ability_system/constants.lua',
    ['common.packages.ability_system.registry'] = 'common/packages/ability_system/registry.lua',
    ['server.packages.ability_system.sub_ability_plugin'] = 'server/packages/ability_system/sub_ability_plugin.lua',
    ['server.packages.ability_system.sub_ability'] = 'server/packages/ability_system/sub_ability.lua',
    ['common.packages.ability_system.event_defs'] = 'common/packages/ability_system/event_defs.lua',
    ['common.packages.ability_system.util'] = 'common/packages/ability_system/util.lua',
}

local function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
    function v:GetNormalized()
        local len = self:Length()
        return len <= 0 and nil or Vector(self.x / len, self.y / len, self.z / len)
    end
    return setmetatable(v, {
        __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
    })
end
local function vecLen(v)
    local value = v == nil and 0 or math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    return value
end

local function vecNorm(v)
    local len = vecLen(v)
    return len <= 0 and nil or Vector(v.x / len, v.y / len, v.z / len)
end

local function tracer(unit)
    local copy = { UnitId = unit.UnitId, Position = unit.Position, Controller = unit.Controller,
        Parent = unit.Parent, Destroying = unit.Destroying, children = unit.children,
        GetPosition = unit.GetPosition, SetPosition = unit.SetPosition, GetChildren = unit.GetChildren,
        HasAnyTags = unit.HasAnyTags, HasAllTags = unit.HasAllTags }
    return copy
end

local function connection(events, name)
    return { Disconnect = function(self) self.connected = false end }
end
local function signal()
    return { handlers = {}, Connect = function(self, handler)
        local conn = { Disconnect = function(self) self.connected = false end }
        self.handlers[#self.handlers + 1] = handler
        return conn
    end, Fire = function(self, ...)
        for _, handler in ipairs(self.handlers) do handler(...) end
    end }
end

local function newController()
    local controller = {
        moves = {}, jumps = 0, flings = 0, rushes = 0, lifts = 0,
        state = 'idle', StateChanged = signal(), OnCollisionEnter = signal(),
        OnJump = signal(), OnLiftBegin = signal(), OnRush = signal(), OnRollBegin = signal(),
    }
    function controller:Move(direction)
        if direction.Length == nil then direction.Length = function(v)
            return vecLen(v)
        end end
        self.moves[#self.moves + 1] = direction
    end
    function controller:Jump() self.jumps = self.jumps + 1 end
    function controller:Fling() self.flings = self.flings + 1 end
    function controller:Rush() self.rushes = self.rushes + 1 end
    function controller:Lift() self.lifts = self.lifts + 1 end
    function controller:GetState() return self.state end
    return controller
end

local function newUnit(id, position)
    local unit = { UnitId = id, Parent = true, Controller = newController(),
        Position = position or Vector(), Destroying = signal(), children = {} }
    function unit:HasAnyTags(tags) return #tags > 0 and false or false end
    function unit:HasAllTags(tags) return #tags == 0 end
    function unit:GetPosition() return self.Position end
    function unit:SetPosition(position) self.Position = position end
    function unit:GetChildren() return self.children end
    function unit:HasAnyTags(tags) return #tags > 0 and false or false end
    function unit:HasAllTags(tags) return #tags == 0 end
    return unit
end

-- deterministic 环境：runFn 返回一个按秒推进的时间回调；Task 调度器轮询所有作业。
function Loader.loadAi()
    local loaded = {}
    local time = { value = 0 }
    local taskService = { tasks = {} }
    function taskService:Spawn(fn)
        local task = { coroutine = coroutine.create(fn), wakeAt = time.value, done = false }
        self.tasks[#self.tasks + 1] = task
        return task
    end
    function taskService:Cancel(task)
        if task == nil then return end
        task.done = true
        for index, value in ipairs(self.tasks) do
            if value == task then table.remove(self.tasks, index) break end
        end
    end
    function taskService:Wait(sec)
        local wake = time.value + (sec or 0)
        coroutine.yield(wake)
    end
    function taskService:pump(sec)
        local stop = time.value + sec
        while true do
            local ready, earliest = nil, nil
            for _, task in ipairs(self.tasks) do
                if not task.done then
                    if task.wakeAt <= time.value and ready == nil then ready = task end
                    if earliest == nil or task.wakeAt < earliest then earliest = task.wakeAt end
                end
            end
            if ready ~= nil then
                local ok, wake = coroutine.resume(ready.coroutine)
                if coroutine.status(ready.coroutine) == 'dead' then
                    ready.done = true
                    if not ok then error('vendor 任务异常: ' .. tostring(wake), 0) end
                elseif ok then ready.wakeAt = wake else ready.done = true error('vendor 任务异常: ' .. tostring(wake), 0) end
            elseif earliest ~= nil and earliest <= stop then time.value = earliest
            else time.value = stop break end
        end
    end
    local players = { list = {} }
    function players:GetPlayers()
        local out = {}
        for i, player in ipairs(self.list) do
            out[i] = { Character = tracer(player.Character) }
        end
        return out
    end
    local world = {}
    function world:GetServerTime() return time.value end
    function world:GetUnitRelationShip() return 1 end
    function world:CreateAsset(assetId)
        local script = { assetId = assetId, attrs = {}, tags = {}, children = {} }
        function script:SetAttribute(key, value) self.attrs[key] = value end
        function script:GetAttribute(key) return self.attrs[key] end
        function script:GetComponent() return nil end
        function script:GetChildren() return self.children end
        function script:Destroy() self.destroyed = true end
        return { script }
    end
    local envGame = { GetService = function(_, name)
        if name == 'Task' then return taskService end
        if name == 'World' then return world end
        if name == 'Players' then return players end
        if name == 'RunService' then return { IsServer = function() return false end } end
    end }
    local Env = {}
    local envMath = setmetatable({ Vector3 = Vector }, { __index = math })
    for key, value in pairs(_G) do Env[key] = value end
    Env.game = envGame
    Env.math = envMath
    Env.Enums = { ControllerStateType = { Moving = 'Moving' } }
    Env.print = print
    Env.os = os
    local function loadOne(name, path)
        path = path or MODULE_PATHS[name]
        assert(path ~= nil, '测试运行环境未登记模块 ' .. tostring(name))
        if loaded[name] ~= nil then return loaded[name] end
        local chunk = assert(loadfile(path, 't', Env))
        loaded[name] = true
        local value = chunk()
        loaded[name] = value == nil and true or value
        return loaded[name]
    end
    Env.require = loadOne
    Env.__stub_ability_api = nil
    local ai = loadOne('server.AiAPI', 'server/AiAPI.lua')
    return ai, {
        time = time, task = taskService, players = players, world = world,
        Vector = Vector, vecLen = vecLen, vecNorm = vecNorm, newUnit = newUnit,
        registry = loaded['common.packages.ability_system.registry'],
    }
end

return Loader
