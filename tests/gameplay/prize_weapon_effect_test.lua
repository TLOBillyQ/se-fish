-- #139 T18 大奖成长切片 5：武器特效挂载（毒匕/炽焰战斧近战、霜之新星/雷霆之力枪械）。
-- 失败方式（先列后写）：
--   1. 特效武器命中后不挂效果（毒匕挥中不中毒）：swing 载荷丢 effect、枪械命中不调应用口；
--   2. 未命中也挂效果 / 无特效武器也挂效果 / 命中被统一入口拒绝（安全区）仍挂效果；
--   3. 近战命中盒重放（同一目标重复进盒）导致效果重复叠加超过一次判定段语义。
-- 接缝：AbilityAPI.StageSwing 载荷、MgrWeapon:AttackMelee/AttackGun、melee_hit 的 process_hit
--   成功分支（_applyDamage 返回 true 后经 MgrAbility:ApplyWeaponEffect 应用）。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

-- ===== 1. 挥砍登记载荷携带 effect（真实 AbilityAPI）=====
TestSwingEffectPassthrough = {}

function TestSwingEffectPassthrough:setUp()
    self.savedGame = rawget(_G, 'game')
    self.oldApi = package.loaded['server.AbilityAPI']
    package.preload['server.packages.ability_system.api'] = function()
        return { CastAbility = function() return true end }
    end
    self.now = 1000
    local env = self
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        return nil
    end }
    self.api = assert(loadfile('server/AbilityAPI.lua'))()
end

function TestSwingEffectPassthrough:tearDown()
    _G.game = self.savedGame
    package.loaded['server.AbilityAPI'] = self.oldApi
end

function TestSwingEffectPassthrough:test_swing_carries_effect_through_stage_and_take()
    self.api.StageSwing(7, { damage = 15, range = 3, effect = { Kind = 'poison' } })
    local swing = self.api.TakeSwing(7)
    lu.assertEquals(swing.damage, 15)
    lu.assertEquals(swing.effect, { Kind = 'poison' })
    -- 无特效挥砍：effect 字段为 nil（不残留上一次登记）
    self.api.StageSwing(7, { damage = 5, range = 2 })
    lu.assertNil(self.api.TakeSwing(7).effect)
end

-- ===== 2. MgrWeapon：近战登记带特效、枪械命中挂特效 =====
TestPrizeWeaponEffect = {}

local function weaponPlayer(id)
    return { UserId = id, Character = { Position = { x = 0, y = 2, z = 0 },
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end } } }
end

function TestPrizeWeaponEffect:setUp()
    self.saved = { game = rawget(_G, 'game'), re = rawget(_G, 'REUtil'),
        api = package.loaded['server.AbilityAPI'] }
    self.now = 1000
    self.player = weaponPlayer(13921)
    self.other = weaponPlayer(13922)
    self.casts, self.swingStaged, self.replies = {}, {}, {}
    self.applied, self.effects = {}, {}
    local env = self
    package.loaded['server.AbilityAPI'] = {
        StageSwing = function(userId, swing) env.swingStaged[userId] = swing end,
        PeekSwing = function(userId) return env.swingStaged[userId] end,
        TakeSwing = function(userId)
            local s = env.swingStaged[userId]; env.swingStaged[userId] = nil; return s end,
        CastAbility = function() return true end,
        AddCastGuard = function(fn) env.castGuard = fn end,
    }
    _G.REUtil = {
        GetRE = function(_, name)
            return { OnServerEvent = { Connect = function() end },
                FireClient = function(_, player, payload)
                    env.replies[#env.replies + 1] = payload end }
        end,
        CheckRECD = function() return nil end,
    }
    self.rayHit = nil
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return { env.player, env.other } end,
            GetPlayerFromCharacter = function(_, c)
                if c == env.player.Character then return env.player end
                if c == env.other.Character then return env.other end
            end }
        end
        if name == 'PhysicsService' then return { Raycast = function() return env.rayHit end } end
        return nil
    end }
    self.mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
    local PlayerData = require('server.Data.PlayerData')
    self.data = PlayerData.New({ UserId = 13921, SetAttribute = function() end })
    self.data:Init()
    self.mgr.PlayerData = { GetDataInst = function() return env.data end,
        SendItemBar = function() end }
    self.mgr.Attr = require('tests.lib.attr_runtime').New(self.mgr.PlayerData)
    self.mgr.Vitals = {
        CanAct = function() return true end,
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, hit, target, amount)
            env.applied[#env.applied + 1] = { target = target, amount = amount }
            return true, amount
        end,
    }
    self.mgr.FishUnit = { Fish = {} }
    self.mgr.FishCarrier = { ResolveCarrier = function() return nil end }
    -- 注入的持续效果应用口（main.lua 接 MgrAbility）
    self.mgr.Ability = { ApplyWeaponEffect = function(_, source, target, effect)
        env.effects[#env.effects + 1] = { source = source, target = target, effect = effect }
        return true
    end }
end

function TestPrizeWeaponEffect:tearDown()
    _G.game = self.saved.game
    _G.REUtil = self.saved.re
    package.loaded['server.AbilityAPI'] = self.saved.api
end

function TestPrizeWeaponEffect:lastReply()
    return self.replies[#self.replies]
end

-- 毒匕挥砍：登记载荷带毒特效；商店匕首不带
function TestPrizeWeaponEffect:test_melee_swing_carries_weapon_effect()
    self.data:GrantWeapon('item152', 1) -- 淬毒匕首
    self.data:HoldWeapon('item152')
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(self.swingStaged[13921].damage, 15)
    lu.assertEquals(self.swingStaged[13921].effect, { Kind = 'poison' })
    self.now = 1000.6
    self.data:GrantWeapon('item135', 1)
    self.data:HoldWeapon('item135')
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertNil(self.swingStaged[13921].effect, '无特效武器不挂 effect')
    self.now = 1001.1
    self.mgr:Attack(self.player) -- 空手也不带
    lu.assertNil(self.swingStaged[13921].effect)
end

-- 霜之新星命中挂霜冻；脱靶/无特效枪不挂
function TestPrizeWeaponEffect:test_gun_hit_applies_effect_only_on_hit()
    self.data:GrantWeapon('item163', 1)
    self.data:HoldWeapon('item163')
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 5 } }
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(#self.effects, 1)
    lu.assertEquals(self.effects[1].source, self.player)
    lu.assertEquals(self.effects[1].target, self.other, "枪击目标已由 GetPlayerFromCharacter 解析为玩家")
    lu.assertEquals(self.effects[1].effect, { Kind = 'frost' })
    -- 脱靶：不挂
    self.rayHit = nil
    self.now = 1001.1
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(#self.effects, 1)
    -- 雷霆之力（麻痹）同样挂载
    self.data:GrantWeapon('item164', 1)
    self.data:HoldWeapon('item164')
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 5 } }
    self.now = 1002.2
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(self.effects[2].effect, { Kind = 'paralyze' })
    -- 沙漠之鹰（无特效）命中也不挂
    self.data:GrantWeapon('item162', 1)
    self.data:HoldWeapon('item162')
    self.now = 1003.3
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(#self.effects, 2)
end

-- 命中被统一入口拒绝（ApplyHit false，如安全区）时不挂效果
function TestPrizeWeaponEffect:test_effect_not_applied_when_damage_rejected()
    self.mgr.Vitals.ApplyHit = function() return false end
    self.data:GrantWeapon('item163', 1)
    self.data:HoldWeapon('item163')
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 5 } }
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(#self.effects, 0)
end

-- ===== 3. melee_hit 行为：命中成功后经 MgrAbility 挂特效 =====
TestMeleeHitEffect = {}

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
        return vec(a.x + b.x, a.y + b.y, a.z + b.z)
    end })
end

local function sig()
    local s = { handlers = {} }
    function s:Connect(fn) self.handlers[#self.handlers + 1] = fn return { Disconnect = function() end } end
    function s:Fire(...) for _, h in ipairs(self.handlers) do h(...) end end
    return s
end

function TestMeleeHitEffect:setUp()
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        Quaternion = rawget(_G, 'Quaternion'),
        vitals = package.loaded['server.Mgr.MgrVitals'],
        carrier = package.loaded['server.Mgr.MgrFishCarrier'],
        gm = package.loaded['server.Mgr.MgrGM'],
        ability = package.loaded['server.Mgr.MgrAbility'],
        api = package.loaded['server.AbilityAPI'] }
    local env = self
    self.effects, self.hitsApplied = {}, {}
    self.owner = { UnitId = 1, Position = vec(0, 0, 0) }
    self.player = { UserId = 13931, Character = self.owner }
    self.target = { UnitId = 2, UnitType = 'EggyUnit', Position = vec(0, 0, 2) }
    self.swing = { damage = 15, range = 3, effect = { Kind = 'poison' }, at = 1000 }
    self.applyOk = true
    _G.Vector3 = { New = vec }
    _G.Quaternion = { FromEulerAngles = function() return {} end }
    package.loaded['server.Mgr.MgrVitals'] = {
        NewHit = function(_, source, category) return { id = 1, source = source, category = category,
            targets = {} } end,
        ApplyHit = function(_, hit, target, amount)
            env.hitsApplied[#env.hitsApplied + 1] = { target = target, amount = amount }
            return env.applyOk
        end,
    }
    package.loaded['server.Mgr.MgrFishCarrier'] = { ResolveCarrier = function() return nil end }
    package.loaded['server.Mgr.MgrGM'] = { GetMeleeDamage = function(_, _, d) return d end }
    package.loaded['server.Mgr.MgrAbility'] = { ApplyWeaponEffect = function(_, source, target, effect)
        env.effects[#env.effects + 1] = { source = source, target = target, effect = effect }
        return true
    end }
    package.loaded['server.AbilityAPI'] = { TakeSwing = function()
        local s = env.swing; env.swing = nil; return s
    end }
    self.anchorStart = sig()
    local anchor = {
        GetAttribute = function(_, name)
            if name == 'Duration' then return 0.3 end
            return nil
        end,
        FindFirstChild = function(_, name)
            if name == 'AnchorStart' then return env.anchorStart end
            return nil
        end,
    }
    local abilityScript = { Parent = nil }
    local manager = { Parent = env.owner }
    abilityScript.Parent = manager
    anchor.Parent = abilityScript
    _G.game = { GetService = function(_, name)
        if name == 'RunService' then return { IsServer = function() return true end } end
        if name == 'Players' then return { GetPlayerFromCharacter = function(_, unit)
            if unit == env.owner then return env.player end
            if unit == env.target then return nil end -- 目标不是玩家角色
        end } end
        if name == 'World' then return { CreateUnit = function(_, unitType, opts)
            if unitType == 'TriggerUnit' then
                env.hitBox = { UnitId = 99, OnTriggerEnter = sig() }
                return env.hitBox
            end
            return nil
        end, GetServerTime = function() return 1000 end } end
        if name == 'PhysicsService' then return { GetPartsInPart = function() return {} end } end
        return nil
    end }
    self.behavior = assert(loadfile('server/AbilityBehaviors/melee_hit.lua'))()
    self.behavior.Attach(anchor)
end

function TestMeleeHitEffect:tearDown()
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.Quaternion = self.saved.Quaternion
    package.loaded['server.Mgr.MgrVitals'] = self.saved.vitals
    package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
    package.loaded['server.Mgr.MgrGM'] = self.saved.gm
    package.loaded['server.Mgr.MgrAbility'] = self.saved.ability
    package.loaded['server.AbilityAPI'] = self.saved.api
end

-- 把 Players 服务换成能认出 victim 的版本（保留其余服务）
function TestMeleeHitEffect:swapPlayers(victim, victimPlayer)
    local env = self
    _G.game.GetService = function(_, name)
        if name == 'RunService' then return { IsServer = function() return true end } end
        if name == 'Players' then return { GetPlayerFromCharacter = function(_, unit)
            if unit == env.owner then return env.player end
            if unit == victim then return victimPlayer end
        end } end
        if name == 'World' then return { CreateUnit = function(_, unitType)
            if unitType == 'TriggerUnit' then
                env.hitBox = env.hitBox or { UnitId = 99, OnTriggerEnter = sig() }
                return env.hitBox
            end
            return nil
        end, GetServerTime = function() return 1000 end } end
        if name == 'PhysicsService' then return { GetPartsInPart = function() return {} end } end
        return nil
    end
end

-- 毒匕命中：伤害结算成功后挂毒；同一目标重复进盒不重复（hit_map 去重）
function TestMeleeHitEffect:test_effect_applied_after_successful_damage_once_per_swing()
    self.anchorStart:Fire()
    lu.assertNotNil(self.hitBox, '登记挥砍后应建命中盒')
    -- 目标是玩家角色才会走 ApplyHit 玩家分支；这里目标不是玩家也不是鱼 → 不结算不挂
    self.hitBox.OnTriggerEnter:Fire(self.target)
    lu.assertEquals(#self.hitsApplied, 0)
    lu.assertEquals(#self.effects, 0)
    -- 目标换成另一玩家角色：命中成功 → 挂毒一次
    local victim = { UnitId = 3, UnitType = 'EggyUnit', Position = vec(0, 0, 2) }
    local victimPlayer = { UserId = 13932, Character = victim }
    self:swapPlayers(victim, victimPlayer)
    self.hitBox.OnTriggerEnter:Fire(victim)
    lu.assertEquals(#self.hitsApplied, 1)
    lu.assertEquals(#self.effects, 1)
    lu.assertEquals(self.effects[1].source, self.player)
    lu.assertEquals(self.effects[1].target, victim)
    lu.assertEquals(self.effects[1].effect, { Kind = 'poison' })
    -- 同一目标再次进盒：去重，不重复结算也不重复挂
    self.hitBox.OnTriggerEnter:Fire(victim)
    lu.assertEquals(#self.hitsApplied, 1)
    lu.assertEquals(#self.effects, 1)
end

-- 伤害被统一入口拒绝（安全区等）：不挂特效、不击退
function TestMeleeHitEffect:test_effect_skipped_when_damage_rejected()
    self.applyOk = false
    local victim = { UnitId = 3, UnitType = 'EggyUnit', Position = vec(0, 0, 2) }
    local victimPlayer = { UserId = 13932, Character = victim }
    self:swapPlayers(victim, victimPlayer)
    self.anchorStart:Fire()
    self.hitBox.OnTriggerEnter:Fire(victim)
    lu.assertEquals(#self.hitsApplied, 1)
    lu.assertEquals(#self.effects, 0)
end
