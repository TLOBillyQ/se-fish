-- T08 武器系统（#129）：空手 / 近战 / 枪械 / 弹匣 / 投掷炸鱼的服务端权威结算。
-- 接缝（只使用、不改协议）：
--   伤害一律经 #128 MgrVitals 命中身份入口（NewHit + ApplyHit，鱼经 FishCarrier.ResolveCarrier）；
--   武器库存用 #124 PlayerData 独立武器库存（GetItemBarSnapshot，装备=held 优先、selectedWeapon 兜底）；
--   投掷消耗走 #123 MgrSave 操作协议（ResolveRequest + Execute，成功回调里才发飞行物）。
-- 设计要点：
--   近战伤害不经预设属性：攻击前按 GameCfg.Ability 表向 AbilityAPI 登记挥砍（伤害/射程），
--   melee_hit 行为取用登记值结算——伪造 RequestCast 与旧的 25 伤害残留被结构性堵住。
--   枪械状态按 (userId, weaponId) 墙钟记录：fireAt 限射速、{ammo, reloadUntil} 管弹匣；
--   手动/自动换弹均 2 秒、到期惰性补满，切枪换不来别的枪的时间线，重开会话弹匣自然回满
--   （弹匣不进 #123 快照，装备/选中由存档恢复，与 #123 契约一致）。
--   投掷落点水平钳到票面 20 米；水中先按钓表行（RodLevel==1 且 Grade=='normal'）权重抽 3–5 条
--   保底鱼（结构排除首领/精英/极品），再按 5 米半径结算伤害；爆炸不伤投掷者自己。
local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local AbilityAPI = require('server.AbilityAPI')

local Mgr = { States = {}, Flying = {} }

-- 投掷物视觉占位网格：与 melee_hit 命中盒同款平台级资源（issue #8 实测可用），
-- 编辑器冻结期间不做资源预设，后续可在编辑器里换成正式爆炸物模型（见 issue #129 编辑器待办）。
local THROW_VISUAL_MESH = 57450

local function acfg() return GameCfg.Ability end
local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end
local function distance2D(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

function Mgr:Now()
    local world = self.World or game:GetService('World')
    return world:GetServerTime()
end

function Mgr:GetState(userId)
    local state = self.States[userId]
    if not state then
        state = { meleeAt = {}, fireAt = {}, mags = {} }
        self.States[userId] = state
    end
    return state
end

function Mgr:MeleeIndex()
    for _, entry in ipairs(acfg().InitialAbilities or {}) do
        if entry.AnchorBehavior == 'melee_hit' then return entry.Index end
    end
    return nil
end

-- 当前装备武器：手持（held.kind=='weapon' 且库存有效）优先，其次选中武器；都没有返回 nil（空手）
function Mgr:EquippedWeapon(data)
    local snap = data and data.GetItemBarSnapshot and data:GetItemBarSnapshot()
    if not snap then return nil end
    local held = snap.held
    if held and held.kind == 'weapon' and held.id and (snap.weapons[held.id] or 0) > 0 then
        return held.id
    end
    local selected = snap.selectedWeapon
    if selected and (snap.weapons[selected] or 0) > 0 then return selected end
    return nil
end

-- 选中格是爆炸物时返回 { slot=, itemId= }（爆炸物在普通道具栏，不占武器库存）
function Mgr:SelectedExplosive(data)
    local snap = data and data.GetItemBarSnapshot and data:GetItemBarSnapshot()
    local slot = snap and snap.selectedSlot
    local entry = slot and snap.slots and snap.slots[slot]
    local definition = entry and GameCfg.Items.Definitions[entry.itemId]
    if definition and definition.Type == '爆炸物' then
        return { slot = slot, itemId = entry.itemId }
    end
    return nil
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('WeaponResult'):FireClient(player, payload)
    return payload
end

function Mgr:Fail(player, action, reason, extra)
    print('[MgrWeapon] 拒绝', player.UserId, tostring(action), reason)
    local payload = { ok = false, action = action, reason = reason }
    if extra then for k, v in pairs(extra) do payload[k] = v end end
    return self:Reply(player, payload)
end

-- ===== 攻击入口 =====

function Mgr:Attack(player)
    if self.Vitals and not self.Vitals:CanAct(player) then
        return self:Fail(player, 'attack', 'cannot-act')
    end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data or not player.Character then
        return self:Fail(player, 'attack', 'unavailable')
    end
    local weaponId = self:EquippedWeapon(data)
    local guns, melee = acfg().Guns, acfg().MeleeWeapons
    if weaponId and guns[weaponId] then return self:AttackGun(player, weaponId, guns[weaponId], data) end
    if weaponId and melee[weaponId] then return self:AttackMelee(player, weaponId, data) end
    if weaponId then
        print('[MgrWeapon] 武器未配置攻击数值，回落空手', player.UserId, weaponId)
    end
    return self:AttackMelee(player, nil, data)
end

function Mgr:CastMelee(player)
    local index = self:MeleeIndex()
    if index == nil or not player.Character then return false end
    local ok, cast = pcall(function() return AbilityAPI.CastAbility(player.Character, index) end)
    if not ok then
        print('[MgrWeapon] 挥砍施法失败', player.UserId, tostring(cast))
        return false
    end
    return cast == true
end

-- 空手（weaponId=nil）与近战武器共用挥砍预设（纯表现），伤害/射程来自登记值；
-- 近战武器吃近战强化（#130 按基础线性叠加），空手不加成
function Mgr:AttackMelee(player, weaponId, data)
    local mcfg = weaponId and acfg().MeleeWeapons[weaponId] or acfg().Unarmed
    if not mcfg then return self:Fail(player, 'attack', 'bad-weapon', { weapon = weaponId }) end
    local now = self:Now()
    local state = self:GetState(player.UserId)
    local key = weaponId or 'unarmed'
    if now - (state.meleeAt[key] or 0) < mcfg.IntervalSec then
        return self:Fail(player, 'attack', 'cooldown', { weapon = weaponId })
    end
    local scale = weaponId and data and data.WeaponDamageScale and data:WeaponDamageScale('melee') or 1
    local damage = mcfg.Damage * scale
    state.meleeAt[key] = now
    -- #139：近战大奖的特效（毒/灼烧）随挥砍登记传给 melee_hit，命中成功后才应用
    AbilityAPI.StageSwing(player.UserId, { damage = damage, range = mcfg.Range, effect = mcfg.Effect })
    local cast = self:CastMelee(player)
    print('[MgrWeapon] 挥砍发起', player.UserId, tostring(weaponId or 'unarmed'),
        'damage=' .. tostring(damage), 'range=' .. tostring(mcfg.Range),
        'interval=' .. tostring(mcfg.IntervalSec), cast and 'cast' or 'cast-failed')
    return self:Reply(player, { ok = true, action = 'attack', weapon = weaponId,
        damage = damage, range = mcfg.Range })
end

function Mgr:MagState(state, weaponId, magazine)
    local mag = state.mags[weaponId]
    if not mag then
        mag = { ammo = magazine, reloadUntil = nil }
        state.mags[weaponId] = mag
    end
    return mag
end

-- 换弹完成检查：到期惰性补满（读状态前都过一次）
function Mgr:RefreshMag(mag, magazine, now)
    if mag.reloadUntil and now >= mag.reloadUntil then
        mag.reloadUntil = nil
        mag.ammo = magazine
    end
end

function Mgr:AttackGun(player, weaponId, gcfg, data)
    local now = self:Now()
    local state = self:GetState(player.UserId)
    -- #130：弹容强化向上取整（PlayerData:MagazineSize），0 级即基础值
    local magazine = data and data.MagazineSize and data:MagazineSize(gcfg.Magazine) or gcfg.Magazine
    local scale = data and data.WeaponDamageScale and data:WeaponDamageScale('ranged') or 1
    local mag = self:MagState(state, weaponId, magazine)
    self:RefreshMag(mag, magazine, now)
    if mag.reloadUntil then
        return self:Fail(player, 'attack', 'reloading', { weapon = weaponId, ammo = mag.ammo })
    end
    if now - (state.fireAt[weaponId] or 0) < gcfg.IntervalSec then
        return self:Fail(player, 'attack', 'cooldown', { weapon = weaponId })
    end
    if mag.ammo <= 0 then
        -- 空匣自动换弹（与手动同口径 2 秒），备弹无限所以一定补满
        mag.reloadUntil = now + acfg().GunShared.ReloadSec
        print('[MgrWeapon] 空匣自动换弹', player.UserId, weaponId,
            'until=' .. tostring(mag.reloadUntil))
        return self:Fail(player, 'attack', 'empty', { weapon = weaponId, autoReload = true })
    end
    mag.ammo = mag.ammo - 1
    state.fireAt[weaponId] = now

    local target, hitPos = self:GunHit(player, gcfg)
    local pellets = gcfg.Pellets or 1
    local damage = gcfg.Damage * scale
    if target then
        local appliedAny = false
        for _ = 1, pellets do
            local hit = self.Vitals:NewHit(player, 'weapon')
            local ok = self.Vitals:ApplyHit(hit, target, damage)
            appliedAny = appliedAny or ok == true
        end
        -- #139：枪械大奖特效（霜冻/麻痹）只在伤害被统一入口接受后挂；脱靶与被拒（安全区等）不挂
        if appliedAny and gcfg.Effect and self.Ability and self.Ability.ApplyWeaponEffect then
            local ok, err = pcall(self.Ability.ApplyWeaponEffect, self.Ability, player, target, gcfg.Effect)
            if not ok then print('[MgrWeapon] 武器特效应用失败', weaponId, tostring(err)) end
        end
        print('[MgrWeapon] 枪击命中', player.UserId, weaponId,
            'damage=' .. tostring(damage), pellets > 1 and ('pellets=' .. pellets) or '',
            'ammo=' .. tostring(mag.ammo))
    else
        print('[MgrWeapon] 枪击未命中', player.UserId, weaponId, 'ammo=' .. tostring(mag.ammo))
    end
    if gcfg.Splash and hitPos then
        -- 火箭筒两段都只归远程强化（不乘爆炸物强化，不双加成）
        local splashHit = self.Vitals:NewHit(player, 'weapon')
        local splashDamage = gcfg.Splash.Damage * scale
        local damaged = self:RadialDamage(hitPos, gcfg.Splash.Radius, splashDamage,
            splashHit, { player, target })
        print('[MgrWeapon] 火箭溅射', player.UserId, 'radius=' .. tostring(gcfg.Splash.Radius),
            'damage=' .. tostring(splashDamage), '命中=' .. tostring(damaged))
    end
    return self:Reply(player, { ok = true, action = 'attack', weapon = weaponId, ammo = mag.ammo })
end

function Mgr:Reload(player)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return self:Fail(player, 'reload', 'unavailable') end
    local weaponId = self:EquippedWeapon(data)
    local gcfg = weaponId and acfg().Guns[weaponId]
    if not gcfg then return self:Fail(player, 'reload', 'not-a-gun', { weapon = weaponId }) end
    local now = self:Now()
    local magazine = data:MagazineSize(gcfg.Magazine)
    local mag = self:MagState(self:GetState(player.UserId), weaponId, magazine)
    self:RefreshMag(mag, magazine, now)
    if mag.reloadUntil then return self:Fail(player, 'reload', 'reloading', { weapon = weaponId }) end
    if mag.ammo >= magazine then return self:Fail(player, 'reload', 'mag-full', { weapon = weaponId }) end
    mag.reloadUntil = now + acfg().GunShared.ReloadSec
    print('[MgrWeapon] 手动换弹', player.UserId, weaponId,
        'sec=' .. tostring(acfg().GunShared.ReloadSec), 'until=' .. tostring(mag.reloadUntil))
    return self:Reply(player, { ok = true, action = 'reload', weapon = weaponId,
        reloadSec = acfg().GunShared.ReloadSec })
end

-- 枪械 hitscan：角色朝向前方 GunShared.Range 米，首命中分类（玩家 / 鱼 / 墙）。
-- 墙与未命中不结算直伤（火箭筒另有落点溅射）。
function Mgr:Vec3(x, y, z)
    if Vector3 then return Vector3.New(x, y, z) end
    return { x = x, y = y, z = z }
end

function Mgr:GunHit(player, gcfg)
    local character = player.Character
    local pos = character and character.Position
    if not pos then return nil, nil end
    local fx, fy, fz = 0, 0, 1
    pcall(function()
        local f = character.Rotation:GetForward()
        fx, fy, fz = f.x or 0, f.y or 0, f.z or 1
    end)
    local range = acfg().GunShared.Range or 30
    local origin = { x = pos.x, y = pos.y + 1, z = pos.z }
    local endPos = { x = origin.x + fx * range, y = origin.y + fy * range, z = origin.z + fz * range }
    local physics = game:GetService('PhysicsService')
    if not physics or not physics.Raycast then return nil, endPos end
    local params
    if RaycastParams then
        local ok, p = pcall(RaycastParams.New)
        if ok and p then
            p.FilterDescendantsInstances = { character }
            params = p
        end
    end
    local ok, hit = pcall(physics.Raycast, physics,
        self:Vec3(origin.x, origin.y, origin.z), self:Vec3(fx * range, fy * range, fz * range), params)
    if not ok or not hit or not hit.Instance then return nil, endPos end
    local hitPos = hit.Position or endPos
    local players = game:GetService('Players')
    local targetPlayer = players and players.GetPlayerFromCharacter
        and players:GetPlayerFromCharacter(hit.Instance)
    if targetPlayer then return targetPlayer, hitPos end
    if self.FishCarrier then
        local carrier = self.FishCarrier:ResolveCarrier(hit.Instance)
        if carrier then return carrier, hitPos end
    end
    return nil, hitPos -- 墙 / 场景
end

-- ===== 投掷 / 爆炸 =====

-- 落点解析：无 target 朝向前方直接投 20 米；有 target（长按选点）水平钳到票面射程；
-- 落点在任意水区 (x,z) 内算落水，水面高度取该水区 SurfaceY。
function Mgr:ResolveTarget(player, target)
    local character = player.Character
    local pos = character and character.Position
    local tcfg = acfg().Throw
    local tx, ty, tz
    if type(target) == 'table' and not isBadNumber(target.x)
        and not isBadNumber(target.y) and not isBadNumber(target.z) then
        tx, ty, tz = target.x, target.y, target.z
    else
        local fx, fz = 0, 1
        pcall(function()
            local f = character.Rotation:GetForward()
            fx, fz = f.x or 0, f.z or 1
        end)
        local len = math.sqrt(fx * fx + fz * fz)
        if len > 0.001 then fx, fz = fx / len, fz / len end
        tx, ty, tz = pos.x + fx * tcfg.Range, pos.y, pos.z + fz * tcfg.Range
    end
    if pos then
        local dx, dz = tx - pos.x, tz - pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist > tcfg.Range then
            local k = tcfg.Range / dist
            tx, tz = pos.x + dx * k, pos.z + dz * k
        end
    end
    local zone = self:WaterZoneAt(tx, tz)
    if zone then ty = zone.SurfaceY end
    return { x = tx, y = ty, z = tz }, zone
end

function Mgr:WaterZoneAt(x, z)
    for _, zone in ipairs(GameCfg.Water.Zones) do
        if MathWaterJudge.InZone(zone, { x = x, y = zone.SurfaceY, z = z }) then return zone end
    end
    return nil
end

-- 保底鱼候选：钓表行 RodLevel==票面（1 级）且鱼种 Grade=='normal'——
-- 首领（boss）/精英（elite）/极品（rare）被结构性排除，普通投掷召唤不出首领。
function Mgr:BlastCandidates(rows)
    local out = {}
    local rod = acfg().Throw.FishRodLevel
    for _, row in ipairs(rows or {}) do
        local species = row.Id and GameCfg.Fish[row.Id]
        if species and row.RodLevel == rod and species.Grade == 'normal' then
            out[#out + 1] = { id = row.Id, weight = row.DrawWeight or 1 }
        end
    end
    return out
end

function Mgr:PickBlastFish(candidates, random)
    local total = 0
    for _, c in ipairs(candidates) do total = total + (c.weight or 1) end
    local r = (random or math.random)() * total
    for _, c in ipairs(candidates) do
        r = r - (c.weight or 1)
        if r <= 0 then return c.id end
    end
    return candidates[#candidates] and candidates[#candidates].id or nil
end

-- 水中爆炸：先生成 3–5 条当地 1 级普通鱼，再算伤害（鱼也会被炸，死亡走 Loot/任务流）
function Mgr:SpawnBlastFish(zone, landing, player)
    local rows = GameCfg.Casting.Zones[zone.Id]
    local candidates = self:BlastCandidates(rows)
    if #candidates == 0 then
        print('[MgrWeapon] 爆炸落水但该水区没有 1 级普通鱼保底', zone.Id)
        return 0
    end
    local tcfg = acfg().Throw
    local random = self.Random or math.random
    local count = random(tcfg.FishMin, tcfg.FishMax)
    for _ = 1, count do
        local fishId = self:PickBlastFish(candidates, random)
        local angle = random() * math.pi * 2
        local radius = 0.5 + random() * 1.5
        local position = { x = landing.x + math.cos(angle) * radius,
            y = zone.SurfaceY, z = landing.z + math.sin(angle) * radius }
        self.FishUnit:SpawnBlastFish(fishId, 1, position, player)
    end
    return count
end

-- 径向伤害：5 米内玩家与活鱼经统一命中入口结算；skip 可以是单个目标或目标数组（投掷者/直伤目标）
function Mgr:RadialDamage(center, radius, amount, hit, skip)
    if not self.Vitals or not hit or not center then return 0 end
    local skipSet = nil
    local singleSkip = nil
    if type(skip) == 'table' and skip[1] ~= nil then
        skipSet = {}
        for _, s in ipairs(skip) do skipSet[s] = true end
    else
        singleSkip = skip
    end
    local function skipped(target)
        if target == nil then return false end
        if skipSet then return skipSet[target] == true end
        return target == singleSkip
    end
    local damaged = 0
    local players = game:GetService('Players')
    for _, p in ipairs(players and players:GetPlayers() or {}) do
        local pos = p.Character and p.Character.Position
        if not skipped(p) and pos and distance2D(center, pos) <= radius then
            if self.Vitals:ApplyHit(hit, p, amount) then damaged = damaged + 1 end
        end
    end
    if self.FishUnit then
        for _, fish in pairs(self.FishUnit.Fish or {}) do
            local body = fish.Carrier and fish.Carrier.Body
            local pos = body and body.Position
            if pos and distance2D(center, pos) <= radius then
                if self.Vitals:ApplyHit(hit, fish.Carrier, amount) then damaged = damaged + 1 end
            end
        end
    end
    return damaged
end

function Mgr:Detonate(player, itemId, landing, zone)
    local ecfg = acfg().Explosives[itemId]
    if not ecfg or not landing then return 0 end
    -- #130：爆炸物强化按基础线性叠加（投掷爆炸结算唯一消费点）
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local scale = data and data.WeaponDamageScale and data:WeaponDamageScale('explosive') or 1
    local damage = ecfg.Damage * scale
    local hit = self.Vitals and self.Vitals:NewHit(player, 'explosive')
    if zone then
        local count = self:SpawnBlastFish(zone, landing, player)
        print('[MgrWeapon] 爆炸落水', zone.Id, itemId, '保底鱼=' .. tostring(count))
    end
    local radius = acfg().Throw.ExplosionRadius
    local damaged = self:RadialDamage(landing, radius, damage, hit, player)
    print('[MgrWeapon] 爆炸', itemId, zone and 'water' or 'land',
        'damage=' .. tostring(damage), 'radius=' .. tostring(radius),
        '命中=' .. tostring(damaged))
    return damaged
end

-- ===== 投掷消耗（#123 协议） =====

function Mgr:Throw(player, payload)
    if self.Vitals and not self.Vitals:CanAct(player) then
        return self:Fail(player, 'throw', 'cannot-act') ~= nil
    end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data or not player.Character then
        self:Fail(player, 'throw', 'unavailable')
        return true
    end
    local slot = payload.slot
    local snap = data:GetItemBarSnapshot()
    local entry = type(slot) == 'number' and slot >= 1 and slot <= (snap.slotCount or 0)
        and snap.slots and snap.slots[slot] or nil
    if not entry or (entry.count or 0) <= 0 then
        self:Fail(player, 'throw', 'bad-slot', { slot = slot })
        return true
    end
    local itemId = entry.itemId
    local definition = GameCfg.Items.Definitions[itemId]
    if not definition or definition.Type ~= '爆炸物' then
        self:Fail(player, 'throw', 'bad-throwable', { slot = slot })
        return true
    end
    local target = payload.target
    if target ~= nil and (type(target) ~= 'table' or isBadNumber(target.x)
        or isBadNumber(target.y) or isBadNumber(target.z)) then
        self:Fail(player, 'throw', 'bad-target')
        return true
    end
    if not self.Save then
        -- 无存档环境（纯逻辑/测试）：直接在活数据上恰减 1 件
        local container = data.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
        local it = container and container[slot]
        if not it or it.count <= 0 or it.itemId ~= itemId then
            self:Fail(player, 'throw', 'empty', { slot = slot })
            return true
        end
        data:UpdateData(function(d)
            local cur = d.Containers[GameCfg.Items.ContainerId.ItemBar][slot]
            if cur and cur.count > 1 then cur.count = cur.count - 1
            else d.Containers[GameCfg.Items.ContainerId.ItemBar][slot] = nil end
        end, true)
        print('[MgrWeapon] 投掷（无存档直扣）', player.UserId, itemId, 'slot=' .. tostring(slot))
        self.PlayerData:SendItemBar(player)
        self:Launch(player, itemId, target)
        self:Reply(player, { ok = true, action = 'throw', itemId = itemId, slot = slot })
        return true
    end
    -- 持久模式：消费与结果同键落账，成功回调里才发飞行物；重放只回历史结果
    -- （operation 身份必须是协议下发的表，与 MgrShop 同款校验）
    local requestId = payload.operation
    if requestId ~= nil and type(requestId) ~= 'table' then
        self:Fail(player, 'throw', 'bad-operation')
        return true
    end
    if requestId == nil then requestId = payload.seq end
    local operation, mode = self.Save:ResolveRequest(player, data, 'throw', requestId)
    if not operation then
        if mode == 'replay' then return true end -- 协议层已回包（理论不可达，resolve 返回 replay 时必有 operation）
        self:Fail(player, 'throw', 'unavailable')
        return true
    end
    if mode == 'replay' then
        local accepted = self.Save:Execute(player, data, operation, function() return nil, 'expired' end,
            function(ok, result)
                if ok then
                    result.operation = operation
                    self:Reply(player, result) -- 原结果重放，不再发射
                end
            end)
        return accepted == true
    end
    return self.Save:Execute(player, data, operation, function(draft)
        local container = draft.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
        local it = container and container[slot]
        if not it or it.count <= 0 or it.itemId ~= itemId then return nil, 'empty' end
        draft:UpdateData(function(d)
            local cur = d.Containers[GameCfg.Items.ContainerId.ItemBar][slot]
            if cur and cur.count > 1 then cur.count = cur.count - 1
            else d.Containers[GameCfg.Items.ContainerId.ItemBar][slot] = nil end
        end, true)
        return { ok = true, action = 'throw', itemId = itemId, slot = slot }
    end, function(written, result)
        if not written then
            self:Fail(player, 'throw', result, { slot = slot })
            return
        end
        result.operation = operation
        print('[MgrWeapon] 投掷落账', player.UserId, operation.id, itemId, 'slot=' .. tostring(slot))
        self.PlayerData:SendItemBar(player)
        self:Reply(player, result)
        self:Launch(player, itemId, target) -- 世界侧效果只在落账成功后发生
    end) == true
end

-- ===== 飞行物 =====

function Mgr:FlightPosition(flight, t)
    local from, to = flight.from, flight.landing
    if not from then return { x = to.x, y = to.y, z = to.z } end
    local arc = acfg().Throw.ArcHeight or 3
    return {
        x = from.x + (to.x - from.x) * t,
        y = from.y + (to.y - from.y) * t + math.sin(t * math.pi) * arc,
        z = from.z + (to.z - from.z) * t,
    }
end

function Mgr:CreateThrowVisual(player, itemId, flight)
    local ok, visual = pcall(function()
        return game:GetService('World'):CreateUnit('TriggerUnit', {
            Name = 'ThrowProjectile',
            PhysicsMeshId = THROW_VISUAL_MESH,
            Position = self:FlightPosition(flight, 0),
            Scale = self:Vec3(1, 1, 1),
        })
    end)
    if ok and visual then return visual end
    print('[MgrWeapon] 投掷物视觉创建失败（不影响结算）', tostring(visual))
    return nil
end

function Mgr:Launch(player, itemId, target)
    local landing, zone = self:ResolveTarget(player, target)
    local character = player.Character
    local flight = { player = player, itemId = itemId,
        from = character and character.Position or nil,
        landing = landing, zone = zone,
        startAt = self:Now(), flightSec = acfg().Throw.FlightSec or 0.8 }
    flight.visual = self:CreateThrowVisual(player, itemId, flight)
    self.Flying[#self.Flying + 1] = flight
    print('[MgrWeapon] 投掷', player.UserId, itemId,
        zone and ('落水 ' .. zone.Id) or '落地', 'flight=' .. tostring(flight.flightSec))
    return flight
end

function Mgr:StepVisual(flight, t)
    if not flight.visual then return end
    pcall(function()
        flight.visual.Position = self:FlightPosition(flight, t)
    end)
end

function Mgr:Update()
    local now = self:Now()
    for i = #self.Flying, 1, -1 do
        local flight = self.Flying[i]
        local t = (now - flight.startAt) / (flight.flightSec or 0.8)
        if t >= 1 then
            table.remove(self.Flying, i)
            if flight.visual then pcall(function() flight.visual:Destroy() end) end
            self:Detonate(flight.player, flight.itemId, flight.landing, flight.zone)
        else
            self:StepVisual(flight, math.max(0, t))
        end
    end
end

-- ===== 施法守卫与 RE =====

-- 近战槽的玩家施法必须有登记挥挡（MgrWeapon 每次攻击前登记）；鱼等非玩家单位不受限
function Mgr:CastGuard(unit, index)
    if index ~= self:MeleeIndex() then return true end
    local players = game:GetService('Players')
    local player = players and players.GetPlayerFromCharacter
        and players:GetPlayerFromCharacter(unit)
    if not player then return true end
    return AbilityAPI.PeekSwing(player.UserId) ~= nil
end

function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or type(player) ~= 'table' then return false end
    if payload.action == 'attack' then self:Attack(player) return true end
    if payload.action == 'reload' then self:Reload(player) return true end
    if payload.action == 'throw' then return self:Throw(player, payload) end
    return false
end

function Mgr:Start()
    _G.REUtil:GetRE('WeaponAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'WeaponAction', acfg().GunShared.ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
    AbilityAPI.AddCastGuard(function(unit, index) return self:CastGuard(unit, index) end)
end

function Mgr:OnPlayerRemoving(player)
    self.States[player.UserId] = nil
end

return Mgr
