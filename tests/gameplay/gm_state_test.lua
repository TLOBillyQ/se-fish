-- #115 外部接缝：GM 请求、玩家快照、存档键值及异步结果。
-- 失败方式：局部补丁误清字段、非法输入部分落地、缩容吞物品、临时状态被自动写入、
-- 在途旧写乱序、手动保存失败误恢复、空槽读取清档、待切槽跨玩家串线或当局热切换。
local lu = require('luaunit')

TestGMState = {}

function TestGMState:setUp()
    self.oldGame = _G.game
    self.cfg = require('common.GameCfg')
    self.oldDebug = self.cfg.Debug
    self.cfg.Debug = { Enabled = true, InitialGrants = self.oldDebug.InitialGrants }
    self.values = {}
    self.failGet, self.failSet = false, false
    self.players = {}
    self.spawns = {}
    local env = self
    self.store = {
        GetAsync = function(_, key)
            if env.failGet then error('read unavailable') end
            return env.values[key]
        end,
        SetAsync = function(_, key, value)
            if env.failSet then error('write unavailable') end
            env.values[key] = value
        end,
        UpdateAsync = function(_, key, fn)
            if env.failSet then error('write unavailable') end
            local value = fn(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return {
            Spawn = function(_, fn) env.spawns[#env.spawns + 1] = fn end,
            Wait = function() end,
        } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.gm = assert(loadfile('server/Mgr/MgrGM.lua'))()
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.data = {}
    self.replies = {}
    self.gm.Save = self.save
    self.gm.PlayerData = {
        GetDataInst = function(_, player) return env.data[player] end,
        SendItemBar = function() end,
    }
    self.gm.Reply = function(_, _, result) env.replies[#env.replies + 1] = result end
    local function add(id)
        local player = { UserId = id, SetAttribute = function() end }
        local data = PlayerData.New(player)
        data:Init()
        env.players[#env.players + 1] = player
        env.data[player] = data
        return player, data
    end
    self.me, self.mine = add(1)
    self.you, self.yours = add(2)
    self.save:LoadInto(self.me, self.mine)
    self.save:LoadInto(self.you, self.yours)
    self:drain()
end

function TestGMState:test_slots_capacity_and_invalid_patch_are_all_or_nothing()
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ApplyState', upgradeLevel = 6,
        slots = { { container = 'backpack', index = 40, itemId = 'tilapia', count = 1, mult = 1.5 } } }))
    lu.assertEquals(self.mine:GetItemBarSnapshot().backpack[40].mult, 1.5)
    local prior = self.mine:Serialize()
    for _, bad in ipairs({
        { coin = -1 }, { upgradeLevel = 7 },
        { slots = { { container = 'backpack', index = 41, clear = true } } },
        { slots = { { container = 'itemBar', index = 2, itemId = 'worm', count = 1 } } },
        { slots = { { container = 'itemBar', index = 2, itemId = 'carp', count = 2 } } },
        { slots = { { container = 'itemBar', index = 2, itemId = 'carp', count = 1, mult = 2.1 } } },
        { upgradeLevel = 0, coin = 99 },
    }) do
        bad.action = 'ApplyState'
        lu.assertFalse(self.gm:Handle(self.me, bad))
        lu.assertEquals(self.mine:Serialize(), prior)
    end
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ApplyState', upgradeLevel = 0,
        slots = { { container = 'backpack', index = 40, clear = true } } }))
    lu.assertNil(self.mine:GetItemBarSnapshot().backpack[40])
end

function TestGMState:test_in_flight_write_finishes_before_temporary_patch_and_all_automatic_paths_pause()
    lu.assertTrue(self.save:Save(1, self.mine:Serialize(), 'old'))
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ApplyState', coin = 777 }))
    lu.assertEquals(self.mine.Data.FishCoin, 0)
    self:drain()
    lu.assertEquals(self.values.u1.coin, 0)
    lu.assertEquals(self.mine.Data.FishCoin, 777)
    lu.assertTrue(self.save:Status(1).autosavePaused)
    lu.assertFalse(self.save:Save(1, self.mine:Serialize(), 'autosave'))
    lu.assertFalse(self.save:Commit(1, self.mine:Serialize(), 'ferry:ticket'))
    self.save:SaveLeaving(self.me, self.mine)
    lu.assertEquals(self.values.u1.coin, 0)
end

function TestGMState:test_explicit_save_confirms_persistence_and_failure_keeps_pause()
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ApplyState', coin = 101 }))
    self.failSet = true
    lu.assertTrue(self.gm:Handle(self.me, { action = 'SaveState' }))
    self:drain()
    lu.assertFalse(self.replies[#self.replies].ok)
    lu.assertTrue(self.replies[#self.replies].status.autosavePaused)
    lu.assertEquals(self.values.u1.coin, 0)
    self.failSet = false
    lu.assertTrue(self.gm:Handle(self.me, { action = 'SaveState' }))
    self:drain()
    lu.assertTrue(self.replies[#self.replies].ok)
    lu.assertFalse(self.replies[#self.replies].status.autosavePaused)
    lu.assertEquals(self.values.u1.coin, 101)
end

function TestGMState:test_read_empty_or_invalid_retains_state_and_valid_read_replaces_it()
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ApplyState', coin = 91 }))
    self.values.u1 = nil
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ReadState' }))
    self:drain()
    lu.assertFalse(self.replies[#self.replies].ok)
    lu.assertEquals(self.mine.Data.FishCoin, 91)
    self.values.u1 = { invalid = true }
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ReadState' }))
    self:drain()
    lu.assertFalse(self.replies[#self.replies].ok)
    lu.assertEquals(self.mine.Data.FishCoin, 91)
    local saved = self.mine:Serialize()
    saved.coin = 55
    self.values.u1 = saved
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ReadState' }))
    self:drain()
    lu.assertTrue(self.replies[#self.replies].ok)
    lu.assertEquals(self.mine.Data.FishCoin, 55)
    lu.assertTrue(self.save:Status(1).autosavePaused)
end

function TestGMState:test_named_slot_is_per_player_and_only_switches_on_rejoin()
    self.gm:Handle(self.me, { action = 'GetState' })
    lu.assertEquals(self.replies[#self.replies].status.currentSlot, '')
    lu.assertTrue(self.gm:Handle(self.me, { action = 'SelectSaveSlot', slot = 'qa-one' }))
    self:drain()
    lu.assertEquals(self.save:Key(1), 'u1')
    lu.assertEquals(self.save:Status(1).nextSlot, 'qa-one')
    lu.assertEquals(self.save:Status(2).nextSlot, '')
    lu.assertEquals(self.values['u1:gm-slot'], 'qa-one')
    lu.assertFalse(self.gm:Handle(self.me, { action = 'SelectSaveSlot', slot = '../bad' }))
    self.save:LoadInto(self.me, self.mine)
    self:drain()
    lu.assertEquals(self.save:Key(1), 'u1:qa:qa-one')
end

function TestGMState:tearDown()
    self.cfg.Debug = self.oldDebug
    _G.game = self.oldGame
end

function TestGMState:drain()
    while #self.spawns > 0 do table.remove(self.spawns, 1)() end
end

function TestGMState:test_partial_patch_keeps_other_fields_and_rejects_bad_requests_atomically()
    lu.assertTrue(self.gm:Handle(self.me, { action = 'ApplyState', coin = 0 }))
    self:drain()
    lu.assertEquals(self.mine.Data.FishCoin, 0)
    lu.assertEquals(self.mine.Data.UpgradeLevel, 0)
    lu.assertEquals(self.mine:GetItemBarSnapshot().slots[1].itemId, 'starterRod')
    lu.assertFalse(self.gm:Handle(self.me, { action = 'ApplyState', coin = 7,
        upgradeLevel = 99 }))
    lu.assertEquals(self.mine.Data.FishCoin, 0)
end
