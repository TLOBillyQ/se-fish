-- #86 迁移（原 tests/gameplay/loot_drop_test.lua，#126 T05 共享掉落）：
-- 真实丢弃、抢占拾取与全区回收预算（真 MgrLoot + MgrPlayerData + PlayerData，替换引擎边界）。
-- 失败方式（先列后写）：
--   1. 丢弃契约没接：PrepareDrop/CommitDrop/CancelDrop 缺失，丢弃仍直接删格、地面不生成实例；
--   2. 丢弃不校验身份/库存/位置：丢不持有的物品、坏 itemId、坏倍率、坏烤制值也能落地，或没有角色也生成；
--   3. 生成失败不整体放弃：实例建不出来仍让调用方扣件（物品凭空消失）；预留阶段就动库存 / 进区队列 / 上屏；
--   4. 拾回不还原实例属性：个体倍率丢失、烤制状态丢失、进错容器（鱼饵不进 Bait 计数、武器不进武器库存）；
--   5. 重复丢弃 / 重复拾取 / 双人争抢复制物品；同一预留重复 CommitDrop 生成两份；
--   6. 取消预留（持久写失败）后地面留残影，或预留实例仍占区预算触发误回收；
--   7. 提交时实例已消失（生成失败）件已扣却不补：物品凭空消失；
--   8. 满格时拾取仍发放或把地上物吞掉。
local GameCfg = require('common.GameCfg')

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

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
    }
end

describe("共享掉落的地面侧", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对。
    -- 掉落点位由角色位置与 GameCfg.Loot 常量算出，链路里唯一的 math.random 是 MgrLoot 的
    -- DeliveryEpoch 一次性字符串（不参与点位与倍率），因此无需固定或恢复随机数。
    before_each(function()
        ctx = { now = 0, created = {}, events = {}, failCreate = false, groundY = 1 }
        ctx.oldGame, ctx.oldRE, ctx.oldVector3 = _G.game, _G.REUtil, _G.Vector3
        ctx.oldColor, ctx.oldRaycastParams = _G.Color, _G.RaycastParams
        ctx.oldCarrier = package.loaded['server.Mgr.MgrFishCarrier']
        ctx.oldDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = false } -- 用例自己造库存，不受进图白送影响
        ctx.world = {
            GetServerTime = function() return ctx.now end,
            CreateUnit = function(_, unitType, values)
                if ctx.failCreate then return nil end
                local unit = { UnitType = unitType, Destroyed = false }
                for k, v in pairs(values) do unit[k] = v end
                function unit:Destroy() self.Destroyed = true end
                ctx.created[#ctx.created + 1] = unit
                return unit
            end,
        }
        ctx.physics = { Raycast = function(_, origin, direction)
            if direction.y < 0 then return { Position = vec(origin.x, ctx.groundY, origin.z), Distance = 1 } end
        end }
        _G.Vector3 = { New = vec }
        -- MgrLoot 落地时按物品表 IconColor 上色（server/Mgr/MgrLoot.lua:301）。
        _G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
        _G.RaycastParams = { New = function() return { FilterDescendantsInstances = {} } end }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return ctx.world end
            if name == 'PhysicsService' then return ctx.physics end
            if name == 'Players' then return { GetPlayers = function() return { ctx.player } end } end
        end }
        _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = { Sent = {},
                    OnServerEvent = signal(),
                    OnClientEvent = signal(),
                    FireAllClients = function(_, payload) ctx.events[name].Sent[#ctx.events[name].Sent + 1] = payload end,
                    FireClient = function(_, player, payload)
                        ctx.events[name].Sent[#ctx.events[name].Sent + 1] = { player = player, payload = payload }
                    end,
                }
            end
            return ctx.events[name]
        end }
        package.loaded['server.Mgr.MgrFishCarrier'] = { SubscribeDied = function() end }
        ctx.loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
        ctx.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
        ctx.playerData = assert(loadfile('server/Data/PlayerData.lua'))()
        ctx.loot.PlayerData, ctx.players.Loot = ctx.players, ctx.loot
        ctx.players.Save, ctx.players.Vitals = nil, { CanEat = function() return true end, Eat = function() end }
        ctx.loot.Listen, ctx.loot.StartSpots = function() end, function() end
        ctx.loot:Start()
        ctx.players:Start()
        ctx.character = { Position = vec(10, 2, 20), Rotation = { GetForward = function() return vec(0, 0, 1) end } }
        ctx.player = { UserId = 5126, Character = ctx.character,
            CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
        ctx.other = { UserId = 5127, Character = { Position = vec(40, 2, 20),
            Rotation = { GetForward = function() return vec(0, 0, 1) end } },
            CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
        ctx.players:OnPlayerAdded(ctx.player)
        ctx.players:OnPlayerAdded(ctx.other)
        ctx.data = ctx.players:GetDataInst(ctx.player)
        ctx.otherData = ctx.players:GetDataInst(ctx.other)
    end)

    -- 玩家、引擎全局、模块缓存与调试开关逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        if ctx.players then
            if ctx.player then ctx.players:OnPlayerRemoving(ctx.player) end
            if ctx.other then ctx.players:OnPlayerRemoving(ctx.other) end
        end
        _G.game, _G.REUtil, _G.Vector3 = ctx.oldGame, ctx.oldRE, ctx.oldVector3
        _G.Color, _G.RaycastParams = ctx.oldColor, ctx.oldRaycastParams
        package.loaded['server.Mgr.MgrFishCarrier'] = ctx.oldCarrier
        GameCfg.Debug = ctx.oldDebug
    end)

    local function operate(payload)
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player, payload)
        local sent = ctx.events.ItemBarResult.Sent
        return sent[#sent] and sent[#sent].payload
    end

    local function bar(data)
        return (data or ctx.data):GetItemBarSnapshot().slots
    end

    -- 场上的丢弃物实例（Kind='item'）与它们的世界单位
    local function drops()
        local list = {}
        for _, loot in pairs(ctx.loot.Loots) do
            if loot.Kind == 'item' then list[#list + 1] = loot end
        end
        table.sort(list, function(a, b) return a.Id < b.Id end)
        return list
    end

    -- 场上的丢弃物世界单位：隐藏的预留实例不算「已上屏」
    local function dropUnits()
        local list = {}
        for _, unit in ipairs(ctx.created) do
            if tostring(unit.Name):find('^ItemDrop_') and not unit.Destroyed and unit.ModelVisible ~= false then
                list[#list + 1] = unit
            end
        end
        return list
    end

    local function seed(itemId, mult, cooked)
        assert.is_true(ctx.data:AddItem(itemId, mult, cooked))
        return ctx.data
    end

    -- 提交时实例已消失（件已扣）：把物品退回库存（#124 遗留边界的补偿）
    it("test_commit_after_spawn_lost_refunds_the_item", function()
        seed('carp', 1.37, 2)
        local reservation = ctx.loot:PrepareDrop(ctx.player, { itemId = 'carp', mult = 1.37, cooked = 2, slot = 1 })
        assert.is_not_nil(reservation)
        ctx.data:ConsumeItemBarItem('carp')
        reservation.Unit:Destroy()
        local ok, reason = ctx.loot:CommitDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37, cooked = 2 })
        assert.is_false(ok)
        assert.same('spawn-failed', reason)
        assert.same(0, #drops())
        assert.same(1, ctx.data:ItemCount('carp'))
        assert.same({ itemId = 'carp', count = 1, containerId = 'itemBar', mult = 1.37, cooked = 2 }, bar()[1])
        -- 回滚只做一次：再提交同一预留不再退第二件
        assert.is_false(ctx.loot:CommitDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37, cooked = 2 }))
        assert.same(1, ctx.data:ItemCount('carp'))
    end)

    -- 同一预留重复 CommitDrop：第二次不生成第二份、不重复回滚
    it("test_commit_is_idempotent_per_reservation", function()
        seed('carp', 1.37)
        local reservation = ctx.loot:PrepareDrop(ctx.player, { itemId = 'carp', mult = 1.37, slot = 1 })
        ctx.data:ConsumeItemBarItem('carp')
        assert.is_true(ctx.loot:CommitDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37 }))
        assert.is_false(ctx.loot:CommitDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37 }))
        assert.same(1, #drops())
        assert.same(0, ctx.data:ItemCount('carp'))
    end)

    -- 契约存在：MgrPlayerData 的丢弃接线（#124）依赖这三个入口
    it("test_drop_contract_exists", function()
        assert.same('function', type(ctx.loot.PrepareDrop))
        assert.same('function', type(ctx.loot.CommitDrop))
        assert.same('function', type(ctx.loot.CancelDrop))
    end)

    -- 重复丢弃 / 重复拾取 / 双人争抢：一份只能被领一次，不复制
    it("test_duplicate_discard_pickup_and_race_never_duplicate", function()
        seed('carp', 1.37)
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same(1, #drops())
        -- 再点一次：格已空，明确拒绝且不生成第二份
        assert.same({ ok = false, reason = 'empty' }, operate({ action = 'Operate', op = 'discard', slot = 1 }))
        assert.same(1, #drops())
        local loot = drops()[1]
        ctx.player.Character.Position = loot.Position
        ctx.other.Character.Position = loot.Position
        assert.is_true(ctx.loot:Pickup(ctx.player, loot.Id))
        assert.is_false(ctx.loot:Pickup(ctx.other, loot.Id))
        assert.is_false(ctx.loot:Pickup(ctx.player, loot.Id))
        assert.same(1, ctx.data:ItemCount('carp'))
        assert.same(0, ctx.otherData:ItemCount('carp'))
        assert.same(0, #drops())
    end)

    -- 满格：拾取失败、地上物仍在、回明确原因（容量校验）
    it("test_full_inventory_keeps_loot_on_ground", function()
        -- 别人丢的物：拾取方库存全满（2 道具栏 + 5 背包），丢弃腾出的空格不属于他
        for i = 1, GameCfg.Items.InitialItemBarSlots + GameCfg.Items.InitialBackpackSlots do
            assert.is_true(ctx.otherData:AddItem('bass', 1 + i / 10))
        end
        seed('carp', 1.37)
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        local loot = drops()[1]
        assert.is_not_nil(loot)
        ctx.other.Character.Position = loot.Position
        assert.is_false(ctx.loot:Pickup(ctx.other, loot.Id))
        assert.is_not_nil(ctx.loot.Loots[loot.Id])
        assert.is_false(dropUnits()[1].Destroyed)
        local sent = ctx.events.LootResult.Sent
        assert.same('full', sent[#sent].payload.reason)
        assert.same(0, ctx.otherData:ItemCount('carp'))
        assert.same(0, ctx.data:ItemCount('carp'))
    end)

    -- 丢弃：库存 -1、地面 +1，落点在角色正前方并贴地
    it("test_operate_discard_moves_one_item_to_ground", function()
        seed('carp', 1.37)
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        local result = operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same({ ok = true, op = 'discard', held = false, itemId = 'carp' }, result)
        assert.is_nil(bar()[1])
        assert.same(0, ctx.data:ItemCount('carp'))
        local list = drops()
        assert.same(1, #list)
        assert.same('carp', list[1].ItemId)
        assert.same(1.37, list[1].Mult)
        -- 落在角色正前方 DropOffset 米、贴地 + Height
        assert.same(20 + GameCfg.Loot.DropOffset, list[1].Position.z)
        assert.same(ctx.groundY + GameCfg.Loot.Height, list[1].Position.y)
        assert.same(1, #dropUnits())
        local broadcast = ctx.events.LootState.Sent[#ctx.events.LootState.Sent]
        assert.same(1, #broadcast)
        assert.same('carp', broadcast[1].itemId)
        assert.same('item', broadcast[1].kind)
    end)

    -- 拾回还原原实例属性：倍率与烤制状态跟着走，并随存档包里的 k 保留
    it("test_pickup_restores_mult_and_cooked_state", function()
        seed('carp', 1.37, 2)
        local reservation = ctx.loot:PrepareDrop(ctx.player, { itemId = 'carp', mult = 1.37, cooked = 2, slot = 1 })
        assert.is_not_nil(reservation)
        ctx.data:ConsumeItemBarItem('carp') -- 调用方（MgrPlayerData）扣件：本用例只验地面侧
        assert.is_true(ctx.loot:CommitDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37, cooked = 2 }))
        assert.same(2, drops()[1].Cooked)
        ctx.other.Character.Position = drops()[1].Position
        assert.is_true(ctx.loot:Pickup(ctx.other, drops()[1].Id))
        assert.same({ itemId = 'carp', count = 1, containerId = 'itemBar', mult = 1.37, cooked = 2 },
            bar(ctx.otherData)[1])
        assert.same(2, ctx.otherData:Serialize().bar[1].k)
        local restored = ctx.playerData.New({ UserId = 1, SetAttribute = function() end })
        restored:Init()
        assert.is_true(restored:ApplySave(ctx.otherData:Serialize()))
        assert.same(2, restored:GetItemBarSnapshot().slots[1].cooked)
        assert.same(1.37, restored:GetItemBarSnapshot().slots[1].mult)
    end)

    -- 容器归属：鱼饵回 Bait 计数（不占格）、武器回武器库存
    it("test_pickup_returns_each_kind_to_its_container", function()
        assert.is_true(ctx.data:AddBait('worm', 3))
        local bait = ctx.loot:PrepareDrop(ctx.player, { itemId = 'worm' })
        assert.is_not_nil(bait)
        ctx.data:EatBait('worm') -- 调用方扣件
        assert.is_true(ctx.loot:CommitDrop(ctx.player, bait, { itemId = 'worm' }))
        local drop = drops()[#drops()]
        ctx.player.Character.Position = drop.Position
        assert.is_true(ctx.loot:Pickup(ctx.player, drop.Id))
        assert.same(3, ctx.data.Data.Bait.worm)
        assert.is_nil(bar()[1])
        assert.is_true(ctx.data:GrantWeapon('item134', 1))
        local weapon = ctx.loot:PrepareDrop(ctx.player, { itemId = 'item134' })
        assert.is_not_nil(weapon)
        ctx.data:ConsumeWeapon('item134', 1)
        assert.is_true(ctx.loot:CommitDrop(ctx.player, weapon, { itemId = 'item134' }))
        drop = drops()[#drops()]
        ctx.player.Character.Position = drop.Position
        assert.is_true(ctx.loot:Pickup(ctx.player, drop.Id))
        assert.same(1, ctx.data:WeaponCount('item134'))
    end)

    -- 预留阶段不动库存、不进区队列、不上屏；取消后不留残影
    it("test_prepare_is_inert_until_commit_and_cancel_releases", function()
        seed('carp', 1.37)
        local reservation = ctx.loot:PrepareDrop(ctx.player, { itemId = 'carp', mult = 1.37, slot = 1 })
        assert.is_not_nil(reservation)
        assert.same(0, #drops())
        assert.same(0, #dropUnits())
        -- 预留期不上屏：从未广播过 LootState
        assert.is_nil(ctx.events.LootState)
        assert.same(1, ctx.data:ItemCount('carp'))
        assert.is_false(reservation.Unit.ModelVisible)
        local zoneId = ctx.loot:RegionAt(reservation.Position)
        assert.is_not_nil(zoneId)
        assert.is_nil(ctx.loot.ZoneQueues[zoneId])
        assert.is_true(ctx.loot:CancelDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37 }))
        assert.is_false(ctx.loot:CancelDrop(ctx.player, reservation, { itemId = 'carp', mult = 1.37 }))
        assert.same(0, #dropUnits())
        assert.is_nil(ctx.loot.ZoneQueues[zoneId])
    end)

    -- 校验：坏 payload / 不持有的物品 / 格号对不上 / 没有角色，一律拒绝且不生成
    it("test_prepare_rejects_bad_payload_and_unowned_items", function()
        assert.is_true(ctx.data:AddItem('carp', 1.37))
        for _, case in ipairs({
            { nil, 'bad-item' },
            { { itemId = 'no-such-item' }, 'bad-item' },
            { { itemId = 42 }, 'bad-item' },
            { { itemId = 'carp', mult = 3 }, 'bad-item' },
            { { itemId = 'carp', cooked = -1 }, 'bad-item' },
            { { itemId = 'bass' }, 'not-owned' },
            { { itemId = 'carp', slot = 2 }, 'not-owned' },
        }) do
            local reservation, reason = ctx.loot:PrepareDrop(ctx.player, case[1])
            assert.is_nil(reservation)
            assert.same(case[2], reason)
        end
        ctx.player.Character = nil
        local reservation, reason = ctx.loot:PrepareDrop(ctx.player, { itemId = 'carp', mult = 1.37, slot = 1 })
        assert.is_nil(reservation)
        assert.same('no-character', reason)
        ctx.player.Character = ctx.character
        assert.same(0, #dropUnits())
    end)

    -- 拾取泡快照与区归属：丢弃物进快照、带区归属与预警标记
    it("test_snapshot_carries_drop_kind_and_warning_flag", function()
        local loot = ctx.loot:SpawnItem('carp', 1.2, nil, { x = 10, y = 5, z = 20 })
        local entry
        for _, row in ipairs(ctx.loot:Snapshot()) do if row.id == loot.Id then entry = row end end
        assert.same('item', entry.kind)
        assert.same('carp', entry.itemId)
        assert.is_nil(entry.warn)
        assert.same(ctx.loot:RegionAt(loot.Position), loot.ZoneId)
    end)

    -- 生成失败：实例建不出来就不进入扣件流程（库存不动、无地面实例）
    it("test_spawn_failure_never_deducts", function()
        seed('carp', 1.37)
        ctx.failCreate = true
        local reservation, reason = ctx.loot:PrepareDrop(ctx.player, { itemId = 'carp', mult = 1.37, slot = 1 })
        assert.is_nil(reservation)
        assert.same('spawn-failed', reason)
        ctx.failCreate = false
        -- 走完整丢弃通道：拒绝回包、库存与手持不变、可以重试
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        ctx.failCreate = true
        local result = operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same({ ok = false, op = 'discard', reason = 'drop-rejected' }, result)
        assert.same(1, ctx.data:ItemCount('carp'))
        assert.same({ kind = 'slot', id = 'carp', slot = 1 }, ctx.data:GetItemBarSnapshot().held)
        assert.same(0, #dropUnits())
        ctx.failCreate = false
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same(1, #drops())
    end)

    -- 满格落地入口（盲盒溢出复用）：不经「先扣后落」，直接生成一份带属性的地面实例
    it("test_spawn_item_lands_a_ground_instance_for_multi_source_drops", function()
        local loot = ctx.loot:SpawnItem('rareShrimp', 1.8, 3, { x = 10, y = 5, z = 20 })
        assert.is_not_nil(loot)
        assert.same('item', loot.Kind)
        assert.same('rareShrimp', loot.ItemId)
        assert.same(1.8, loot.Mult)
        assert.same(3, loot.Cooked)
        assert.same(1, #dropUnits())
        assert.is_nil(bar()[1])
        ctx.player.Character.Position = loot.Position
        assert.is_true(ctx.loot:Pickup(ctx.player, loot.Id))
        assert.same({ itemId = 'rareShrimp', count = 1, containerId = 'itemBar', mult = 1.8, cooked = 3 }, bar()[1])
        assert.is_nil(ctx.loot:SpawnItem('no-such-item', 1, nil, { x = 10, y = 5, z = 20 }))
    end)

    -- 票面「覆盖一切可丢弃品」：船票（过关道具）与首领饵也能丢回地面并原样拾回
    it("test_ticket_and_boss_bait_round_trip", function()
        assert.is_true(ctx.data:AddItem('shrimpTicket', 1))
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        operate({ action = 'Operate', op = 'discard', slot = 1 })
        assert.same('shrimpTicket', drops()[1].ItemId)
        ctx.player.Character.Position = drops()[1].Position
        assert.is_true(ctx.loot:Pickup(ctx.player, drops()[1].Id))
        assert.same(1, ctx.data:ItemCount('shrimpTicket'))
        -- 首领饵（鸭子）按物品表没有 bait 容器：拾回进道具栏，不混进普通鱼饵计数
        assert.is_true(ctx.data:AddItem('duck', 1))
        local duckSlot
        for index, entry in pairs(bar()) do
            if entry.itemId == 'duck' then duckSlot = index end
        end
        assert.is_not_nil(duckSlot)
        operate({ action = 'Operate', op = 'discard', slot = duckSlot })
        operate({ action = 'Operate', op = 'discard', slot = duckSlot })
        assert.same('duck', drops()[1].ItemId)
        assert.same(0, ctx.data:ItemCount('duck'))
        ctx.player.Character.Position = drops()[1].Position
        assert.is_true(ctx.loot:Pickup(ctx.player, drops()[1].Id))
        assert.same(1, ctx.data:ItemBarItemCount('duck'))
        assert.is_nil(ctx.data.Data.Bait.duck)
    end)
end)
