-- #90 迁移：战斗命中入口（原 tests/gameplay/combat_behavior_test.lua，3 类 6 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（LuaUnit 按 `类名.方法名` 全局字典序，
-- 故 TestEelDischargeEntry 在前、TestMainCombatWiring 居中、TestMeleeHitEntry 在后）。
-- #128：武器命中与电鳗范围命中必须经统一伤害入口；同一判定段重放不双扣。
-- #129：玩家挥砍只认 AbilityAPI 挥砍登记（伤害/射程来自 GameCfg 表），未登记不结算。
--
-- 迁移纪律：
--   * 旧 setUp/tearDown 的替身（全局引擎 + 4 个 package.loaded 管理器模块）改成逐案例 before_each/after_each，
--     快照在夹具动作之前取，恢复在案例失败时也执行（Busted 的 after_each 在 before_each 抛错后仍跑）；
--   * MgrVitals / MgrFishCarrier / MgrGM / server.AbilityAPI 都以模块缓存桩注入，行为在
--     server/AbilityBehaviors/melee_hit.lua 与 eel_discharge.lua 这两个公开接缝上观察，不伸手进实现；
--   * server/main.lua 的接线守卫读源码断言：assertStrContains 的 plain 子串语义用
--     assert.matches(needle, haystack, nil, true) 保留（`.` 在 Lua pattern 里是任意字符，不能当 pattern 跑）。
local GameCfg = require('common.GameCfg')

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire(...)
        for _, fn in ipairs(self.handlers) do fn(...) end
    end
    return s
end

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

local function readSource(path)
    local parts = {}
    for line in io.lines(path) do
        parts[#parts + 1] = line
    end
    return table.concat(parts, "\n")
end

describe('TestEelDischargeEntry', function()
    local ctx
    local saved
    before_each(function()
        saved = { game = rawget(_G, 'game'),
            vitals = package.loaded['server.Mgr.MgrVitals'],
            carrier = package.loaded['server.Mgr.MgrFishCarrier'] }
        ctx = { hits = {}, seenHits = {}, hitSerial = 0 }
        package.loaded['server.Mgr.MgrVitals'] = {
            NewHit = function(_, source, category)
                ctx.hitSerial = ctx.hitSerial + 1
                return { id = ctx.hitSerial, source = source, category = category }
            end,
            ApplyHit = function(_, hit, player, amount)
                local key = tostring(hit.id) .. ':' .. tostring(player.UserId)
                if ctx.seenHits[key] then return false end
                ctx.seenHits[key] = true
                ctx.hits[#ctx.hits + 1] = { hit, player, amount }
                return true, amount
            end,
        }
        ctx.owner = { Position = vec(0, 0, 0) }
        ctx.carrier = { Receiver = ctx.owner }
        package.loaded['server.Mgr.MgrFishCarrier'] = {
            ResolveCarrier = function(_, unit) return unit == ctx.owner and ctx.carrier or nil end,
        }
        ctx.inside = { UserId = 1, Character = { Position = vec(1, 0, 0), Controller = { Health = 300 } } }
        ctx.outside = { UserId = 2, Character = { Position = vec(9, 0, 0), Controller = { Health = 300 } } }
        _G.game = { GetService = function(_, name)
            if name == 'Players' then return { GetPlayers = function() return { ctx.inside, ctx.outside } end } end
        end }
    end)
    after_each(function()
        _G.game = saved.game
        package.loaded['server.Mgr.MgrVitals'] = saved.vitals
        package.loaded['server.Mgr.MgrFishCarrier'] = saved.carrier
    end)

    it('test_discharge_uses_fish_hit_and_replay_does_not_double_apply', function()
        local behavior = assert(loadfile('server/AbilityBehaviors/eel_discharge.lua'))()
        assert.same(1, behavior.Discharge(ctx.owner, 5, 15))
        assert.same(1, #ctx.hits)
        assert.same(ctx.carrier, ctx.hits[1][1].source)
        assert.same('fishAttack', ctx.hits[1][1].category)
        assert.same(ctx.inside, ctx.hits[1][2])
        local replay = { id = 99, source = ctx.carrier, category = 'fishAttack' }
        assert.same(1, behavior.Discharge(ctx.owner, 5, 15, replay))
        assert.same(0, behavior.Discharge(ctx.owner, 5, 15, replay))
        assert.same(2, #ctx.hits)
    end)

    -- #134 范围：按 GameCfg.Ability 的 5 米 / 10 伤害，边界上命中、超出与已死玩家不命中；电鳗已死锚点点火不放电。
    it('test_formal_radius_boundary_and_dead_targets', function()
        local eel = GameCfg.Ability.FishAbilities.eel
        local behavior = assert(loadfile('server/AbilityBehaviors/eel_discharge.lua'))()
        ctx.inside.Character.Position = vec(3, 0, 4)
        ctx.outside.Character.Position = vec(5.01, 0, 0)
        assert.same(1, behavior.Discharge(ctx.owner, eel.Radius, eel.Damage))
        assert.same(ctx.inside, ctx.hits[1][2])
        assert.same(10, ctx.hits[1][3])
        ctx.inside.Character.Controller.Health = 0
        assert.same(0, behavior.Discharge(ctx.owner, eel.Radius, eel.Damage))
        local fired
        local anchor = {
            FindFirstChild = function() return { Connect = function(_, fn) fired = fn return { Disconnect = function() end } end } end,
            Destroying = { Connect = function() return { Disconnect = function() end } end },
            GetAttribute = function(_, key) return key == 'DischargeRadius' and eel.Radius or eel.Damage end,
        }
        ctx.owner.Controller = { Health = 0 }
        anchor.Parent = { Parent = { Parent = ctx.owner } }
        ctx.inside.Character.Controller.Health = 300
        behavior.Attach(anchor)
        fired()
        assert.same(1, #ctx.hits)
        ctx.owner.Controller.Health = 300
        fired()
        assert.same(2, #ctx.hits)
    end)
end)

describe('TestMainCombatWiring', function()
    -- #128：server/main.lua 必须完成战斗接线，否则运行时各管理器拿不到统一入口。
    it('test_combat_managers_are_wired_to_unified_entry', function()
        local src = readSource('server/main.lua')
        for _, needle in ipairs({
            'MgrMap.MgrAbility.Vitals = MgrMap.MgrVitals',
            'MgrMap.MgrFishUnit.Vitals = MgrMap.MgrVitals',
            'MgrMap.MgrVitals.FishCarrier = MgrMap.MgrFishCarrier',
            'MgrMap.MgrCast.Vitals = MgrMap.MgrVitals',
            'MgrMap.MgrFishCarrier.DamageListener',
            -- 有效鱼受击伤害要回报仇恨：监听里必须经 FindByCarrier 找回鱼并 NoteDamage
            'FindByCarrier',
            'NoteDamage',
        }) do
            assert.message('server/main.lua 缺接线：' .. needle).matches(needle, src, nil, true)
        end
    end)
end)

describe('TestMeleeHitEntry', function()
    local ctx
    local saved
    before_each(function()
        saved = {
            game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion'),
            vitals = package.loaded['server.Mgr.MgrVitals'],
            carrier = package.loaded['server.Mgr.MgrFishCarrier'],
            gm = package.loaded['server.Mgr.MgrGM'],
            api = package.loaded['server.AbilityAPI'],
        }
        ctx = { controllerCalls = 0, hits = {}, swingStaged = {}, created = {} }
        _G.Vector3 = { New = vec }
        _G.Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
        ctx.ownerPlayer = { UserId = 7 }
        ctx.owner = { UnitId = 70, Position = vec(0, 0, 0) }
        ctx.ownerPlayer.Character = ctx.owner
        ctx.target = { UnitId = 80, UnitType = 'EggyUnit', Position = vec(1, 0, 0), Controller = {
            TakeDamage = function() ctx.controllerCalls = ctx.controllerCalls + 1 end,
        } }
        ctx.carrier = { Receiver = ctx.target }
        -- #129：玩家挥砍只认 AbilityAPI 登记值；测试用假登记模块，不经真实包链
        package.loaded['server.AbilityAPI'] = {
            TakeSwing = function(userId)
                local s = ctx.swingStaged[userId]
                ctx.swingStaged[userId] = nil
                return s
            end,
        }
        package.loaded['server.Mgr.MgrVitals'] = {
            NewHit = function(_, source, category)
                local hit = { source = source, category = category, id = 1 }
                ctx.createdHit = hit
                return hit
            end,
            ApplyHit = function(_, hit, target, amount)
                ctx.hits[#ctx.hits + 1] = { hit, target, amount }
                return true, amount
            end,
        }
        package.loaded['server.Mgr.MgrFishCarrier'] = {
            ResolveCarrier = function(_, target) return target == ctx.target and ctx.carrier or nil end,
        }
        package.loaded['server.Mgr.MgrGM'] = { GetMeleeDamage = function(_, _, damage) return damage end }
        _G.game = { GetService = function(_, name)
            if name == 'RunService' then return { IsServer = function() return true end } end
            if name == 'World' then return { CreateUnit = function(_, unitType, values)
                local unit = { UnitId = 500 + #ctx.created, UnitType = unitType, OnTriggerEnter = signal() }
                for k, v in pairs(values or {}) do unit[k] = v end
                ctx.created[#ctx.created + 1] = unit
                return unit
            end, CreateAsset = function() return {} end } end
            if name == 'Players' then return { GetPlayerFromCharacter = function(_, unit)
                return ctx.ownerPlayer.Character == unit and ctx.ownerPlayer or nil
            end } end
            if name == 'PhysicsService' then return { GetPartsInPart = function() return {} end } end
            if name == 'TimerService' then return { CreateTimer = function() end } end
        end }
    end)
    after_each(function()
        _G.game = saved.game
        _G.Vector3 = saved.Vector3
        _G.Quaternion = saved.Quaternion
        package.loaded['server.Mgr.MgrVitals'] = saved.vitals
        package.loaded['server.Mgr.MgrFishCarrier'] = saved.carrier
        package.loaded['server.Mgr.MgrGM'] = saved.gm
        package.loaded['server.AbilityAPI'] = saved.api
    end)

    local function buildAnchor(attrs)
        local manager = { Parent = ctx.owner }
        local ability = { Parent = manager }
        local anchor = { Parent = ability, AnchorStart = signal(), Destroying = signal() }
        function anchor:FindFirstChild(name) return self[name] end
        function anchor:GetAttribute(name) return attrs[name] end
        local behavior = assert(loadfile('server/AbilityBehaviors/melee_hit.lua'))()
        behavior.Attach(anchor)
        return anchor
    end

    local function baseAttrs()
        return {
            Duration = 0.2,
            ABILITY_ANOSTATE_HITBOX_OFFSET = vec(0, 0, 1),
            ABILITY_ANOSTATE_HITBOX_SCALE = vec(2, 2, 2),
            ABILITY_ANOSTATE_BULLET_DAMAGE = 25,
            ABILITY_ANOSTATE_HITPOWER = 0,
            ABILITY_ANOSTATE_USE_PERFAB = '',
            ABILITY_ANOSTATE_ANIMKEY = '',
        }
    end

    -- #129：玩家挥砍经 AbilityAPI 登记（MgrWeapon 按 GameCfg 表登记伤害/射程），
    -- 命中盒由登记射程推导，伤害不再回落到预设属性 25；命中身份与去重口径不变。
    it('test_fish_hit_uses_staged_swing_not_attribute_25', function()
        ctx.swingStaged[7] = { damage = 12, range = 4 }
        buildAnchor(baseAttrs()).AnchorStart:Fire()
        local hitBox = ctx.created[#ctx.created]
        assert.same(4, hitBox.Scale.z) -- 命中盒射程 = 登记射程
        assert.same(2, hitBox.Scale.x)
        hitBox.OnTriggerEnter:Fire(ctx.target)
        hitBox.OnTriggerEnter:Fire(ctx.target)
        assert.same(0, ctx.controllerCalls)
        assert.same(1, #ctx.hits)
        assert.same(ctx.createdHit, ctx.hits[1][1])
        assert.same(ctx.ownerPlayer, ctx.hits[1][1].source)
        assert.same('weapon', ctx.hits[1][1].category)
        assert.same(ctx.target, ctx.hits[1][2])
        assert.same(12, ctx.hits[1][3])
    end)

    -- 非玩家单位（鱼类施法）没有登记概念：沿用预设属性，行为不变
    it('test_non_player_owner_keeps_attribute_fallback', function()
        ctx.ownerPlayer.Character = nil -- GetPlayerFromCharacter 不再认 owner
        local attrs = baseAttrs()
        attrs.ABILITY_ANOSTATE_HITBOX_SCALE = vec(3, 2, 3)
        buildAnchor(attrs).AnchorStart:Fire()
        local hitBox = ctx.created[#ctx.created]
        assert.same(vec(3, 2, 3), hitBox.Scale)
        hitBox.OnTriggerEnter:Fire(ctx.target)
        assert.same(1, #ctx.hits)
        assert.same(25, ctx.hits[1][3])
    end)

    -- 未经登记的玩家挥砍（伪造 RequestCast）：不建命中盒、不结算伤害，只播表现
    it('test_unregistered_player_swing_deals_nothing', function()
        buildAnchor(baseAttrs()).AnchorStart:Fire()
        assert.same(0, #ctx.created)
        assert.same(0, #ctx.hits)
    end)
end)
