-- #84 迁移：挥砍杀鱼与鱼获拾取（原 tests/gameplay/fish_loot_test.lua，8 例）。
-- 接缝：MgrLoot:OnCarrierDied / Pickup 与鱼种配置表——一份鱼获、身份与距离校验、满栏拒绝、极品掉落与抽签行同源。
-- 沿用 tests/support/fish_loot 共享夹具（真 PlayerData + 真 MgrLoot + 举鱼假引擎）。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local FishLoot = require('tests.support.fish_loot')

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

-- #134 鱼塘极品六条（钓鱼表 R8–R13，物品表 R8–R13）
local POND_RARES = {
    { id = 'item7', base = 'tilapia' }, { id = 'item8', base = 'carp' }, { id = 'item9', base = 'knifeFish' },
    { id = 'item10', base = 'catfish' }, { id = 'item11', base = 'bass' }, { id = 'item12', base = 'goldfish' },
}

local function selectable(rows, rodLevel, baitId)
    local FishCatch = require('common.FishCatch')
    local total = 0
    for _, row in ipairs(rows) do
        if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then total = total + row.DrawWeight end
    end
    local found = {}
    for roll = 1, total do
        found[FishCatch.Select(rows, rodLevel, baitId, function() return roll end)] = true
    end
    return found
end

describe('TestFishLoot', function()
    local env

    before_each(function()
        env = FishLoot.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_death_spawns_one_static_loot_with_species_and_mult', function()
        assert.are.equal(1, #env.diedSubs)
        local fish = env:land(env.player, 'catfish', 1.6)
        fish.Carrier.Body.Position = vec(4, 3, 8)
        fish.Anchor = fish.Carrier.Body.Position
        env:kill(fish)
        env:kill(fish)
        local loot = env:onlyLoot()
        assert.are.equal('catfish', loot.FishId)
        assert.are.equal(1.6, loot.Mult)
        assert.is_nil(env.mgr.Fish[fish.Id])
        assert.same(fish.Carrier, env.despawned[#env.despawned])
        local units = env:lootUnits()
        assert.are.equal(1, #units)
        local unit = units[1]
        assert.are.equal('official://mesh/7000553', unit.RenderMeshId)
        assert.is_false(unit.PhysicsActive)
        assert.is_false(unit.CanCollide)
        assert.is_false(unit.Liftable)
        assert.are.equal(4, unit.Position.x)
        assert.are.equal(8, unit.Position.z)
        assert.is_true(unit.Position.y >= env.groundY and unit.Position.y < 2)
        -- 不自动入栏；放很久也不消失
        assert.is_nil(env:bar(env.player)[2])
        env.now = 3600
        env.mgr:Update()
        env.loot:Update()
        assert.are.equal(1, #env:lootUnits())
        assert.is_true(env.broadcasts >= 1)
    end)

    it('test_each_loot_takes_own_slot_and_full_bar_refuses_with_notice', function()
        local data = env.data[env.player.UserId]
        local mults = { 1.1, 1.2, 1.3, 1.4, 1.5, 1.6 }
        for _, mult in ipairs(mults) do assert.is_true(data:AddItem('carp', mult)) end
        local slots = env:bar(env.player)
        for index = 2, 2 do
            assert.are.equal(1, slots[index].count)
            assert.are.equal(mults[index - 1], slots[index].mult)
        end
        local backpack = data:GetItemBarSnapshot().backpack
        for index = 1, 5 do
            assert.are.equal(mults[index + 1], backpack[index].mult)
        end
        local fish = env:land(env.player, 'bass', 1.3)
        env:kill(fish)
        local loot = env:onlyLoot()
        env.player.Character.Position = loot.Position
        assert.is_false(env.loot:Pickup(env.player, loot.Id))
        assert.is_not.is_nil(env.loot.Loots[loot.Id])
        assert.is_false(env:lootUnits()[1].Destroyed)
        assert.same(env.player, env.replies[#env.replies].player)
        assert.are.equal('full', env.replies[#env.replies].payload.reason)
        assert.is_false(data:AddItem('carp', 1))
    end)

    it('test_fish_table_matches_m1_spec', function()
        local cfg = assert(loadfile('common/GameCfg.lua'))()
        -- 鱼种表（#84，GameSpec §5.1/§5.2）：鱼塘 6 普通 + 精英电鳗 + 首领鳄雀鳝；虾池 6 普通 + 6 极品
        local expected = {
            tilapia = 'normal', carp = 'normal', knifeFish = 'normal', bass = 'normal', catfish = 'normal', goldfish = 'normal',
            item7 = 'rare', item8 = 'rare', item9 = 'rare', item10 = 'rare', item11 = 'rare', item12 = 'rare',
            eel = 'elite', alligatorGar = 'boss',
            shrimp = 'normal', riverShrimp = 'normal', crayfish = 'normal',
            bostonLobster = 'normal', aussieLobster = 'normal', milkLobster = 'normal',
            rareShrimp = 'rare', rareRiverShrimp = 'rare', rareCrayfish = 'rare',
            rareBostonLobster = 'rare', rareAussieLobster = 'rare', rareMilkLobster = 'rare',
        }
        local count = 0
        for id, grade in pairs(expected) do
            assert.are.equal(grade, cfg.Fish[id].Grade, id)
            count = count + 1
        end
        assert.are.equal(26, count)
        assert.are.equal(7, #cfg.Zones)
        local total = 0
        for _ in pairs(cfg.Fish) do total = total + 1 end
        assert.are.equal(98, total)
        -- 原表极品奶龙的基础重量与普通版不同，只核对其余字段。
        for _, pair in ipairs({ { 'shrimp', 'rareShrimp' }, { 'riverShrimp', 'rareRiverShrimp' }, { 'crayfish', 'rareCrayfish' },
            { 'bostonLobster', 'rareBostonLobster' }, { 'aussieLobster', 'rareAussieLobster' }, { 'milkLobster', 'rareMilkLobster' } }) do
            local base, rare = cfg.Fish[pair[1]], cfg.Fish[pair[2]]
            assert.same({ base.Health, base.BasePrice, base.Model, base.Speed },
                { rare.Health, rare.BasePrice, rare.Model, rare.Speed }, pair[2])
            if pair[1] ~= 'milkLobster' then assert.are.equal(base.BaseWeight, rare.BaseWeight, pair[2]) end
            assert.are.equal('极品' .. base.Name, rare.Name, pair[2])
        end
        -- 原表极品奶龙的基础重量为 50 kg，其普通版为 10 kg；按资料优先级保留。
        assert.are.equal(50, cfg.Fish.rareMilkLobster.BaseWeight)
        -- 普通/极品的鱼获即自身（同名物品定义）；精英/首领不掉自身，Drops 逐项落到已有物品定义
        for id, species in pairs(cfg.Fish) do
            if species.Drops then
                for _, drop in ipairs(species.Drops) do
                    assert.is_not.is_nil(cfg.Items.Definitions[drop.ItemId], id .. ' 的掉落 ' .. drop.ItemId .. ' 没有物品定义')
                    assert.is_true(drop.Count >= 1, id .. ' 的掉落 ' .. drop.ItemId .. ' 数量')
                end
            else
                assert.is_not.is_nil(cfg.Items.Definitions[id], id .. ' 没有物品定义')
            end
        end
        -- 精英/首领数值（GameSpec §5.1 第 7/8 行与已确认结论）
        assert.same({ cfg.Fish.eel.Health, cfg.Fish.eel.Attack, cfg.Fish.eel.EscapeSec }, { 300, 10, 180 })
        assert.same({ cfg.Fish.alligatorGar.Health, cfg.Fish.alligatorGar.Attack, cfg.Fish.alligatorGar.EscapeSec }, { 600, 30, 300 })
        assert.same({ { ItemId = 'eelMeat', Count = 2 }, { ItemId = 'eelHead', Count = 1 } }, cfg.Fish.eel.Drops)
        assert.same({ { ItemId = 'garMeat', Count = 2 }, { ItemId = 'garHead', Count = 1 } }, cfg.Fish.alligatorGar.Drops)
        -- 信物 / 首领饵 / 船票物品定义（鸭子挂饵必出鳄雀鳝的钓取逻辑在 #88 落地）
        local defs = cfg.Items.Definitions
        assert.are.equal('电鳗头', defs.eelHead.Name)     -- 精英信物
        assert.are.equal('鳄雀鳝鱼头', defs.garHead.Name) -- 首领信物
        assert.are.equal('鸭子', defs.duck.Name)
        assert.is_nil(defs.duck.Container) -- #85：首领饵占道具栏或背包格
        assert.are.equal('虾池船票', defs.shrimpTicket.Name)
        assert.is_nil(defs.shrimpTicket.EatPercent) -- 过关道具不能吃
        -- #86：电鳗加入蚯蚓抽签表；#88 首领饵必出鳄雀鳝；虾池鱼表 shrimpPond.water（行数与权重见 shrimp_pond_test）。
        for zoneId, rows in pairs(cfg.Casting.Zones) do
            for _, row in ipairs(rows) do assert.is_not.is_nil(cfg.Fish[row.Id], row.Id) end
            if zoneId == 'WaterCircle2' then
                assert.are.equal(13, #rows) -- #134：6 普通 + 电鳗 + 6 极品
                assert.same({ Id = 'eel', Bait = 'worm', RodLevel = 1, DrawWeight = 10 }, rows[7])
            end
        end
    end)

    it('test_held_fish_killed_is_released_and_loot_lands_at_holders_feet', function()
        local fish = env:land(env.player, 'bass', 1.3)
        fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
        env.pushed = {}
        env.groundY = 0.2
        env:kill(fish)
        assert.is_nil(env.mgr:GetHeld(env.player))
        assert.is_true(env:mounts()[1].Destroyed)
        assert.same(env.player, env.pushed[#env.pushed])
        local unit = env:lootUnits()[1]
        assert.are.equal(env.player.Character.Position.x, unit.Position.x)
        assert.are.equal(env.player.Character.Position.z, unit.Position.z)
        assert.is_true(unit.Position.y >= 0.2 and unit.Position.y < 1)
        assert.are.equal(1.3, env:onlyLoot().Mult)
        assert.is_true(env.mgr:CanCast(env.player))
    end)

    it('test_pickup_checks_target_and_distance', function()
        local fish = env:land(env.player, 'bass', 1.3)
        env:kill(fish)
        local loot = env:onlyLoot()
        for _, bad in ipairs({ 'x', 1.5, -1, 999 }) do
            assert.is_false(env.loot:Pickup(env.player, bad))
        end
        env.other.Character.Position = vec(loot.Position.x + 3, loot.Position.y, loot.Position.z)
        assert.is_false(env.loot:Pickup(env.other, loot.Id))
        assert.is_not.is_nil(env.loot.Loots[loot.Id])
        assert.is_nil(env:bar(env.other)[2])
        env.other.Character.Position = vec(loot.Position.x + 1.8, loot.Position.y + 0.8, loot.Position.z)
        assert.is_true(env.loot:Pickup(env.other, loot.Id))
        assert.same({ itemId = 'bass', count = 1, containerId = 'itemBar', mult = 1.3 }, env:bar(env.other)[2])
    end)

    it('test_pickup_success_destroys_loot_syncs_and_replay_gives_nothing', function()
        local fish = env:land(env.player, 'goldfish', 1.9)
        env:kill(fish)
        local loot = env:onlyLoot()
        local unit = env:lootUnits()[1]
        env.other.Character.Position = loot.Position
        env.player.Character.Position = loot.Position
        local before = env.broadcasts
        assert.is_true(env.loot:Pickup(env.player, loot.Id))
        assert.is_false(env.loot:Pickup(env.player, loot.Id))
        assert.is_false(env.loot:Pickup(env.other, loot.Id))
        assert.is_true(unit.Destroyed)
        assert.is_nil(env.loot.Loots[loot.Id])
        assert.same({ env.player }, env.synced)
        assert.is_true(env.broadcasts > before)
        assert.is_nil(env:bar(env.other)[2])
        local count = 0
        for _, entry in pairs(env:bar(env.player)) do
            if entry.itemId == 'goldfish' then count = count + 1 end
        end
        assert.are.equal(1, count)
    end)

    it('test_pond_rare_death_drops_one_own_loot_and_pickup_keeps_mult', function()
        local cfg = require('common.GameCfg')
        for index, pair in ipairs(POND_RARES) do
            local mult = 1 + index / 10
            local fish = env:land(env.player, pair.id, mult)
            assert.are.equal(cfg.Fish[pair.id].Model, fish.Carrier.Opts.ModelId, pair.id)
            assert.are.equal(cfg.Fish[pair.id].Health, fish.Carrier.Opts.MaxHealth, pair.id)
            env:kill(fish)
            env:kill(fish)
            local loot = env:onlyLoot()
            assert.same({ pair.id, pair.id, mult }, { loot.ItemId, loot.FishId, loot.Mult })
            local units = env:lootUnits()
            assert.are.equal(1, #units, pair.id)
            assert.are.equal('official://mesh/' .. cfg.Fish[pair.id].Model, units[1].RenderMeshId)
            env.player.Character.Position = loot.Position
            assert.is_true(env.loot:Pickup(env.player, loot.Id))
            assert.is_nil(next(env.loot.Loots))
            local snapshot = env.data[env.player.UserId]:GetItemBarSnapshot()
            local found = {}
            for _, list in ipairs({ snapshot.slots, snapshot.backpack }) do
                for _, entry in pairs(list) do
                    if entry.itemId == pair.id then found[#found + 1] = entry end
                end
            end
            assert.are.equal(1, #found, pair.id)
            assert.are.equal(mult, found[1].mult)
        end
    end)

    it('test_pond_rares_match_source_rows_and_are_catchable', function()
        local cfg = assert(loadfile('common/GameCfg.lua'))()
        local rows = cfg.Casting.Zones.WaterCircle2
        local byId = {}
        for _, row in ipairs(rows) do byId[row.Id] = row end
        for _, pair in ipairs(POND_RARES) do
            local rare, base = cfg.Fish[pair.id], cfg.Fish[pair.base]
            assert.is_true(rare.implemented, pair.id)
            assert.are.equal('极品' .. base.Name, rare.Name, pair.id)
            -- 模型按鱼名复用同名普通鱼，并在鱼载体表内
            assert.are.equal(base.Model, rare.Model, pair.id)
            assert.is_not.is_nil(cfg.FishCarrier.Models[rare.Model], pair.id)
            assert.same({ { ItemId = pair.id, Count = 1 } }, rare.Drops)
            -- 抽签行与鱼种表（原表）同源
            assert.same({ Id = pair.id, Bait = rare.Bait, RodLevel = rare.RodLevel, DrawWeight = rare.DrawWeight }, byId[pair.id])
            -- 抽奖机赌注资格：物品表类别「极品食物」、已接入、有图标
            local item = cfg.Items.Definitions[pair.id]
            assert.same({ rare.Name, '极品食物', true }, { item.Name, item.Type, item.implemented })
            assert.are.equal(rare.BasePrice, item.BasePrice, pair.id)
            assert.is_not.is_nil(item.Icon, pair.id)
        end
        -- 原表数值逐行钉住（血量/重量/鱼饵/竿级/权重/价格；R11/R12 与普通同号行对调，按原表保留）
        local source = {
            item7 = { 5, 1, 0, 1, 2, 3 }, item8 = { 10, 5, 'worm', 1, 2, 4 }, item9 = { 15, 0.5, 'worm', 1, 2, 5 },
            item10 = { 20, 2, 'worm', 1, 8, 6 }, item11 = { 25, 5, 'worm', 1, 6, 7 }, item12 = { 3, 0.1, 'worm', 1, 4, 8 },
        }
        for id, values in pairs(source) do
            local f = cfg.Fish[id]
            assert.same(values, { f.Health, f.BaseWeight, f.Bait, f.RodLevel, f.DrawWeight, f.BasePrice }, id)
            assert.same({ 0, 3, 1, 'fishPond', 'rare' }, { f.Attack, f.Speed, f.EscapeSec, f.ZoneId, f.Grade }, id)
        end
        -- 不挂饵只出罗非鱼保底（含极品）；蚯蚓 1 级竿 13 行全可出
        assert.same({ tilapia = true, item7 = true }, selectable(rows, 1, nil))
        local worm = selectable(rows, 1, 'worm')
        local count = 0
        for _ in pairs(worm) do count = count + 1 end
        assert.are.equal(13, count)
        for _, pair in ipairs(POND_RARES) do assert.is_true(worm[pair.id], pair.id) end
        -- 鱼塘外圈条带水域共用同一张表
        assert.same(rows, cfg.Casting.Zones.PondWest_1_1)
    end)
end)
