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
    Mgr.Save = nil
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
    lu.assertEquals(second, { ok = true, op = 'eat', held = false, itemId = 'carp' })
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

-- 持久模式：走 MgrSave 的 ResolveRequest+Execute；两步语义整体落在隔离 draft 上。
function TestHoldOperateMgr:test_operate_persistent_path_resolves_and_executes()
    local resolvedKinds = {}
    Mgr.Save = {
        ResolveRequest = function(_, player, data, kind, requestId)
            resolvedKinds[#resolvedKinds + 1] = kind
            return { id = '34010:' .. tostring(#resolvedKinds), sequence = #resolvedKinds,
                kind = kind, requestKey = 'k' .. tostring(#resolvedKinds) }, 'new'
        end,
        Execute = function(_, player, data, operation, transform, done)
            local result, reason = transform(data)
            if result == nil then done(false, reason) return false end
            done(true, result)
            return true
        end,
    }
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    local first = self:operate({ action = 'Operate', op = 'eat', slot = 1, seq = 1 })
    lu.assertEquals(resolvedKinds, { 'operate:eat' })
    lu.assertEquals(first, { ok = true, op = 'eat', held = true })
    lu.assertEquals(#self.eaten, 0)
    local second = self:operate({ action = 'Operate', op = 'eat', slot = 1, seq = 2 })
    lu.assertEquals(second, { ok = true, op = 'eat', held = false, itemId = 'carp' })
    lu.assertEquals(#self.eaten, 1)
    lu.assertEquals(self.eaten[1].itemId, 'carp')
    Mgr.Save = nil
end

-- 持久模式重放：同 seq 重试只回原结果，不重复扣食。
function TestHoldOperateMgr:test_operate_persistent_replay_returns_recorded_result()
    local recorded = {}
    Mgr.Save = {
        ResolveRequest = function(_, player, data, kind, requestId)
            if recorded[requestId] then return recorded[requestId], 'replay' end
            local operation = { id = '34010:' .. tostring(requestId), sequence = requestId,
                kind = kind, requestKey = 'k' .. tostring(requestId) }
            recorded[requestId] = operation
            return operation, 'new'
        end,
        Execute = function(_, player, data, operation, transform, done)
            for _, rec in pairs(recorded) do
                if rec == operation and rec.result then
                    done(true, rec.result)
                    return true
                end
            end
            local result, reason = transform(data)
            if result == nil then done(false, reason) return false end
            operation.result = result
            done(true, result)
            return true
        end,
    }
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    self:operate({ action = 'Operate', op = 'eat', slot = 1, seq = 1 })
    lu.assertTrue(self:operate({ action = 'Operate', op = 'eat', slot = 1, seq = 2 }).ok)
    lu.assertEquals(#self.eaten, 1)
    -- 同 seq 重放：原结果回包，不再吃
    local replayed = self:operate({ action = 'Operate', op = 'eat', slot = 1, seq = 2 })
    lu.assertEquals(replayed, { ok = true, op = 'eat', held = false, itemId = 'carp' })
    lu.assertEquals(#self.eaten, 1)
    Mgr.Save = nil
end

