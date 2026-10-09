-- #57 管理器独立回归：只替换引擎对象与时间，使用真实鱼种、水区、载体及鱼获消费者。
-- 失败方式（实现前列出）：
-- 1. 普通/极品空中鱼一秒后尚未入水就销毁，或仍在巡航而不朝最近水区逃脱。
-- 2. 速度不取鱼种配置、三秒不重新对准水区，或重复放下改变逃脱起点。
-- 3. 入水未回收本体/受击体，或逃脱产生鱼获。
-- 4. 一秒后无法受击、击杀丢失鱼种/个体倍率，或重复死亡产生多份鱼获。
-- 5. 地面鱼、精英/首领飞行时限、沧龙跃起或爆炸保底鱼的生命周期改变。
local lu = require('luaunit')
local Cfg = require('common.GameCfg')
local WaterJudge = require('common.MathWaterJudge')

TestFishAirEscape = {}
local AIR_IDS = { 'item81', 'item83', 'item84', 'item85', 'item86',
    'item87', 'item89', 'item90', 'item91', 'item92' }
local MODULES = { 'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit', 'server.Mgr.MgrLoot' }

local function signal()
    local slots = {}
    return {
        Connect = function(_, fn)
            slots[fn] = true
            return { Disconnect = function() slots[fn] = nil end }
        end,
        Fire = function(_, ...)
            local copy = {}
            for fn in pairs(slots) do copy[#copy + 1] = fn end
            for _, fn in ipairs(copy) do if slots[fn] then fn(...) end end
        end,
    }
end

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

function TestFishAirEscape:setUp()
    self.saved = { game = _G.game, Vector3 = _G.Vector3, Quaternion = _G.Quaternion }
    self.modules = {}
    for _, name in ipairs(MODULES) do
        self.modules[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    self.now, self.units = 0, {}
    local env = self
    self.world = {
        GetServerTime = function() return env.now end,
        CreateUnit = function(_, kind, values)
            local unit = { UnitId = #env.units + 1, UnitType = kind,
                OnLiftedBegin = signal(), OnLiftedEnd = signal(), LinearVelocity = vec(0, 0, 0) }
            for k, v in pairs(values) do unit[k] = v end
            env.units[#env.units + 1] = unit
            function unit:Destroy()
                self.Destroyed = true
                for _, child in ipairs(env.units) do
                    if child.Parent == self and not child.Destroyed then child:Destroy() end
                end
            end
            function unit:AddNoCollisionPairWithUnit() end
            function unit:SetPosition(pos) self.Position = pos end
            if values.EnableController then
                unit.Controller = { Health = 100, HealthChanged = signal(), Died = signal() }
                function unit.Controller:TakeDamage(amount)
                    self.Health = math.max(0, self.Health - amount)
                    self.HealthChanged:Fire()
                    if self.Health == 0 then self.Died:Fire() end
                end
            end
            return unit
        end,
    }
    _G.Vector3 = { New = vec }
    _G.Quaternion = { FromEulerAngles = function()
        return { GetForward = function() return vec(0, 0, 1) end }
    end }
    local safe = Cfg.Zones[6].Scene.SafePoint
    self.player = { UserId = 5701, Character = {
        Position = vec(safe.x, safe.y, safe.z), Rotation = Quaternion.FromEulerAngles(0, 0, 0),
        Controller = { Lift = function() end },
    } }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return env.world end
        if name == 'Players' then return { GetPlayers = function() return { env.player } end } end
    end }
    self.carrier = require('server.Mgr.MgrFishCarrier')
    self.carrier.DamagePublisher = function() end
    self.mgr = require('server.Mgr.MgrFishUnit')
    self.mgr:Start()
    self.loot = require('server.Mgr.MgrLoot')
    self.loot.FishUnit = self.mgr
    self.loot.Broadcast = function() end
    self.carrier:SubscribeDied(function(carrier) self.loot:OnCarrierDied(carrier) end)
end

function TestFishAirEscape:tearDown()
    for _, fish in pairs(self.mgr.Fish) do self.mgr:Remove(fish) end
    self.mgr:Stop()
    for _, name in ipairs(MODULES) do package.loaded[name] = self.modules[name] end
    for _, name in ipairs({ 'game', 'Vector3', 'Quaternion' }) do _G[name] = self.saved[name] end
end

function TestFishAirEscape:drop(id)
    local fish = assert(self.mgr:SpawnLanded(self.player, { fishId = id, mult = 1.57 },
        self.player.Character.Position))
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    lu.assertTrue(self.mgr:Drop(self.player))
    return fish
end

-- 假引擎只模拟 Kinematic 速度积分；逃脱决策及入水回收全部经过真实 Update。
function TestFishAirEscape:advance(to)
    while self.now < to - 1e-8 do
        local dt = math.min(0.05, to - self.now)
        for _, fish in pairs(self.mgr.Fish) do
            if fish.State == 'escaping' then
                local body = fish.Carrier.Body
                local p, v = body.Position, body.LinearVelocity
                body.Position = vec(p.x + v.x * dt, p.y + v.y * dt, p.z + v.z * dt)
            end
        end
        self.now = self.now + dt
        self.mgr:Update()
        self.carrier:Update()
    end
end

function TestFishAirEscape:test_all_normal_and_rare_air_fish_survive_one_second_then_escape_without_loot()
    for _, id in ipairs(AIR_IDS) do
        local fish = self:drop(id)
        local body, receiver = fish.Carrier.Body, fish.Carrier.Receiver
        local start = body.Position
        self:advance(self.now + 1.05)
        lu.assertEquals(self.mgr.Fish[fish.Id], fish, id)
        lu.assertFalse(body.Destroyed == true, id)
        lu.assertFalse(receiver.Destroyed == true, id)
        lu.assertEquals(fish.State, 'escaping', id)
        lu.assertNil(fish.FleeAt, id)
        lu.assertNil(fish.Flight, id)
        lu.assertAlmostEquals(body.Position.z - start.z, Cfg.Fish[id].Speed * 1.05, 1e-6, id)
        lu.assertAlmostEquals(body.LinearVelocity.x, 0, 1e-6, id)
        lu.assertTrue(body.LinearVelocity.z > 0, id)
        lu.assertNil(WaterJudge.HitZone(Cfg.Water.Zones,
            { x = body.Position.x, y = 2, z = body.Position.z }), id)
        lu.assertEquals(receiver.Position, body.Position, id)
        lu.assertEquals(receiver.Controller.Health, Cfg.Fish[id].Health, id)
        self:advance(self.now + 5)
        lu.assertNil(self.mgr.Fish[fish.Id], id)
        lu.assertTrue(body.Destroyed, id)
        lu.assertTrue(receiver.Destroyed, id)
        lu.assertNil(fish.Carrier.Receiver, id)
        lu.assertNil(self.carrier.Carriers[body.UnitId], id)
        lu.assertNil(next(self.loot.Loots), id)
        lu.assertNil(self.mgr:TakeKilled(fish), id)
    end
end

function TestFishAirEscape:test_air_fish_rehead_after_three_seconds_and_release_is_idempotent()
    local fish = self:drop('item87')
    local body = fish.Carrier.Body
    local escapeAt = fish.EscapeAt
    self:advance(1.05)
    body.OnLiftedEnd:Fire()
    lu.assertFalse(self.mgr:Release(fish, 'drop'))
    lu.assertEquals(fish.EscapeAt, escapeAt)
    -- 挪到礁石岛水区北侧：到三秒整点后应由朝北改为朝南。
    body.Position = vec(880, body.Position.y, 170)
    self.now = 2.95
    self.mgr:Update()
    lu.assertTrue(body.LinearVelocity.z > 0)
    self.now = 3.05
    self.mgr:Update()
    lu.assertAlmostEquals(body.LinearVelocity.z, -Cfg.Fish.item87.Speed, 1e-6)
end

function TestFishAirEscape:test_kill_after_one_second_keeps_correct_loot_once_and_cleans_receiver()
    for _, id in ipairs({ 'item81', 'item87' }) do
        local fish = self:drop(id)
        local body, receiver = fish.Carrier.Body, fish.Carrier.Receiver
        local controller = receiver.Controller
        self:advance(self.now + 1.05)
        controller:TakeDamage(Cfg.Fish[id].Health)
        controller.Died:Fire()
        self.carrier:NotifyDied(fish.Carrier)
        local found = {}
        for _, loot in pairs(self.loot.Loots) do
            if loot.FishId == id then found[#found + 1] = loot end
        end
        lu.assertEquals(#found, 1, id)
        lu.assertEquals({ found[1].ItemId, found[1].Mult }, { id, 1.57 }, id)
        lu.assertEquals(found[1].Position.x, body.Position.x, id)
        lu.assertEquals(found[1].Position.z, body.Position.z, id)
        lu.assertTrue(body.Destroyed, id)
        lu.assertTrue(receiver.Destroyed, id)
        lu.assertNil(self.mgr.Fish[fish.Id], id)
    end
end

function TestFishAirEscape:test_special_flight_lifetimes_and_ground_fish_remain_unchanged()
    for _, id in ipairs({ 'fish47Elite', 'fish48Boss', 'fish55Elite' }) do
        local fish = self:drop(id)
        local deadline = self.now + Cfg.Fish[id].EscapeSec
        lu.assertEquals(fish.State, 'flying', id)
        lu.assertEquals(fish.FleeAt, deadline, id)
        self.now = deadline - 0.05
        self.mgr:Update()
        lu.assertEquals(self.mgr.Fish[fish.Id], fish, id)
        lu.assertEquals(fish.State, 'flying', id)
        self.now = deadline
        self.mgr:Update()
        lu.assertEquals(self.mgr.Fish[fish.Id], fish, id)
        lu.assertEquals(fish.State, 'escaping', id)
        self.mgr:Remove(fish)
    end
    local ground = self:drop('item82')
    lu.assertEquals(ground.State, 'escaping')
    lu.assertNil(ground.FleeAt)
    self.mgr:Remove(ground)
    local wild = assert(self.mgr:SpawnBlastFish('item81', 1.57, self.player.Character.Position, self.player))
    self.now = wild.WildUntil
    self.mgr:Update()
    lu.assertNil(self.mgr.Fish[wild.Id])
    lu.assertNil(next(self.loot.Loots))
end
