-- #139 T18 大奖成长切片 3：MgrAbility 持续效果状态机与属性应用。
-- 失败方式（先列后写）：
--   1. 毒/灼烧叠层无上限或刷新清零层数；DOT 不走 T07/#128 统一伤害入口（绕过 NewHit/ApplyHit）；
--   2. 霜冻/麻痹可叠加（重复命中把时间越加越长）；失效后状态残留继续生效；
--   3. 移速多写口：成长/虚弱/霜冻/麻痹各自写 WalkSpeed，恢复顺序丢成长（#131 已知边界根因）；
--   4. 目标离场（玩家退出/鱼移除）后状态不清理，DOT 打空目标、查询泄漏；
--   5. BodyPlan 读不存在的 player.Data 恒为 0（#132 原型死代码），存档里的药水永远不生效。
-- 接缝：loadfile 取全新 MgrAbility 实例；桩 _G.game（World:GetServerTime 可控时钟、Players）、
--   server.AbilityAPI；Vitals/PlayerData/Survival 以假实现注入（与 main.lua 的接线同形状）。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn) callbacks[#callbacks + 1] = fn
            return { Disconnect = function() end } end,
        Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
    }
end

TestStatusEffect = {}

function TestStatusEffect:setUp()
    self.now = 100
    self.savedGame = rawget(_G, 'game')
    self.savedAPI = package.loaded['server.AbilityAPI']
    self.savedMgr = package.loaded['server.Mgr.MgrAbility']
    local env = self
    self.bodyScales = {}
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end,
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
            env.bodyScales[#env.bodyScales + 1] = scale
            return { Ok = true, Scale = scale, Derived = {} }
        end,
    }
    self.mgr = assert(loadfile('server/Mgr/MgrAbility.lua'))()
    -- 假 Vitals：记录 DOT 结算（统一入口证据）
    self.hits = {}
    self.refreshedMaxHealth = {}
    self.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category, targets = {} } end,
        ApplyHit = function(_, hit, target, amount)
            env.hits[#env.hits + 1] = { target = target, amount = amount, category = hit.category,
                source = hit.source }
            return true
        end,
        RefreshMaxHealth = function(_, player) env.refreshedMaxHealth[#env.refreshedMaxHealth + 1] = player; return true end,
        FishCarrier = nil, -- 按需在各用例里装
    }
    -- 假 PlayerData / Survival
    self.potions = {}
    self.mgr.PlayerData = { GetDataInst = function() return {
        PotionCount = function(_, itemId) return env.potions[itemId] or 0 end } end }
    self.weak = false
    self.mgr.Survival = { GetState = function()
        return env.weak and { weakUntil = env.now + 60 } or nil
    end }
    self.player = { UserId = 13901,
        Character = { Controller = { WalkSpeed = 7 }, SetAttribute = function() end },
        CharacterAdded = signal(), CharacterRemoving = signal() }
end

function TestStatusEffect:tearDown()
    _G.game = self.savedGame
    package.loaded['server.AbilityAPI'] = self.savedAPI
    package.loaded['server.Mgr.MgrAbility'] = self.savedMgr
end

function TestStatusEffect:advance(sec)
    self.now = self.now + sec
    self.mgr:Update(sec)
end

function TestStatusEffect:installFish()
    local carrier = { Body = { UnitId = 5001 }, Dead = false }
    local fish = { Id = 77, Carrier = carrier }
    self.mgr.Vitals.FishCarrier = { ResolveCarrier = function(_, target)
        if target == fish or target == carrier or target == carrier.Body then return carrier end
    end }
    return fish, carrier
end

-- 毒：叠层上限 5、刷新保层数与 tick 相位、每秒一跳走统一入口、3 秒失效
function TestStatusEffect:test_poison_stacks_caps_refreshes_and_ticks_via_unified_entry()
    local src, target = self.player, { UserId = 13902, Character = { Controller = {} } }
    for _ = 1, 6 do
        lu.assertTrue(self.mgr:ApplyWeaponEffect(src, target, { Kind = 'poison' }))
    end
    local entry = self.mgr.Effects['p:13902']
    lu.assertEquals(entry.poison.stacks, 5, '毒最多 5 层')
    lu.assertEquals(entry.poison.nextTickAt, 101)
    lu.assertEquals(entry.poison.expiresAt, 103)
    -- 刷新：层数保留、持续刷新、tick 相位不变
    self:advance(1.5) -- 到 101.5：第一跳已结算（5 层 × 1 = 5）
    lu.assertEquals(#self.hits, 1)
    lu.assertEquals(self.hits[1].amount, 5)
    lu.assertEquals(self.hits[1].category, 'dot')
    lu.assertEquals(self.hits[1].source, src)
    lu.assertEquals(self.hits[1].target, target)
    self.mgr:ApplyWeaponEffect(src, target, { Kind = 'poison' })
    entry = self.mgr.Effects['p:13902']
    lu.assertEquals(entry.poison.stacks, 5)
    lu.assertEquals(entry.poison.nextTickAt, 102, '刷新不改 tick 相位')
    lu.assertEquals(entry.poison.expiresAt, 104.5)
    -- 第二跳 102、第三跳 103、104 之后 104.5 到期失效：每跳都重新 NewHit
    self:advance(0.5)
    self:advance(1.0)
    lu.assertEquals(#self.hits, 3)
    self:advance(1.0) -- 104：第四跳
    lu.assertEquals(#self.hits, 4)
    self:advance(0.5) -- 104.5 到期
    lu.assertNil(self.mgr.Effects['p:13902'], '到期后状态应清空')
    self:advance(5)
    lu.assertEquals(#self.hits, 4, '失效后不再跳')
end

-- 灼烧：每层 4 点，一跳 = 层数 × 4
function TestStatusEffect:test_burn_ticks_damage_per_stack()
    local target = { UserId = 13903, Character = { Controller = {} } }
    self.mgr:ApplyWeaponEffect(self.player, target, { Kind = 'burn' })
    self.mgr:ApplyWeaponEffect(self.player, target, { Kind = 'burn' })
    self:advance(1.0)
    lu.assertEquals(#self.hits, 1)
    lu.assertEquals(self.hits[1].amount, 8)
end

-- 刷新已过期状态视为全新（层数不继承）
function TestStatusEffect:test_expired_dot_restarts_from_zero_stacks()
    local target = { UserId = 13904, Character = { Controller = {} } }
    for _ = 1, 5 do self.mgr:ApplyWeaponEffect(self.player, target, { Kind = 'poison' }) end
    self:advance(4) -- 到期清空
    self.mgr:ApplyWeaponEffect(self.player, target, { Kind = 'poison' })
    lu.assertEquals(self.mgr.Effects['p:13904'].poison.stacks, 1)
end

-- 霜冻：移速经唯一口写 0.7 倍；重复命中只刷新不衰减两次；到期恢复
function TestStatusEffect:test_frost_slows_once_refreshes_and_restores()
    self.mgr:CaptureBaseSpeed(self.player)
    lu.assertTrue(self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'frost' }))
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 7 * 0.7, 1e-9)
    self:advance(2)
    self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'frost' })
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 7 * 0.7, 1e-9, '霜冻不叠加')
    lu.assertEquals(self.mgr.Effects['p:13901'].frost.expiresAt, self.now + 3)
    self:advance(3) -- 到期
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 7, 1e-9, '霜冻失效恢复')
end

-- 麻痹：无法行动闸 + 移速 0；0.5 秒到期恢复；不叠加
function TestStatusEffect:test_paralyze_blocks_acts_and_zeroes_speed_briefly()
    self.mgr:CaptureBaseSpeed(self.player)
    self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'paralyze' })
    lu.assertTrue(self.mgr:IsParalyzed(self.player))
    lu.assertEquals(self.player.Character.Controller.WalkSpeed, 0)
    self:advance(0.3)
    self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'paralyze' })
    lu.assertEquals(self.mgr.Effects['p:13901'].paralyze.expiresAt, self.now + 0.5, '麻痹只刷新')
    self:advance(0.5)
    lu.assertFalse(self.mgr:IsParalyzed(self.player))
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 7, 1e-9)
end

-- 移速唯一口：成长 × 虚弱 × 霜冻在同一处连乘（20 个加速 + 虚弱 + 霜冻 = 7×3×0.5×0.7）
function TestStatusEffect:test_refresh_move_speed_is_the_single_write_point()
    self.potions.item167 = 20
    self.mgr:CaptureBaseSpeed(self.player)
    self.mgr:RefreshMoveSpeed(self.player)
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 21, 1e-9)
    self.weak = true
    self.mgr:RefreshMoveSpeed(self.player)
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 10.5, 1e-9)
    self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'frost' })
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 21 * 0.5 * 0.7, 1e-9)
    -- 虚弱消退（Survival 委托同一路径）：霜冻仍在，只去掉 0.5
    self.weak = false
    self.mgr:RefreshMoveSpeed(self.player)
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 21 * 0.7, 1e-9)
    self:advance(3)
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 21, 1e-9, '全部失效后回到成长后速度')
end

-- 基准速捕获：只捕一次（异常速度不覆盖基准），无控制器时回落配置基准 7
function TestStatusEffect:test_capture_base_speed_once_with_cfg_fallback()
    self.mgr:CaptureBaseSpeed(self.player)
    lu.assertEquals(self.mgr.SpeedBase[13901], 7)
    self.player.Character.Controller.WalkSpeed = 999 -- 已被外部改坏
    self.mgr:CaptureBaseSpeed(self.player)
    lu.assertEquals(self.mgr.SpeedBase[13901], 7, '基准只捕一次')
    local bare = { UserId = 13905 }
    self.mgr:CaptureBaseSpeed(bare)
    self.mgr:RefreshMoveSpeed(bare)
    lu.assertEquals(self.mgr.SpeedBase[13905], nil, '无控制器不缓存假基准')
end

-- 鱼侧：霜冻减速 0.7、麻痹 0；鱼移除（RemoveFish）后状态清理
function TestStatusEffect:test_fish_speed_factor_and_cleanup_on_remove()
    local fish = self:installFish()
    lu.assertEquals(self.mgr:FishSpeedFactor(fish), 1)
    self.mgr:ApplyWeaponEffect(self.player, fish, { Kind = 'frost' })
    lu.assertAlmostEquals(self.mgr:FishSpeedFactor(fish), 0.7, 1e-9)
    self.mgr:ApplyWeaponEffect(self.player, fish, { Kind = 'paralyze' })
    lu.assertEquals(self.mgr:FishSpeedFactor(fish), 0)
    lu.assertTrue(self.mgr:FishParalyzed(fish))
    self:advance(0.5) -- 麻痹到期
    lu.assertAlmostEquals(self.mgr:FishSpeedFactor(fish), 0.7, 1e-9)
    self.mgr:RemoveFish(fish)
    lu.assertEquals(self.mgr:FishSpeedFactor(fish), 1, '鱼移除后效果清理')
    lu.assertFalse(self.mgr:FishParalyzed(fish))
end

-- 鱼的 DOT 也走统一入口；鱼死亡（carrier.Dead）即清理
function TestStatusEffect:test_fish_dot_ticks_and_dead_fish_is_cleaned()
    local fish, carrier = self:installFish()
    self.mgr:ApplyWeaponEffect(self.player, fish, { Kind = 'burn' })
    self:advance(1)
    lu.assertEquals(#self.hits, 1)
    lu.assertEquals(self.hits[1].amount, 4)
    carrier.Dead = true
    self:advance(0.1)
    self:advance(1) -- 到期前不再跳
    lu.assertEquals(#self.hits, 1, '死鱼不再吃 DOT')
end

-- 玩家离场：效果与基准速清理
function TestStatusEffect:test_player_removal_clears_effects_and_base_speed()
    self.mgr:CaptureBaseSpeed(self.player)
    self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'poison' })
    self.mgr:OnPlayerRemoving(self.player)
    lu.assertNil(self.mgr.Effects['p:13901'])
    lu.assertNil(self.mgr.SpeedBase[13901])
    self:advance(2)
    lu.assertEquals(#self.hits, 0, '离场后不再跳')
end

-- 无法解析的目标不建状态
function TestStatusEffect:test_unresolvable_target_is_rejected()
    lu.assertFalse(self.mgr:ApplyWeaponEffect(self.player, {}, { Kind = 'poison' }))
    lu.assertFalse(self.mgr:ApplyWeaponEffect(self.player, nil, { Kind = 'poison' }))
    lu.assertFalse(self.mgr:ApplyWeaponEffect(self.player, self.player, { Kind = 'nosuch' }))
    lu.assertEquals(next(self.mgr.Effects), nil)
end

-- 血量上限按变大药水数（委托 AttrGrowth/BodyScale）；BodyPlan 改走注入的 PlayerData
function TestStatusEffect:test_max_health_and_body_plan_read_injected_player_data()
    self.potions.item168 = 10
    lu.assertEquals(self.mgr:MaxHealth(self.player), 900)
    local plan = self:BodyPlan(self.player)
    lu.assertEquals(plan.Scale, 3)
    lu.assertEquals(plan.Health, 900)
    -- #132 死代码回归：引擎玩家没有 .Data 字段也不报错、按 0 个处理
    self.mgr.PlayerData = nil
    lu.assertEquals(self:BodyPlan(self.player).Scale, 1)
    lu.assertEquals(self.mgr:MaxHealth(self.player), 300)
end

function TestStatusEffect:BodyPlan(player)
    return self.mgr:BodyPlan(player)
end

-- 成长一站应用：体型 + 血量上限刷新 + 移速（喝药后只调一次 ApplyGrowth）
function TestStatusEffect:test_apply_growth_applies_scale_health_and_speed()
    self.potions.item167 = 20
    self.potions.item168 = 10
    self.mgr:CaptureBaseSpeed(self.player)
    local applied = self.mgr:ApplyGrowth(self.player)
    lu.assertTrue(applied.Ok)
    lu.assertEquals(self.bodyScales[#self.bodyScales], 3)
    lu.assertEquals(self.refreshedMaxHealth[1], self.player)
    lu.assertAlmostEquals(self.player.Character.Controller.WalkSpeed, 21, 1e-9)
end

-- 审查边界：引擎拒绝速度写入与上限刷新失败必须传播到整体成长结果，不伪装体型成功。
function TestStatusEffect:test_growth_propagates_controller_write_failure_and_retries()
    local c = self.player.Character.Controller
    self.mgr:CaptureBaseSpeed(self.player)
    c.WalkSpeed = nil
    setmetatable(c, { __newindex = function(_, key) error('拒绝写属性:' .. key) end })
    local applied = self.mgr:ApplyGrowth(self.player)
    lu.assertFalse(applied.Ok)
    lu.assertStrContains(tostring(applied.Error), 'WalkSpeed')
    setmetatable(c, nil)
    self.potions.item167 = 20
    self.mgr:Update(0.1) -- 生产心跳重试当前存档属性
    lu.assertEquals(c.WalkSpeed, 21)
    lu.assertTrue(self.mgr:ApplyGrowth(self.player).Ok)
    self.mgr.Vitals.RefreshMaxHealth = function() return false, '拒绝写MaxHealth' end
    applied = self.mgr:ApplyGrowth(self.player)
    lu.assertFalse(applied.Ok)
    lu.assertStrContains(tostring(applied.Error), 'MaxHealth')
end

-- 来源退出策略：取消其所有效果；真实 Vitals 在退出前签发来源身份，退出后不再产生无来源 DOT。
function TestStatusEffect:test_source_leave_cancels_dot_via_public_lifecycle()
    local v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    v.Now = function() return self.now end
    v:OnPlayerAdded(self.player)
    local fish, carrier = self:installFish()
    local seen, calls = {}, 0
    v.FishCarrier = self.mgr.Vitals.FishCarrier
    v.FishCarrier.Damage = function(_, _, amount, hit)
        calls = calls + 1
        seen[calls] = v:ResolveHitSource(hit)
        lu.assertEquals(amount, 1)
        return true, amount
    end
    self.mgr.Vitals = v
    self.mgr:ApplyWeaponEffect(self.player, fish, { Kind = 'poison' })
    self:advance(1)
    lu.assertEquals(seen, { self.player })
    v:OnPlayerRemoving(self.player)
    self.mgr:OnPlayerRemoving(self.player)
    self:advance(1)
    lu.assertEquals(calls, 1, '来源离场后取消效果，不再生成无来源DOT')
end

-- 真实效果计时 + 真实逃跑更新：麻痹0.5秒到期恢复霜冻速度，霜冻3秒到期恢复原速。
function TestStatusEffect:test_straight_escape_uses_real_status_expiration()
    local oldVector = _G.Vector3
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    local unit = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    unit.Ability = self.mgr
    local fish, carrier = self:installFish()
    fish.FishId, fish.StraightEscape, fish.Heading = 'alligatorGar', true, { x = 1, z = 0 }
    carrier.Body.Position = { x = 9999, y = 500, z = 9999 }
    local base = GameCfg.Fish.alligatorGar.Speed
    self.mgr:ApplyWeaponEffect(self.player, fish, { Kind = 'frost' })
    self.mgr:ApplyWeaponEffect(self.player, fish, { Kind = 'paralyze' })
    unit:UpdateEscaping(fish, self.now)
    lu.assertEquals(carrier.Body.LinearVelocity.x, 0)
    self:advance(0.5)
    unit:UpdateEscaping(fish, self.now)
    lu.assertAlmostEquals(carrier.Body.LinearVelocity.x, base * 0.7, 1e-9)
    self:advance(2.5)
    unit:UpdateEscaping(fish, self.now)
    _G.Vector3 = oldVector
    lu.assertEquals(carrier.Body.LinearVelocity.x, base)
end
