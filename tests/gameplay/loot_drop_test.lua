-- #126 T05 共享掉落：真实丢弃、抢占拾取与全区回收预算（真 MgrLoot + MgrPlayerData + PlayerData，替换引擎边界）。
-- 失败方式（先列后写）：
--   1. 丢弃契约没接：PrepareDrop/CommitDrop/CancelDrop 缺失，丢弃仍直接删格、地面不生成实例；
--   2. 丢弃不校验身份/库存/位置：丢不持有的物品、坏 itemId、坏倍率、坏烤制值也能落地，或没有角色也生成；
--   3. 生成失败不整体放弃：实例建不出来仍让调用方扣件（物品凭空消失）；预留阶段就动库存 / 进区队列 / 上屏；
--   4. 拾回不还原实例属性：个体倍率丢失、烤制状态丢失、进错容器（鱼饵不进 Bait 计数、武器不进武器库存）；
--   5. 重复丢弃 / 重复拾取 / 双人争抢复制物品；同一预留重复 CommitDrop 生成两份；
--   6. 取消预留（持久写失败）后地面留残影，或预留实例仍占区预算触发误回收；
--   7. 提交时实例已消失（生成失败）件已扣却不补：物品凭空消失；
--   8. 满格时拾取仍发放或把地上物吞掉。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestLootDrop = {}

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

function TestLootDrop:setUp()
    local env = self
    self.oldGame, self.oldRE, self.oldVector3 = _G.game, _G.REUtil, _G.Vector3
    self.oldRaycastParams, self.oldCarrier = _G.RaycastParams, package.loaded['server.Mgr.MgrFishCarrier']
    self.oldDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false } -- 用例自己造库存，不受进图白送影响
    self.now, self.created, self.events = 0, {}, {}
    self.failCreate = false
    self.groundY = 1
    self.world = {
        GetServerTime = function() return env.now end,
        CreateUnit = function(_, unitType, values)
            if env.failCreate then return nil end
            local unit = { UnitType = unitType, Destroyed = false }
            for k, v in pairs(values) do unit[k] = v end
            function unit:Destroy() self.Destroyed = true end
            env.created[#env.created + 1] = unit
            return unit
        end,
    }
    self.physics = { Raycast = function(_, origin, direction)
        if direction.y < 0 then return { Position = vec(origin.x, env.groundY, origin.z), Distance = 1 } end
    end }
    _G.Vector3 = { New = vec }
    _G.RaycastParams = { New = function() return { FilterDescendantsInstances = {} } end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return env.world end
        if name == 'PhysicsService' then return env.physics end
        if name == 'Players' then return { GetPlayers = function() return { env.player } end } end
    end }
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { Sent = {},
                OnServerEvent = signal(),
                OnClientEvent = signal(),
                FireAllClients = function(_, payload) env.events[name].Sent[#env.events[name].Sent + 1] = payload end,
                FireClient = function(_, player, payload)
                    env.events[name].Sent[#env.events[name].Sent + 1] = { player = player, payload = payload }
                end,
            }
        end
        return env.events[name]
    end }
    package.loaded['server.Mgr.MgrFishCarrier'] = { SubscribeDied = function() end }
    self.loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
    self.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    self.playerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.loot.PlayerData, self.players.Loot = self.players, self.loot
    self.players.Save, self.players.Vitals = nil, { CanEat = function() return true end, Eat = function() end }
    self.loot.Listen, self.loot.StartSpots = function() end, function() end
    self.loot:Start()
    self.players:Start()
    self.character = { Position = vec(10, 2, 20), Rotation = { GetForward = function() return vec(0, 0, 1) end } }
    self.player = { UserId = 5126, Character = self.character,
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    self.other = { UserId = 5127, Character = { Position = vec(40, 2, 20),
        Rotation = { GetForward = function() return vec(0, 0, 1) end } },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    self.players:OnPlayerAdded(self.player)
    self.players:OnPlayerAdded(self.other)
    self.data = self.players:GetDataInst(self.player)
    self.otherData = self.players:GetDataInst(self.other)
end

function TestLootDrop:tearDown()
    self.players:OnPlayerRemoving(self.player)
    self.players:OnPlayerRemoving(self.other)
    _G.game, _G.REUtil, _G.Vector3 = self.oldGame, self.oldRE, self.oldVector3
    _G.RaycastParams = self.oldRaycastParams
    package.loaded['server.Mgr.MgrFishCarrier'] = self.oldCarrier
    GameCfg.Debug = self.oldDebug
end

function TestLootDrop:operate(payload)
    self.events.ItemBarAction.OnServerEvent:Fire(self.player, payload)
    local sent = self.events.ItemBarResult.Sent
    return sent[#sent] and sent[#sent].payload
end

function TestLootDrop:bar(data)
    return (data or self.data):GetItemBarSnapshot().slots
end

-- 场上的丢弃物实例（Kind='item'）与它们的世界单位
function TestLootDrop:drops()
    local list = {}
    for _, loot in pairs(self.loot.Loots) do
        if loot.Kind == 'item' then list[#list + 1] = loot end
    end
    table.sort(list, function(a, b) return a.Id < b.Id end)
    return list
end

-- 场上的丢弃物世界单位：隐藏的预留实例不算「已上屏」
function TestLootDrop:dropUnits()
    local list = {}
    for _, unit in ipairs(self.created) do
        if tostring(unit.Name):find('^ItemDrop_') and not unit.Destroyed and unit.ModelVisible ~= false then
            list[#list + 1] = unit
        end
    end
    return list
end

function TestLootDrop:seed(itemId, mult, cooked)
    lu.assertTrue(self.data:AddItem(itemId, mult, cooked))
    return self.data
end

-- 契约存在：MgrPlayerData 的丢弃接线（#124）依赖这三个入口
function TestLootDrop:test_drop_contract_exists()
    lu.assertEquals(type(self.loot.PrepareDrop), 'function')
    lu.assertEquals(type(self.loot.CommitDrop), 'function')
    lu.assertEquals(type(self.loot.CancelDrop), 'function')
end

-- 丢弃：库存 -1、地面 +1，落点在角色正前方并贴地
function TestLootDrop:test_operate_discard_moves_one_item_to_ground()
    self:seed('carp', 1.37)
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    local result = self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(result, { ok = true, op = 'discard', held = false, itemId = 'carp' })
    lu.assertNil(self:bar()[1])
    lu.assertEquals(self.data:ItemCount('carp'), 0)
    local drops = self:drops()
    lu.assertEquals(#drops, 1)
    lu.assertEquals(drops[1].ItemId, 'carp')
    lu.assertEquals(drops[1].Mult, 1.37)
    -- 落在角色正前方 DropOffset 米、贴地 + Height
    lu.assertEquals(drops[1].Position.z, 20 + GameCfg.Loot.DropOffset)
    lu.assertEquals(drops[1].Position.y, self.groundY + GameCfg.Loot.Height)
    lu.assertEquals(#self:dropUnits(), 1)
    local broadcast = self.events.LootState.Sent[#self.events.LootState.Sent]
    lu.assertEquals(#broadcast, 1)
    lu.assertEquals(broadcast[1].itemId, 'carp')
    lu.assertEquals(broadcast[1].kind, 'item')
end

-- 拾回还原原实例属性：倍率与烤制状态跟着走，并随存档包里的 k 保留
function TestLootDrop:test_pickup_restores_mult_and_cooked_state()
    self:seed('carp', 1.37, 2)
    local reservation = self.loot:PrepareDrop(self.player, { itemId = 'carp', mult = 1.37, cooked = 2, slot = 1 })
    lu.assertNotNil(reservation)
    self.data:ConsumeItemBarItem('carp') -- 调用方（MgrPlayerData）扣件：本用例只验地面侧
    lu.assertTrue(self.loot:CommitDrop(self.player, reservation, { itemId = 'carp', mult = 1.37, cooked = 2 }))
    local loot = self:drops()[1]
    lu.assertEquals(loot.Cooked, 2)
    self.other.Character.Position = loot.Position
    lu.assertTrue(self.loot:Pickup(self.other, loot.Id))
    local slots = self:bar(self.otherData)
    lu.assertEquals(slots[1], { itemId = 'carp', count = 1, containerId = 'itemBar', mult = 1.37, cooked = 2 })
    lu.assertEquals(self.otherData:Serialize().bar[1].k, 2)
    local restored = self.playerData.New({ UserId = 1, SetAttribute = function() end })
    restored:Init()
    lu.assertTrue(restored:ApplySave(self.otherData:Serialize()))
    lu.assertEquals(restored:GetItemBarSnapshot().slots[1].cooked, 2)
    lu.assertEquals(restored:GetItemBarSnapshot().slots[1].mult, 1.37)
end

-- 容器归属：鱼饵回 Bait 计数（不占格）、武器回武器库存
function TestLootDrop:test_pickup_returns_each_kind_to_its_container()
    lu.assertTrue(self.data:AddBait('worm', 3))
    local bait = self.loot:PrepareDrop(self.player, { itemId = 'worm' })
    lu.assertNotNil(bait)
    self.data:EatBait('worm') -- 调用方扣件
    lu.assertTrue(self.loot:CommitDrop(self.player, bait, { itemId = 'worm' }))
    local drop = self:drops()[#self:drops()]
    self.player.Character.Position = drop.Position
    lu.assertTrue(self.loot:Pickup(self.player, drop.Id))
    lu.assertEquals(self.data.Data.Bait.worm, 3)
    lu.assertNil(self:bar()[1])
    lu.assertTrue(self.data:GrantWeapon('item134', 1))
    local weapon = self.loot:PrepareDrop(self.player, { itemId = 'item134' })
    lu.assertNotNil(weapon)
    self.data:ConsumeWeapon('item134', 1)
    lu.assertTrue(self.loot:CommitDrop(self.player, weapon, { itemId = 'item134' }))
    drop = self:drops()[#self:drops()]
    self.player.Character.Position = drop.Position
    lu.assertTrue(self.loot:Pickup(self.player, drop.Id))
    lu.assertEquals(self.data:WeaponCount('item134'), 1)
end

-- 满格：拾取失败、地上物仍在、回明确原因（容量校验）
function TestLootDrop:test_full_inventory_keeps_loot_on_ground()
    -- 别人丢的物：拾取方库存全满（2 道具栏 + 5 背包），丢弃腾出的空格不属于他
    for i = 1, GameCfg.Items.InitialItemBarSlots + GameCfg.Items.InitialBackpackSlots do
        lu.assertTrue(self.otherData:AddItem('bass', 1 + i / 10))
    end
    self:seed('carp', 1.37)
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    local loot = self:drops()[1]
    lu.assertNotNil(loot)
    self.other.Character.Position = loot.Position
    lu.assertFalse(self.loot:Pickup(self.other, loot.Id))
    lu.assertNotNil(self.loot.Loots[loot.Id])
    lu.assertFalse(self:dropUnits()[1].Destroyed)
    local sent = self.events.LootResult.Sent
    lu.assertEquals(sent[#sent].payload.reason, 'full')
    lu.assertEquals(self.otherData:ItemCount('carp'), 0)
    lu.assertEquals(self.data:ItemCount('carp'), 0)
end

-- 重复丢弃 / 重复拾取 / 双人争抢：一份只能被领一次，不复制
function TestLootDrop:test_duplicate_discard_pickup_and_race_never_duplicate()
    self:seed('carp', 1.37)
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(#self:drops(), 1)
    -- 再点一次：格已空，明确拒绝且不生成第二份
    local again = self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(again, { ok = false, reason = 'empty' })
    lu.assertEquals(#self:drops(), 1)
    local loot = self:drops()[1]
    self.player.Character.Position = loot.Position
    self.other.Character.Position = loot.Position
    lu.assertTrue(self.loot:Pickup(self.player, loot.Id))
    lu.assertFalse(self.loot:Pickup(self.other, loot.Id))
    lu.assertFalse(self.loot:Pickup(self.player, loot.Id))
    lu.assertEquals(self.data:ItemCount('carp'), 1)
    lu.assertEquals(self.otherData:ItemCount('carp'), 0)
    lu.assertEquals(#self:drops(), 0)
end

-- 同一预留重复 CommitDrop：第二次不生成第二份、不重复回滚
function TestLootDrop:test_commit_is_idempotent_per_reservation()
    self:seed('carp', 1.37)
    local reservation = self.loot:PrepareDrop(self.player, { itemId = 'carp', mult = 1.37, slot = 1 })
    self.data:ConsumeItemBarItem('carp')
    lu.assertTrue(self.loot:CommitDrop(self.player, reservation, { itemId = 'carp', mult = 1.37 }))
    local ok = self.loot:CommitDrop(self.player, reservation, { itemId = 'carp', mult = 1.37 })
    lu.assertFalse(ok)
    lu.assertEquals(#self:drops(), 1)
    lu.assertEquals(self.data:ItemCount('carp'), 0)
end

-- 预留阶段不动库存、不进区队列、不上屏；取消后不留残影
function TestLootDrop:test_prepare_is_inert_until_commit_and_cancel_releases()
    self:seed('carp', 1.37)
    local reservation = self.loot:PrepareDrop(self.player, { itemId = 'carp', mult = 1.37, slot = 1 })
    lu.assertNotNil(reservation)
    lu.assertEquals(#self:drops(), 0)
    lu.assertEquals(#self:dropUnits(), 0)
    -- 预留期不上屏：从未广播过 LootState
    lu.assertNil(self.events.LootState)
    lu.assertEquals(self.data:ItemCount('carp'), 1)
    lu.assertFalse(reservation.Unit.ModelVisible)
    local zoneId = self.loot:RegionAt(reservation.Position)
    lu.assertNotNil(zoneId)
    lu.assertNil(self.loot.ZoneQueues[zoneId])
    lu.assertTrue(self.loot:CancelDrop(self.player, reservation, { itemId = 'carp', mult = 1.37 }))
    lu.assertFalse(self.loot:CancelDrop(self.player, reservation, { itemId = 'carp', mult = 1.37 }))
    lu.assertEquals(#self:dropUnits(), 0)
    lu.assertNil(self.loot.ZoneQueues[zoneId])
end

-- 校验：坏 payload / 不持有的物品 / 格号对不上 / 没有角色，一律拒绝且不生成
function TestLootDrop:test_prepare_rejects_bad_payload_and_unowned_items()
    lu.assertTrue(self.data:AddItem('carp', 1.37))
    for _, case in ipairs({
        { nil, 'bad-item' },
        { { itemId = 'no-such-item' }, 'bad-item' },
        { { itemId = 42 }, 'bad-item' },
        { { itemId = 'carp', mult = 3 }, 'bad-item' },
        { { itemId = 'carp', cooked = -1 }, 'bad-item' },
        { { itemId = 'bass' }, 'not-owned' },
        { { itemId = 'carp', slot = 2 }, 'not-owned' },
    }) do
        local reservation, reason = self.loot:PrepareDrop(self.player, case[1])
        lu.assertNil(reservation)
        lu.assertEquals(reason, case[2])
    end
    self.player.Character = nil
    local reservation, reason = self.loot:PrepareDrop(self.player, { itemId = 'carp', mult = 1.37, slot = 1 })
    lu.assertNil(reservation)
    lu.assertEquals(reason, 'no-character')
    self.player.Character = self.character
    lu.assertEquals(#self:dropUnits(), 0)
end

-- 生成失败：实例建不出来就不进入扣件流程（库存不动、无地面实例）
function TestLootDrop:test_spawn_failure_never_deducts()
    self:seed('carp', 1.37)
    self.failCreate = true
    local reservation, reason = self.loot:PrepareDrop(self.player, { itemId = 'carp', mult = 1.37, slot = 1 })
    lu.assertNil(reservation)
    lu.assertEquals(reason, 'spawn-failed')
    self.failCreate = false
    -- 走完整丢弃通道：拒绝回包、库存与手持不变、可以重试
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    self.failCreate = true
    local result = self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(result, { ok = false, op = 'discard', reason = 'drop-rejected' })
    lu.assertEquals(self.data:ItemCount('carp'), 1)
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'slot', id = 'carp', slot = 1 })
    lu.assertEquals(#self:dropUnits(), 0)
    self.failCreate = false
    self:operate({ action = 'Operate', op = 'discard', slot = 1 })
    lu.assertEquals(#self:drops(), 1)
end

-- 提交时实例已消失（件已扣）：把物品退回库存（#124 遗留边界的补偿）
function TestLootDrop:test_commit_after_spawn_lost_refunds_the_item()
    self:seed('carp', 1.37, 2)
    local reservation = self.loot:PrepareDrop(self.player, { itemId = 'carp', mult = 1.37, cooked = 2, slot = 1 })
    lu.assertNotNil(reservation)
    self.data:ConsumeItemBarItem('carp')
    reservation.Unit:Destroy()
    local ok, reason = self.loot:CommitDrop(self.player, reservation, { itemId = 'carp', mult = 1.37, cooked = 2 })
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'spawn-failed')
    lu.assertEquals(#self:drops(), 0)
    lu.assertEquals(self.data:ItemCount('carp'), 1)
    lu.assertEquals(self:bar()[1], { itemId = 'carp', count = 1, containerId = 'itemBar', mult = 1.37, cooked = 2 })
    -- 回滚只做一次：再提交同一预留不再退第二件
    lu.assertFalse(self.loot:CommitDrop(self.player, reservation, { itemId = 'carp', mult = 1.37, cooked = 2 }))
    lu.assertEquals(self.data:ItemCount('carp'), 1)
end

-- 满格落地入口（盲盒溢出复用）：不经「先扣后落」，直接生成一份带属性的地面实例
function TestLootDrop:test_spawn_item_lands_a_ground_instance_for_multi_source_drops()
    local loot = self.loot:SpawnItem('rareShrimp', 1.8, 3, { x = 10, y = 5, z = 20 })
    lu.assertNotNil(loot)
    lu.assertEquals(loot.Kind, 'item')
    lu.assertEquals(loot.ItemId, 'rareShrimp')
    lu.assertEquals(loot.Mult, 1.8)
    lu.assertEquals(loot.Cooked, 3)
    lu.assertEquals(#self:dropUnits(), 1)
    lu.assertEquals(self:bar()[1], nil)
    self.player.Character.Position = loot.Position
    lu.assertTrue(self.loot:Pickup(self.player, loot.Id))
    lu.assertEquals(self:bar()[1], { itemId = 'rareShrimp', count = 1, containerId = 'itemBar', mult = 1.8, cooked = 3 })
    lu.assertNil(self.loot:SpawnItem('no-such-item', 1, nil, { x = 10, y = 5, z = 20 }))
end

-- 拾取泡快照与区归属：丢弃物进快照、带区归属与预警标记
function TestLootDrop:test_snapshot_carries_drop_kind_and_warning_flag()
    local loot = self.loot:SpawnItem('carp', 1.2, nil, { x = 10, y = 5, z = 20 })
    local entry
    for _, row in ipairs(self.loot:Snapshot()) do if row.id == loot.Id then entry = row end end
    lu.assertEquals(entry.kind, 'item')
    lu.assertEquals(entry.itemId, 'carp')
    lu.assertEquals(entry.warn, nil)
    lu.assertEquals(loot.ZoneId, self.loot:RegionAt(loot.Position))
end
