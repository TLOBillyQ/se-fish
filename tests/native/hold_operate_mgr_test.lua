-- #86 迁移（原 tests/gameplay/hold_operate_mgr_test.lua，#124 统一分发失败方式）：
-- 首次即消费、重复点击重复扣物、丢弃未接地面物品接口仍扣物、
-- 分发不写回包客户端无从重试、绕开 Vitals 直接扣食。
-- 接缝：MgrPlayerData:Handle 请求入口。
local GameCfg = require('common.GameCfg')
local Mgr = require('server.Mgr.MgrPlayerData')

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

describe("持有操作的服务端分发", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对：分发夹具逐例建立、逐例清理。
    before_each(function()
        ctx = { events = {}, eaten = {} }
        ctx.debug = GameCfg.Debug
        GameCfg.Debug = { Enabled = false }
        ctx.oldREUtil = _G.REUtil
        _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = {
                    OnServerEvent = signal(),
                    FireClient = function(_, player, payload) player.lastResult = payload end,
                }
            end
            return ctx.events[name]
        end }
        ctx.player = { UserId = 34010, Character = { Name = 'Eggy' },
            CharacterAdded = signal(), CharacterRemoving = signal() }
        function ctx.player:SetAttribute() end
        Mgr.Vitals = { CanEat = function() return true end,
            Eat = function(_, player, itemId)
                ctx.eaten[#ctx.eaten + 1] = { player = player, itemId = itemId }
            end }
        Mgr.Save = nil
        Mgr:Start()
        Mgr:OnPlayerAdded(ctx.player)
        ctx.data = Mgr:GetDataInst(ctx.player)
    end)

    -- 分发夹具逐例回收；setUp 中途失败时仍恢复全局与配置（MgrPlayerData 是双端共享单例）。
    after_each(function()
        if ctx.player then Mgr:OnPlayerRemoving(ctx.player) end
        Mgr.Vitals = nil
        Mgr.Save = nil
        Mgr.Loot = nil
        _G.REUtil = ctx.oldREUtil
        GameCfg.Debug = ctx.debug
    end)

    local function operate(payload)
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player, payload)
        return ctx.player.lastResult
    end

    -- 切手持与实际使用分两次：首次只切手持不消费，再次才经 Vitals 吃掉。
    it("test_operate_eat_first_hold_then_eat", function()
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        local first = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same({ ok = true, op = 'eat', held = true }, first)
        assert.same(0, #ctx.eaten)
        assert.same({ kind = 'slot', id = 'carp', slot = 1 }, ctx.data:GetItemBarSnapshot().held)
        local second = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same({ ok = true, op = 'eat', held = false, itemId = 'carp' }, second)
        assert.same(1, #ctx.eaten)
        assert.same('carp', ctx.eaten[1].itemId)
        assert.is_nil(ctx.data:GetItemBarSnapshot().held.kind)
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[1])
        -- 吃完再点：格已空，明确拒绝
        local third = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same({ ok = false, reason = 'empty' }, third)
        assert.same(1, #ctx.eaten)
    end)

    -- 换一个槽目标是先切手持：旧手持取消，新槽手持，仍不消费。
    it("test_operate_switch_target_resets_hold", function()
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        assert.is_true(ctx.data:AddItem('bass', 1.99))
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        local switched = operate({ action = 'Operate', op = 'eat', slot = 2 })
        assert.same({ ok = true, op = 'eat', held = true }, switched)
        assert.same({ kind = 'slot', id = 'bass', slot = 2 }, ctx.data:GetItemBarSnapshot().held)
        assert.same(0, #ctx.eaten)
    end)

    -- 药水走同一 eat 通道：两步语义不变；按 PotionLimits 累计，超限拒绝且不扣格。
    it("test_operate_potion_counts_and_caps", function()
        assert.is_true(ctx.data:AddItem('item167', 1.5))
        local first = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same({ ok = true, op = 'eat', held = true }, first)
        local second = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same({ ok = true, op = 'eat', held = false, itemId = 'item167', action = 'potion' }, second)
        assert.same(1, ctx.data:PotionCount('item167'))
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[1])
        -- 到上限后拒绝且不扣格（再造一格药水）
        assert.is_true(ctx.data:AddItem('item167', 1.5))
        ctx.data.Extra.growth.potions.item167 = GameCfg.Items.PotionLimits.item167
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        local capped = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same({ ok = false, op = 'eat', reason = 'potion-capped' }, capped)
        assert.same('item167', ctx.data:GetItemBarSnapshot().slots[1].itemId)
        assert.same(GameCfg.Items.PotionLimits.item167, ctx.data:PotionCount('item167'))
    end)

    -- 丢弃接了地面物品接口（T05 契约）：先 PrepareDrop 预留，成功才扣 1 件并按倍率生成；
    -- PrepareDrop 拒绝时不扣物。
    it("test_discard_uses_ground_item_api_when_available", function()
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
        assert.is_true(ctx.data:AddItem('bass', 1.99))
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        local dropped = operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same({ ok = true, op = 'discard', held = false, itemId = 'bass' }, dropped)
        assert.same(1, #prepared)
        assert.same(1.99, prepared[1].mult)
        assert.same(1, #committed)
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[1])
        assert.same('carp', ctx.data:GetItemBarSnapshot().slots[2].itemId)
        -- PrepareDrop 拒绝：不扣物、明确错误
        operate({ action = 'Operate', op = 'discard', slot = 2 })
        local blocked = operate({ action = 'Operate', op = 'discard', slot = 2 })
        assert.same({ ok = false, op = 'discard', reason = 'drop-rejected' }, blocked)
        assert.same('carp', ctx.data:GetItemBarSnapshot().slots[2].itemId)
        Mgr.Loot = nil
    end)

    -- 攻击占位：首次切武器手持，再次明确未接战斗系统（#128），不结算伤害。
    it("test_attack_hold_first_combat_pending_second", function()
        assert.is_true(ctx.data:GrantWeapon('item134', 1))
        local first = operate({ action = 'Operate', op = 'attack', weapon = 'item134' })
        assert.same({ ok = true, op = 'attack', held = true }, first)
        assert.same({ kind = 'weapon', id = 'item134', slot = nil }, ctx.data:GetItemBarSnapshot().held)
        local second = operate({ action = 'Operate', op = 'attack', weapon = 'item134' })
        assert.same({ ok = false, op = 'attack', reason = 'combat-pending' }, second)
        assert.same(1, ctx.data:WeaponCount('item134'))
    end)

    -- 双向拖拽动作：MoveSlot 经 ItemBarAction 通道，换格/越界/非法容器都服务端复验。
    it("test_move_slot_action_dispatches_with_server_validation", function()
        for _ = 1, 6 do assert.is_true(ctx.data:AddItem('carp', 1.37)) end
        assert.is_true(ctx.data:GrantItem('duck', 1))
        local snapshot = ctx.data:GetItemBarSnapshot()
        assert.same('duck', snapshot.backpack[5].itemId)
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player,
            { action = 'MoveSlot', from = 'backpack', index = 5, target = 'itemBar', slot = 1 })
        snapshot = ctx.data:GetItemBarSnapshot()
        assert.same('duck', snapshot.slots[1].itemId)
        -- 非法容器名：拒绝且无副作用
        local before = ctx.data:GetItemBarSnapshot()
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player,
            { action = 'MoveSlot', from = 'bogus', index = 1, target = 'itemBar', slot = 2 })
        assert.same(before, ctx.data:GetItemBarSnapshot())
        -- 越界槽位：拒绝且无副作用
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player,
            { action = 'MoveSlot', from = 'itemBar', index = 1, target = 'backpack', slot = 99 })
        assert.same(before, ctx.data:GetItemBarSnapshot())
    end)

    -- 丢弃未接 PrepareDrop/CommitDrop：服务端拒绝、不扣物、回明确错误。
    it("test_discard_rejected_without_ground_item_api", function()
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        local result = operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same({ ok = false, op = 'discard', reason = 'drop-unavailable' }, result)
        local snapshot = ctx.data:GetItemBarSnapshot()
        assert.same('carp', snapshot.slots[1].itemId)
        assert.same(1, snapshot.slots[1].count)
    end)

    -- 持久模式：走 MgrSave 的 ResolveRequest+Execute；两步语义整体落在隔离 draft 上。
    it("test_operate_persistent_path_resolves_and_executes", function()
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
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        local first = operate({ action = 'Operate', op = 'eat', slot = 1, seq = 1 })
        assert.same({ 'operate:eat' }, resolvedKinds)
        assert.same({ ok = true, op = 'eat', held = true }, first)
        assert.same(0, #ctx.eaten)
        local second = operate({ action = 'Operate', op = 'eat', slot = 1, seq = 2 })
        assert.same({ ok = true, op = 'eat', held = false, itemId = 'carp' }, second)
        assert.same(1, #ctx.eaten)
        assert.same('carp', ctx.eaten[1].itemId)
        Mgr.Save = nil
    end)

    -- 持久模式重放：同 seq 重试只回原结果，不重复扣食。
    it("test_operate_persistent_replay_returns_recorded_result", function()
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
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        operate({ action = 'Operate', op = 'eat', slot = 1, seq = 1 })
        assert.is_true(operate({ action = 'Operate', op = 'eat', slot = 1, seq = 2 }).ok)
        assert.same(1, #ctx.eaten)
        -- 同 seq 重放：原结果回包，不再吃
        local replayed = operate({ action = 'Operate', op = 'eat', slot = 1, seq = 2 })
        assert.same({ ok = true, op = 'eat', held = false, itemId = 'carp' }, replayed)
        assert.same(1, #ctx.eaten)
        Mgr.Save = nil
    end)
end)
