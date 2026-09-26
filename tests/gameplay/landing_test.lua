-- #37 上岸结算：收线到 100% 后只生成一条待举起的活鱼，交给活鱼单位管理器。
-- 失败方式（先列后写）：
--   1. 上岸不生成鱼，或重复批次 / 迟到消息 / 结束收线 / 再次结算生成第二条；
--   2. 脱钩、收竿也生成鱼；
--   3. 鱼种或个体倍率与上钩时不同，或鱼不在玩家正前方；
--   4. 重量 / 售价存成快照、或不是「基础值 × 倍率」；
--   5. 上岸后卡在 landed 不回 idle，上岸 / 脱钩后不回到选中鱼竿；
--   6. 上岸加金币，旧等级字段、旧鱼管理链仍在；
--   7. 鱼生成失败或玩家离线时会话残留。
local lu = require('luaunit')

TestLanding = {}

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            callbacks[#callbacks + 1] = fn
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end,
    }
end

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

function TestLanding:setUp()
    local env = self
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3') }
    self.modules = {}
    for _, name in ipairs({ 'common.REUtil', 'server.Mgr.MgrPlayerData',
        'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }) do
        self.modules[name] = package.loaded[name]
    end
    self.now = 0
    self.events = {}
    self.spawned = {}
    self.despawned = {}
    self.played = {}
    self.restored = {}
    self.sentBars = 0
    _G.Vector3 = { New = vec }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
    end }
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            if not env.events[name] then
                env.events[name] = { OnServerEvent = signal(), FireClient = function(_, player, value)
                    player.messages[#player.messages + 1] = { name = name, value = value }
                end }
            end
            return env.events[name]
        end,
        CheckRECD = function() return false end,
    }
    self.data = { Data = { SelectedSlot = 1, FishCoin = 0, Bait = { worm = 3 }, SelectedBait = 'worm',
        Containers = { itemBar = { [1] = { itemId = 'starterRod', count = 1, containerId = 'itemBar' } } } } }
    function self.data:ConsumeSelectedBait() return true, 'worm' end
    function self.data:RestoreSlot(index)
        env.restored[#env.restored + 1] = index
        self.Data.SelectedSlot = index
        return true
    end
    package.loaded['server.Mgr.MgrPlayerData'] = {
        GetDataInst = function(_, player) return player == env.player and env.data or nil end,
        SendItemBar = function() env.sentBars = env.sentBars + 1 end,
    }
    self.carrierOk = true
    package.loaded['server.Mgr.MgrFishCarrier'] = {
        Spawn = function(_, opts)
            if not env.carrierOk then return nil, 'body-create-failed' end
            local carrier = { Opts = opts, Body = { UnitId = #env.spawned + 1 } }
            env.spawned[#env.spawned + 1] = carrier
            return carrier
        end,
        Despawn = function(_, carrier) env.despawned[#env.despawned + 1] = carrier end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = nil
    self.fishUnit = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    package.loaded['server.Mgr.MgrFishUnit'] = self.fishUnit
    self.reel = assert(loadfile('server/Mgr/MgrReelIn.lua'))()
    self.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    self.cast.ReelIn = self.reel
    self.cast.FishUnit = self.fishUnit
    self.reel.Cast = self.cast
    self.reel:Start()
    self.cast:Start()
    local animator = { LoadAnimation = function(_, uri)
        return { Play = function() env.played[#env.played + 1] = uri end }
    end }
    self.player = { UserId = 7, messages = {}, CharacterAdded = signal(), CharacterRemoving = signal(),
        Character = { Position = vec(10, 2, 20), Animator = animator,
            Rotation = { GetForward = function() return vec(0, 0, 1) end } } }
    self.reel:OnPlayerAdded(self.player)
end

function TestLanding:tearDown()
    self.reel:Stop()
    self.cast:Stop()
    for name, value in pairs(self.modules) do package.loaded[name] = value end
    for _, name in ipairs({ 'common.REUtil', 'server.Mgr.MgrPlayerData',
        'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }) do
        if not self.modules[name] then package.loaded[name] = nil end
    end
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
end

-- 直接摆一个已上钩的会话，省掉抛竿与选鱼的随机
function TestLanding:hook(fishId, mult)
    local id = 'r' .. tostring(#self.spawned) .. ':' .. tostring(self.now)
    self.cast.Sessions[self.player.UserId] = { player = self.player, session = {
        phase = 'hooked', fishId = fishId, mult = mult, reelSession = id, slot = 1,
    } }
    lu.assertTrue(self.reel:Begin(self.player, id, self.now))
    return id
end

function TestLanding:reelIn(id, n, q)
    self.events.ReelInRE.OnServerEvent:Fire(self.player, { s = id, n = n, q = q })
end

function TestLanding:lastState()
    local last
    for _, message in ipairs(self.player.messages) do
        if message.name == 'CastState' then last = message.value end
    end
    return last
end

function TestLanding:test_landing_spawns_exactly_one_fish_with_hooked_parameters()
    local id = self:hook('bass', 1.37)
    self:reelIn(id, 10, 1)
    lu.assertEquals(#self.spawned, 1)
    local opts = self.spawned[1].Opts
    lu.assertEquals(opts.FishId, 'bass')
    lu.assertEquals(opts.Player, self.player)
    lu.assertEquals(opts.MaxHealth, 20)
    lu.assertEquals(self:lastState().phase, 'landed')
    local fish = self.fishUnit:GetFish(self.player)
    lu.assertEquals(#fish, 1)
    lu.assertEquals(fish[1].FishId, 'bass')
    lu.assertEquals(fish[1].Mult, 1.37)
    lu.assertEquals(fish[1].State, 'awaitLift')
    lu.assertEquals(self.played, { 'official://animation/24450' })
end

function TestLanding:test_fish_lands_in_front_of_player()
    local id = self:hook('carp', 1.5)
    self:reelIn(id, 10, 1)
    local pos = self.spawned[1].Opts.Position
    lu.assertAlmostEquals(pos.x, 10, 1e-6)
    lu.assertTrue(pos.z > 20 and pos.z <= 22.5)
    lu.assertTrue(pos.y >= 2)
end

function TestLanding:test_repeated_batches_late_close_and_second_finish_do_not_spawn_again()
    local id = self:hook('bass', 1.2)
    self:reelIn(id, 10, 1)
    self:reelIn(id, 10, 2)
    self.now = 0.3
    self:reelIn(id, 5, 3)
    self.reel:Close(self.player, { session = id })
    self.cast:FinishReel(self.player, id, 'landed')
    self.reel:Update()
    self.cast:Update()
    lu.assertEquals(#self.spawned, 1)
end

function TestLanding:test_unhook_and_manual_reel_spawn_nothing()
    local id = self:hook('bass', 1.2)
    self.now = 30
    self.reel:Update()
    lu.assertEquals(self:lastState().phase, 'idle')
    lu.assertEquals(#self.spawned, 0)
    local closed = self:hook('carp', 1.1)
    self.reel:Close(self.player, { session = closed })
    lu.assertEquals(#self.spawned, 0)
end

function TestLanding:test_landed_returns_to_idle_with_rod_selected_after_hold()
    local id = self:hook('goldfish', 2)
    self.data.Data.SelectedSlot = nil
    self:reelIn(id, 10, 1)
    self.now = 0.5
    self.cast:Update()
    lu.assertEquals(self:lastState().phase, 'landed')
    self.now = 5
    self.cast:Update()
    lu.assertEquals(self:lastState().phase, 'idle')
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(self.data.Data.SelectedSlot, 1)
    lu.assertTrue(self.sentBars >= 1)
    self.cast:Update()
    lu.assertEquals(#self.spawned, 1)
end

function TestLanding:test_unhook_restores_rod_selection()
    self:hook('bass', 1.2)
    self.data.Data.SelectedSlot = nil
    self.now = 30
    self.reel:Update()
    lu.assertEquals(self.data.Data.SelectedSlot, 1)
end

function TestLanding:test_landing_does_not_pay_coins()
    local id = self:hook('catfish', 1.9)
    self:reelIn(id, 10, 1)
    self.now = 5
    self.cast:Update()
    lu.assertEquals(self.data.Data.FishCoin, 0)
end

function TestLanding:test_spawn_failure_still_ends_session()
    self.carrierOk = false
    local id = self:hook('bass', 1.2)
    self:reelIn(id, 10, 1)
    lu.assertEquals(#self.fishUnit:GetFish(self.player), 0)
    self.now = 5
    self.cast:Update()
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(self:lastState().phase, 'idle')
end

function TestLanding:test_offline_during_landed_hold_clears_session_and_waiting_fish()
    local id = self:hook('bass', 1.2)
    self:reelIn(id, 10, 1)
    self.cast:OnPlayerRemoving(self.player)
    self.fishUnit:OnPlayerRemoving(self.player)
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(#self.fishUnit:GetFish(self.player), 0)
    lu.assertEquals(#self.despawned, 1)
    self.now = 5
    self.cast:Update()
end

function TestLanding:test_weight_and_price_derive_from_species_and_multiplier()
    local id = self:hook('goldfish', 1.15)
    self:reelIn(id, 10, 1)
    local fish = self.fishUnit:GetFish(self.player)[1]
    lu.assertNil(fish.Weight)
    lu.assertNil(fish.Price)
    lu.assertEquals(self.fishUnit:Weight(fish), 0.12)
    lu.assertEquals(self.fishUnit:Price(fish), 9)
    fish.Mult = 2
    lu.assertEquals(self.fishUnit:Weight(fish), 0.2)
    lu.assertEquals(self.fishUnit:Price(fish), 16)
end

TestLandingRetired = {}

local function read(path)
    local file = io.open(path, 'r')
    if not file then return nil end
    local text = file:read('*a')
    file:close()
    return text
end

function TestLandingRetired:test_fish_unit_is_registered()
    lu.assertStrContains(read('server/main.lua'), 'MgrFishUnit = require')
end

function TestLandingRetired:test_every_catchable_fish_has_species_values()
    local cfg = assert(loadfile('common/GameCfg.lua'))()
    for zone, rows in pairs(cfg.Casting.Zones) do
        for _, row in ipairs(rows) do
            local species = cfg.Fish[row.Id]
            lu.assertNotNil(species, zone .. ' 的 ' .. row.Id .. ' 没有鱼种配置')
            lu.assertTrue(species.BaseWeight > 0 and species.Health > 0, row.Id)
            lu.assertTrue(species.BasePrice > 0 or species.Drops ~= nil, row.Id)
            lu.assertNotNil(cfg.FishCarrier.Models[species.Model], row.Id .. ' 的模型号不在鱼载体表里')
        end
    end
    lu.assertEquals(cfg.Items.Definitions.starterRod.Level, 1)
end

-- #52 新手任务事实（失败方式 8. 陆地抛竿冒充「水边抛竿」、每次落水不带唯一 eventId；
--   9. 脱钩 / 收竿也报「上岸」，或一次上岸报两次）
function TestLanding:spyQuest()
    local env = self
    env.facts = {}
    self.cast.Quest = { Notify = function(_, kind, player, payload)
        env.facts[#env.facts + 1] = { kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId }
        return true
    end }
end

function TestLanding:test_cast_into_water_notifies_each_cast_and_land_cast_does_not()
    self:spyQuest()
    self.player.Character.Position = vec(10, 2, 20)
    self.cast:Cast(self.player, { slot = 1, itemId = 'starterRod' })
    lu.assertNil(self.cast.Sessions[self.player.UserId].session.zoneId)
    lu.assertEquals(#self.facts, 0)
    self.cast:Reel(self.player)
    self.player.Character.Position = vec(-11.75, 2, 22.75)
    self.cast:Cast(self.player, { slot = 1, itemId = 'starterRod' })
    lu.assertNotNil(self.cast.Sessions[self.player.UserId].session.zoneId)
    self.cast:Reel(self.player)
    self.cast:Cast(self.player, { slot = 1, itemId = 'starterRod' })
    lu.assertEquals(#self.facts, 2)
    lu.assertEquals(self.facts[1].kind, 'CastWater')
    lu.assertEquals(self.facts[1].player, self.player)
    lu.assertNotNil(self.facts[1].eventId)
    lu.assertNotEquals(self.facts[1].eventId, self.facts[2].eventId)
end

function TestLanding:test_landed_notifies_land_once_and_unhook_does_not()
    self:spyQuest()
    local lost = self:hook('carp', 1.1)
    self.now = 30
    self.reel:Update()
    lu.assertEquals(#self.facts, 0)
    local id = self:hook('bass', 1.2)
    self:reelIn(id, 10, 1)
    self.cast:FinishReel(self.player, id, 'landed')
    lu.assertEquals(#self.facts, 1)
    lu.assertEquals(self.facts[1].kind, 'Land')
    lu.assertEquals(self.facts[1].itemId, 'bass')
    lu.assertEquals(self.facts[1].player, self.player)
    lu.assertTrue(tostring(self.facts[1].eventId):find(id, 1, true) ~= nil)
    lu.assertNotEquals(lost, id)
end
