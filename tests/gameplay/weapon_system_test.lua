-- #129 失败方式先列：见 .scratch/129/progress.md。
-- 验收锁定：数值与商店表/票面一致（空手 5/0.5/2，不再 25）；挥砍登记驱动命中盒与伤害；
-- 服务端射速/弹量/换弹（2 秒）权威，切枪与重连不绕过；霰弹 5×20、火箭筒 500+5 米 100；
-- 投掷一发一件走 #123 协议（重放不重复扣）、20 米钳制、落水 3–5 条当地 1 级普通鱼后算伤害、
-- 5 米爆炸、普通投掷召唤不出首领；装备/选中重进恢复、弹匣按满匣恢复。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

-- ===== 数值与表一致性 =====
TestWeaponConfig = {}

function TestWeaponConfig:test_unarmed_uses_ticket_values_not_25()
    local u = GameCfg.Ability.Unarmed
    lu.assertNotNil(u)
    lu.assertEquals(u.Damage, 5)
    lu.assertEquals(u.IntervalSec, 0.5)
    lu.assertEquals(u.Range, 2)
    lu.assertNotEquals(u.Damage, 25)
end

function TestWeaponConfig:test_melee_weapons_match_design_table()
    -- 商店表 R27/R26/R25：指虎 10/0.5、匕首 15/0.5、斧头 40/1.0；#129 票面射程 2/3/4 米
    local m = GameCfg.Ability.MeleeWeapons
    lu.assertEquals(m.item134, { Damage = 10, IntervalSec = 0.5, Range = 2 })
    lu.assertEquals(m.item135, { Damage = 15, IntervalSec = 0.5, Range = 3 })
    lu.assertEquals(m.item136, { Damage = 40, IntervalSec = 1.0, Range = 4 })
end

function TestWeaponConfig:test_guns_match_shop_table()
    -- 商店表 R24—R19：手枪 10/1s/10、霰弹 5×20/1.5s/2、冲锋 13/0.15s/30、
    -- 自动步枪 20/0.2s/30、狙击 200/1.5s/5、火箭筒 500/1 发/周围 5 米 100
    local g = GameCfg.Ability.Guns
    lu.assertEquals(g.item137, { Damage = 10, IntervalSec = 1.0, Magazine = 10 })
    lu.assertEquals(g.item138, { Damage = 20, Pellets = 5, IntervalSec = 1.5, Magazine = 2 })
    lu.assertEquals(g.item139, { Damage = 13, IntervalSec = 0.15, Magazine = 30, Auto = true })
    lu.assertEquals(g.item140, { Damage = 20, IntervalSec = 0.2, Magazine = 30, Auto = true })
    lu.assertEquals(g.item141, { Damage = 200, IntervalSec = 1.5, Magazine = 5 })
    lu.assertEquals(g.item142, { Damage = 500, IntervalSec = 2.0, Magazine = 1,
        Splash = { Damage = 100, Radius = 5 } })
end

function TestWeaponConfig:test_gun_shared_reload_two_seconds()
    lu.assertEquals(GameCfg.Ability.GunShared.ReloadSec, 2)
    lu.assertTrue(GameCfg.Ability.GunShared.Range > 0)
end

function TestWeaponConfig:test_throwables_and_throw_ticket()
    -- 商店表 R18/R17/R16：鞭炮 50、手雷 100、炸药 150；票面：直接 20 米、5 米爆炸、保底 3–5 条
    local e = GameCfg.Ability.Explosives
    lu.assertEquals(e.item143.Damage, 50)
    lu.assertEquals(e.item144.Damage, 100)
    lu.assertEquals(e.item145.Damage, 150)
    local t = GameCfg.Ability.Throw
    lu.assertEquals(t.Range, 20)
    lu.assertEquals(t.ExplosionRadius, 5)
    lu.assertEquals(t.FishMin, 3)
    lu.assertEquals(t.FishMax, 5)
end

function TestWeaponConfig:test_weapon_ids_registered_in_shop_and_items()
    -- 全量商品表（GameCfg.Shop.Goods 是已接入白名单，武器购买归 #130）
    local shopGoods = {}
    for _, goods in ipairs(GameCfg.Content.Shop.Goods) do
        if goods.page == '武器' and goods.itemKey then shopGoods[goods.itemKey] = true end
    end
    -- #139 起武器来源不止商店：抽奖武器大奖（weaponChoice 组）也进同两张表，
    -- 口径改为「每件武器要么在商店武器页、要么是抽奖大奖」，且物品表分类正确。
    local lotteryPrizes = {}
    for _, entry in ipairs(GameCfg.Content.Lottery.Patterns) do
        if entry.tripleReward and entry.tripleReward.kind == 'weaponChoice' then
            for _, itemKey in ipairs(entry.tripleReward.itemKeys) do lotteryPrizes[itemKey] = true end
        end
    end
    local function checkSource(id, wantType)
        lu.assertTrue(shopGoods[id] or lotteryPrizes[id], id .. ' 既不在商店武器页也不是抽奖大奖')
        lu.assertEquals(GameCfg.Items.Definitions[id].Type, wantType)
    end
    for id, _ in pairs(GameCfg.Ability.MeleeWeapons) do checkSource(id, '近战武器') end
    for id, _ in pairs(GameCfg.Ability.Guns) do checkSource(id, '远程武器') end
    for id, _ in pairs(GameCfg.Ability.Explosives) do
        lu.assertTrue(shopGoods[id], id .. ' 不在商店武器页')
        lu.assertEquals(GameCfg.Items.Definitions[id].Type, '爆炸物')
    end
end

-- ===== #130 强化加成消费 =====
-- 失败方式：加成买了不生效/生效错对象（火箭筒溅射双加成、空手被加成）、
-- 弹容没向上取整、按复利算。
TestMgrWeaponUpgrade = {}
function TestMgrWeaponUpgrade:setUp() TestMgrWeapon.setUp(self) end
function TestMgrWeaponUpgrade:tearDown() TestMgrWeapon.tearDown(self) end
function TestMgrWeaponUpgrade:lastReply()
    local r = self.replies[#self.replies]
    return r and r.payload or nil
end

-- 近战满级 +70%：斧头 40→68 登记进挥砍；空手不吃武器加成
function TestMgrWeaponUpgrade:test_melee_max_level_scales_staged_swing()
    self.data.Extra.growth.upgrades.melee = 7
    self.data:GrantWeapon('item136', 1)
    self.data:HoldWeapon('item136')
    self.mgr:Attack(self.player)
    lu.assertAlmostEquals(self.swingStaged[42].damage, 68, 1e-9)
    lu.assertEquals(self.swingStaged[42].range, 4)
    self.data.Extra.inventory.selection.held = { kind = nil, id = nil, slot = nil } -- 回到空手
    self.data.Extra.inventory.selection.weapon = nil
    self.now = 1002 -- 过冷却
    self.mgr:Attack(self.player)
    lu.assertEquals(self.swingStaged[42].damage, 5) -- 空手不加成
end

-- 远程满级 +50%：每发弹丸乘算（霰弹 20→30）
function TestMgrWeaponUpgrade:test_ranged_max_level_scales_each_pellet()
    self.data.Extra.growth.upgrades.ranged = 5
    self.data:GrantWeapon('item138', 1)
    self.data:HoldWeapon('item138')
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 5 } }
    self.mgr:Attack(self.player)
    lu.assertEquals(#self.applied, 5)
    for _, a in ipairs(self.applied) do lu.assertAlmostEquals(a.amount, 30, 1e-9) end
end

-- 火箭筒两段只归远程：直击 500→750；溅射 100→150，且不吃爆炸物加成（不双加成）
function TestMgrWeaponUpgrade:test_rocket_two_stages_only_ranged_no_double_bonus()
    self.data.Extra.growth.upgrades.ranged = 5
    self.data.Extra.growth.upgrades.explosive = 3
    self.data:GrantWeapon('item142', 1)
    self.data:HoldWeapon('item142')
    self.other.Character.Position = { x = 0, y = 2, z = 4 }
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 4 } }
    self.mgr:Attack(self.player)
    local direct = 0
    for _, a in ipairs(self.applied) do
        if a.target == self.other then
            direct = direct + 1
            lu.assertAlmostEquals(a.amount, 750, 1e-9) -- 直击只吃远程
        else
            lu.assertAlmostEquals(a.amount, 150, 1e-9) -- 溅射只吃远程：100×1.5，不乘爆炸物 1.6
            lu.assertNotEquals(a.target, self.player)
        end
    end
    lu.assertEquals(direct, 1)
end

-- 弹容满级 +150% 向上取整：狙击 5→13（7.5→8 逐级验证在配置层），第 14 发才空匣
function TestMgrWeaponUpgrade:test_magazine_max_level_rounds_up_and_extends_ammo()
    self.data.Extra.growth.upgrades.magazine = 3
    self.data:GrantWeapon('item141', 1) -- 狙击 5 发
    self.data:HoldWeapon('item141')
    for i = 1, 13 do
        self.now = 1000 + i * 2 -- 间隔 1.5 秒
        lu.assertTrue(self.mgr:Attack(self.player).ok)
    end
    lu.assertEquals(self:lastReply().ammo, 0)
    self.now = 1000 + 14 * 2
    local reply = self.mgr:Attack(self.player)
    lu.assertEquals(reply.reason, 'empty') -- 第 14 发才触发空匣换弹
    lu.assertTrue(reply.autoReload)
end

-- 爆炸物满级 +60%：投掷爆炸伤害乘算（手雷 100→160）
function TestMgrWeaponUpgrade:test_explosive_max_level_scales_detonation()
    self.data.Extra.growth.upgrades.explosive = 3
    local landing = { x = 0, y = 2, z = 10 }
    self.other.Character.Position = { x = 0, y = 2, z = 14.9 }
    self.mgr:Detonate(self.player, 'item144', landing, nil)
    lu.assertTrue(#self.applied >= 1)
    for _, a in ipairs(self.applied) do
        lu.assertAlmostEquals(a.amount, 160, 1e-9)
    end
end

-- 无强化时行为与 #129 基线完全一致（0 级不加成、弹容取基础值）
function TestMgrWeaponUpgrade:test_zero_level_matches_129_baseline()
    self.data:GrantWeapon('item136', 1)
    self.data:HoldWeapon('item136')
    self.mgr:Attack(self.player)
    lu.assertEquals(self.swingStaged[42].damage, 40)
    self.data:GrantWeapon('item141', 1)
    self.data:HoldWeapon('item141')
    self.now = 1002
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(self:lastReply().ammo, 4) -- 5 发基础弹匣
end

-- ===== 挥砍登记（AbilityAPI） =====
TestAbilitySwingRegistry = {}


function TestAbilitySwingRegistry:setUp()
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
function TestAbilitySwingRegistry:tearDown()
    _G.game = self.savedGame
    package.loaded['server.AbilityAPI'] = self.oldApi
end

function TestAbilitySwingRegistry:test_stage_take_once_and_overwrite()
    lu.assertTrue(self.api.StageSwing(7, { damage = 5, range = 2 }))
    lu.assertEquals(self.api.PeekSwing(7).damage, 5)
    lu.assertEquals(self.api.TakeSwing(7), { damage = 5, range = 2, at = 1000 })
    lu.assertNil(self.api.TakeSwing(7))
    -- 重复登记覆盖旧的（换武器不串档）
    self.api.StageSwing(7, { damage = 40, range = 4 })
    self.api.StageSwing(7, { damage = 10, range = 2 })
    lu.assertEquals(self.api.TakeSwing(7).damage, 10)
end

function TestAbilitySwingRegistry:test_expired_or_future_swing_rejected()
    self.api.StageSwing(7, { damage = 5, range = 2 })     -- at=1000
    self.now = 1000 + 1.6                                  -- TTL 1.5 秒
    lu.assertNil(self.api.PeekSwing(7))
    lu.assertNil(self.api.TakeSwing(7))
    self.now = 1000
    self.api.StageSwing(8, { damage = 5, range = 2 })
    self.now = 500                                          -- 登记在未来（时钟回拨）视为过期
    lu.assertNil(self.api.TakeSwing(8))
end

function TestAbilitySwingRegistry:test_add_cast_guard_chains_after_base_guard()
    local baseCalls, extraCalls = 0, 0
    self.api.SetCastGuard(function() baseCalls = baseCalls + 1 return true end)
    self.api.AddCastGuard(function(unit, index)
        extraCalls = extraCalls + 1
        return index ~= 2 -- 近战槽无登记时拒绝
    end)
    lu.assertTrue(self.api.CastAbility({}, 0))  -- 非近战槽不受追加守卫影响
    lu.assertFalse(self.api.CastAbility({}, 2)) -- 追加守卫拒绝
    lu.assertEquals({ baseCalls, extraCalls }, { 2, 2 })
end

-- ===== MgrWeapon：空手 / 近战 / 枪械 =====
TestMgrWeapon = {}
-- #37 失败方式：客户端俯仰丢失；方向尺度扩大射程；NaN/inf/零向量消耗弹药；
-- 客户端声称命中绕过墙；正常攻击按钮/武器栏入口未带相机瞄准。
function TestMgrWeapon:test_attack_payload_aims_up_with_authoritative_origin_and_range()
    self.data:GrantWeapon('item141',1); self.data:HoldWeapon('item141')
    self.mgr:Start()
    self.reHandler(self.player,{action='attack',aim={x=0,y=30,z=40}})
    lu.assertAlmostEquals(self.lastRay.d.y,GameCfg.Ability.GunShared.Range*0.6,1e-6)
    lu.assertAlmostEquals(self.lastRay.d.z,GameCfg.Ability.GunShared.Range*0.8,1e-6)
    lu.assertEquals(self.lastRay.o,{x=0,y=3,z=0})
    -- 首命中墙，客户端的伪造目标不会绕过它；已发一枪仍只扣票面一发。
    self.now=self.now+2
    self.rayHit={Instance={},Position={x=0,y=4,z=2}}
    self.reHandler(self.player,{action='attack',aim={x=0,y=3,z=4},target=self.other})
    lu.assertEquals(#self.applied,0)
    local ammo=self.mgr:GetState(self.player.UserId).mags.item141.ammo
    for _,bad in ipairs({false,{}, {x=0,y=0,z=0}, {x=0,y=0/0,z=1},
        {x=0,y=math.huge,z=1}, {x='0',y=1,z=1}, {x=1e308,y=1,z=1}}) do
        self.now=self.now+2
        self.reHandler(self.player,{action='attack',aim=bad})
        lu.assertEquals(self:lastReply().reason,'bad-aim')
        lu.assertEquals(self.mgr:GetState(self.player.UserId).mags.item141.ammo,ammo)
    end
end

function TestMgrWeapon:test_camera_aim_payload_uses_normalized_viewport_center()
    local prior=_G.game
    _G.game={GetService=function(_,name)
        if name=='CameraService' then return {ViewportPointToRay=function(_,x,y)
            lu.assertEquals({x,y},{0.5,0.5})
            return {Direction={x=0,y=0.6,z=0.8}}
        end} end
    end}
    local ok,payload=pcall(function() return require('client.WeaponAim'):AttackPayload() end)
    _G.game=prior
    lu.assertTrue(ok,tostring(payload))
    lu.assertEquals(payload,{action='attack',aim={x=0,y=0.6,z=0.8}})
end
local function weaponPlayer(id)
    return { UserId = id, Character = { Position = { x = 0, y = 2, z = 0 },
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end } } }
end
function TestMgrWeapon:setUp()
    self.saved = { game = rawget(_G, 'game'), re = rawget(_G, 'REUtil'),
        api = package.loaded['server.AbilityAPI'] }
    self.now = 1000
    self.player = weaponPlayer(42)
    self.other = weaponPlayer(43)
    self.casts, self.swingStaged, self.replies = {}, {}, {}
    self.applied, self.spawnedFish, self.order = {}, {}, 0
    local env = self
    -- 与真实 server.AbilityAPI 一致的点调用签名（模块函数，非方法）
    package.loaded['server.AbilityAPI'] = {
        StageSwing = function(userId, swing) env.swingStaged[userId] = swing end,
        PeekSwing = function(userId) return env.swingStaged[userId] end,
        TakeSwing = function(userId)
            local s = env.swingStaged[userId]; env.swingStaged[userId] = nil; return s end,
        CastAbility = function(unit, index)
            env.casts[#env.casts + 1] = { unit = unit, index = index }; return true end,
        AddCastGuard = function(fn) env.castGuard = fn end,
    }
    _G.REUtil = {
        GetRE = function(_, name)
            return { OnServerEvent = { Connect = function(_, fn) env.reHandler = fn end },
                FireClient = function(_, player, payload)
                    env.replies[#env.replies + 1] = { name = name, player = player, payload = payload } end }
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
        if name == 'PhysicsService' then return { Raycast = function(_, o, d, p)
            env.lastRay = { o = o, d = d, p = p }
            return env.rayHit end }
        end
        return nil
    end }
    self.mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
    self.data = PlayerData.New({ UserId = 42, SetAttribute = function() end })
    self.data:Init()
    self.mgr.PlayerData = { GetDataInst = function() return env.data end,
        SendItemBar = function() end }
    self.mgr.Attr = require('tests.lib.attr_runtime').New(self.mgr.PlayerData)
    self.mgr.Vitals = {
        CanAct = function() return true end,
        NewHit = function(_, source, category)
            env.order = env.order + 1
            return { id = env.order, source = source, category = category }
        end,
        ApplyHit = function(_, hit, target, amount)
            env.order = env.order + 1
            env.applied[#env.applied + 1] = { order = env.order, hit = hit,
                target = target, amount = amount }
            return true, amount
        end,
    }
    self.mgr.FishUnit = { Fish = {}, SpawnBlastFish = function(_, fishId, mult, pos, owner)
        env.order = env.order + 1
        env.spawnedFish[#env.spawnedFish + 1] = { order = env.order,
            fishId = fishId, mult = mult, pos = pos, owner = owner }
        return { Id = #env.spawnedFish }
    end }
    self.mgr.FishCarrier = { ResolveCarrier = function(_, unit) return nil end }
end
function TestMgrWeapon:tearDown()
    _G.game = self.saved.game
    _G.REUtil = self.saved.re
    package.loaded['server.AbilityAPI'] = self.saved.api
end
function TestMgrWeapon:lastReply()
    local r = self.replies[#self.replies]
    return r and r.payload or nil
end

function TestMgrWeapon:test_unarmed_attack_stages_cfg_swing_and_casts_melee()
    self.mgr:Attack(self.player)
    lu.assertEquals(self.swingStaged[42], { damage = 5, range = 2 })
    lu.assertEquals(#self.casts, 1)
    lu.assertEquals(self.casts[1].index, 1) -- GameCfg 挥砍槽位
    lu.assertEquals(self.casts[1].unit, self.player.Character)
    lu.assertTrue(self:lastReply().ok)
end

function TestMgrWeapon:test_melee_interval_enforced_per_weapon_and_switching()
    self.data:GrantWeapon('item136', 1) -- 斧头 40 / 1.0s / 4m
    self.data:GrantWeapon('item135', 1) -- 匕首 15 / 0.5s / 3m
    self.data:HoldWeapon('item136')
    self.mgr:Attack(self.player)
    lu.assertEquals(self.swingStaged[42].damage, 40)
    self.mgr:Attack(self.player) -- 间隔内连点：拒绝且不重复登记/施法
    lu.assertEquals(self:lastReply().reason, 'cooldown')
    lu.assertEquals(#self.casts, 1)
    self.now = 1000.5
    self.data:HoldWeapon('item135') -- 切武器不绕冷却：匕首自己的时间线
    self.mgr:Attack(self.player)
    lu.assertEquals(self.swingStaged[42].damage, 15)
    lu.assertEquals(#self.casts, 2)
    self.data:HoldWeapon('item136') -- 换回斧头：仍在 1 秒冷却内
    self.mgr:Attack(self.player)
    lu.assertEquals(self:lastReply().reason, 'cooldown')
    self.now = 1001.01
    self.mgr:Attack(self.player)
    lu.assertEquals(#self.casts, 3)
end

function TestMgrWeapon:test_gun_magazine_empties_then_auto_reload_two_seconds()
    self.data:GrantWeapon('item137', 1) -- 手枪 10 发
    self.data:HoldWeapon('item137')
    for i = 1, 10 do
        self.now = 1000 + i -- 间隔 1 秒，打光 10 发
        lu.assertTrue(self.mgr:Attack(self.player).ok)
    end
    lu.assertEquals(self:lastReply().ammo, 0)
    self.now = 1011
    local reply = self.mgr:Attack(self.player)
    lu.assertFalse(reply.ok)
    lu.assertEquals(reply.reason, 'empty')
    lu.assertTrue(reply.autoReload)
    lu.assertTrue(self.mgr:GetState(42).mags.item137.reloadUntil > 1011)
    -- 换弹中发射被拒
    lu.assertEquals(self.mgr:Attack(self.player).reason, 'reloading')
    -- 手动换弹不重置/不叠加
    lu.assertEquals(self.mgr:Reload(self.player).reason, 'reloading')
    -- 2 秒到期惰性补满；备弹无限（再打 10 发仍合法）
    self.now = 1013.01
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(self:lastReply().ammo, 9)
    lu.assertTrue(self.mgr:GetState(42).mags.item137.ammo >= 0)
end

function TestMgrWeapon:test_manual_reload_two_seconds_not_bypassed_by_switching()
    self.data:GrantWeapon('item137', 1)
    self.data:GrantWeapon('item141', 1) -- 狙击 5 发
    self.data:HoldWeapon('item137')
    self.now = 1000
    self.mgr:Attack(self.player)
    lu.assertEquals(self.mgr:Reload(self.player).ok, true)
    lu.assertEquals(self.mgr:Reload(self.player).reason, 'reloading')
    -- 切到狙击打一发再切回：手枪仍在换弹
    self.data:HoldWeapon('item141')
    self.now = 1001
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    self.data:HoldWeapon('item137')
    lu.assertEquals(self.mgr:Attack(self.player).reason, 'reloading')
    self.now = 1002.01 -- 手枪 2 秒换弹完成
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(self:lastReply().ammo, 9)
end

function TestMgrWeapon:test_fire_rate_enforced_server_side()
    self.data:GrantWeapon('item139', 1) -- 冲锋枪 0.15s
    self.data:HoldWeapon('item139')
    self.now = 1000
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    self.now = 1000.1 -- 客户端加速：0.1 < 0.15 拒绝
    lu.assertEquals(self.mgr:Attack(self.player).reason, 'cooldown')
    self.now = 1000.16 -- 0.16 ≥ 0.15 放行（0.15 恰为浮点边界，避开）
    lu.assertTrue(self.mgr:Attack(self.player).ok)
end

function TestMgrWeapon:test_shotgun_five_pellets_one_shell()
    self.data:GrantWeapon('item138', 1) -- 霰弹 2 发 × 5×20
    self.data:HoldWeapon('item138')
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 5 } }
    self.mgr:Attack(self.player)
    lu.assertEquals(#self.applied, 5)
    for _, a in ipairs(self.applied) do lu.assertEquals(a.amount, 20) end
    lu.assertEquals(self.applied[1].target, self.other)
    lu.assertEquals(self:lastReply().ammo, 1) -- 一发一壳
end

function TestMgrWeapon:test_rocket_direct_500_and_splash_5m_excludes_shooter()
    self.data:GrantWeapon('item142', 1)
    self.data:HoldWeapon('item142')
    self.other.Character.Position = { x = 0, y = 2, z = 4 }   -- 落点 5 米内
    self.rayHit = { Instance = self.other.Character, Position = { x = 0, y = 2, z = 4 } }
    self.mgr:Attack(self.player)
    local direct, splash = 0, {}
    for _, a in ipairs(self.applied) do
        if a.amount == 500 then direct = direct + 1 else splash[#splash + 1] = a end
    end
    lu.assertEquals(direct, 1) -- 直伤一次
    -- 直伤目标被溅射跳过（不双算），投掷者不炸自己
    for _, a in ipairs(splash) do
        lu.assertEquals(a.amount, 100)
        lu.assertNotEquals(a.target, self.other)
        lu.assertNotEquals(a.target, self.player)
    end
    lu.assertEquals(self:lastReply().ammo, 0) -- 1 发弹匣
end

function TestMgrWeapon:test_gun_ray_miss_applies_nothing()
    self.data:GrantWeapon('item137', 1)
    self.data:HoldWeapon('item137')
    self.rayHit = nil -- 未命中任何物体
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(#self.applied, 0)
    self.rayHit = { Instance = { UnitId = 999, UnitType = 'WorldUnit', PhysicsActive = true },
        Position = { x = 0, y = 2, z = 3 } } -- 墙：不解析出玩家/鱼
    self.now = 1001 -- 过射速间隔再打一发
    lu.assertTrue(self.mgr:Attack(self.player).ok)
    lu.assertEquals(#self.applied, 0)
end

function TestMgrWeapon:test_cast_guard_requires_staged_swing_for_melee_only()
    self.mgr:Start() -- 注册 AddCastGuard 与 WeaponAction 通道
    lu.assertNotNil(self.castGuard)
    self.swingStaged[42] = { damage = 5, range = 2 }
    lu.assertTrue(self.castGuard(self.player.Character, 1))  -- 已登记放行
    self.swingStaged[42] = nil
    lu.assertFalse(self.castGuard(self.player.Character, 1)) -- 近战槽无登记拒绝
    lu.assertTrue(self.castGuard(self.player.Character, 0))  -- 其它槽位不受影响
    lu.assertTrue(self.castGuard({ UnitId = 5 }, 1))         -- 非玩家单位（鱼施法）不受影响
end

-- ===== 投掷 / 爆炸 =====
TestMgrWeaponThrow = {}
local function throwPlayer(id)
    return { UserId = id, Character = { Position = { x = 0, y = 2, z = 0 },
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end } } }
end
function TestMgrWeaponThrow:setUp()
    self.saved = { game = rawget(_G, 'game'), re = rawget(_G, 'REUtil'),
        api = package.loaded['server.AbilityAPI'] }
    self.now = 2000
    self.player = throwPlayer(77)
    self.other = throwPlayer(78)
    self.replies, self.applied, self.spawnedFish, self.order = {}, {}, {}, 0
    self.launches = {}
    package.loaded['server.AbilityAPI'] = { StageSwing = function() end,
        PeekSwing = function() return nil end, TakeSwing = function() return nil end,
        CastAbility = function() return true end, AddCastGuard = function() end }
    local env = self
    _G.REUtil = { GetRE = function(_, name)
        return { OnServerEvent = { Connect = function() end },
            FireClient = function(_, player, payload)
                env.replies[#env.replies + 1] = payload end }
        end, CheckRECD = function() return nil end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end,
            CreateUnit = function() return { Destroy = function() end, Position = { x = 0, y = 0, z = 0 } } end } end
        if name == 'Players' then return { GetPlayers = function() return { env.player, env.other } end,
            GetPlayerFromCharacter = function() return nil end } end
        return nil
    end }
    self.mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
    self.data = PlayerData.New({ UserId = 77, SetAttribute = function() end })
    self.data:Init()
    self.mgr.PlayerData = { GetDataInst = function() return env.data end,
        SendItemBar = function() end }
    self.mgr.Attr = require('tests.lib.attr_runtime').New(self.mgr.PlayerData)
    self.mgr.Vitals = {
        CanAct = function() return true end,
        NewHit = function(_, source, category)
            env.order = env.order + 1
            return { id = env.order, source = source, category = category } end,
        ApplyHit = function(_, hit, target, amount)
            env.order = env.order + 1
            env.applied[#env.applied + 1] = { order = env.order, target = target, amount = amount }
            return true, amount end,
    }
    self.mgr.FishUnit = { Fish = {}, SpawnBlastFish = function(_, fishId, mult, pos, owner)
        env.order = env.order + 1
        env.spawnedFish[#env.spawnedFish + 1] = { order = env.order,
            fishId = fishId, mult = mult, pos = pos, owner = owner }
        -- 真实 MgrFishUnit 会把鱼登记进 Fish 表：爆炸结算能看到刚生成的保底鱼
        local id = 1000 + #env.spawnedFish
        env.mgr.FishUnit.Fish[id] = { Id = id, Carrier = { Body = { Position = pos } } }
        return { Id = id } end }
    self.mgr.FishCarrier = { ResolveCarrier = function() return nil end }
    local realLaunch = self.mgr.Launch
    self.mgr.Launch = function(m, player, itemId, target)
        env.launches[#env.launches + 1] = { itemId = itemId, target = target }
        return realLaunch(m, player, itemId, target)
    end
end
function TestMgrWeaponThrow:tearDown()
    _G.game = self.saved.game
    _G.REUtil = self.saved.re
    package.loaded['server.AbilityAPI'] = self.saved.api
end

local function giveExplosive(data, itemId, count)
    -- AddItem 一次添一件（mult 是倍率元数据，不是数量）；每格一件不堆叠
    for _ = 1, count do lu.assertTrue(data:AddItem(itemId)) end
end

-- 道具栏初始有新手鱼竿占 1 号位（容量 2）：按实际落格找槽位
local function barSlotOf(data, itemId)
    local snap = data:GetItemBarSnapshot()
    for index, entry in pairs(snap.slots) do
        if entry.itemId == itemId then return index end
    end
    return nil
end

function TestMgrWeaponThrow:test_throw_consumes_exactly_one_without_save()
    giveExplosive(self.data, 'item143', 2)
    local slot = barSlotOf(self.data, 'item143')
    lu.assertNotNil(slot)
    lu.assertTrue(self.mgr:Handle(self.player, { action = 'throw', slot = slot, seq = 1 }))
    lu.assertEquals(self.data:ItemCount('item143'), 1)
    lu.assertEquals(#self.launches, 1)
    lu.assertEquals(self.launches[1].itemId, 'item143')
end

function TestMgrWeaponThrow:test_throw_replay_does_not_consume_or_launch_again()
    -- 模拟 MgrSave 协议：同 requestId 第二次返回 replay，只回历史结果
    local executions = 0
    self.mgr.Save = {
        ResolveRequest = function(_, player, data, kind, requestId)
            lu.assertEquals(kind, 'throw')
            if requestId == 7 and self.replayed then
                return { id = '77:1', sequence = 1, kind = 'throw', requestKey = 'k' }, 'replay'
            end
            return { id = '77:1', sequence = 1, kind = 'throw', requestKey = 'k' }, 'new'
        end,
        Execute = function(_, player, data, operation, transform, done)
            if self.replayed then
                done(true, { ok = true, op = 'throw', itemId = 'item143', slot = 1 })
                return true
            end
            local draft = PlayerData.New({ UserId = 77, SetAttribute = function() end })
            draft:Init(); draft:ApplySave(data:Serialize())
            local result = transform(draft)
            if result then
                data:ApplySave(draft:Serialize()) -- 模拟真实 Execute 的写回
                done(true, result)
            else
                done(false, 'rejected')
            end
            executions = executions + 1
            return true
        end,
    }
    giveExplosive(self.data, 'item143', 2)
    local slot = barSlotOf(self.data, 'item143')
    self.mgr:Handle(self.player, { action = 'throw', slot = slot, seq = 7 })
    lu.assertEquals(self.data:ItemCount('item143'), 1)
    lu.assertEquals(#self.launches, 1)
    self.replayed = true
    self.mgr:Handle(self.player, { action = 'throw', slot = slot, seq = 7 }) -- 同 seq 重放
    lu.assertEquals(self.data:ItemCount('item143'), 1) -- 不重复扣
    lu.assertEquals(#self.launches, 1)                -- 不再发射
    lu.assertEquals(executions, 1)                    -- 新结算只一次
end

function TestMgrWeaponThrow:test_throw_rejects_non_explosive_and_bad_slot()
    giveExplosive(self.data, 'item143', 1)
    lu.assertTrue(self.mgr:Handle(self.player, { action = 'throw', slot = 9, seq = 1 }))
    lu.assertEquals(self.replies[#self.replies].reason, 'bad-slot')
    -- 非爆炸物用初始道具栏里的新手鱼竿验证（鱼会进背包，占不到道具栏格）
    local rodSlot = barSlotOf(self.data, GameCfg.Items.Id.StarterRod)
    lu.assertNotNil(rodSlot)
    lu.assertTrue(self.mgr:Handle(self.player, { action = 'throw', slot = rodSlot, seq = 2 }))
    lu.assertEquals(self.replies[#self.replies].reason, 'bad-throwable')
    lu.assertEquals(self.data:ItemCount('item143'), 1)
end

function TestMgrWeaponThrow:test_target_clamped_to_20m()
    local landing, zone = self.mgr:ResolveTarget(self.player, { x = 0, y = 2, z = 100 })
    lu.assertNil(zone)
    lu.assertAlmostEquals(landing.z, 20, 0.01) -- 直接投掷钳到 20 米
    lu.assertEquals(landing.x, 0)
end

function TestMgrWeaponThrow:test_water_detonation_spawns_3_to_5_fish_before_damage()
    -- WaterCircle2 中心 (-11.75, 27.75) HalfXZ=6，SurfaceY=2.183
    local zone = { Id = 'WaterCircle2', Center = { x = -11.75, y = 1.05, z = 27.75 },
        HalfXZ = 6.0, SurfaceY = 2.183 }
    local landing = { x = -11.75, y = 2.183, z = 27.75 }
    self.mgr.Random = function(a, b)
        if a and b then return b end -- 数量取上限，候选取最后一个（确定性）
        return 0.999
    end
    self.mgr:Detonate(self.player, 'item143', landing, zone)
    lu.assertEquals(#self.spawnedFish, GameCfg.Ability.Throw.FishMax)
    lu.assertTrue(#self.spawnedFish >= GameCfg.Ability.Throw.FishMin)
    for _, f in ipairs(self.spawnedFish) do
        lu.assertEquals(f.owner, self.player)
        lu.assertEquals(f.mult, 1)
        local species = GameCfg.Fish[f.fishId]
        lu.assertEquals(species.Grade, 'normal') -- 普通投掷召唤不出首领/精英/极品
        lu.assertEquals(species.RodLevel, 1)
        -- 保底鱼在伤害之前生成
        for _, a in ipairs(self.applied) do lu.assertTrue(a.order > f.order) end
    end
    lu.assertEquals(#self.applied > 0, true) -- 随后按 5 米半径结算爆炸
end

function TestMgrWeaponThrow:test_blast_candidates_exclude_boss_elite_rare_and_high_rod()
    local pondRows = GameCfg.Casting.Zones.WaterCircle2
    for _, c in ipairs(self.mgr:BlastCandidates(pondRows)) do
        lu.assertEquals(GameCfg.Fish[c.id].Grade, 'normal')
    end
    local shrimpRows = GameCfg.Casting.Zones.ShrimpPool
    local picked = self.mgr:BlastCandidates(shrimpRows)
    for _, c in ipairs(picked) do
        lu.assertEquals(GameCfg.Fish[c.id].Grade, 'normal')
        lu.assertEquals(GameCfg.Fish[c.id].RodLevel, 1)
    end
    lu.assertFalse((function()
        for _, c in ipairs(picked) do
            if c.id:match('rare') or c.id:match('Lobster') then return true end
        end
        return false
    end)())
end

function TestMgrWeaponThrow:test_land_detonation_5m_radius_no_fish_skips_thrower()
    local landing = { x = 0, y = 2, z = 10 }
    self.other.Character.Position = { x = 0, y = 2, z = 14.9 }  -- 4.9 米内
    local far = throwPlayer(79)
    far.Character.Position = { x = 0, y = 2, z = 16.1 }         -- 6.1 米外
    local oldGet = _G.game.GetService
    local env = self
    _G.game.GetService = function(_, name)
        if name == 'Players' then return { GetPlayers = function()
            return { env.player, env.other, far } end,
            GetPlayerFromCharacter = function() return nil end } end
        return oldGet(_, name)
    end
    self.mgr:Detonate(self.player, 'item144', landing, nil)
    lu.assertEquals(#self.spawnedFish, 0)
    local hitNear, hitFar, hitSelf = false, false, false
    for _, a in ipairs(self.applied) do
        lu.assertEquals(a.amount, 100)
        if a.target == self.other then hitNear = true end
        if a.target == far then hitFar = true end
        if a.target == self.player then hitSelf = true end
    end
    lu.assertTrue(hitNear)
    lu.assertFalse(hitFar)
    lu.assertFalse(hitSelf)
end

function TestMgrWeaponThrow:test_projectile_flies_then_detonates_in_water()
    giveExplosive(self.data, 'item143', 1)
    -- 20 米钳制是票面规则：站近水边投，选点才够得到 WaterCircle2 中心
    self.player.Character.Position = { x = -11.75, y = 2, z = 12 }
    local waterLanding = { x = -11.75, y = 2.183, z = 27.75 }
    self.mgr.Random = function(a, b) if a and b then return a end return 0.5 end -- 数量 3
    self.mgr:Launch(self.player, 'item143', waterLanding)
    lu.assertEquals(#self.mgr.Flying, 1)
    self.now = 2000 + GameCfg.Ability.Throw.FlightSec + 0.01
    self.mgr:Update()
    lu.assertEquals(#self.mgr.Flying, 0)
    lu.assertEquals(#self.spawnedFish, 3) -- 落水保底鱼
    lu.assertEquals(self.data:ItemCount('item143'), 1) -- Launch 不经存档协议，本用例直接发射不扣
end

-- ===== 爆炸保底鱼（MgrFishUnit Wild 状态） =====
TestMgrFishUnitBlastFish = {}
function TestMgrFishUnitBlastFish:setUp()
    self.saved = { game = rawget(_G, 'game'), carrier = package.loaded['server.Mgr.MgrFishCarrier'] }
    self.now = 3000
    self.despawned = {}
    self.spawnOpts = {}
    local env = self
    package.loaded['server.Mgr.MgrFishCarrier'] = {
        Spawn = function(_, opts)
            env.spawnOpts[#env.spawnOpts + 1] = opts
            return { Body = { Position = opts.Position }, Receiver = { Controller = {} } }, nil
        end,
        Despawn = function(_, carrier) env.despawned[#env.despawned + 1] = carrier end,
        Attach = function() end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
        return nil
    end }
    self.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    self.owner = { UserId = 55 }
end
function TestMgrFishUnitBlastFish:tearDown()
    _G.game = self.saved.game
    package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
end

function TestMgrFishUnitBlastFish:test_spawn_wild_fish_with_ttl_and_owner()
    local fish = self.mgr:SpawnBlastFish('tilapia', 1, { x = 1, y = 2, z = 3 }, self.owner)
    lu.assertNotNil(fish)
    lu.assertEquals(fish.State, self.mgr.State.Wild)
    lu.assertEquals(fish.Owner, self.owner)
    lu.assertEquals(fish.WildUntil, 3000 + GameCfg.Ability.Throw.FishTtlSec)
    lu.assertEquals(self.mgr.Fish[fish.Id], fish)
    lu.assertEquals(self.spawnOpts[1].FishId, 'tilapia')
    lu.assertEquals(self.spawnOpts[1].Position, { x = 1, y = 2, z = 3 })
    lu.assertEquals(self.spawnOpts[1].MaxHealth, GameCfg.Fish.tilapia.Health)
    -- Wild 鱼不接抓举：不会发起 Lift（没有 Conns/RequestLift 副作用）
    lu.assertNil(fish.Conns)
end

function TestMgrFishUnitBlastFish:test_wild_fish_expire_after_ttl()
    local fish = self.mgr:SpawnBlastFish('carp', 2, { x = 0, y = 2, z = 0 }, self.owner)
    self.now = 3000 + GameCfg.Ability.Throw.FishTtlSec - 1
    self.mgr:Update()
    lu.assertEquals(self.mgr.Fish[fish.Id], fish) -- 未到期保留
    self.now = 3000 + GameCfg.Ability.Throw.FishTtlSec
    self.mgr:Update()
    lu.assertNil(self.mgr.Fish[fish.Id])          -- 到期移除
    lu.assertEquals(#self.despawned, 1)
end

function TestMgrFishUnitBlastFish:test_wild_fish_can_be_killed_for_loot()
    local fish = self.mgr:SpawnBlastFish('bass', 1, { x = 0, y = 2, z = 0 }, self.owner)
    local killed = self.mgr:TakeKilled(fish)
    lu.assertEquals(killed.fishId, 'bass')
    lu.assertEquals(killed.mult, 1)
    lu.assertNil(self.mgr.Fish[fish.Id]) -- 只会成功一次
    lu.assertNil(self.mgr:TakeKilled(fish))
end

-- ===== 重进恢复 =====
TestWeaponPersistence = {}
function TestWeaponPersistence:test_rejoin_restores_equipment_and_full_magazine()
    local data = PlayerData.New({ UserId = 129, SetAttribute = function() end })
    data:Init()
    lu.assertTrue(data:GrantWeapon('item137', 1))
    lu.assertTrue(data:SelectWeapon('item137'))
    local snapshot = data:Serialize()
    local re = PlayerData.New({ UserId = 129, SetAttribute = function() end })
    re:Init()
    lu.assertTrue(re:ApplySave(snapshot))
    local mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
    mgr.PlayerData = { GetDataInst = function() return re end }
    lu.assertEquals(mgr:EquippedWeapon(re), 'item137') -- 选中武器重进恢复
    local mag = mgr:MagState(mgr:GetState(129), 'item137', GameCfg.Ability.Guns.item137.Magazine)
    lu.assertEquals(mag.ammo, GameCfg.Ability.Guns.item137.Magazine) -- 弹匣按满匣恢复（不进 #123 快照）
    local snapshot = re:Serialize()
    lu.assertNil(snapshot.ammo) -- 快照 schema 未被动过：没有弹匣字段
    lu.assertEquals(re:WeaponCount('item137'), 1)
end

-- ===== main.lua 接线守卫 =====
TestMainWeaponWiring = {}
local function readSource(path)
    local parts = {}
    for line in io.lines(path) do parts[#parts + 1] = line end
    return table.concat(parts, '\n')
end
function TestMainWeaponWiring:test_main_registers_and_wires_mgr_weapon()
    local src = readSource('server/main.lua')
    lu.assertStrContains(src, 'MgrWeapon = require("server.Mgr.MgrWeapon")')
    lu.assertStrContains(src, 'MgrMap.MgrWeapon.Vitals = MgrMap.MgrVitals')
    lu.assertStrContains(src, 'MgrMap.MgrWeapon.PlayerData = MgrMap.MgrPlayerData')
    lu.assertStrContains(src, 'MgrMap.MgrWeapon.FishUnit = MgrMap.MgrFishUnit')
end

-- ===== 客户端手势状态机 =====
TestPressGesture = {}
function TestPressGesture:test_tap_and_long_press_and_move_cancel()
    local Gesture = require('client.PressGesture')
    local g = Gesture.New({ LongPressSec = 0.35 })
    g:Begin(10, { x = 100, y = 100 })
    lu.assertEquals(g:End(10.1, { x = 103, y = 101 }), 'tap')
    g:Begin(20, { x = 100, y = 100 })
    lu.assertFalse(g:Update(20.2))
    lu.assertTrue(g:Update(20.4)) -- 长按触发选点
    lu.assertEquals(g:End(20.5, { x = 300, y = 300 }), 'long')
    g:Begin(30, { x = 100, y = 100 })
    lu.assertNil(g:End(30.1, { x = 200, y = 100 })) -- 滑出容差：既不是点按也不是长按
end
