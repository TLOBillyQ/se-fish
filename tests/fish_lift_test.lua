-- #41 上岸自动举鱼与稳定搬运：上岸生成的活鱼由服务端原生抓举，挂到角色头顶挂点。
-- 失败方式（先列后写）：
--   1. 上岸后不发起抓举，或一次上岸调两次 Lift（Lift 是占用语义，第二次会把鱼放开）；
--   2. 手上已有鱼时仍调 Lift，或举着鱼还能抛竿 / 再上岸出第二条被抓；
--   3. OnLiftedBegin 不建挂点、挂点参数不对（origin / (0,1.9,0) / Parent=角色）、鱼没挂进挂点；
--   4. 重复 OnLiftedBegin 建第二个挂点或改掉持有者；
--   5. 抓举期间把鱼切回 Dynamic；
--   6. 抓举没确认就立刻重试（迟到的回调会被二次 Lift 放开），或无限重试；
--   7. 待抓的鱼漂移 / NaN 不回位，重力没关；
--   8. 碰撞隔离漏掉玩家、受击体或其他鱼，或受击体仍可被抓举；
--   9. 举起后鱼种 / 个体倍率丢失，客户端状态不带持有信息；
--  10. 主人离线后举着的鱼与挂点残留。
local lu = require('luaunit')

TestFishLift = {}

local function signal()
    local slots = {}
    return {
        Connect = function(_, fn)
            slots[#slots + 1] = fn
            return { Disconnect = function()
                for i, f in ipairs(slots) do if f == fn then table.remove(slots, i) break end end
            end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(slots) do fn(...) end end,
        Count = function() return #slots end,
    }
end

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

function TestFishLift:setUp()
    local env = self
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        RaycastParams = rawget(_G, 'RaycastParams') }
    self.modules = {}
    for _, name in ipairs({ 'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }) do
        self.modules[name] = package.loaded[name]
    end
    self.now = 0
    self.created = {}
    self.spawned = {}
    self.despawned = {}
    self.lifts = {}
    _G.Vector3 = { New = vec }
    self.world = {
        GetServerTime = function() return env.now end,
        CreateUnit = function(_, unitType, values)
            local unit = { UnitType = unitType, Destroyed = false }
            for k, v in pairs(values) do unit[k] = v end
            function unit:Destroy() self.Destroyed = true end
            env.created[#env.created + 1] = unit
            return unit
        end,
    }
    self.players = {}
    _G.game = { GetService = function(_, name)
        if name == 'World' then return env.world end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end }
    local nextUnit = 0
    local function body(position)
        nextUnit = nextUnit + 1
        local unit = { UnitId = nextUnit, Position = position, BodyType = 4, Parent = nil, Pairs = {},
            LinearVelocity = vec(0, 0, 0), AngularVelocity = vec(0, 0, 0),
            OnLiftedBegin = signal(), OnLiftedEnd = signal() }
        function unit:AddNoCollisionPairWithUnit(other) self.Pairs[other] = true end
        return unit
    end
    package.loaded['server.Mgr.MgrFishCarrier'] = {
        Spawn = function(_, opts)
            local carrier = { Opts = opts, Body = body(opts.Position),
                Receiver = { UnitId = 'r' .. tostring(#env.spawned + 1), Controller = { LiftedEnabled = true } } }
            env.spawned[#env.spawned + 1] = carrier
            return carrier
        end,
        Despawn = function(_, carrier) env.despawned[#env.despawned + 1] = carrier end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = nil
    self.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    self.pushed = {}
    self.mgr.Cast = { PushState = function(_, player) env.pushed[#env.pushed + 1] = player end }
    self.mgr:Start()
    self.player = self:newPlayer(7, vec(10, 2, 20))
    self.other = self:newPlayer(8, vec(30, 2, 20))
end

function TestFishLift:newPlayer(id, position)
    local env = self
    local character
    character = { Position = position, Rotation = { GetForward = function() return vec(0, 0, 1) end },
        Controller = { Died = signal(), Lift = function()
            env.lifts[#env.lifts + 1] = character
        end } }
    local player = { UserId = id, Character = character, CharacterAdded = signal(), CharacterRemoving = signal() }
    self.players[#self.players + 1] = player
    self.mgr:OnPlayerAdded(player)
    return player
end

function TestFishLift:tearDown()
    self.mgr:Stop()
    for name, value in pairs(self.modules) do package.loaded[name] = value end
    for _, name in ipairs({ 'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }) do
        if not self.modules[name] then package.loaded[name] = nil end
    end
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.RaycastParams = self.saved.RaycastParams
end

function TestFishLift:land(player, fishId, mult)
    local c = player.Character.Position
    return self.mgr:SpawnLanded(player, { fishId = fishId or 'bass', mult = mult or 1.37 }, vec(c.x, c.y, c.z + 2))
end

function TestFishLift:mounts()
    local list = {}
    for _, unit in ipairs(self.created) do
        if unit.UnitType == 'SkeletalSocketMount' then list[#list + 1] = unit end
    end
    return list
end

function TestFishLift:test_landing_lifts_once_and_mounts_on_head()
    local fish = self:land(self.player)
    lu.assertEquals(#self.lifts, 1)
    lu.assertEquals(self.lifts[1], self.player.Character)
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    fish.Carrier.Body.BodyType = 2
    lu.assertEquals(fish.State, 'held')
    lu.assertEquals(self.mgr:GetHeld(self.player), fish)
    local mounts = self:mounts()
    lu.assertEquals(#mounts, 1)
    lu.assertEquals(mounts[1].SocketName, 'origin')
    lu.assertEquals(mounts[1].Parent, self.player.Character)
    lu.assertAlmostEquals(mounts[1].SocketOffset.y, 1.9, 1e-9)
    lu.assertEquals(mounts[1].SocketOffset.x, 0)
    lu.assertEquals(fish.Carrier.Body.Parent, mounts[1])
    self.now = 5
    self.mgr:Update()
    lu.assertEquals(fish.Carrier.Body.BodyType, 2)
    lu.assertEquals(#self.lifts, 1)
end

function TestFishLift:test_duplicate_lifted_begin_keeps_one_mount_and_holder()
    local fish = self:land(self.player)
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    fish.Carrier.Body.OnLiftedBegin:Fire(self.other.Character)
    lu.assertEquals(#self:mounts(), 1)
    lu.assertEquals(fish.Holder, self.player)
    lu.assertNil(self.mgr:GetHeld(self.other))
end

function TestFishLift:test_lifted_begin_without_argument_uses_pending_lifter()
    local fish = self:land(self.player)
    fish.Carrier.Body.OnLiftedBegin:Fire()
    lu.assertEquals(fish.Holder, self.player)
end

function TestFishLift:test_holding_blocks_new_lift_and_cast()
    local fish = self:land(self.player)
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    local second = self:land(self.player, 'carp', 1.1)
    lu.assertEquals(#self.lifts, 1)
    lu.assertEquals(second.State, 'awaitLift')
    self.now = 10
    self.mgr:Update()
    lu.assertEquals(#self.lifts, 1)
    lu.assertFalse(self.mgr:CanCast(self.player))
    lu.assertTrue(self.mgr:CanCast(self.other))
end

function TestFishLift:test_unconfirmed_lift_retries_after_confirm_window_with_cap()
    local fish = self:land(self.player)
    self.now = 0.3
    self.mgr:Update()
    lu.assertEquals(#self.lifts, 1)
    for step = 1, 40 do
        self.now = 0.3 + step * 0.5
        self.mgr:Update()
    end
    lu.assertEquals(#self.lifts, 3)
    lu.assertEquals(fish.State, 'awaitLift')
end

function TestFishLift:test_waiting_fish_is_held_still_and_nan_is_reset()
    local fish = self:land(self.player)
    local body = fish.Carrier.Body
    lu.assertFalse(fish.Carrier.Opts.GravityEnabled)
    local anchor = body.Position
    body.Position = vec(anchor.x + 0.4, anchor.y - 0.3, anchor.z)
    body.LinearVelocity = vec(1, 0, 0)
    self.mgr:Update()
    lu.assertAlmostEquals(body.Position.x, anchor.x, 1e-9)
    lu.assertAlmostEquals(body.Position.y, anchor.y, 1e-9)
    lu.assertEquals(body.LinearVelocity.x, 0)
    body.Position = vec(0 / 0, 1, 1)
    self.mgr:Update()
    lu.assertAlmostEquals(body.Position.z, anchor.z, 1e-9)
end

function TestFishLift:test_collision_isolation_covers_players_receivers_and_other_fish()
    local first = self:land(self.player)
    local second = self:land(self.other, 'carp', 1.2)
    local a, b = first.Carrier, second.Carrier
    lu.assertTrue(b.Body.Pairs[self.player.Character])
    lu.assertTrue(b.Body.Pairs[self.other.Character])
    lu.assertTrue(b.Body.Pairs[a.Body] or a.Body.Pairs[b.Body])
    lu.assertTrue(b.Body.Pairs[a.Receiver])
    lu.assertTrue(a.Body.Pairs[b.Receiver])
    lu.assertFalse(a.Receiver.Controller.LiftedEnabled)
    local late = self:newPlayer(9, vec(0, 2, 0))
    lu.assertTrue(a.Body.Pairs[late.Character])
    local respawned = { Position = vec(0, 2, 0), Controller = {} }
    late.Character = respawned
    late.CharacterAdded:Fire(respawned)
    lu.assertTrue(a.Body.Pairs[respawned])
end

function TestFishLift:test_held_info_keeps_species_and_multiplier_and_pushes_state()
    local fish = self:land(self.player, 'goldfish', 1.85)
    lu.assertNil(self.mgr:HeldInfo(self.player))
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    lu.assertEquals(self.mgr:HeldInfo(self.player), { fishId = 'goldfish', mult = 1.85 })
    lu.assertEquals(self.pushed[#self.pushed], self.player)
end

function TestFishLift:test_owner_leaving_removes_held_fish_and_mount()
    local fish = self:land(self.player)
    fish.Carrier.Body.OnLiftedBegin:Fire(self.player.Character)
    self.mgr:OnPlayerRemoving(self.player)
    lu.assertNil(self.mgr:GetHeld(self.player))
    lu.assertEquals(#self.despawned, 1)
    lu.assertTrue(self:mounts()[1].Destroyed)
    self.mgr:Update()
end
