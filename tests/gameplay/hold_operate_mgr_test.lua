-- #124 统一分发失败方式：首次即消费、重复点击重复扣物、丢弃未接地面物品接口仍扣物、
-- 分发不写回包客户端无从重试、绕开 Vitals 直接扣食。
-- 接缝：MgrPlayerData:Handle 请求入口。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local Mgr = require('server.Mgr.MgrPlayerData')

TestHoldOperateMgr = {}

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            callbacks[#callbacks + 1] = fn
            return { Disconnect = function() for i, cb in ipairs(callbacks) do
                if cb == fn then callbacks[i] = nil end
            end end }
        end,
        Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
    }
end

function TestHoldOperateMgr:setUp()
    self.debug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false }
    self.oldREUtil = _G.REUtil
    self.events = {}
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = {
                OnServerEvent = signal(),
                FireClient = function(_, player, payload) player.lastResult = payload end,
            }
        end
        return self.events[name]
    end }
    self.player = { UserId = 34010, Character = { Name = 'Eggy' },
        CharacterAdded = signal(), CharacterRemoving = signal() }
    function self.player:SetAttribute() end
    self.eaten = {}
    Mgr.Vitals = { CanEat = function() return true end,
        Eat = function(_, player, itemId) self.eaten[#self.eaten + 1] = { player = player, itemId = itemId } end }
    Mgr.Save = nil
    Mgr:Start()
    Mgr:OnPlayerAdded(self.player)
    self.data = Mgr:GetDataInst(self.player)
end

function TestHoldOperateMgr:tearDown()
    Mgr:OnPlayerRemoving(self.player)
    Mgr.Vitals = nil
    _G.REUtil = self.oldREUtil
    GameCfg.Debug = self.debug
end

function TestHoldOperateMgr:operate(payload)
    self.events.ItemBarAction.OnServerEvent:Fire(self.player, payload)
    return self.player.lastResult
end

-- 切手持与实际使用分两次：首次只切手持不消费，再次才经 Vitals 吃掉。
function TestHoldOperateMgr:test_operate_eat_first_hold_then_eat()
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    local first = self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    lu.assertEquals(first, { ok = true, op = 'eat', held = true })
    lu.assertEquals(#self.eaten, 0)
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'slot', id = 'carp', slot = 1 })
    local second = self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    lu.assertEquals(second, { ok = true, op = 'eat', held = false })
    lu.assertEquals(#self.eaten, 1)
    lu.assertEquals(self.eaten[1].itemId, 'carp')
    lu.assertNil(self.data:GetItemBarSnapshot().held.kind)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[1])
    -- 吃完再点：格已空，明确拒绝
    local third = self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    lu.assertEquals(third, { ok = false, reason = 'empty' })
    lu.assertEquals(#self.eaten, 1)
end

-- 换一个槽目标是先切手持：旧手持取消，新槽手持，仍不消费。
function TestHoldOperateMgr:test_operate_switch_target_resets_hold()
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    lu.assertTrue(self.data:AddItem('bass', 1.99))
    self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    local switched = self:operate({ action = 'Operate', op = 'eat', slot = 2 })
    lu.assertEquals(switched, { ok = true, op = 'eat', held = true })
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'slot', id = 'bass', slot = 2 })
    lu.assertEquals(#self.eaten, 0)
end

-- 丢弃未接 PrepareDrop/CommitDrop：服务端拒绝、不扣物、回明确错误。
function TestHoldOperateMgr:test_discard_rejected_without_ground_item_api()
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    local result = self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(result, { ok = false, op = 'discard', reason = 'drop-unavailable' })
    local snapshot = self.data:GetItemBarSnapshot()
    lu.assertEquals(snapshot.slots[1].itemId, 'carp')
    lu.assertEquals(snapshot.slots[1].count, 1)
end
