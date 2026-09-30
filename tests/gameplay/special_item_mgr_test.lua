-- #140 T19 特殊道具：服务端接缝（MgrSpecialItem 的选中调和、飞行驱动、吐息结算、冷却镜像）。
-- 纯逻辑用例见 tests/gameplay/special_item_test.lua；这里只测「接缝有没有被正确驱动」，
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
--  13. 缓降被高于区地面基准的地形托住时仍判空中、重力一直关闭（站在礁石上滞空）。
local lu = require('luaunit')
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
        BindAppearance = function(_, appearanceId, socket)
            ch.Calls[#ch.Calls + 1] = { 'bind', appearanceId, socket }
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

TestSpecialItemMgr = {}

function TestSpecialItemMgr:setUp()
    local env = self
    self.saved = { Vector3 = rawget(_G, 'Vector3'), game = rawget(_G, 'game'), REUtil = rawget(_G, 'REUtil'),
        mgr = package.loaded['server.Mgr.MgrSpecialItem'] }
    self.now = 1000
    self.players = {}
    self.events = {}
    self.pushed = {}
    _G.Vector3 = { New = vec }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
        return {}
    end }
    _G.REUtil = {
        CheckRECD = function() return false end,
        GetRE = function(_, name)
            if not env.events[name] then
                env.events[name] = {
                    OnServerEvent = signal(),
                    FireClient = function(_, player, payload)
                        env.pushed[#env.pushed + 1] = { name = name, userId = player.UserId, payload = payload }
                        if name == 'SpecialItemResult' then player.lastResult = payload
                        else player.lastState = payload end
                    end,
                }
            end
            return env.events[name]
        end,
    }
    package.loaded['server.Mgr.MgrSpecialItem'] = nil
    self.mgr = assert(loadfile('server/Mgr/MgrSpecialItem.lua'))()
    -- 协作接缝：Vitals / PlayerData / FishUnit 全桩
    self.alive = {}
    self.hits = {}
    self.mgr.Vitals = {
        CanAct = function(_, player) return env.alive[player.UserId] == true end,
        NewHit = function(_, source, category)
            return { source = source, category = category, targets = {} }
        end,
        -- 与 MgrVitals:ApplyHit 同契约：同一命中身份对同一目标只结算一次（DOT 每段须重新 NewHit）
        ApplyHit = function(_, hit, target, amount)
            if hit.targets[target] then return false end
            hit.targets[target] = true
            env.hits[#env.hits + 1] = { category = hit.category, target = target, amount = amount,
                source = hit.source }
            return true
        end,
    }
    self.dataByUser = {}
    self.mgr.PlayerData = { GetDataInst = function(_, player) return env.dataByUser[player.UserId] end }
    self.fish = {}
    self.mgr.FishUnit = { Fish = self.fish }
    -- 外观资源占位：配置空值时不调外观接缝；测试填入占位资源验证接缝被驱动
    self.oldWingAsset = GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId
    self.oldSkinAsset = GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = 'wingAssetPlaceholder'
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = 'godzillaSkinPlaceholder'
    self.mgr:Start()
end

function TestSpecialItemMgr:tearDown()
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = self.oldWingAsset
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = self.oldSkinAsset
    _G.Vector3 = self.saved.Vector3
    _G.game = self.saved.game
    _G.REUtil = self.saved.REUtil
    package.loaded['server.Mgr.MgrSpecialItem'] = self.saved.mgr
end

function TestSpecialItemMgr:addPlayer(userId, x, y, z, itemId, fx, fz)
    local player = { UserId = userId, Character = newCharacter(x, y, z, fx, fz) }
    self.players[#self.players + 1] = player
    self.alive[userId] = true
    self.dataByUser[userId] = newData('fishPond', itemId and 1 or nil, itemId)
    self.mgr:OnPlayerAdded(player)
    return player
end

function TestSpecialItemMgr:selectItem(player, itemId)
    local data = self.dataByUser[player.UserId]
    data.Data.Containers.itemBar[1] = itemId and { itemId = itemId, count = 1 } or nil
    data.Data.SelectedSlot = itemId and 1 or nil
end

function TestSpecialItemMgr:fire(player, payload)
    self.events.SpecialItemAction.OnServerEvent:Fire(player, payload)
end

function TestSpecialItemMgr:step(frames, dt)
    for _ = 1, frames do
        self.now = self.now + dt
        self.mgr:Update(dt)
    end
end

-- 失败方式 1：选中即背负（BindAppearance 驱动、重力关闭接管 y）
function TestSpecialItemMgr:test_selecting_wings_binds_appearance_and_takes_over_gravity()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'wings')
    lu.assertTrue(hasCall(player.Character, 'bind'))
    -- 失败方式 12：地面待机保留重力（关重力会让跳跃 / 走下台阶直接漂浮）
    lu.assertTrue(player.Character.Controller.GravityEnabled, '地面待机不接管重力')
    self:fire(player, { action = 'fly', holding = true })
    self:step(1, 0.05)
    lu.assertFalse(player.Character.Controller.GravityEnabled, '长按起飞才接管 y')
end

-- 失败方式 2：切换 / 丢弃后恢复原外观与运动状态（解绑、重力恢复、不滞空）
function TestSpecialItemMgr:test_switching_away_restores_appearance_and_motion()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    -- 升空后切走：半空中切道具也必须恢复重力（不滞空）
    self:fire(player, { action = 'fly', holding = true })
    self:step(20, 0.05) -- 1 秒，升到 5.01 + 8 = 13 左右
    lu.assertTrue(player.Character.Position.y > 6)
    self:selectItem(player, 'carp')
    self:step(1, 0.05)
    lu.assertNil(self.mgr.States[1].effect)
    lu.assertTrue(hasCall(player.Character, 'unbind'))
    lu.assertTrue(player.Character.Controller.GravityEnabled, '切换后重力必须恢复')
    lu.assertFalse(self.mgr.States[1].airborne)
    lu.assertFalse(self.mgr.States[1].holding)
    -- 丢弃（槽位清空、选中取消）同样恢复
    self:selectItem(player, 'item169')
    self:step(1, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'wings')
    self:selectItem(player, nil)
    self:step(1, 0.05)
    lu.assertNil(self.mgr.States[1].effect)
    lu.assertTrue(player.Character.Controller.GravityEnabled)
end

-- 失败方式 1/2：选中哥斯拉即变身（换皮肤），切走复位；不碰体型（三倍叠加由 #132 独立管）
function TestSpecialItemMgr:test_godzilla_transform_sets_and_resets_skin_without_touching_scale()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item170')
    self:step(1, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'godzilla')
    lu.assertTrue(hasCall(player.Character, 'skin'))
    lu.assertEquals(player.Character.Controller.WalkSpeed, 6, '变身不改移动参数')
    self:selectItem(player, nil)
    self:step(1, 0.05)
    lu.assertTrue(hasCall(player.Character, 'resetSkin'))
    lu.assertNil(self.mgr.States[1].effect)
end

-- 失败方式 3：死亡 / 濒死清理效果并拒绝动作；复活后按选中重放
function TestSpecialItemMgr:test_death_clears_effect_and_blocks_actions_until_revive()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    self:fire(player, { action = 'fly', holding = true })
    self:step(10, 0.05)
    self.alive[1] = false -- 濒死 / 死亡
    self:step(1, 0.05)
    lu.assertNil(self.mgr.States[1].effect, '死亡必须清掉生效效果')
    lu.assertTrue(player.Character.Controller.GravityEnabled)
    self:fire(player, { action = 'fly', holding = true })
    lu.assertFalse(self.mgr.States[1].holding, '死亡中拒绝飞行指令')
    lu.assertEquals(player.lastResult.ok, false)
    -- 复活：选中未变，效果重放
    self.alive[1] = true
    self:step(1, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'wings')
end

-- 失败方式 4：摆渡钩子结束飞行（重力恢复、不滞空），外观随新区调和重放
function TestSpecialItemMgr:test_teleport_hook_ends_flight_motion()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    self:fire(player, { action = 'fly', holding = true })
    self:step(10, 0.05)
    self.mgr:OnTeleport(player)
    lu.assertTrue(player.Character.Controller.GravityEnabled)
    lu.assertFalse(self.mgr.States[1].airborne)
    lu.assertFalse(self.mgr.States[1].holding)
    -- 调和仍认为翅膀选中：到新区地面待机保持重力，再长按才重新接管
    self:step(1, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'wings')
    lu.assertTrue(player.Character.Controller.GravityEnabled)
    self:fire(player, { action = 'fly', holding = true })
    self:step(1, 0.05)
    lu.assertFalse(player.Character.Controller.GravityEnabled)
end

-- 失败方式 5：离线重进不复活飞行状态；冷却镜像按剩余秒数恢复（不重置）
function TestSpecialItemMgr:test_offline_rejoin_restores_cooldown_without_reviving_flight()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item170')
    self:step(1, 0.05)
    self:fire(player, { action = 'breath' })
    lu.assertTrue(player.lastResult.ok)
    local data = self.dataByUser[1]
    self:step(4, 0.5) -- 吐息 3 秒走完，冷却剩 18 秒
    local remaining = data.Extra.cooldowns.godzillaBreath
    lu.assertAlmostEquals(remaining, 18, 0.6)
    -- 离场：镜像留在存档；重进：恢复成绝对时刻（CD 还剩多少就剩多少）
    self.mgr:OnPlayerRemoving(player)
    lu.assertNil(self.mgr.States[1])
    self.now = self.now + 6 -- 离线 6 秒
    local rejoined = { UserId = 1, Character = newCharacter(6, 5.01, 40) }
    self.players = { rejoined }
    self.mgr:OnPlayerAdded(rejoined)
    local state = self.mgr.States[1]
    lu.assertFalse(state.airborne, '重进不得复活滞空')
    lu.assertTrue(rejoined.Character.Controller.GravityEnabled, '重进不得残留关重力')
    self:step(1, 0.05) -- 调和：变身重放（选中未变）
    lu.assertEquals(state.effect, 'godzilla')
    -- CD 剩约 12 秒：现在放不出吐息
    self:fire(rejoined, { action = 'breath' })
    lu.assertEquals(rejoined.lastResult.ok, false)
    lu.assertEquals(rejoined.lastResult.reason, 'cooldown')
end

-- 失败方式 6：切换 / 死亡清不掉冷却（冷却只依赖绝对时刻）
function TestSpecialItemMgr:test_breath_cooldown_survives_switch_and_death()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item170')
    self:step(1, 0.05)
    self:fire(player, { action = 'breath' })
    lu.assertTrue(player.lastResult.ok)
    self:step(8, 0.5) -- 吐息走完，冷却剩 16 秒
    -- 切换走再切回来
    self:selectItem(player, 'item169')
    self:step(2, 0.05)
    self:selectItem(player, 'item170')
    self:step(2, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'godzilla')
    self:fire(player, { action = 'breath' })
    lu.assertEquals(player.lastResult.ok, false, '切换不得清冷却')
    -- 死亡再复活
    self.alive[1] = false
    self:step(2, 0.05)
    self.alive[1] = true
    self:step(2, 0.05)
    self:fire(player, { action = 'breath' })
    lu.assertEquals(player.lastResult.ok, false, '死亡不得清冷却')
    -- 冷却真的到期后能放
    self:step(40, 0.5)
    self:fire(player, { action = 'breath' })
    lu.assertTrue(player.lastResult.ok)
end

-- 失败方式 7/8/10：吐息经 Vitals 结算走廊内目标（玩家 + 鱼），每目标恰 1000、无重复段；
-- 30 米内有效（证明没读首领 10 米配置）；自己、背后、走廊外、超程目标不挨打
function TestSpecialItemMgr:test_breath_settles_corridor_targets_via_vitals()
    local caster = self:addPlayer(1, 0, 5.01, 40, 'item170', 0, 1) -- 朝 +z
    local victim = self:addPlayer(2, 1, 5.01, 60, nil)            -- 正前 20 米（首领 10 米够不着）
    local behind = self:addPlayer(3, 0, 5.01, 30, nil)            -- 背后
    local offSide = self:addPlayer(4, 20, 5.01, 50, nil)          -- 走廊外
    local far = self:addPlayer(5, 0, 5.01, 75, nil)               -- 35 米超程
    self.fish[9] = { Id = 9, Carrier = { Body = { Position = vec(0, 5, 55) }, Dead = false } }
    self:step(1, 0.05)
    self:fire(caster, { action = 'breath' })
    lu.assertTrue(caster.lastResult.ok)
    self:step(7, 0.5) -- 3.5 秒：吐息 3 秒走完
    lu.assertNil(self.mgr.States[1].breath, '吐息窗口必须收尾')
    -- 每目标总额与身份
    local byTarget = {}
    for _, hit in ipairs(self.hits) do
        lu.assertEquals(hit.category, 'specialBreath')
        lu.assertEquals(hit.source, caster)
        byTarget[hit.target] = (byTarget[hit.target] or 0) + hit.amount
    end
    lu.assertEquals(byTarget[victim], 1000, '每个目标总伤害恰 1000')
    lu.assertEquals(byTarget[self.fish[9].Carrier], 1000)
    lu.assertNil(byTarget[caster], '不得打自己')
    lu.assertNil(byTarget[behind], '背后不挨打')
    lu.assertNil(byTarget[offSide], '走廊外不挨打')
    lu.assertNil(byTarget[far], '超 30 米不挨打')
end

-- 失败方式 9：两玩家状态隔离（A 变身 / 飞行不影响 B）
function TestSpecialItemMgr:test_two_players_states_are_isolated()
    local a = self:addPlayer(1, 6, 5.01, 40, 'item170')
    local b = self:addPlayer(2, 100, 6, 100, nil)
    self.dataByUser[2].Data.Zone = 'shrimpPond'
    self:step(1, 0.05)
    lu.assertEquals(self.mgr.States[1].effect, 'godzilla')
    lu.assertNil(self.mgr.States[2].effect)
    lu.assertTrue(b.Character.Controller.GravityEnabled)
    self:fire(a, { action = 'breath' })
    self:step(8, 0.5)
    lu.assertNil(self.mgr.States[2].lastBreathAt, 'A 的冷却不得落到 B 头上')
    -- B 在 A 的 30 米走廊外（另一区），不挨打
    for _, hit in ipairs(self.hits) do
        lu.assertNotEquals(hit.target, b)
    end
end

-- 失败方式 11：未选中翅膀时 fly 指令被拒，不改变运动状态
function TestSpecialItemMgr:test_fly_rejected_without_wings_selected()
    local player = self:addPlayer(1, 6, 5.01, 40, 'carp')
    self:step(1, 0.05)
    self:fire(player, { action = 'fly', holding = true })
    lu.assertFalse(self.mgr.States[1].holding)
    lu.assertEquals(player.lastResult.ok, false)
    self:step(10, 0.05)
    lu.assertEquals(player.Character.Position.y, 5.01, '未选翅膀不得升空')
    lu.assertTrue(player.Character.Controller.GravityEnabled)
end

-- 失败方式 1 补充：飞行到顶钳住、松开缓降落地后重力仍由翅膀接管（关重力悬浮在地面）
function TestSpecialItemMgr:test_flight_climbs_to_ceiling_then_descends_and_lands()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    self:fire(player, { action = 'fly', holding = true })
    self:step(60, 0.1) -- 6 秒：8 m/s 早就该到顶（CeilingY = 25.01）
    lu.assertAlmostEquals(player.Character.Position.y, 25.01, 0.01)
    self:fire(player, { action = 'fly', holding = false })
    self:step(80, 0.1) -- 8 秒缓降：3 m/s 降 24 米，早该落地
    lu.assertAlmostEquals(player.Character.Position.y, 5.01, 0.01)
    lu.assertFalse(self.mgr.States[1].airborne)
    -- 失败方式 12：落地即交还重力；实际地形低于区地面基准时由引擎重力接着落下，不悬在基准面
    lu.assertTrue(player.Character.Controller.GravityEnabled, '落地后重力恢复')
end

-- 失败方式 13：缓降途中被地形（礁石 / 屋顶，高于区地面基准）托住 → 判落地、交还重力
function TestSpecialItemMgr:test_descent_blocked_by_terrain_lands_and_restores_gravity()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    self:fire(player, { action = 'fly', holding = true })
    self:step(20, 0.1) -- 升到 CeilingY 25.01
    self:fire(player, { action = 'fly', holding = false })
    local terrainY = 15
    for _ = 1, 60 do
        self:step(1, 0.1)
        -- 引擎碰撞：角色不会穿进地形，被顶回地形表面
        local pos = player.Character.Position
        if pos.y < terrainY then player.Character.Position = vec(pos.x, terrainY, pos.z) end
    end
    lu.assertFalse(self.mgr.States[1].airborne, '被地形托住应判落地')
    lu.assertTrue(player.Character.Controller.GravityEnabled, '落地后重力恢复')
    lu.assertAlmostEquals(player.Character.Position.y, terrainY, 0.01)
end

-- 失败方式（跨区）：空中水平越界被钳回本区（不能借飞行跨区）
function TestSpecialItemMgr:test_flight_clamps_horizontal_position_inside_the_zone()
    local player = self:addPlayer(1, 6, 5.01, 40, 'item169')
    self:step(1, 0.05)
    self:fire(player, { action = 'fly', holding = true })
    self:step(5, 0.05)
    -- 外部力量（客户端预测 / 击退）把角色推出围栏：下一帧必须钳回
    player.Character.Position = vec(999, player.Character.Position.y, 40)
    self:step(1, 0.05)
    lu.assertTrue(player.Character.Position.x <= 60, 'x ' .. tostring(player.Character.Position.x))
    player.Character.Position = vec(6, player.Character.Position.y, -500)
    self:step(1, 0.05)
    lu.assertTrue(player.Character.Position.z >= -10, 'z ' .. tostring(player.Character.Position.z))
end
