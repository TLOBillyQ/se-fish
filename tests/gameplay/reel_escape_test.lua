-- #133 脱钩→收竿→可再抛竿。失败方式（先列后写）：
--   1. 收线到 0 脱钩后直接回到 idle（线还没收，玩家能立刻再抛竿）；
--   2. 脱钩时把鱼竿归位 / 生成活鱼 / 报「上岸」事实；
--   3. escaped 阶段按收竿不生效，或收竿后仍不能再次抛竿；
--   4. 死亡 / 离线打断走成 escaped，把「收竿」留给一个已经没线的玩家；
--   5. escaped 阶段重复收竿回包两次、或再次抛竿被受理。
local lu = require('luaunit')

TestReelEscape = {}

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

function TestReelEscape:setUp()
    local env = self
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3') }
    self.modules = {}
    for _, name in ipairs({ 'common.REUtil', 'server.Mgr.MgrPlayerData',
        'server.Mgr.MgrFishUnit' }) do
        self.modules[name] = package.loaded[name]
    end
    self.now, self.events, self.messages, self.spawned, self.facts = 0, {}, {}, {}, {}
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
    function self.data:RestoreSlot(index) self.Data.SelectedSlot = index return true end
    package.loaded['server.Mgr.MgrPlayerData'] = {
        GetDataInst = function(_, player) return player == env.player and env.data or nil end,
        SendItemBar = function() end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = {
        CanCast = function() return true end,
        HeldInfo = function() end,
        SpawnLanded = function(_, player, opts)
            env.spawned[#env.spawned + 1] = opts
            return { Id = #env.spawned }
        end,
    }
    self.reel = assert(loadfile('server/Mgr/MgrReelIn.lua'))()
    self.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    self.cast.ReelIn = self.reel
    self.reel.Cast = self.cast
    self.cast.Quest = { Notify = function(_, kind, _, payload)
        env.facts[#env.facts + 1] = { kind = kind, eventId = payload.eventId }
        return true
    end }
    self.reel:Start()
    self.cast:Start()
    self.player = { UserId = 7, messages = {}, Character = { Position = vec(-11.75, 2, 22.75),
        Rotation = { GetForward = function() return vec(0, 0, 1) end },
        Animator = { LoadAnimation = function() return { Play = function() end } end } } }
    self.reel:OnPlayerAdded(self.player)
end

function TestReelEscape:tearDown()
    self.reel:Stop()
    self.cast:Stop()
    for name, value in pairs(self.modules) do package.loaded[name] = value end
    for _, name in ipairs({ 'common.REUtil', 'server.Mgr.MgrPlayerData',
        'server.Mgr.MgrFishUnit' }) do
        if not self.modules[name] then package.loaded[name] = nil end
    end
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
end

-- 直接摆一个已上钩的会话，省掉抛竿与抽签
function TestReelEscape:hook(fishId, mult)
    local id = 'r' .. tostring(#self.spawned) .. ':' .. tostring(self.now)
    self.cast.Sessions[self.player.UserId] = { player = self.player, session = {
        phase = 'hooked', fishId = fishId, mult = mult, reelSession = id, reelSerial = 1, slot = 1,
    } }
    lu.assertTrue(self.reel:Begin(self.player, id, self.now))
    return id
end

function TestReelEscape:lastState()
    local last
    for _, message in ipairs(self.player.messages) do
        if message.name == 'CastState' then last = message.value end
    end
    return last
end

function TestReelEscape:test_progress_zero_leaves_the_line_out_until_reeled()
    local id = self:hook('bass', 1.2)
    self.data.Data.SelectedSlot = nil
    self.now = 30
    self.reel:Update()
    local current = self.cast.Sessions[self.player.UserId]
    lu.assertNotNil(current, '脱钩后会话不该被清掉：线还在水里')
    lu.assertEquals(current.session.phase, 'escaped')
    lu.assertEquals(self:lastState().phase, 'escaped')
    lu.assertNil(self.reel.Sessions[self.player.UserId])
    lu.assertEquals(#self.spawned, 0)
    lu.assertNil(self.data.Data.SelectedSlot)
    lu.assertEquals(#self.facts, 0)
    lu.assertEquals(id, current.session.reelSession)
end

function TestReelEscape:test_escaped_blocks_casting_until_reeled_back()
    self:hook('bass', 1.2)
    self.now = 30
    self.reel:Update()
    lu.assertEquals(self.cast.Sessions[self.player.UserId].session.phase, 'escaped')
    self.events.CastAction.OnServerEvent:Fire(self.player, {
        action = 'Cast', slot = 1, itemId = 'starterRod' })
    lu.assertEquals(self:lastState().result.reason, 'alreadyCasting')
    lu.assertEquals(self.cast.Sessions[self.player.UserId].session.phase, 'escaped')
    lu.assertEquals(#self.spawned, 0)
end

function TestReelEscape:test_reel_back_returns_to_idle_and_allows_casting_again()
    self:hook('bass', 1.2)
    self.now = 30
    self.reel:Update()
    self.events.CastAction.OnServerEvent:Fire(self.player, { action = 'Reel' })
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(self:lastState().phase, 'idle')
    local sent = #self.player.messages
    self.events.CastAction.OnServerEvent:Fire(self.player, { action = 'Reel' })
    lu.assertEquals(#self.player.messages, sent)
    self.now = 31
    self.events.CastAction.OnServerEvent:Fire(self.player, {
        action = 'Cast', slot = 1, itemId = 'starterRod' })
    local current = self.cast.Sessions[self.player.UserId]
    lu.assertNotNil(current)
    lu.assertEquals(current.session.phase, 'cast')
    lu.assertEquals(self:lastState().phase, 'cast')
end
