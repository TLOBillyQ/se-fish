-- #140 T19 特殊道具（风神之翼 item169 / 哥斯拉变身 item170）：服务端装配与状态调和。
-- 纯逻辑（选中映射 / 飞行步进 / 吐息台账 / 冷却）在 common/SpecialItem.lua，数值在
-- GameCfg.Ability.SpecialItem；本模块只做三件事：
--   * 调和（Reconcile）：每帧把「期望生效效果」（选中槽物品 × CanAct）与「已应用效果」对齐，
--     切换 / 丢弃 / 死亡 / 复活 / 摆渡 / 重进全走这一条路，不保留事件式残留；
--   * 引擎接缝：背负翅膀（EggyAppearance:BindAppearance / UnbindAppearance）、变身换肤
--     （SetAppearanceByAssetId / ResetAppearance）、飞行接管（Controller.GravityEnabled +
--     逐帧写 Character.Position，#132 叼人已验证的接缝）、吐息结算（Vitals:NewHit/ApplyHit）；
--   * 冷却镜像：吐息 CD 以剩余秒数写 Extra.cooldowns（与 MgrSurvival.Mirror 同口径），
--     重进恢复成绝对时刻；冷却只依赖绝对时刻，切换 / 死亡清不掉。
-- 首领哥斯拉（BossPhase.Attacks.breath，10 米 OneShot 秒杀）与玩家吐息（本模块
-- GameCfg.Ability.SpecialItem.Godzilla.Breath，30 米 / 每目标 1000）严格分开，互不读取。
-- 依赖（server/main.lua 单向注入）：Vitals（CanAct/NewHit/ApplyHit）、PlayerData（选中槽与
-- 冷却镜像）、FishUnit（鱼目标枚举）。MgrFerry:Teleport 前调 OnTeleport 结束飞行。
local GameCfg = require('common.GameCfg')
local SpecialItem = require('common.SpecialItem')
local FlightPath = require('common.FlightPath')

local Mgr = { States = {} }

local function cfg()
    return GameCfg.Ability.SpecialItem
end

local function breathCfg()
    return cfg().Godzilla.Breath
end

local function zoneScene(zoneId)
    for _, zone in ipairs(GameCfg.Zones or {}) do
        if zone.Id == zoneId then return zone.Scene end
    end
end

-- 光束走廊判定（纯几何）：正前 [0, Range] 米、横向与纵向各半宽 Width 内
local function inCorridor(origin, forward, pos, bc)
    local dx, dz = pos.x - origin.x, pos.z - origin.z
    local along = dx * forward.x + dz * forward.z
    if along < 0 or along > bc.Range then return false end
    local perp = math.abs(dx * forward.z - dz * forward.x)
    if perp > bc.Width then return false end
    if math.abs(pos.y - origin.y) > bc.Width then return false end
    return true
end

local function flatForward(rotation)
    local f = rotation and rotation.GetForward and rotation:GetForward() or nil
    local fx, fz = (f and f.x) or 0, (f and f.z) or 1
    local len = math.sqrt(fx * fx + fz * fz)
    if len < 1e-6 then return { x = 0, z = 1 } end
    return { x = fx / len, z = fz / len }
end

local function setGravity(character, enabled)
    local controller = character and character.Controller
    if not controller then return end
    pcall(function() controller.GravityEnabled = enabled end)
end

function Mgr:Now()
    return game:GetService('World'):GetServerTime()
end

-- 在线玩家枚举是测试替身的注入点（试玩里就是 Players:GetPlayers()）
function Mgr:OnlinePlayers()
    return game:GetService('Players'):GetPlayers()
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('SpecialItemResult'):FireClient(player, payload)
end

function Mgr:Fail(player, action, reason)
    print('[MgrSpecialItem] 请求拒绝', player.UserId, action, tostring(reason))
    self:Reply(player, { ok = false, action = action, reason = reason })
    return false
end

-- 状态下发：客户端按 effect 切换道具键语义、按 breathRemaining 显示冷却
function Mgr:SendState(player)
    local state = self.States[player.UserId]
    if not state then return end
    _G.REUtil:GetRE('SpecialItemState'):FireClient(player, {
        effect = state.effect,
        airborne = state.airborne,
        breathRemaining = SpecialItem.CooldownRemaining(state.lastBreathAt, self:Now(), breathCfg().CooldownSec),
    })
end

function Mgr:GetState(player)
    local state = self.States[player.UserId]
    if not state then
        state = { player = player, effect = nil, holding = false, airborne = false,
            gravityOff = false, flightY = nil, wingBindId = nil, skinApplied = false,
            lastBreathAt = nil, breath = nil }
        self.States[player.UserId] = state
    end
    return state
end

function Mgr:CanAct(player)
    return self.Vitals and self.Vitals:CanAct(player) == true or false
end

-- 选中槽物品 id（SelectedSlot 是选中模型；手持 held 是另一层，本模块不读）
local function selectedItemId(data)
    local slot = data and data.Data and data.Data.SelectedSlot
    if type(slot) ~= 'number' then return nil end
    local bar = data.Data.Containers and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    local entry = bar and bar[slot]
    return entry and entry.itemId or nil
end

-- ===== 效果应用与恢复 =====

function Mgr:Apply(player, state, effect)
    local character = player.Character
    state.effect = effect
    if effect == 'wings' then
        local wings = cfg().Wings
        local appearance = character and character.EggyAppearance
        -- 外观件资源待编辑器预设（[未查证]）；空值只开飞行能力、不改外观
        if appearance and wings.AppearanceAssetId and appearance.BindAppearance then
            local ok, bindId = pcall(appearance.BindAppearance, appearance,
                wings.AppearanceAssetId, wings.Socket,
                Vector3.New(wings.Offset.x, wings.Offset.y, wings.Offset.z))
            if ok then state.wingBindId = bindId end
        end
        -- 飞行接管只在空中（长按升 / 松开缓降）由 UpdateFlight 关重力；地面待机保留重力，
        -- 否则跳跃 / 走下台阶即漂浮（GravityEnabled「关闭后单位将漂浮」）
    elseif effect == 'godzilla' then
        local appearance = character and character.EggyAppearance
        local assetId = cfg().Godzilla.AppearanceAssetId
        -- 皮肤资源待 AIGC / 编辑器预设（[未查证]）；空值不变外观，吐息照常
        if appearance and assetId and appearance.SetAppearanceByAssetId then
            local ok = pcall(appearance.SetAppearanceByAssetId, appearance, assetId)
            state.skinApplied = ok
        end
    end
end

-- 恢复原外观与运动状态：解绑翅膀 / 复位皮肤、重力恢复、中止飞行与吐息。
-- 冷却（lastBreathAt）不动——切换 / 死亡清不掉冷却。
function Mgr:Restore(player, state)
    local character = player.Character
    local appearance = character and character.EggyAppearance
    if state.wingBindId and appearance and appearance.UnbindAppearance then
        pcall(appearance.UnbindAppearance, appearance, state.wingBindId)
    end
    state.wingBindId = nil
    if state.skinApplied and appearance and appearance.ResetAppearance then
        pcall(appearance.ResetAppearance, appearance)
    end
    state.skinApplied = false
    if state.gravityOff then setGravity(character, true) end
    state.gravityOff = false
    state.airborne = false
    state.holding = false
    state.flightY = nil
    state.breath = nil
    state.effect = nil
end

-- 调和：期望（选中 × CanAct）与已应用对齐；切换 / 丢弃 / 死亡 / 复活全走这条路
function Mgr:Reconcile(player, state)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local desired = nil
    if data and self:CanAct(player) then
        desired = SpecialItem.Desired(selectedItemId(data))
    end
    if desired == state.effect then return end
    self:Restore(player, state)
    if desired and player.Character then
        self:Apply(player, state, desired)
    end
    self:SendState(player)
end

-- ===== 飞行 =====

function Mgr:UpdateFlight(player, state, dt)
    local character = player.Character
    if not character or not character.Position then return end
    local wings = cfg().Wings
    -- 缓降被地形托住（引擎把角色顶回到上一帧写入的 y 之上）：视为落地
    if state.airborne and not state.holding and state.flightY
        and character.Position.y > state.flightY + wings.LandEpsilon then
        state.airborne = false
    end
    if not state.holding and not state.airborne then
        -- 地面待机 / 刚落地：交还重力，实际地形低于区地面基准时由引擎接着落下
        if state.gravityOff then setGravity(character, true) end
        state.gravityOff = false
        state.flightY = nil
        return
    end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local scene = data and zoneScene(GameCfg.ResolveZoneId(data.Data.Zone))
    local bounds = scene and FlightPath.BoundsOf(scene, GameCfg.Ability.Flight)
    if not bounds then return end -- 无边界不飞（FlightPath 契约）
    -- 空中接管 y：重力关闭（角色重建 / 外部改动后下一帧纠正）
    setGravity(character, false)
    state.gravityOff = true
    local y, airborne = SpecialItem.StepFlightY(wings,
        { Y = state.flightY or character.Position.y, Airborne = state.airborne },
        state.holding, dt, bounds)
    local cx, cz = SpecialItem.ClampXZ(bounds, character.Position.x, character.Position.z)
    pcall(function() character.Position = Vector3.New(cx, y, cz) end)
    state.flightY = y
    state.airborne = airborne
    if not airborne then -- 降到区地面基准：本帧即交还重力
        setGravity(character, true)
        state.gravityOff = false
        state.flightY = nil
    end
end

-- ===== 原子吐息 =====

-- 施法校验：变身中、活着、冷却就绪；一本台账 + 一个命中身份管全程
function Mgr:CastBreath(player)
    local state = self:GetState(player)
    if state.effect ~= 'godzilla' then return self:Fail(player, 'breath', 'not-godzilla') end
    if not self:CanAct(player) then return self:Fail(player, 'breath', 'not-alive') end
    local character = player.Character
    local pos = character and character.Position
    if not pos then return self:Fail(player, 'breath', 'no-character') end
    if not self.Vitals then return self:Fail(player, 'breath', 'no-vitals') end
    local now = self:Now()
    local bc = breathCfg()
    if SpecialItem.CooldownRemaining(state.lastBreathAt, now, bc.CooldownSec) > 0 then
        return self:Fail(player, 'breath', 'cooldown')
    end
    state.lastBreathAt = now
    state.breath = {
        castAt = now, tick = 1,
        hit = self.Vitals:NewHit(player, 'specialBreath'),
        ledger = SpecialItem.NewBreathLedger(bc),
        origin = { x = pos.x, y = pos.y, z = pos.z },
        forward = flatForward(character.Rotation),
    }
    self:Reply(player, { ok = true, action = 'breath', endsAt = now + bc.DurationSec })
    self:SendState(player)
    return true
end

-- 单段结算：走廊内每个目标经台账取本段伤害（无重复段、不超 1000），过统一伤害入口
function Mgr:BreathTick(player, breath, tick)
    local bc = breathCfg()
    local function settle(target, key, pos)
        if pos and inCorridor(breath.origin, breath.forward, pos, bc) then
            local amount = SpecialItem.BreathHit(breath.ledger, key, tick)
            if amount then self.Vitals:ApplyHit(breath.hit, target, amount) end
        end
    end
    for _, p in ipairs(self:OnlinePlayers() or {}) do
        if p ~= player and p.Character and p.Character.Position then
            settle(p, 'player:' .. tostring(p.UserId), p.Character.Position)
        end
    end
    if self.FishUnit then
        for _, fish in pairs(self.FishUnit.Fish or {}) do
            local carrier = fish.Carrier
            local body = carrier and carrier.Body
            if carrier and not carrier.Dead and body and body.Position then
                settle(carrier, 'fish:' .. tostring(fish.Id), body.Position)
            end
        end
    end
end

function Mgr:UpdateBreath(player, state, now)
    local breath = state.breath
    local bc = breathCfg()
    local plan = breath.ledger.Plan
    while breath.tick <= #plan and now >= breath.castAt + (breath.tick - 1) * bc.TickSec do
        self:BreathTick(player, breath, breath.tick)
        breath.tick = breath.tick + 1
    end
    if now >= breath.castAt + bc.DurationSec then
        state.breath = nil
        self:SendState(player)
    end
end

-- 冷却镜像：剩余秒数写 Extra.cooldowns（与 MgrSurvival.Mirror 同口径），随普通存档落盘
function Mgr:MirrorCooldown(state, now)
    if not state.lastBreathAt then return end
    local data = self.PlayerData and self.PlayerData:GetDataInst(state.player)
    local mark = data and data.Extra and data.Extra.cooldowns
    if type(mark) ~= 'table' then return end
    mark.godzillaBreath = SpecialItem.CooldownRemaining(state.lastBreathAt, now, breathCfg().CooldownSec)
end

-- ===== 生命周期与心跳 =====

function Mgr:Update(dt)
    local now = self:Now()
    for _, state in pairs(self.States) do
        local player = state.player
        if player then
            self:Reconcile(player, state)
            if state.effect == 'wings' then self:UpdateFlight(player, state, dt) end
            if state.breath then self:UpdateBreath(player, state, now) end
            self:MirrorCooldown(state, now)
        end
    end
end

function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or type(player) ~= 'table' then return false end
    local state = self:GetState(player)
    if payload.action == 'fly' then
        -- 未装备翅膀或不能行动时指令无效：holding 强制清空，杜绝「幽灵升空」
        if state.effect ~= 'wings' or not self:CanAct(player) then
            state.holding = false
            return self:Fail(player, 'fly', 'not-wings')
        end
        state.holding = payload.holding == true
        return true
    end
    if payload.action == 'breath' then
        return self:CastBreath(player)
    end
    return false
end

function Mgr:Start()
    _G.REUtil:GetRE('SpecialItemAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'SpecialItemAction', cfg().ReLimitSec) then return end
        self:Handle(player, payload)
    end)
end

function Mgr:OnPlayerAdded(player)
    local state = self:GetState(player)
    state.player = player
    -- 离线恢复：冷却镜像存的是剩余秒数（防服务器重启后按绝对时刻卡死），恢复成绝对时刻；
    -- 飞行 / 变身不复活，等下一帧调和按当前选中重放（重力保持引擎默认开）。
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local mark = data and data.Extra and data.Extra.cooldowns
    local remaining = mark and mark.godzillaBreath
    if type(remaining) == 'number' and remaining > 0 then
        state.lastBreathAt = self:Now() - (breathCfg().CooldownSec - remaining)
    end
    self:SendState(player)
end

-- 摆渡钩子（MgrFerry:Teleport 前调用）：结束飞行运动状态，外观随新区下一帧调和重放
function Mgr:OnTeleport(player)
    local state = self.States[player.UserId]
    if not state then return end
    if state.gravityOff and player.Character then setGravity(player.Character, true) end
    state.gravityOff = false
    state.airborne = false
    state.holding = false
    state.flightY = nil
end

function Mgr:OnPlayerRemoving(player)
    local state = self.States[player.UserId]
    if state then
        -- 离场前尽力恢复原外观与运动状态（角色可能已销毁，pcall 兜底）
        pcall(function() self:Restore(player, state) end)
    end
    self.States[player.UserId] = nil
end

return Mgr
