-- #88 首领饵「鸭子」挂饵与必出首领（GameSpec §12 已确认链路）。
-- 设计（本文件即口径）：鸭子占道具栏/背包格、不进 Bait 计数；挂饵走既有 SelectBait 通道，
-- 抛竿时从道具栏（优先）或背包扣 1 只；钓出首领后消耗，脱钩 / 逃脱不返还（消耗发生在抛竿一刻）。
-- 挂首领饵在任意水区抛竿必出对应首领：无视抽签权重、鱼饵-鱼种匹配与竿级。
-- 失败方式（先列后写）：
--   1. 没鸭子也能挂、或挂了鸭子却不消耗 / 消耗错容器（该扣道具栏却扣了背包、一次扣两只）；
--   2. 最后一只鸭子被消耗后选中态残留，或快照 bait 表不带鸭子数量（客户端按钮画不出）；
--   3. 挂鸭子仍按权重抽签、被竿级 / 匹配表挡住，或只在配了行的水区才出首领；
--   4. 首领饵被当成普通鱼饵参与 FishCatch.Select 或喂钓鱼佬入账；
--   5. 收竿 / 脱钩 / 逃脱把鸭子退回库存；
--   6. 蚯蚓等普通鱼饵的既有行为被改坏。
local lu = require('luaunit')

TestBossBait = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function signal()
    local slots = {}
    return {
        Connect = function(_, fn)
            slots[#slots + 1] = fn
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(slots) do fn(...) end end,
    }
end

function TestBossBait:setUp()
    local env = self
    self.savedGame = _G.game
    self.savedCfg = package.loaded['common.GameCfg']
    self.savedRE = package.loaded['common.REUtil']
    self.savedPlayerData = package.loaded['server.Mgr.MgrPlayerData']
    self.savedFishUnit = package.loaded['server.Mgr.MgrFishUnit']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    self.cfg.Debug = { Enabled = false }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.player = { UserId = 1, Character = {
        Position = vec(-11.75, 2.183, 22.75),
        Rotation = { GetForward = function() return vec(0, 0, 1) end } },
        SetAttribute = function() end }
    self.data = PlayerData.New(self.player, function() end)
    self.data:Init()
    -- MgrCast 桩：REUtil 记录下发，MgrPlayerData 指向真数据，MgrFishUnit 只读持有
    self.now = 0
    self.sent = {}
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            env.sent[name] = env.sent[name] or {}
            return { OnServerEvent = signal(), FireClient = function(_, player, payload)
                env.sent[name][#env.sent[name] + 1] = payload
            end }
        end,
        CheckRECD = function() return false end,
    }
    package.loaded['server.Mgr.MgrPlayerData'] = {
        GetDataInst = function(_, p) return p == env.player and env.data or nil end,
        SendItemBar = function() end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = {
        HeldInfo = function() return nil end,
        CanCast = function() return true end,
    }
    self.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    self.cast.World = { GetServerTime = function() return env.now end }
    self.cast.ReelIn = { Begin = function() return true end }
end

function TestBossBait:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
    package.loaded['common.REUtil'] = self.savedRE
    package.loaded['server.Mgr.MgrPlayerData'] = self.savedPlayerData
    package.loaded['server.Mgr.MgrFishUnit'] = self.savedFishUnit
    _G.game = self.savedGame
end

function TestBossBait:hookSession(baitId, zoneId)
    local session = { phase = 'cast', landing = vec(0, 2, 0), zoneId = zoneId,
        baitId = baitId, slot = 1, rodLevel = 1, hookAt = 0 }
    self.cast.Sessions[1] = { player = self.player, session = session }
    self.now = 10
    self.cast:Update()
    return session
end

-- 配置钉住：首领饵映射与首领近战占位参数
function TestBossBait:test_config_pins()
    -- #141：树林岛首领饵 item123 必出三头鲨（#88 口径：BossBait 键即首领饵物品 id）
    lu.assertEquals(self.cfg.Casting.BossBait,
        { duck = 'alligatorGar', item121 = 'fish16Boss', item122 = 'fish24Boss', item123 = 'fish32Boss' })
    lu.assertEquals(self.cfg.Fish.alligatorGar.Combat, 'gar')
    lu.assertNotNil(self.cfg.FishCombat.gar.BiteRange)
    lu.assertNotNil(self.cfg.FishCombat.gar.BiteCooldownSec)
    lu.assertEquals(self.cfg.Fish.alligatorGar.Drops,
        { { ItemId = 'garMeat', Count = 2 }, { ItemId = 'garHead', Count = 1 } })
end

function TestBossBait:test_pearl_hooks_dragon_in_every_water_and_abort_does_not_refund()
    lu.assertTrue(self.data:AddItem('starterRod'))
    lu.assertTrue(self.data:AddItem('item121'))
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertTrue(self.data:SelectBait('item121'))
    self.cast:Cast(self.player, { slot = 1, itemId = 'starterRod' })
    lu.assertEquals(self.data:ItemCount('item121'), 0)
    self.cast:Abort(self.player)
    lu.assertEquals(self.data:ItemCount('item121'), 0)
    for _, zone in ipairs(self.cfg.Water.Zones) do
        local session = self:hookSession('item121', zone.Id)
        lu.assertEquals(session.fishId, 'fish16Boss', zone.Id)
    end
end

function TestBossBait:test_select_duck_requires_duck_in_storage()
    lu.assertFalse(self.data:SelectBait('duck'))
    lu.assertNil(self.data.Data.SelectedBait)
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:SelectBait('duck'))
    lu.assertEquals(self.data.Data.SelectedBait, 'duck')
end

function TestBossBait:test_consume_duck_takes_itembar_before_backpack()
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:AddItem('duck')) -- 道具栏 2 格满，第三只进背包
    lu.assertTrue(self.data:SelectBait('duck'))
    local ok, baitId = self.data:ConsumeSelectedBait()
    lu.assertTrue(ok)
    lu.assertEquals(baitId, 'duck')
    local bar = self.data.Data.Containers.itemBar
    local barDucks = 0
    for index = 1, self.data:ItemBarCapacity() do
        if bar[index] and bar[index].itemId == 'duck' then barDucks = barDucks + 1 end
    end
    lu.assertEquals(barDucks, 1)
    lu.assertEquals(self.data.Data.Containers.backpack[1].itemId, 'duck')
end

function TestBossBait:test_last_duck_consumed_clears_selection()
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:SelectBait('duck'))
    lu.assertTrue(self.data:ConsumeSelectedBait())
    lu.assertNil(self.data.Data.SelectedBait)
    local ok, baitId = self.data:ConsumeSelectedBait()
    lu.assertTrue(ok) -- 没挂饵是合法抛竿（不挂饵），不算失败
    lu.assertNil(baitId)
end

function TestBossBait:test_snapshot_lists_duck_count_alongside_worm()
    self.data.Data.Bait.worm = 3
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:AddItem('duck'))
    local bait = self.data:GetItemBarSnapshot().bait
    lu.assertEquals(bait.worm, 3)
    lu.assertEquals(bait.duck, 2)
end

function TestBossBait:test_duck_hook_always_alligator_gar_ignoring_table_and_rod()
    local session = self:hookSession('duck', 'WaterCircle2')
    lu.assertEquals(session.phase, 'hooked')
    lu.assertEquals(session.fishId, 'alligatorGar')
    lu.assertNotNil(session.mult)
    lu.assertEquals(self.sent.CastState[#self.sent.CastState].fishId, 'alligatorGar')
end

function TestBossBait:test_duck_hook_works_in_zone_without_rows()
    local session = self:hookSession('duck', 'WaterCircle1')
    lu.assertEquals(session.fishId, 'alligatorGar')
    -- 对照：同水区挂蚯蚓没有配置行，抽不出鱼
    local worm = self:hookSession('worm', 'WaterCircle1')
    lu.assertNil(worm.fishId)
    lu.assertEquals(worm.phase, 'cast')
end

function TestBossBait:test_worm_hook_still_draws_from_zone_table()
    local session = self:hookSession('worm', 'WaterCircle2')
    lu.assertNotNil(session.fishId)
    lu.assertNotEquals(session.fishId, 'alligatorGar')
end

function TestBossBait:test_cast_consumes_duck_and_never_returns_it()
    lu.assertTrue(self.data:AddItem('starterRod'))
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertTrue(self.data:SelectBait('duck'))
    self.cast:Cast(self.player, { slot = 1, itemId = 'starterRod' })
    local current = self.cast.Sessions[1]
    lu.assertNotNil(current)
    lu.assertEquals(current.session.baitId, 'duck')
    lu.assertEquals(self.data:ItemCount('duck'), 0)
    lu.assertNil(self.data.Data.SelectedBait)
    -- 收竿（未上钩放弃）：鸭子不退
    self.cast:Reel(self.player)
    lu.assertNil(self.cast.Sessions[1])
    lu.assertEquals(self.data:ItemCount('duck'), 0)
end
