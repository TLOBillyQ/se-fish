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
    Mgr.Loot = nil
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

-- 药水走同一 eat 通道：两步语义不变；按 PotionLimits 累计，超限拒绝且不扣格。
function TestHoldOperateMgr:test_operate_potion_counts_and_caps()
    lu.assertTrue(self.data:AddItem('item167', 1.5))
    local first = self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    lu.assertEquals(first, { ok = true, op = 'eat', held = true })
    local second = self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    lu.assertEquals(second, { ok = true, op = 'eat', held = false, itemId = 'item167', action = 'potion' })
    lu.assertEquals(self.data:PotionCount('item167'), 1)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[1])
    -- 到上限后拒绝且不扣格（再造一格药水）
    lu.assertTrue(self.data:AddItem('item167', 1.5))
    self.data.Extra.growth.potions.item167 = GameCfg.Items.PotionLimits.item167
    self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    local capped = self:operate({ action = 'Operate', op = 'eat', slot = 1 })
    lu.assertEquals(capped, { ok = false, op = 'eat', reason = 'potion-capped' })
    lu.assertEquals(self.data:GetItemBarSnapshot().slots[1].itemId, 'item167')
    lu.assertEquals(self.data:PotionCount('item167'), GameCfg.Items.PotionLimits.item167)
end

-- 丢弃接了地面物品接口（T05 契约）：先 PrepareDrop 预留，成功才扣 1 件并按倍率生成；
-- PrepareDrop 拒绝时不扣物。
function TestHoldOperateMgr:test_discard_uses_ground_item_api_when_available()
    local prepared, committed = {}, {}
    Mgr.Loot = {
        -- T05 契约：PrepareDrop(player, drop) -> reservation|nil, reason
        PrepareDrop = function(_, player, drop)
            if drop.itemId == 'carp' then return nil, 'blocked' end
            prepared[#prepared + 1] = drop
            return { token = #prepared }
        end,
        -- CommitDrop(player, reservation, drop) -> ok
        CommitDrop = function(_, player, reservation, drop)
            committed[#committed + 1] = { reservation = reservation, drop = drop }
            return true
        end,
    }
    lu.assertTrue(self.data:AddItem('bass', 1.99))
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    local dropped = self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(dropped, { ok = true, op = 'discard', held = false, itemId = 'bass' })
    lu.assertEquals(#prepared, 1)
    lu.assertEquals(prepared[1].mult, 1.99)
    lu.assertEquals(#committed, 1)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[1])
    lu.assertEquals(self.data:GetItemBarSnapshot().slots[2].itemId, 'carp')
    -- PrepareDrop 拒绝：不扣物、明确错误
    self:operate({ action = 'Operate', op = 'discard', slot = 2 })
    local blocked = self:operate({ action = 'Operate', op = 'discard', slot = 2 })
    lu.assertEquals(blocked, { ok = false, op = 'discard', reason = 'drop-rejected' })
    lu.assertEquals(self.data:GetItemBarSnapshot().slots[2].itemId, 'carp')
    Mgr.Loot = nil
end

-- 攻击占位：首次切武器手持，再次明确未接战斗系统（#128），不结算伤害。
function TestHoldOperateMgr:test_attack_hold_first_combat_pending_second()
    lu.assertTrue(self.data:GrantWeapon('item134', 1))
    local first = self:operate({ action = 'Operate', op = 'attack', weapon = 'item134' })
    lu.assertEquals(first, { ok = true, op = 'attack', held = true })
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'weapon', id = 'item134', slot = nil })
    local second = self:operate({ action = 'Operate', op = 'attack', weapon = 'item134' })
    lu.assertEquals(second, { ok = false, op = 'attack', reason = 'combat-pending' })
    lu.assertEquals(self.data:WeaponCount('item134'), 1)
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

