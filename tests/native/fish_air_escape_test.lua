-- #84 迁移：空中鱼逃脱与入水回收（原 tests/gameplay/fish_air_escape_test.lua，4 例）。
-- 接缝：真实 MgrFishCarrier / MgrFishUnit / MgrLoot 只换引擎对象与时间——空中鱼 1 秒内不销毁、
-- 朝最近水区直线逃脱、3 秒重定向、重复放下幂等、入水回收本体与受击体且不产鱼获、1 秒后可击杀且只掉一份。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local Cfg = require('common.GameCfg')
local WaterJudge = require('common.MathWaterJudge')

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

-- 夹具：本用例自己重建三块管理器，收尾恢复引擎全局与模块缓存。
-- Busted 把案例体放在沙箱 _ENV 里（写全局只进 context.env），业务模块用的是真 _G，
-- 因此引擎全局必须显式写 _G.xxx；Color 也自建桩，不依赖旧套件里的残留。
local FishAirEscape = {}

function FishAirEscape:setUp()
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        Quaternion = rawget(_G, 'Quaternion'), Color = rawget(_G, 'Color') }
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
    _G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
    _G.Quaternion = { FromEulerAngles = function()
        return { GetForward = function() return vec(0, 0, 1) end }
    end }
    -- #102 现场同步：合同安全点移到区内侧（离本区水岸线 62.5 米），而本文件的时序是按「起点在水岸线外
    -- 32 米」调的（1.05 秒仍在岸上、5 秒后飞进水面被回收），所以起点按本区水岸线自己取，不借 SafePoint。
    local water = Cfg.Zones[6].Scene.Waters[1]
    local startZ = water.Center.z - (water.HalfZ + 32)
    self.player = { UserId = 5701, Character = {
        Position = vec(water.Center.x, Cfg.Zones[6].Scene.SafePoint.y, startZ), Rotation = _G.Quaternion.FromEulerAngles(0, 0, 0),
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

function FishAirEscape:tearDown()
    -- 即使 setUp 只走到一半也要恢复进程状态：先清鱼与停管理器，再回滚全局与模块缓存。
    if self.mgr then
        for _, fish in pairs(self.mgr.Fish) do self.mgr:Remove(fish) end
        self.mgr:Stop()
    end
    for _, name in ipairs(MODULES) do package.loaded[name] = self.modules[name] end
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.Quaternion = self.saved.Quaternion
    _G.Color = self.saved.Color
end

-- 放下鱼：落地后举起再松手，返回空中鱼
function FishAirEscape:drop(id)
    local fish = assert(self.mgr:SpawnLanded(self.player, { fishId = id, mult = 1.57 },
        self.player.Character.Position))
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    assert.is_true(self.mgr:Drop(self.player))
    return fish
end

-- 假引擎只模拟 Kinematic 速度积分；逃脱决策及入水回收全部经过真实 Update。
function FishAirEscape:advance(to)
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

describe('TestFishAirEscape', function()
    local env

    before_each(function()
        env = setmetatable({}, { __index = FishAirEscape })
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_air_fish_rehead_after_three_seconds_and_release_is_idempotent', function()
        local fish = env:drop('item87')
        local body = fish.Carrier.Body
        local escapeAt = fish.EscapeAt
        env:advance(1.05)
        body.OnLiftedEnd:Fire()
        assert.is_false(env.mgr:Release(fish, 'drop'))
        assert.are.equal(escapeAt, fish.EscapeAt)
        -- 挪到礁石岛水区北侧：到三秒整点后应由朝北改为朝南。
        body.Position = vec(480, body.Position.y, 390)
        env.now = 2.95
        env.mgr:Update()
        assert.is_true(body.LinearVelocity.z > 0)
        env.now = 3.05
        env.mgr:Update()
        assert.near(-Cfg.Fish.item87.Speed, body.LinearVelocity.z, 1e-6)
    end)

    it('test_all_normal_and_rare_air_fish_survive_one_second_then_escape_without_loot', function()
        for _, id in ipairs(AIR_IDS) do
            local fish = env:drop(id)
            local body, receiver = fish.Carrier.Body, fish.Carrier.Receiver
            local start = body.Position
            env:advance(env.now + 1.05)
            assert.same(fish, env.mgr.Fish[fish.Id], id)
            assert.is_false(body.Destroyed == true, id)
            assert.is_false(receiver.Destroyed == true, id)
            assert.are.equal('escaping', fish.State, id)
            assert.is_nil(fish.FleeAt, id)
            assert.is_nil(fish.Flight, id)
            assert.near(Cfg.Fish[id].Speed * 1.05, body.Position.z - start.z, 1e-6, id)
            assert.near(0, body.LinearVelocity.x, 1e-6, id)
            assert.is_true(body.LinearVelocity.z > 0, id)
            assert.is_nil(WaterJudge.HitZone(Cfg.Water.Zones,
                { x = body.Position.x, y = 2, z = body.Position.z }), id)
            assert.same(body.Position, receiver.Position, id)
            assert.are.equal(Cfg.Fish[id].Health, receiver.Controller.Health, id)
            env:advance(env.now + 5)
            assert.is_nil(env.mgr.Fish[fish.Id], id)
            assert.is_true(body.Destroyed, id)
            assert.is_true(receiver.Destroyed, id)
            assert.is_nil(fish.Carrier.Receiver, id)
            assert.is_nil(env.carrier.Carriers[body.UnitId], id)
            assert.is_nil(next(env.loot.Loots), id)
            assert.is_nil(env.mgr:TakeKilled(fish), id)
        end
    end)

    it('test_kill_after_one_second_keeps_correct_loot_once_and_cleans_receiver', function()
        for _, id in ipairs({ 'item81', 'item87' }) do
            local fish = env:drop(id)
            local body, receiver = fish.Carrier.Body, fish.Carrier.Receiver
            local controller = receiver.Controller
            env:advance(env.now + 1.05)
            controller:TakeDamage(Cfg.Fish[id].Health)
            controller.Died:Fire()
            env.carrier:NotifyDied(fish.Carrier)
            local found = {}
            for _, loot in pairs(env.loot.Loots) do
                if loot.FishId == id then found[#found + 1] = loot end
            end
            assert.are.equal(1, #found, id)
            assert.same({ id, 1.57 }, { found[1].ItemId, found[1].Mult }, id)
            assert.are.equal(body.Position.x, found[1].Position.x, id)
            assert.are.equal(body.Position.z, found[1].Position.z, id)
            assert.is_true(body.Destroyed, id)
            assert.is_true(receiver.Destroyed, id)
            assert.is_nil(env.mgr.Fish[fish.Id], id)
        end
    end)

    it('test_special_flight_lifetimes_and_ground_fish_remain_unchanged', function()
        for _, id in ipairs({ 'fish47Elite', 'fish48Boss', 'fish55Elite' }) do
            local fish = env:drop(id)
            local deadline = env.now + Cfg.Fish[id].EscapeSec
            assert.are.equal('flying', fish.State, id)
            assert.are.equal(deadline, fish.FleeAt, id)
            env.now = deadline - 0.05
            env.mgr:Update()
            assert.same(fish, env.mgr.Fish[fish.Id], id)
            assert.are.equal('flying', fish.State, id)
            env.now = deadline
            env.mgr:Update()
            assert.same(fish, env.mgr.Fish[fish.Id], id)
            assert.are.equal('escaping', fish.State, id)
            env.mgr:Remove(fish)
        end
        local ground = env:drop('item82')
        assert.are.equal('escaping', ground.State)
        assert.is_nil(ground.FleeAt)
        env.mgr:Remove(ground)
        local wild = assert(env.mgr:SpawnBlastFish('item81', 1.57, env.player.Character.Position, env.player))
        env.now = wild.WildUntil
        env.mgr:Update()
        assert.is_nil(env.mgr.Fish[wild.Id])
        assert.is_nil(next(env.loot.Loots))
    end)
end)
