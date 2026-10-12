-- #86 迁移（原 tests/gameplay/item_bar_flow_test.lua）：道具栏动作的服务端请求流。
-- 接缝：ItemBarAction / RequestItemBar 的 OnServerEvent 与 ItemBarState 回包。
local GameCfg = require('common.GameCfg')
local Mgr = require('server.Mgr.MgrPlayerData')

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

describe("道具栏的请求流", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对。
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）。
    before_each(function()
        ctx = { events = {}, cooldowns = {}, enableCooldown = false, now = 0 }
        ctx.savedGrantDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = true, InitialGrants = ctx.savedGrantDebug.InitialGrants }
        ctx.previousREUtil = _G.REUtil
        _G.REUtil = { CheckRECD = function(_, player, name, duration)
            if not ctx.enableCooldown then return false end
            assert.same('ItemBarAction', name)
            assert.same(GameCfg.Items.ActionCooldownSec, duration)
            local expiry = ctx.cooldowns[player.UserId]
            if expiry and ctx.now <= expiry then return true end
            ctx.cooldowns[player.UserId] = ctx.now + duration
            return false
        end, GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = {
                    OnServerEvent = signal(),
                    FireClient = function(_, player, state)
                        player.lastState = state
                        player.stateCount = (player.stateCount or 0) + 1
                    end,
                }
            end
            return ctx.events[name]
        end }
        ctx.player = { UserId = 341, attrs = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
        function ctx.player:SetAttribute(key, value) self.attrs[key] = value end
        Mgr:Start()
        Mgr:OnPlayerAdded(ctx.player)
    end)

    -- 配置、全局与玩家实例逐例回收；setUp 中途失败也照样清理。
    after_each(function()
        GameCfg.Debug = ctx.savedGrantDebug
        if ctx.player then Mgr:OnPlayerRemoving(ctx.player) end
        _G.REUtil = ctx.previousREUtil
    end)

    it("test_client_commands_are_authoritative_and_state_replies", function()
        local action = ctx.events.ItemBarAction.OnServerEvent
        action:Fire(ctx.player, { action = 'SelectSlot', value = 1 })
        assert.same(1, ctx.player.lastState.selectedSlot)
        action:Fire(ctx.player, { action = 'SelectBait', value = 'worm' })
        assert.same(10, ctx.player.lastState.bait.worm)
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        assert.same(9, ctx.player.lastState.bait.worm)
        action:Fire(ctx.player, { action = 'SelectSlot', value = 2 })
        assert.is_nil(ctx.player.lastState.selectedSlot)
        ctx.events.RequestItemBar.OnServerEvent:Fire(ctx.player)
        assert.same('worm', ctx.player.lastState.selectedBait)
    end)

    it("test_reject_invalid_commands_and_other_player", function()
        local action = ctx.events.ItemBarAction.OnServerEvent
        local previous = ctx.player.lastState
        action:Fire(ctx.player, { action = 'Invalid' })
        action:Fire(ctx.player, { action = 'DiscardSlot', value = '1' })
        action:Fire(ctx.player, { action = 'SelectBait', value = 'other' })
        action:Fire(ctx.player, { action = 'ConsumeSelectedBait' })
        action:Fire(ctx.player, 'SelectSlot')
        assert.equal(ctx.player.lastState, previous)
        local stranger = { UserId = ctx.player.UserId }
        action:Fire(stranger, { action = 'DiscardSlot', value = 1 })
        assert.same('starterRod', Mgr:GetDataInst(ctx.player):GetItemBarSnapshot().slots[1].itemId)
    end)

    it("test_external_item_depletion_broadcasts_state", function()
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player, { action = 'SelectSlot', value = 1 })
        Mgr:GetDataInst(ctx.player):UpdateData(function(data)
            data.Containers[GameCfg.Items.ContainerId.ItemBar][1].count = 0
        end, true)
        assert.is_nil(ctx.player.lastState.selectedSlot)
        assert.is_nil(ctx.player.lastState.slots[1])
    end)

    it("test_cast_consumption_broadcasts_and_clears_last_bait", function()
        local data = Mgr:GetDataInst(ctx.player)
        data:UpdateData(function(state) state.Bait.worm = 1 end, true)
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player, { action = 'SelectBait', value = 'worm' })
        assert.same(1, ctx.player.lastState.bait.worm)
        assert.same('worm', ctx.player.lastState.selectedBait)
        local previous = ctx.player.lastState
        local ok, itemId = data:ConsumeSelectedBait()
        assert.is_true(ok)
        assert.same('worm', itemId)
        assert.is_not.equal(ctx.player.lastState, previous)
        assert.same(0, ctx.player.lastState.bait.worm)
        assert.is_nil(ctx.player.lastState.selectedBait)
    end)

    it("test_eating_last_selected_bait_broadcasts_clear", function()
        local data = Mgr:GetDataInst(ctx.player)
        data:UpdateData(function(state) state.Bait.worm = 1 end, true)
        local action = ctx.events.ItemBarAction.OnServerEvent
        action:Fire(ctx.player, { action = 'SelectBait', value = 'worm' })
        local sent = ctx.player.stateCount
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        assert.same(sent + 1, ctx.player.stateCount)
        assert.same(0, ctx.player.lastState.bait.worm)
        assert.is_nil(ctx.player.lastState.selectedBait)
    end)

    it("test_discard_and_depletion_update_reply", function()
        local action = ctx.events.ItemBarAction.OnServerEvent
        action:Fire(ctx.player, { action = 'SelectSlot', value = 1 })
        action:Fire(ctx.player, { action = 'DiscardSlot', value = 1 })
        assert.is_nil(ctx.player.lastState.selectedSlot)
        assert.is_nil(ctx.player.lastState.slots[1])
        Mgr:GetDataInst(ctx.player).Data.Bait.worm = 1
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        assert.same(0, ctx.player.lastState.bait.worm)
    end)

    it("test_action_rate_limit_and_recovery", function()
        ctx.enableCooldown = true
        local action = ctx.events.ItemBarAction.OnServerEvent
        action:Fire(ctx.player, { action = 'Invalid', value = 'worm' })
        action:Fire(ctx.player, { action = 'EatBait', value = 'bogus' })
        action:Fire(ctx.player, { action = 'SelectSlot', value = '1' })
        assert.is_nil(ctx.cooldowns[ctx.player.UserId])
        local impostor = { UserId = ctx.player.UserId }
        action:Fire(impostor, { action = 'EatBait', value = 'worm' })
        assert.is_nil(ctx.cooldowns[ctx.player.UserId])
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        assert.same(9, ctx.player.lastState.bait.worm)
        local sent = ctx.player.stateCount
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        action:Fire(ctx.player, { action = 'SelectSlot', value = 1 })
        assert.same(9, ctx.player.lastState.bait.worm)
        assert.is_nil(ctx.player.lastState.selectedSlot)
        assert.same(sent, ctx.player.stateCount)
        ctx.now = GameCfg.Items.ActionCooldownSec + 0.001
        action:Fire(ctx.player, { action = 'SelectSlot', value = 1 })
        assert.same(1, ctx.player.lastState.selectedSlot)
        ctx.now = ctx.now + GameCfg.Items.ActionCooldownSec + 0.001
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        assert.same(8, ctx.player.lastState.bait.worm)
    end)

    it("test_action_rate_limit_is_per_player", function()
        ctx.enableCooldown = true
        local other = { UserId = 342, CharacterAdded = signal(), CharacterRemoving = signal() }
        function other:SetAttribute() end
        Mgr:OnPlayerAdded(other)
        local action = ctx.events.ItemBarAction.OnServerEvent
        action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
        action:Fire(other, { action = 'EatBait', value = 'worm' })
        assert.same(9, ctx.player.lastState.bait.worm)
        assert.same(9, other.lastState.bait.worm)
        Mgr:OnPlayerRemoving(other)
    end)

    -- EatSlot 动作通道（#53 吃鱼获；#85 验收「转入道具栏后可吃」依赖它）。失败方式（先列后写）：
    --   1. EatSlot 不在 actions 表里，动作在 method 查找处被静默丢弃，选中鱼获点「吃」没反应
    --      （#53 的特例分支排在 method 判空之后，从来没接通；ba6a78c 重构时按死代码删掉了）；
    --   2. 吃的不是选中格（value 与 SelectedSlot 不符也生效），或鱼竿等没配 EatPercent 的物品也能吃；
    --   3. Vitals 拒绝（死亡期间）仍扣格，或只扣格不走 Vitals:Eat 恢复血量饥饿；
    --   4. 吃完不推送 ItemBarState，客户端残留旧格子与选中态。
    it("test_eat_slot_action_consumes_selected_food_and_heals", function()
        local data = Mgr:GetDataInst(ctx.player)
        local bar = GameCfg.Items.ContainerId.ItemBar
        local function putFish()
            data:UpdateData(function(state)
                state.Containers[bar][2] = { itemId = 'carp', count = 1, containerId = bar }
            end, true)
        end
        local healed = {}
        local canEat = true
        Mgr.Vitals = {
            CanEat = function() return canEat end,
            Eat = function(_, _, itemId) healed[#healed + 1] = itemId end,
        }
        -- pcall 包住主体：Vitals 挂上后即使断言失败也要摘掉，再抛错让本例失败。
        local ok, err = pcall(function()
            local action = ctx.events.ItemBarAction.OnServerEvent
            putFish()
            action:Fire(ctx.player, { action = 'EatSlot', value = 2 }) -- 未选中任何格：不吃
            assert.is_not_nil(data.Data.Containers[bar][2])
            action:Fire(ctx.player, { action = 'SelectSlot', value = 2 })
            action:Fire(ctx.player, { action = 'EatSlot', value = 1 }) -- 与选中格不符：不吃
            assert.is_not_nil(data.Data.Containers[bar][2])
            canEat = false -- Vitals 拒绝（如死亡期间）：不扣格、不恢复
            action:Fire(ctx.player, { action = 'EatSlot', value = 2 })
            assert.is_not_nil(data.Data.Containers[bar][2])
            assert.same({}, healed)
            canEat = true
            local sent = ctx.player.stateCount
            action:Fire(ctx.player, { action = 'EatSlot', value = 2 })
            assert.is_nil(data.Data.Containers[bar][2])
            assert.same({ 'carp' }, healed)
            assert.is_true(ctx.player.stateCount > sent) -- 吃完推送了新状态
            assert.is_nil(ctx.player.lastState.slots[2])
            assert.is_nil(ctx.player.lastState.selectedSlot)
            action:Fire(ctx.player, { action = 'SelectSlot', value = 1 }) -- 鱼竿没配 EatPercent：不能吃
            action:Fire(ctx.player, { action = 'EatSlot', value = 1 })
            assert.is_not_nil(data.Data.Containers[bar][1])
            assert.same({ 'carp' }, healed)
        end)
        Mgr.Vitals = nil
        if not ok then error(err, 0) end
    end)

    -- #52 新手任务「挂饵」事实（失败方式：取消挂饵 / 挂不存在或已用完的饵也报挂饵；
    --   每次挂饵不带唯一 eventId；别的动作也报挂饵）
    it("test_select_bait_success_notifies_equip_with_distinct_ids", function()
        local facts = {}
        Mgr.Quest = { Notify = function(_, kind, player, payload)
            facts[#facts + 1] = { kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId }
            return true
        end }
        -- pcall 包住主体：Quest 挂上后即使断言失败也要摘掉，再抛错让本例失败。
        local ok, err = pcall(function()
            local action = ctx.events.ItemBarAction.OnServerEvent
            action:Fire(ctx.player, { action = 'SelectSlot', value = 1 })
            action:Fire(ctx.player, { action = 'SelectBait', value = 'other' })
            action:Fire(ctx.player, { action = 'SelectBait' })
            action:Fire(ctx.player, { action = 'EatBait', value = 'worm' })
            assert.same(0, #facts)
            action:Fire(ctx.player, { action = 'SelectBait', value = 'worm' })
            action:Fire(ctx.player, { action = 'SelectBait', value = 'worm' })
            assert.same(2, #facts)
            assert.same('EquipBait', facts[1].kind)
            assert.same('worm', facts[1].itemId)
            assert.equal(ctx.player, facts[1].player)
            assert.is_not_nil(facts[1].eventId)
            assert.is_not.equal(facts[1].eventId, facts[2].eventId)
            Mgr:GetDataInst(ctx.player):UpdateData(function(state) state.Bait.worm = 0 end, true)
            action:Fire(ctx.player, { action = 'SelectBait', value = 'worm' })
            assert.same(2, #facts)
        end)
        Mgr.Quest = nil
        if not ok then error(err, 0) end
    end)
end)
