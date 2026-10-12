-- #89 迁移（原 tests/gameplay/status_effect_test.lua，#139 T18 大奖成长切片 3）：
-- MgrAbility 持续效果状态机与属性应用。
-- 失败方式（先列后写）：
--   1. 毒/灼烧叠层无上限或刷新清零层数；DOT 不走 T07/#128 统一伤害入口（绕过 NewHit/ApplyHit）；
--   2. 霜冻/麻痹可叠加（重复命中把时间越加越长）；失效后状态残留继续生效；
--   3. 移速多写口：成长/虚弱/霜冻/麻痹各自写 WalkSpeed，恢复顺序丢成长（#131 已知边界根因）；
--   4. 目标离场（玩家退出/鱼移除）后状态不清理，DOT 打空目标、查询泄漏；
--   5. BodyPlan 读不存在的 player.Data 恒为 0（#132 原型死代码），存档里的药水永远不生效。
-- 接缝：loadfile 取全新 MgrAbility 实例；桩 _G.game（World:GetServerTime 可控时钟、Players）、
--   server.AbilityAPI；Vitals/PlayerData/Survival 以假实现注入（与 main.lua 的接线同形状）。
-- 旧 setUp/tearDown 逐例映射为 before_each/after_each：替换的全局（game / Vector3）、模块缓存
-- （server.AbilityAPI、server.Mgr.MgrAbility、common.REUtil）在 after_each 恢复，对未完成的
-- before_each 幂等。describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
local GameCfg = require('common.GameCfg')

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn) callbacks[#callbacks + 1] = fn
            return { Disconnect = function() end } end,
        Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
    }
end

-- 可拒写的控制器：写 WalkSpeed 时按开关抛错，用于「到期已删除而写速失败」的重试路径
local function rejectableSpeed(state)
    local value, writes, reject = 7, 0, false
    state.player.Character.Controller = setmetatable({}, {
        __index = function(_, k) if k == 'WalkSpeed' then return value end end,
        __newindex = function(_, k, v)
            if k == 'WalkSpeed' then
                writes = writes + 1
                if reject then error('瞬时拒写WalkSpeed') end
                value = v
            end
        end,
    })
    return function(v) reject = v end, function() return value, writes end
end

describe('TestStatusEffect', function()
    local ctx

    before_each(function()
        ctx = {
            now = 100,
            savedGame = rawget(_G, 'game'),
            savedAPI = package.loaded['server.AbilityAPI'],
            savedMgr = package.loaded['server.Mgr.MgrAbility'],
            bodyScales = {},
            hits = {},
            refreshedMaxHealth = {},
            potions = {},
            weak = false,
        }
        local state = ctx
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return state.now end,
                CreateAsset = function() return nil end } end
            if name == 'Players' then return { GetPlayerFromCharacter = function(_, unit)
                return unit and unit.PlayerRef or nil
            end } end
            if name == 'Task' then return { Spawn = function() end, Wait = function() end } end
            return {}
        end }
        package.loaded['server.AbilityAPI'] = {
            SetCastGuard = function() end,
            SetBodyScale = function(character, scale) -- 根 AbilityAPI 为点号调用
                state.bodyScales[#state.bodyScales + 1] = scale
                return { Ok = true, Scale = scale, Derived = {} }
            end,
        }
        state.mgr = assert(loadfile('server/Mgr/MgrAbility.lua'))()
        -- 假 Vitals：记录 DOT 结算（统一入口证据）
        state.mgr.Vitals = {
            NewHit = function(_, source, category) return { source = source, category = category, targets = {} } end,
            ApplyHit = function(_, hit, target, amount)
                state.hits[#state.hits + 1] = { target = target, amount = amount, category = hit.category,
                    source = hit.source }
                return true
            end,
            RefreshMaxHealth = function(_, player) state.refreshedMaxHealth[#state.refreshedMaxHealth + 1] = player; return true end,
            FishCarrier = nil, -- 按需在各用例里装
        }
        -- 假 PlayerData / Survival
        state.mgr.PlayerData = { GetDataInst = function() return {
            PotionCount = function(_, itemId) return state.potions[itemId] or 0 end } end }
        state.mgr.Survival = { GetState = function()
            return state.weak and { weakUntil = state.now + 60 } or nil
        end }
        state.runtime = require('tests.tooling.modifier_runtime').New(state.now)
        state.mgr.Modifier = state.runtime.loadModifier()
        state.mgr.Modifier.Vitals = state.mgr.Vitals
        state.mgr.Modifier.Ability = state.mgr
        state.mgr.Attr = require('tests.lib.attr_runtime').New(state.mgr.PlayerData,
            function(p) return state.mgr.Modifier:GetMoveMultiplier(p) end)
        local character = state.runtime.unit('character')
        character.Controller = { WalkSpeed = 7 }
        function character:SetScale(v) state.bodyScales[#state.bodyScales + 1] = v.x end
        state.player = { UserId = 13901, Character = character,
            CharacterAdded = signal(), CharacterRemoving = signal() }
        state.mgr.Attr.Vitals = state.mgr.Vitals
    end)

    after_each(function()
        if not ctx then return end
        _G.game = ctx.savedGame
        package.loaded['server.AbilityAPI'] = ctx.savedAPI
        package.loaded['server.Mgr.MgrAbility'] = ctx.savedMgr
    end)

    local function advance(sec)
        ctx.runtime.wait(sec)
        ctx.now = ctx.runtime.now
        ctx.mgr.Modifier:Update()
        ctx.mgr:Update(sec)
    end

    local function installFish()
        local carrier = { Body = ctx.runtime.unit('fish'), Dead = false }
        local fish = { Id = 77, Carrier = carrier }
        ctx.mgr.Vitals.FishCarrier = { ResolveCarrier = function(_, target)
            if target == fish or target == carrier or target == carrier.Body then return carrier end
        end }
        return fish, carrier
    end

    -- 成长一站应用：体型 + 血量上限刷新 + 移速（喝药后只调一次 ApplyGrowth）
    it('test_apply_growth_applies_scale_health_and_speed', function()
        ctx.potions.item167 = 20
        ctx.potions.item168 = 10
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        local applied = ctx.mgr:ApplyGrowth(ctx.player)
        assert.is_true(applied.Ok)
        assert.same(3, ctx.bodyScales[#ctx.bodyScales])
        assert.same(ctx.player, ctx.refreshedMaxHealth[1])
        assert.near(21, ctx.player.Character.Controller.WalkSpeed, 1e-9)
    end)

    -- 灼烧：每层 4 点，一跳 = 层数 × 4
    it('test_burn_ticks_damage_per_stack', function()
        local target = { UserId = 13903, Character = ctx.runtime.unit('target') }
        ctx.mgr:ApplyWeaponEffect(ctx.player, target, { Kind = 'burn' })
        ctx.mgr:ApplyWeaponEffect(ctx.player, target, { Kind = 'burn' })
        advance(1.0)
        assert.same(1, #ctx.hits)
        assert.same(8, ctx.hits[1].amount)
    end)

    -- 基准速捕获：只捕一次（异常速度不覆盖基准），无控制器时回落配置基准 7
    it('test_capture_base_speed_once_with_cfg_fallback', function()
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        assert.same(7, ctx.player.Character.Controller.WalkSpeed)
        ctx.player.Character.Controller.WalkSpeed = 999 -- 已被外部改坏
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        assert.message('基准只捕一次').same(7, ctx.player.Character.Controller.WalkSpeed)
        local bare = { UserId = 13905 }
        ctx.mgr:CaptureBaseSpeed(bare)
        ctx.mgr:RefreshMoveSpeed(bare)
        assert.is_nil(ctx.mgr.SpeedBase[13905], '无控制器不缓存假基准')
    end)

    -- 刷新已过期状态视为全新（层数不继承）
    it('test_expired_dot_restarts_from_zero_stacks', function()
        local target = { UserId = 13904, Character = ctx.runtime.unit('target') }
        for _ = 1, 5 do ctx.mgr:ApplyWeaponEffect(ctx.player, target, { Kind = 'poison' }) end
        advance(4) -- 到期清空
        ctx.mgr:ApplyWeaponEffect(ctx.player, target, { Kind = 'poison' })
        assert.same(1, ctx.mgr.Modifier.ModifierAPI.GetUnitModifiers(target.Character, 'test:poison')[1]:GetAttribute('CurrCount'))
    end)

    -- 鱼的 DOT 也走统一入口；鱼死亡（carrier.Dead）即清理
    it('test_fish_dot_ticks_and_dead_fish_is_cleaned', function()
        local fish, carrier = installFish()
        ctx.mgr:ApplyWeaponEffect(ctx.player, fish, { Kind = 'burn' })
        advance(1)
        assert.same(1, #ctx.hits)
        assert.same(4, ctx.hits[1].amount)
        carrier.Dead = true
        advance(0.1)
        advance(1) -- 到期前不再跳
        assert.message('死鱼不再吃 DOT').same(1, #ctx.hits)
    end)

    -- 鱼侧：霜冻减速 0.7、麻痹 0；鱼移除（RemoveFish）后状态清理
    it('test_fish_speed_factor_and_cleanup_on_remove', function()
        local fish = installFish()
        assert.same(1, ctx.mgr:FishSpeedFactor(fish))
        ctx.mgr:ApplyWeaponEffect(ctx.player, fish, { Kind = 'frost' })
        assert.near(0.7, ctx.mgr:FishSpeedFactor(fish), 1e-9)
        ctx.mgr:ApplyWeaponEffect(ctx.player, fish, { Kind = 'paralyze' })
        assert.same(0, ctx.mgr:FishSpeedFactor(fish))
        assert.is_true(ctx.mgr:FishParalyzed(fish))
        advance(0.5) -- 麻痹到期
        assert.near(0.7, ctx.mgr:FishSpeedFactor(fish), 1e-9)
        ctx.mgr:RemoveFish(fish)
        assert.message('鱼移除后效果清理').same(1, ctx.mgr:FishSpeedFactor(fish))
        assert.is_false(ctx.mgr:FishParalyzed(fish))
    end)

    -- 霜冻：移速经唯一口写 0.7 倍；重复命中只刷新不衰减两次；到期恢复
    it('test_frost_slows_once_refreshes_and_restores', function()
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        assert.is_true(ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'frost' }))
        assert.near(7 * 0.7, ctx.player.Character.Controller.WalkSpeed, 1e-9)
        advance(2)
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'frost' })
        assert.message('霜冻不叠加').near(7 * 0.7, ctx.player.Character.Controller.WalkSpeed, 1e-9)
        assert.same(3, ctx.mgr.Modifier:GetRemaining(ctx.player, 'frost'))
        advance(3) -- 到期
        assert.message('霜冻失效恢复').near(7, ctx.player.Character.Controller.WalkSpeed, 1e-9)
    end)

    -- 审查边界：引擎拒绝速度写入与上限刷新失败必须传播到整体成长结果，不伪装体型成功。
    it('test_growth_propagates_controller_write_failure_and_retries', function()
        local c = ctx.player.Character.Controller
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        c.WalkSpeed = nil
        setmetatable(c, { __newindex = function(_, key) error('拒绝写属性:' .. key) end })
        local applied = ctx.mgr:ApplyGrowth(ctx.player)
        assert.is_false(applied.Ok)
        assert.matches('WalkSpeed', tostring(applied.Error), nil, true)
        setmetatable(c, nil)
        ctx.potions.item167 = 20
        ctx.mgr:Update(0.1) -- 生产心跳重试当前存档属性
        assert.same(21, c.WalkSpeed)
        assert.is_true(ctx.mgr:ApplyGrowth(ctx.player).Ok)
        ctx.mgr.Vitals.RefreshMaxHealth = function() return false, '拒绝写MaxHealth' end
        applied = ctx.mgr:ApplyGrowth(ctx.player)
        assert.is_false(applied.Ok)
        assert.matches('MaxHealth', tostring(applied.Error), nil, true)
    end)

    -- 玩家退出后不再重试写速、不再刷失败日志
    it('test_leave_cancels_failed_speed_retry', function()
        local reject, read = rejectableSpeed(ctx)
        reject(true)
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        ctx.mgr:OnPlayerRemoving(ctx.player)
        local _, before = read()
        advance(0.1)
        local _, after = read()
        assert.message('退出后不继续写控制器或刷失败日志').same(after, before)
    end)

    -- 血量上限按变大药水数（委托 AttrGrowth/BodyScale）；BodyPlan 改走注入的 PlayerData
    it('test_max_health_and_body_plan_read_injected_player_data', function()
        ctx.potions.item168 = 10
        assert.same(900, ctx.mgr:MaxHealth(ctx.player))
        local plan = ctx.mgr:BodyPlan(ctx.player)
        assert.same(3, plan.Scale)
        assert.same(900, plan.Health)
        -- #132 死代码回归：引擎玩家没有 .Data 字段也不报错、按 0 个处理
        ctx.mgr.PlayerData = nil
        ctx.mgr.Attr.PlayerData = nil
        assert.same(1, ctx.mgr:BodyPlan(ctx.player).Scale)
        assert.same(300, ctx.mgr:MaxHealth(ctx.player))
    end)

    -- 麻痹：无法行动闸 + 移速 0；0.5 秒到期恢复；不叠加
    it('test_paralyze_blocks_acts_and_zeroes_speed_briefly', function()
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'paralyze' })
        assert.is_true(ctx.mgr:IsParalyzed(ctx.player))
        assert.same(0, ctx.player.Character.Controller.WalkSpeed)
        advance(0.3)
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'paralyze' })
        assert.message('麻痹只刷新').same(0.5, ctx.mgr.Modifier:GetRemaining(ctx.player, 'paralyze'))
        advance(0.5)
        assert.is_false(ctx.mgr:IsParalyzed(ctx.player))
        assert.near(7, ctx.player.Character.Controller.WalkSpeed, 1e-9)
    end)

    -- 玩家离场：效果与基准速清理
    it('test_player_removal_clears_effects_and_base_speed', function()
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'poison' })
        ctx.mgr:OnPlayerRemoving(ctx.player)
        ctx.mgr.Modifier:OnPlayerRemoving(ctx.player)
        assert.same(0, ctx.mgr.Modifier:GetRemaining(ctx.player, 'poison'))
        assert.is_nil(ctx.mgr.SpeedBase[13901])
        advance(2)
        assert.message('离场后不再跳').same(0, #ctx.hits)
    end)

    -- 毒：叠层上限 5、刷新保层数与 tick 相位、每秒一跳走统一入口、3 秒失效
    it('test_poison_stacks_caps_refreshes_and_ticks_via_unified_entry', function()
        local src, target = ctx.player, { UserId = 13902, Character = ctx.runtime.unit('target') }
        for _ = 1, 6 do
            assert.is_true(ctx.mgr:ApplyWeaponEffect(src, target, { Kind = 'poison' }))
        end
        local entity = ctx.mgr.Modifier.ModifierAPI.GetUnitModifiers(target.Character, 'test:poison')[1]
        assert.message('毒最多 5 层').same(5, entity:GetAttribute('CurrCount'))
        assert.same(3, ctx.mgr.Modifier:GetRemaining(target, 'poison'))
        -- 刷新：层数保留、持续刷新、tick 相位不变
        advance(1.5) -- 到 101.5：第一跳已结算（5 层 × 1 = 5）
        assert.same(1, #ctx.hits)
        assert.same(5, ctx.hits[1].amount)
        assert.same('dot', ctx.hits[1].category)
        assert.same(src, ctx.hits[1].source)
        assert.same(target, ctx.hits[1].target)
        ctx.mgr:ApplyWeaponEffect(src, target, { Kind = 'poison' })
        assert.same(5, entity:GetAttribute('CurrCount'))
        assert.same(3, ctx.mgr.Modifier:GetRemaining(target, 'poison'))
        -- 第二跳 102、第三跳 103、104 之后 104.5 到期失效：每跳都重新 NewHit
        advance(0.5)
        advance(1.0)
        assert.same(3, #ctx.hits)
        advance(1.0) -- 104：第四跳
        assert.same(4, #ctx.hits)
        advance(0.5) -- 104.5 到期
        assert.message('到期后状态应清空').same(0, ctx.mgr.Modifier:GetRemaining(target, 'poison'))
        advance(5)
        assert.message('失效后不再跳').same(4, #ctx.hits)
    end)

    -- 移速唯一口：成长 × 虚弱 × 霜冻在同一处连乘（20 个加速 + 虚弱 + 霜冻 = 7×3×0.5×0.7）
    it('test_refresh_move_speed_is_the_single_write_point', function()
        ctx.potions.item167 = 20
        ctx.mgr:CaptureBaseSpeed(ctx.player)
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        assert.near(21, ctx.player.Character.Controller.WalkSpeed, 1e-9)
        ctx.mgr.Modifier:Apply(nil, ctx.player, 'weak')
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        assert.near(10.5, ctx.player.Character.Controller.WalkSpeed, 1e-9)
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'frost' })
        assert.near(21 * 0.5 * 0.7, ctx.player.Character.Controller.WalkSpeed, 1e-9)
        -- 虚弱消退（Survival 委托同一路径）：霜冻仍在，只去掉 0.5
        ctx.mgr.Modifier:Clear(ctx.player, 'weak')
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        assert.near(21 * 0.7, ctx.player.Character.Controller.WalkSpeed, 1e-9)
        advance(3)
        assert.message('全部失效后回到成长后速度').near(21, ctx.player.Character.Controller.WalkSpeed, 1e-9)
    end)

    -- 来源退出策略：取消其所有效果；真实 Vitals 在退出前签发来源身份，退出后不再产生无来源 DOT。
    it('test_source_leave_cancels_dot_via_public_lifecycle', function()
        local v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
        v.Now = function() return ctx.now end
        v:OnPlayerAdded(ctx.player)
        local fish, carrier = installFish()
        local seen, calls = {}, 0
        v.FishCarrier = ctx.mgr.Vitals.FishCarrier
        v.FishCarrier.Damage = function(_, _, amount, hit)
            calls = calls + 1
            seen[calls] = v:ResolveHitSource(hit)
            assert.same(1, amount)
            return true, amount
        end
        ctx.mgr.Vitals = v
        ctx.mgr.Modifier.Vitals = v
        ctx.mgr:ApplyWeaponEffect(ctx.player, fish, { Kind = 'poison' })
        advance(1)
        assert.same({ ctx.player }, seen)
        v:OnPlayerRemoving(ctx.player)
        ctx.mgr:OnPlayerRemoving(ctx.player)
        ctx.mgr.Modifier:OnPlayerRemoving(ctx.player)
        advance(1)
        assert.message('来源离场后取消效果，不再生成无来源DOT').same(1, calls)
    end)

    -- 真实效果计时 + 真实逃跑更新：麻痹0.5秒到期恢复霜冻速度，霜冻3秒到期恢复原速。
    it('test_straight_escape_uses_real_status_expiration', function()
        local oldVector = _G.Vector3
        _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
        local unit = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
        unit.Ability = ctx.mgr
        local fish, carrier = installFish()
        fish.FishId, fish.StraightEscape, fish.Heading = 'alligatorGar', true, { x = 1, z = 0 }
        carrier.Body.Position = { x = 9999, y = 500, z = 9999 }
        local base = GameCfg.Fish.alligatorGar.Speed
        ctx.mgr:ApplyWeaponEffect(ctx.player, fish, { Kind = 'frost' })
        ctx.mgr:ApplyWeaponEffect(ctx.player, fish, { Kind = 'paralyze' })
        unit:UpdateEscaping(fish, ctx.now)
        assert.same(0, carrier.Body.LinearVelocity.x)
        advance(0.5)
        unit:UpdateEscaping(fish, ctx.now)
        assert.near(base * 0.7, carrier.Body.LinearVelocity.x, 1e-9)
        advance(2.5)
        unit:UpdateEscaping(fish, ctx.now)
        _G.Vector3 = oldVector
        assert.same(base, carrier.Body.LinearVelocity.x)
    end)

    -- 无法解析的目标不建状态
    it('test_unresolvable_target_is_rejected', function()
        assert.is_false(ctx.mgr:ApplyWeaponEffect(ctx.player, {}, { Kind = 'poison' }))
        assert.is_false(ctx.mgr:ApplyWeaponEffect(ctx.player, nil, { Kind = 'poison' }))
        assert.is_false(ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'nosuch' }))
        assert.same(0, ctx.mgr.Modifier:GetRemaining(ctx.player, 'poison'))
    end)

    -- #139 复核失败方式：状态到期已删除而写速失败，下一帧必须按当前权威状态重算；退出不得继续重试。
    it('test_status_expiry_write_failure_retries_current_growth_and_other_effects', function()
        local reject, read = rejectableSpeed(ctx)
        ctx.potions.item167 = 20
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'frost' })
        ctx.mgr:ApplyWeaponEffect(ctx.player, ctx.player, { Kind = 'paralyze' })
        reject(true)
        advance(0.5) -- 麻痹到期，控制器拒写，仍为0
        assert.same(0, read())
        assert.is_false(ctx.mgr:IsParalyzed(ctx.player))
        ctx.potions.item167 = 10 -- 重试读取当前存档，而非失败时的21
        reject(false)
        advance(0.1)
        assert.near(9.8, read(), 1e-9) -- 7*2*0.7
        reject(true)
        advance(2.4) -- 霜冻到期
        reject(false)
        advance(0.1)
        assert.same(14, read())
    end)

    -- 虚弱到期写失败：清标记不留伪虚弱，下一帧按当前状态重试
    it('test_weak_expiry_write_failure_retries_next_frame_without_fake_weak_state', function()
        local reject, read = rejectableSpeed(ctx)
        local oldRE = package.loaded['common.REUtil']
        package.loaded['common.REUtil'] = { GetRE = function() return { FireClient = function() end } end }
        local survival = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
        package.loaded['common.REUtil'] = oldRE
        survival.Now = function() return ctx.now end
        survival.SpeedWriter = ctx.mgr
        survival.Modifier = ctx.mgr.Modifier
        survival.SendState, survival.Mirror = function() end, function() end
        local state = { player = ctx.player, phase = 'alive' }
        survival.States[ctx.player.UserId] = state
        ctx.mgr.Survival = survival
        ctx.potions.item167 = 20
        ctx.mgr:RefreshMoveSpeed(ctx.player)
        survival:ApplyWeak(state, 1)
        assert.same(10.5, read())
        reject(true)
        ctx.runtime.wait(1)
        ctx.now = ctx.runtime.now
        survival:Update()
        assert.message('到期标记清除，不保留伪虚弱').is_nil(survival:GetState(ctx.player).weakUntil)
        reject(false)
        ctx.mgr:Update(0.1)
        assert.same(21, read())
    end)
end)
