-- #90 迁移：特殊道具服务端接缝（原 tests/gameplay/special_item_mgr_test.lua，1 类 27 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（单类，方法按字典序）。
-- #140 T19 特殊道具：服务端接缝（MgrSpecialItem 的选中调和、飞行驱动、吐息结算、冷却镜像）。
-- 纯逻辑用例见 tests/native/special_item_test.lua；这里只测「接缝有没有被正确驱动」，
-- 引擎侧（Character.Position/Controller.GravityEnabled/EggyAppearance）与协作管理器
-- （Vitals/PlayerData/FishUnit/REUtil/Players/World）全部以桩注入。
--
-- 失败方式（先列后写）：
--   1. 选中不生效：选中 item169 不背负/不关重力，选中 item170 不换皮肤；
--   2. 切换 / 丢弃后残留：旧外观未解绑或皮肤未复位、滞空（重力未恢复、holding 未清）；
--   3. 死亡 / 濒死（CanAct=false）不清理：还在飞、还能吐息；
--   4. 摆渡钩子不结束飞行：传送后重力残留关闭、继续滞空；
--   5. 离线重进复活飞行状态，或冷却镜像丢失 / 翻倍（重进即重置 CD）；
--   6. 吐息 CD 被切换 / 死亡清掉（冷却必须只依赖绝对时刻）；
--   7. 吐息旁路伤害（不走 Vitals:NewHit/ApplyHit），或同一目标被重复段结算；
--   8. 玩家吐息误用首领配置（BossPhase 的 10 米 OneShot 秒杀），或首领路径误读玩家配置；
--   9. 两玩家状态串扰（身份隔离）；
--  10. 吐息打中自己，或打中走廊外 / 背后 / 超 30 米的目标；
--  11. 未选中翅膀也能收 fly 指令升空；
--  12. 地面待机也关重力（跳跃 / 走下台阶即漂浮滞空），或落地后不交还重力；
--  13. 缓降被高于区地面基准的地形托住时仍判空中、重力一直关闭（站在礁石上滞空）；
--  14. 通道限频吞掉紧跟按下的「松开」，holding 卡死一路升到顶。
--
-- 迁移纪律：旧 setUp 会就地改 GameCfg 的两条外观资源 id，并在 tearDown 复原；
-- helper 的根级快照只管 Debug / AcceptanceSlot，覆盖不到这两个字段，所以本 spec 自己存自己回，
-- 且快照在任何赋值之前取（before_each 半路抛错时 after_each 仍会跑，见 issue-90-mapping.md 探针）。
local GameCfg = require('common.GameCfg')

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn) callbacks[#callbacks + 1] = fn end,
        Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
    }
end

-- 角色替身：记录外观接缝调用；Position 可写（服务端逐帧写回是 #132 已验证的接缝）
local function newCharacter(x, y, z, fx, fz)
    local ch = {
        Position = vec(x, y, z),
        Rotation = { GetForward = function() return { x = fx or 0, y = 0, z = fz or 1 } end },
        Controller = { GravityEnabled = true, WalkSpeed = 6, Health = 100, MaxHealth = 100 },
        Calls = {},
    }
    ch.EggyAppearance = {
        BindAppearance = function(_, appearanceId, socket, offset, rot, scale)
            ch.Calls[#ch.Calls + 1] = { 'bind', appearanceId, socket, offset, rot, scale }
            return 77
        end,
        UnbindAppearance = function(_, bindId)
            ch.Calls[#ch.Calls + 1] = { 'unbind', bindId }
            return true
        end,
        SetAppearanceByAssetId = function(_, assetId)
            ch.Calls[#ch.Calls + 1] = { 'skin', assetId }
        end,
        ResetAppearance = function()
            ch.Calls[#ch.Calls + 1] = { 'resetSkin' }
        end,
    }
    return ch
end

local function hasCall(ch, kind)
    for _, call in ipairs(ch.Calls) do
        if call[1] == kind then return true end
    end
    return false
end

-- 存档替身：只带本模块会读的字段（选中槽、区、冷却镜像）
local function newData(zone, slot, itemId)
    local bar = {}
    if slot and itemId then bar[slot] = { itemId = itemId, count = 1 } end
    return {
        Data = { SelectedSlot = slot, Zone = zone,
            Containers = { itemBar = bar } },
        Extra = { cooldowns = {} },
    }
end

describe('TestSpecialItemMgr', function()
    local ctx
    local saved
    before_each(function()
        saved = { Vector3 = rawget(_G, 'Vector3'), game = rawget(_G, 'game'), REUtil = rawget(_G, 'REUtil'),
            mgr = package.loaded['server.Mgr.MgrSpecialItem'], Enums = rawget(_G, 'Enums'),
            Quaternion = rawget(_G, 'Quaternion'),
            wingAsset = GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId,
            skinAsset = GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId }
        ctx = { now = 1000, players = {}, events = {}, pushed = {}, alive = {}, hits = {}, dataByUser = {}, fish = {} }
        _G.Vector3 = { New = vec }
        _G.Enums = { SkeletalSocketType = { Spine = 'socket_body' } }
        _G.Quaternion = { Identity = function() return { x = 0, y = 0, z = 0, w = 1 } end }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return ctx.now end } end
            if name == 'Players' then return { GetPlayers = function() return ctx.players end } end
            return {}
        end }
        _G.REUtil = {
            CheckRECD = function() return false end,
            GetRE = function(_, name)
                if not ctx.events[name] then
                    ctx.events[name] = {
                        OnServerEvent = signal(),
                        FireClient = function(_, player, payload)
                            ctx.pushed[#ctx.pushed + 1] = { name = name, userId = player.UserId, payload = payload }
                            if name == 'SpecialItemResult' then player.lastResult = payload
                            else player.lastState = payload end
                        end,
                    }
                end
                return ctx.events[name]
            end,
        }
        package.loaded['server.Mgr.MgrSpecialItem'] = nil
        ctx.mgr = assert(loadfile('server/Mgr/MgrSpecialItem.lua'))()
        -- 协作接缝：Vitals / PlayerData / FishUnit 全桩
        ctx.mgr.Vitals = {
            CanAct = function(_, player) return ctx.alive[player.UserId] == true end,
            NewHit = function(_, source, category)
                return { source = source, category = category, targets = {} }
            end,
            -- 与 MgrVitals:ApplyHit 同契约：同一命中身份对同一目标只结算一次（DOT 每段须重新 NewHit）
            ApplyHit = function(_, hit, target, amount)
                if hit.targets[target] then return false end
                hit.targets[target] = true
                ctx.hits[#ctx.hits + 1] = { category = hit.category, target = target, amount = amount,
                    source = hit.source }
                return true
            end,
        }
        ctx.mgr.PlayerData = { GetDataInst = function(_, player) return ctx.dataByUser[player.UserId] end }
        ctx.mgr.FishUnit = { Fish = ctx.fish }
        -- 外观资源占位：配置空值时不调外观接缝；测试填入占位资源验证接缝被驱动
        GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = 'wingAssetPlaceholder'
        GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = 'godzillaSkinPlaceholder'
        ctx.mgr:Start()
    end)
    after_each(function()
        GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = saved.wingAsset
        GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = saved.skinAsset
        _G.Enums = saved.Enums
        _G.Quaternion = saved.Quaternion
        _G.Vector3 = saved.Vector3
        _G.game = saved.game
        _G.REUtil = saved.REUtil
        package.loaded['server.Mgr.MgrSpecialItem'] = saved.mgr
    end)

    local function addPlayer(userId, x, y, z, itemId, fx, fz)
        local player = { UserId = userId, Character = newCharacter(x, y, z, fx, fz) }
        ctx.players[#ctx.players + 1] = player
        ctx.alive[userId] = true
        ctx.dataByUser[userId] = newData('fishPond', itemId and 1 or nil, itemId)
        ctx.mgr:OnPlayerAdded(player)
        return player
    end

    local function selectItem(player, itemId)
        local data = ctx.dataByUser[player.UserId]
        data.Data.Containers.itemBar[1] = itemId and { itemId = itemId, count = 1 } or nil
        data.Data.SelectedSlot = itemId and 1 or nil
    end

    local function fire(player, payload)
        ctx.events.SpecialItemAction.OnServerEvent:Fire(player, payload)
    end

    local function step(frames, dt)
        for _ = 1, frames do
            ctx.now = ctx.now + dt
            ctx.mgr:Update(dt)
        end
    end

    -- 旧文件的 rejoinWithPendingCleanup 是被两条用例复用的辅助方法（名字不以 test_ 开头，LuaUnit 不执行）；
    -- 这里同样作为 describe 内的局部函数，注册顺序不影响执行。
    local function rejoinWithPendingCleanup(persistent)
        local old = addPlayer(1, 6, 5.01, 40, 'item170')
        step(1, 0.05)
        fire(old, { action = 'breath' })
        step(20, 0.05)
        ctx.mgr:BeforeLeave(old)
        local remaining = ctx.dataByUser[1].Extra.cooldowns.godzillaBreath
        local previousState = ctx.mgr.States[1]
        local resets = 0
        old.Character.EggyAppearance.ResetAppearance = function()
            resets = resets + 1
            if persistent or resets <= 1 then error('old-reset-failed') end
        end
        ctx.mgr:OnPlayerRemoving(old)
        local fresh = { UserId = 1, Character = newCharacter(6, 5.01, 40) }
        ctx.players = { fresh }
        ctx.mgr:OnPlayerAdded(fresh)
        local current = ctx.mgr.States[1]
        assert.is_not.same(current, previousState)
        assert.message('旧清理只能持有旧玩家').same(old, previousState.player)
        step(100, 0.05)
        assert.message('旧清理不得删除新会话').same(current, ctx.mgr.States[1])
        assert.same(fresh, current.player)
        assert.same('godzilla', current.effect)
        assert.is_false(current.restoring == true)
        assert.is_true(hasCall(fresh.Character, 'skin'))
        assert.message('旧清理不能复位新角色').is_false(hasCall(fresh.Character, 'resetSkin'))
        assert.near(remaining - 5, ctx.dataByUser[1].Extra.cooldowns.godzillaBreath, 0.01)
        fire(fresh, { action = 'breath' })
        assert.same('cooldown', fresh.lastResult.reason)
        -- 迟到的旧会话退出不能删除新会话
        ctx.mgr:OnPlayerRemoving(old)
        assert.same(current, ctx.mgr.States[1])
        return function() return resets end
    end

    -- 失败方式 6：切换 / 死亡清不掉冷却（冷却只依赖绝对时刻）
    it('test_breath_cooldown_survives_switch_and_death', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item170')
        step(1, 0.05)
        fire(player, { action = 'breath' })
        assert.is_true(player.lastResult.ok)
        step(8, 0.5) -- 吐息走完，冷却剩 16 秒
        -- 切换走再切回来
        selectItem(player, 'item169')
        step(2, 0.05)
        selectItem(player, 'item170')
        step(2, 0.05)
        assert.same('godzilla', ctx.mgr.States[1].effect)
        fire(player, { action = 'breath' })
        assert.message('切换不得清冷却').is_false(player.lastResult.ok)
        -- 死亡再复活
        ctx.alive[1] = false
        step(2, 0.05)
        ctx.alive[1] = true
        step(2, 0.05)
        fire(player, { action = 'breath' })
        assert.message('死亡不得清冷却').is_false(player.lastResult.ok)
        -- 冷却真的到期后能放
        step(40, 0.5)
        fire(player, { action = 'breath' })
        assert.is_true(player.lastResult.ok)
    end)

    -- 失败方式 7/8/10：吐息经 Vitals 结算走廊内目标（玩家 + 鱼），每目标恰 1000、无重复段；
    -- 30 米内有效（证明没读首领 10 米配置）；自己、背后、走廊外、超程目标不挨打
    it('test_breath_settles_corridor_targets_via_vitals', function()
        local caster = addPlayer(1, 0, 5.01, 40, 'item170', 0, 1) -- 朝 +z
        local victim = addPlayer(2, 1, 5.01, 60, nil)             -- 正前 20 米（首领 10 米够不着）
        local behind = addPlayer(3, 0, 5.01, 30, nil)             -- 背后
        local offSide = addPlayer(4, 20, 5.01, 50, nil)           -- 走廊外
        local far = addPlayer(5, 0, 5.01, 75, nil)                -- 35 米超程
        ctx.fish[9] = { Id = 9, Carrier = { Body = { Position = vec(0, 5, 55) }, Dead = false } }
        step(1, 0.05)
        fire(caster, { action = 'breath' })
        assert.is_true(caster.lastResult.ok)
        step(7, 0.5) -- 3.5 秒：吐息 3 秒走完
        assert.message('吐息窗口必须收尾').is_nil(ctx.mgr.States[1].breath)
        -- 每目标总额与身份
        local byTarget = {}
        for _, hit in ipairs(ctx.hits) do
            assert.same('specialBreath', hit.category)
            assert.same(caster, hit.source)
            byTarget[hit.target] = (byTarget[hit.target] or 0) + hit.amount
        end
        assert.message('每个目标总伤害恰 1000').same(1000, byTarget[victim])
        assert.same(1000, byTarget[ctx.fish[9].Carrier])
        assert.message('不得打自己').is_nil(byTarget[caster])
        assert.message('背后不挨打').is_nil(byTarget[behind])
        assert.message('走廊外不挨打').is_nil(byTarget[offSide])
        assert.message('超 30 米不挨打').is_nil(byTarget[far])
    end)

    -- 失败方式 15：施法后还没心跳就离线，冷却镜像必须已写入，不能重进清 CD
    it('test_cast_immediately_mirrors_cooldown_before_disconnect', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item170')
        step(1, 0.05)
        fire(player, { action = 'breath' })
        assert.is_true(player.lastResult.ok)
        assert.same(20, ctx.dataByUser[1].Extra.cooldowns.godzillaBreath)
    end)

    it('test_cleanup_failure_history_is_bounded_and_has_no_object_references', function()
        for id = 1, 20 do
            local p = addPlayer(id, 6, 5.01, 40, 'item170')
            step(1, 0.05)
            p.Character.EggyAppearance.ResetAppearance = function() error('reset-permanent') end
            ctx.mgr:OnPlayerRemoving(p)
        end
        step(150, 0.05)
        assert.same(16, #ctx.mgr.CleanupFailures)
        assert.is_nil(next(ctx.mgr.PendingCleanup))
        for _, record in ipairs(ctx.mgr.CleanupFailures) do
            for _, value in pairs(record) do
                assert.is_true(type(value) == 'string' or type(value) == 'number')
            end
        end
    end)

    -- 失败方式 3：死亡 / 濒死清理效果并拒绝动作；复活后按选中重放
    it('test_death_clears_effect_and_blocks_actions_until_revive', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        step(10, 0.05)
        ctx.alive[1] = false -- 濒死 / 死亡
        step(1, 0.05)
        assert.message('死亡必须清掉生效效果').is_nil(ctx.mgr.States[1].effect)
        assert.is_true(player.Character.Controller.GravityEnabled)
        fire(player, { action = 'fly', holding = true })
        assert.message('死亡中拒绝飞行指令').is_false(ctx.mgr.States[1].holding)
        assert.is_false(player.lastResult.ok)
        -- 复活：选中未变，效果重放
        ctx.alive[1] = true
        step(1, 0.05)
        assert.same('wings', ctx.mgr.States[1].effect)
    end)

    -- 失败方式 13：缓降途中被地形（礁石 / 屋顶，高于区地面基准）托住 → 判落地、交还重力
    it('test_descent_blocked_by_terrain_lands_and_restores_gravity', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        step(20, 0.1) -- 升到 CeilingY 25.01
        fire(player, { action = 'fly', holding = false })
        local terrainY = 15
        for _ = 1, 60 do
            step(1, 0.1)
            -- 引擎碰撞：角色不会穿进地形，被顶回地形表面
            local pos = player.Character.Position
            if pos.y < terrainY then player.Character.Position = vec(pos.x, terrainY, pos.z) end
        end
        assert.message('被地形托住应判落地').is_false(ctx.mgr.States[1].airborne)
        assert.message('落地后重力恢复').is_true(player.Character.Controller.GravityEnabled)
        assert.near(terrainY, player.Character.Position.y, 0.01)
    end)

    -- 引擎抛错不能当成功，清理失败必须保留对象与标志以便重试
    it('test_engine_failures_keep_cleanup_and_retry', function()
        local p = addPlayer(1, 6, 5.01, 40, 'item169')
        local appearance = p.Character.EggyAppearance
        local bind = appearance.BindAppearance
        appearance.BindAppearance = function() error('bind-failed') end
        step(1, 0.05)
        assert.is_nil(ctx.mgr.States[1].effect)
        appearance.BindAppearance = bind
        step(30, 0.05)
        assert.same('wings', ctx.mgr.States[1].effect)
        local unbind = appearance.UnbindAppearance
        appearance.UnbindAppearance = function() error('unbind-failed') end
        selectItem(p, nil)
        step(1, 0.05)
        assert.same(77, ctx.mgr.States[1].wingBindId)
        appearance.UnbindAppearance = unbind
        step(30, 0.05)
        assert.is_nil(ctx.mgr.States[1].wingBindId)
        selectItem(p, 'item170')
        step(1, 0.05)
        local reset = appearance.ResetAppearance
        appearance.ResetAppearance = function() error('reset-failed') end
        selectItem(p, nil)
        step(1, 0.05)
        assert.is_true(ctx.mgr.States[1].skinApplied)
        appearance.ResetAppearance = reset
        step(30, 0.05)
        assert.is_false(ctx.mgr.States[1].skinApplied)
    end)

    it('test_ferry_public_teleport_cancels_breath_and_appearance_keeps_cooldown', function()
        local p = addPlayer(1, 6, 5.01, 40, 'item170')
        addPlayer(2, 6, 5.01, 50)
        step(1, 0.05)
        fire(p, { action = 'breath' })
        step(1, 0.05)
        local count, castAt = #ctx.hits, ctx.mgr.States[1].lastBreathAt
        local ferry = assert(loadfile('server/Mgr/MgrFerry.lua'))()
        ferry.SpecialItem = ctx.mgr
        assert.is_true(ferry:Teleport(p, { x = 100, y = 6, z = 100 }))
        step(80, 0.05)
        assert.message('摆渡后旧区不能继续吃吐息段').same(count, #ctx.hits)
        assert.is_nil(ctx.mgr.States[1].breath)
        assert.is_nil(ctx.mgr.States[1].effect)
        assert.is_false(ctx.mgr.States[1].skinApplied)
        assert.same(castAt, ctx.mgr.States[1].lastBreathAt)
        selectItem(p, 'item169')
        step(1, 0.05)
        fire(p, { action = 'fly', holding = true })
        step(1, 0.05)
        assert.is_true(ferry:Teleport(p, { x = 6, y = 5.01, z = 40 }))
        step(1, 0.05)
        assert.is_nil(ctx.mgr.States[1].wingBindId)
        assert.is_nil(ctx.mgr.States[1].effect)
        assert.is_true(p.Character.Controller.GravityEnabled)
    end)

    -- 失败方式（跨区）：空中水平越界被钳回本区（不能借飞行跨区）
    it('test_flight_clamps_horizontal_position_inside_the_zone', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        step(5, 0.05)
        -- 外部力量（客户端预测 / 击退）把角色推出围栏：下一帧必须钳回
        player.Character.Position = vec(999, player.Character.Position.y, 40)
        step(1, 0.05)
        assert.message('x ' .. tostring(player.Character.Position.x)).is_true(player.Character.Position.x <= 60)
        player.Character.Position = vec(6, player.Character.Position.y, -500)
        step(1, 0.05)
        assert.message('z ' .. tostring(player.Character.Position.z)).is_true(player.Character.Position.z >= -50)
    end)

    -- 失败方式 1 补充：飞行到顶钳住、松开缓降落地后重力交还
    it('test_flight_climbs_to_ceiling_then_descends_and_lands', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        step(60, 0.1) -- 6 秒：8 m/s 早就该到顶（CeilingY = 25.01）
        assert.near(25.01, player.Character.Position.y, 0.01)
        fire(player, { action = 'fly', holding = false })
        step(80, 0.1) -- 8 秒缓降：3 m/s 降 24 米，早该落地
        assert.near(5.01, player.Character.Position.y, 0.01)
        assert.is_false(ctx.mgr.States[1].airborne)
        -- 失败方式 12：落地即交还重力；实际地形低于区地面基准时由引擎重力接着落下，不悬在基准面
        assert.message('落地后重力恢复').is_true(player.Character.Controller.GravityEnabled)
    end)

    -- 失败方式 11：未选中翅膀时 fly 指令被拒，不改变运动状态
    it('test_fly_rejected_without_wings_selected', function()
        local player = addPlayer(1, 6, 5.01, 40, 'carp')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        assert.is_false(ctx.mgr.States[1].holding)
        assert.is_false(player.lastResult.ok)
        step(10, 0.05)
        assert.message('未选翅膀不得升空').same(5.01, player.Character.Position.y)
        assert.is_true(player.Character.Controller.GravityEnabled)
    end)

    -- 失败方式 1/2：选中哥斯拉即变身（换皮肤），切走复位；不碰体型（三倍叠加由 #132 独立管）
    it('test_godzilla_transform_sets_and_resets_skin_without_touching_scale', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item170')
        step(1, 0.05)
        assert.same('godzilla', ctx.mgr.States[1].effect)
        assert.is_true(hasCall(player.Character, 'skin'))
        assert.message('变身不改移动参数').same(6, player.Character.Controller.WalkSpeed)
        selectItem(player, nil)
        step(1, 0.05)
        assert.is_true(hasCall(player.Character, 'resetSkin'))
        assert.is_nil(ctx.mgr.States[1].effect)
    end)

    it('test_gravity_exception_retains_restore_flag', function()
        local p = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(p, { action = 'fly', holding = true })
        step(1, 0.05)
        local original = p.Character.Controller
        p.Character.Controller = setmetatable({}, { __newindex = function() error('gravity-failed') end })
        selectItem(p, nil)
        step(1, 0.05)
        assert.is_true(ctx.mgr.States[1].gravityOff)
        p.Character.Controller = original
        step(30, 0.05)
        assert.is_false(ctx.mgr.States[1].gravityOff)
        assert.is_true(original.GravityEnabled)
    end)

    -- 失败方式 5：离线重进不复活飞行状态；冷却镜像按剩余秒数恢复（不重置）
    it('test_offline_rejoin_restores_cooldown_without_reviving_flight', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item170')
        step(1, 0.05)
        fire(player, { action = 'breath' })
        assert.is_true(player.lastResult.ok)
        local data = ctx.dataByUser[1]
        step(4, 0.5) -- 吐息 3 秒走完，冷却剩 18 秒
        assert.near(18, data.Extra.cooldowns.godzillaBreath, 0.6)
        -- 离场：镜像留在存档；重进：恢复成绝对时刻（CD 还剩多少就剩多少）
        ctx.mgr:OnPlayerRemoving(player)
        assert.is_nil(ctx.mgr.States[1])
        ctx.now = ctx.now + 6 -- 离线 6 秒
        local rejoined = { UserId = 1, Character = newCharacter(6, 5.01, 40) }
        ctx.players = { rejoined }
        ctx.mgr:OnPlayerAdded(rejoined)
        local state = ctx.mgr.States[1]
        assert.message('重进不得复活滞空').is_false(state.airborne)
        assert.message('重进不得残留关重力').is_true(rejoined.Character.Controller.GravityEnabled)
        step(1, 0.05) -- 调和：变身重放（选中未变）
        assert.same('godzilla', state.effect)
        -- CD 剩约 12 秒：现在放不出吐息
        fire(rejoined, { action = 'breath' })
        assert.is_false(rejoined.lastResult.ok)
        assert.same('cooldown', rejoined.lastResult.reason)
    end)

    it('test_query_recovers_dropped_initial_snapshot_without_mutation', function()
        local p = addPlayer(1, 6, 5.01, 40, 'item170')
        step(1, 0.05)
        fire(p, { action = 'breath' })
        local castAt = ctx.mgr.States[1].lastBreathAt
        p.lastState = nil
        ctx.events.SpecialItemStateRequest.OnServerEvent:Fire(p)
        assert.same('godzilla', p.lastState.effect)
        assert.near(20, p.lastState.breathRemaining, 0.001)
        assert.same(castAt, ctx.mgr.States[1].lastBreathAt)
    end)

    it('test_rejoin_survives_old_cleanup_eventually_succeeding', function()
        local count = rejoinWithPendingCleanup(false)
        assert.is_true(count() >= 2)
    end)

    it('test_rejoin_survives_old_cleanup_persistently_failing', function()
        local count = rejoinWithPendingCleanup(true)
        step(800, 0.05)
        assert.same(6, count()) -- 首次清理 + 五次重试
        assert.message('旧清理重试必须有界').is_true(count() <= 6)
        assert.same('godzilla', ctx.mgr.States[1].effect)
    end)

    -- 失败方式 14：快速点按时松开落在限频窗口内，也必须生效（停止只会更安全，不限频）
    it('test_release_bypasses_rate_limit', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        assert.is_true(ctx.mgr.States[1].holding)
        _G.REUtil.CheckRECD = function() return true end -- 之后的请求都落在限频窗口内
        fire(player, { action = 'fly', holding = false })
        assert.message('松开被限频吞掉').is_false(ctx.mgr.States[1].holding)
        fire(player, { action = 'fly', holding = true })
        assert.message('按下仍受限频').is_false(ctx.mgr.States[1].holding)
    end)

    -- 失败方式 1：选中即背负（BindAppearance 驱动、重力关闭接管 y）
    it('test_selecting_wings_binds_appearance_and_takes_over_gravity', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        assert.same('wings', ctx.mgr.States[1].effect)
        assert.is_true(hasCall(player.Character, 'bind'))
        -- 失败方式 12：地面待机保留重力（关重力会让跳跃 / 走下台阶直接漂浮）
        assert.message('地面待机不接管重力').is_true(player.Character.Controller.GravityEnabled)
        fire(player, { action = 'fly', holding = true })
        step(1, 0.05)
        assert.message('长按起飞才接管 y').is_false(player.Character.Controller.GravityEnabled)
    end)

    -- 失败方式 17：非空外观资源时挂点不是枚举值，或缺 rot / scale 必需参数
    it('test_skin_apply_exception_does_not_report_effect', function()
        local p = addPlayer(1, 6, 5.01, 40, 'item170')
        local appearance = p.Character.EggyAppearance
        local original = appearance.SetAppearanceByAssetId
        appearance.SetAppearanceByAssetId = function() error('skin-failed') end
        step(1, 0.05)
        assert.is_nil(ctx.mgr.States[1].effect)
        assert.is_false(ctx.mgr.States[1].skinApplied)
        appearance.SetAppearanceByAssetId = original
        step(30, 0.05)
        assert.same('godzilla', ctx.mgr.States[1].effect)
    end)

    -- 失败方式 2：切换 / 丢弃后恢复原外观与运动状态（解绑、重力恢复、不滞空）
    it('test_switching_away_restores_appearance_and_motion', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        -- 升空后切走：半空中切道具也必须恢复重力（不滞空）
        fire(player, { action = 'fly', holding = true })
        step(20, 0.05) -- 1 秒，升到 5.01 + 8 = 13 左右
        assert.is_true(player.Character.Position.y > 6)
        selectItem(player, 'carp')
        step(1, 0.05)
        assert.is_nil(ctx.mgr.States[1].effect)
        assert.is_true(hasCall(player.Character, 'unbind'))
        assert.message('切换后重力必须恢复').is_true(player.Character.Controller.GravityEnabled)
        assert.is_false(ctx.mgr.States[1].airborne)
        assert.is_false(ctx.mgr.States[1].holding)
        -- 丢弃（槽位清空、选中取消）同样恢复
        selectItem(player, 'item169')
        step(1, 0.05)
        assert.same('wings', ctx.mgr.States[1].effect)
        selectItem(player, nil)
        step(1, 0.05)
        assert.is_nil(ctx.mgr.States[1].effect)
        assert.is_true(player.Character.Controller.GravityEnabled)
    end)

    it('test_takeoff_below_safe_point_integrates_without_teleport', function()
        local p = addPlayer(1, 6, 1, 40, 'item169')
        step(1, 0.05)
        fire(p, { action = 'fly', holding = true })
        ctx.mgr:Update(0)
        assert.same(1, p.Character.Position.y)
        step(1, 0.1)
        assert.near(1.8, p.Character.Position.y, 0.001)
        fire(p, { action = 'fly', holding = false })
        step(1, 0.1)
        assert.near(1.5, p.Character.Position.y, 0.001)
        fire(p, { action = 'fly', holding = true })
        step(80, 0.1)
        assert.message('实际起飞地面上限20米').near(21, p.Character.Position.y, 0.001)
    end)

    -- 失败方式 4：摆渡钩子结束飞行（重力恢复、不滞空），外观随新区调和重放
    it('test_teleport_hook_ends_flight_motion', function()
        local player = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        fire(player, { action = 'fly', holding = true })
        step(10, 0.05)
        ctx.mgr:OnTeleport(player)
        assert.is_true(player.Character.Controller.GravityEnabled)
        assert.is_false(ctx.mgr.States[1].airborne)
        assert.is_false(ctx.mgr.States[1].holding)
        -- 摆渡后必须重新选中，不能自动重挂外观
        step(1, 0.05)
        assert.is_nil(ctx.mgr.States[1].effect)
        selectItem(player, nil)
        step(1, 0.05)
        selectItem(player, 'item169')
        step(1, 0.05)
        assert.same('wings', ctx.mgr.States[1].effect)
        assert.is_true(player.Character.Controller.GravityEnabled)
        fire(player, { action = 'fly', holding = true })
        step(1, 0.05)
        assert.is_false(player.Character.Controller.GravityEnabled)
    end)

    -- 失败方式 9：两玩家状态隔离（A 变身 / 飞行不影响 B）
    it('test_two_players_states_are_isolated', function()
        local a = addPlayer(1, 6, 5.01, 40, 'item170')
        local b = addPlayer(2, 100, 6, 100, nil)
        ctx.dataByUser[2].Data.Zone = 'shrimpPond'
        step(1, 0.05)
        assert.same('godzilla', ctx.mgr.States[1].effect)
        assert.is_nil(ctx.mgr.States[2].effect)
        assert.is_true(b.Character.Controller.GravityEnabled)
        fire(a, { action = 'breath' })
        step(8, 0.5)
        assert.message('A 的冷却不得落到 B 头上').is_nil(ctx.mgr.States[2].lastBreathAt)
        -- B 在 A 的 30 米走廊外（另一区），不挨打
        for _, hit in ipairs(ctx.hits) do
            assert.is_not.same(b, hit.target)
        end
    end)

    -- 失败方式 16：Player 在引擎中不是 Lua table，不能按 type(player) 拒绝；身份须与注册对象一致
    it('test_unregistered_player_cannot_create_state_through_request', function()
        local impostor = { UserId = 999, Character = newCharacter(6, 5.01, 40) }
        assert.is_false(ctx.mgr:Handle(impostor, { action = 'fly', holding = true }))
        assert.message('未经 OnPlayerAdded 的请求不能创建状态').is_nil(ctx.mgr.States[999])
    end)

    -- 用 userdata 代理复现引擎 Player 的类型边界，身份必须精确匹配登记对象
    it('test_userdata_player_allowed_only_when_registered_object_matches', function()
        local original = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        local proxy = assert(io.tmpfile())
        local mt = getmetatable(proxy)
        debug.setmetatable(proxy, { __index = original })
        -- 旧文件把断言包在 pcall 里再 assert(ok, err)：代理的元表必须在任何失败路径下都被还原，
        -- 否则 io.tmpfile 的共享元表被改坏，后续案例会以莫名其妙的方式失败。迁移保留这层 pcall。
        local ok, err = pcall(function()
            assert.same('userdata', type(proxy))
            -- 同 UserId 不同对象仍拒绝
            assert.is_false(ctx.mgr:Handle(proxy, { action = 'fly', holding = true }))
            ctx.mgr.States[1].player = proxy
            assert.is_true(ctx.mgr:Handle(proxy, { action = 'fly', holding = true }))
            assert.is_true(ctx.mgr.States[1].holding)
            assert.is_false(ctx.mgr:Handle(original, { action = 'fly', holding = false }))
            assert.message('冒用 UserId 不得修改已登记玩家状态').is_true(ctx.mgr.States[1].holding)
        end)
        debug.setmetatable(proxy, mt)
        proxy:close()
        assert(ok, err)
    end)

    it('test_wing_binding_matches_engine_signature', function()
        local p = addPlayer(1, 6, 5.01, 40, 'item169')
        step(1, 0.05)
        local bind
        for _, call in ipairs(p.Character.Calls) do if call[1] == 'bind' then bind = call end end
        assert.is_not_nil(bind)
        assert.same(_G.Enums.SkeletalSocketType.Spine, bind[3])
        assert.same(vec(0, 0, 0), bind[4])
        assert.same({ x = 0, y = 0, z = 0, w = 1 }, bind[5])
        assert.same(vec(1, 1, 1), bind[6])
        selectItem(p, nil)
        step(1, 0.05)
        local unbind
        for _, call in ipairs(p.Character.Calls) do if call[1] == 'unbind' then unbind = call end end
        assert.same(77, unbind[2])
    end)
end)
