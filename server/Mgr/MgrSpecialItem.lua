-- #140 T19 特殊道具（风神之翼 item169 / 哥斯拉变身 item170）：服务端装配与状态调和。
-- 纯逻辑（选中映射 / 飞行步进 / 吐息台账 / 冷却）在 common/SpecialItem.lua，数值在
-- GameCfg.Ability.SpecialItem；本模块只做三件事：
--   * 调和（Reconcile）：每帧把「期望生效效果」（选中槽物品 × CanAct）与「已应用效果」对齐，
--     切换 / 丢弃 / 死亡 / 复活 / 摆渡 / 重进全走这一条路，不保留事件式残留；
--   * 引擎接缝：背负翅膀（EggyAppearance:BindAppearance / UnbindAppearance）、变身换肤
--     （SetAppearanceByAssetId / ResetAppearance）、飞行接管（仅空中关 Controller.GravityEnabled +
--     逐帧写 Character.Position，#132 叼人已验证的接缝）、吐息结算（每段 Vitals:NewHit/ApplyHit）；
--   * 冷却镜像：吐息 CD 以剩余秒数写 Extra.cooldowns（与 MgrSurvival.Mirror 同口径），
--     重进恢复成绝对时刻；冷却只依赖绝对时刻，切换 / 死亡清不掉。
-- 首领哥斯拉（BossPhase.Attacks.breath，10 米 OneShot 秒杀）与玩家吐息（本模块
-- GameCfg.Ability.SpecialItem.Godzilla.Breath，30 米 / 每目标 1000）严格分开，互不读取。
-- 依赖（server/main.lua 单向注入）：Vitals（CanAct/NewHit/ApplyHit）、PlayerData（选中槽与
-- 冷却镜像）、FishUnit（鱼目标枚举）。MgrFerry:Teleport 前调 OnTeleport 结束飞行。
local GameCfg = require('common.GameCfg')
local SpecialItem = require('common.SpecialItem')
local FlightPath = require('common.FlightPath')

local Mgr = { States = {}, PendingCleanup = {}, CleanupFailures = {} }
local CLEANUP_HISTORY_LIMIT = 16 -- 仅保留字符串诊断，不持有已销毁引擎对象
local CLEANUP_RETRIES = 5 -- 离场后最多五次重试，耗尽后保留失败记录而不继续调用引擎

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
    if not controller then return false, "no-controller" end
    return pcall(function() controller.GravityEnabled = enabled end)
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
        effect = not state.restoring and state.effect or nil,
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

-- 每个引擎操作每秒最多重试一次；只在首次失败时记录对象与错误，成功后删除重试依据。
function Mgr:EngineCall(state, key, object, fn)
    state.failures = state.failures or {}
    local failure = state.failures[key]
    if failure and self:Now() < failure.nextAt then return false end
    local ok, result = pcall(fn)
    if ok and result ~= false then
        state.failures[key] = nil
        return true, result
    end
    if not failure then print('[MgrSpecialItem] 引擎操作失败', key, tostring(object), tostring(result)) end
    state.failures[key] = { object = object, error = result, nextAt = self:Now() + 1 }
    return false
end

function Mgr:Apply(player, state, effect)
    local character = player.Character
    local appearance = character and character.EggyAppearance
    if effect == 'wings' and cfg().Wings.AppearanceAssetId then
        local wings = cfg().Wings
        local ok, id = self:EngineCall(state, 'bind', appearance, function()
            return appearance:BindAppearance(wings.AppearanceAssetId, Enums.SkeletalSocketType[wings.Socket],
                Vector3.New(wings.Offset.x, wings.Offset.y, wings.Offset.z),
                Quaternion.Identity(), Vector3.New(1, 1, 1))
        end)
        if not ok or type(id) ~= 'number' then return false end
        state.wingBindId, state.appearance = id, appearance
    elseif effect == 'godzilla' and cfg().Godzilla.AppearanceAssetId then
        if not self:EngineCall(state, 'skin', appearance, function()
            appearance:SetAppearanceByAssetId(cfg().Godzilla.AppearanceAssetId)
        end) then return false end
        state.skinApplied, state.appearance = true, appearance
    end
    state.effect = effect
    return true
end

function Mgr:Gravity(player, state, enabled)
    local character = state.gravityCharacter or state.cleanupCharacter or player.Character
    local ok = self:EngineCall(state, 'gravity', character, function()
        local success, err = setGravity(character, enabled)
        if not success then error(err) end
    end)
    if ok then
        state.gravityOff = not enabled
        state.gravityCharacter = not enabled and character or nil
    end
    return ok
end

function Mgr:Restore(player, state)
    state.holding, state.airborne, state.flightY, state.breath = false, false, nil, nil
    state.flightGroundY = nil
    local character = state.cleanupCharacter or player.Character
    local appearance = state.appearance or (character and character.EggyAppearance)
    if state.wingBindId then
        if self:EngineCall(state, 'unbind', appearance, function()
            return appearance:UnbindAppearance(state.wingBindId)
        end) then state.wingBindId = nil end
    end
    if state.skinApplied then
        if self:EngineCall(state, 'reset', appearance, function() appearance:ResetAppearance() end) then
            state.skinApplied = false
        end
    end
    if state.gravityOff then self:Gravity(player, state, true) end
    if state.wingBindId or state.skinApplied or state.gravityOff then
        state.restoring = true
        return false
    end
    state.restoring, state.effect, state.appearance = false, nil, nil
    return true
end

function Mgr:Reconcile(player, state)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local selected = selectedItemId(data)
    if state.suspendedItem and selected ~= state.suspendedItem then state.suspendedItem = nil end
    local desired = data and self:CanAct(player) and not state.suspendedItem and SpecialItem.Desired(selected) or nil
    if desired == state.effect and not state.restoring then return end
    if not self:Restore(player, state) then return end
    if desired and player.Character then self:Apply(player, state, desired) end
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
        if state.gravityOff then self:Gravity(player, state, true) end
        state.flightY, state.flightGroundY = nil, nil
        return
    end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local scene = data and zoneScene(GameCfg.ResolveZoneId(data.Data.Zone))
    local bounds = scene and FlightPath.BoundsOf(scene, GameCfg.Ability.Flight)
    if not bounds then return end -- 无边界不飞（FlightPath 契约）
    if not state.flightGroundY then state.flightGroundY = character.Position.y end
    bounds.GroundY = state.flightGroundY
    bounds.CeilingY = math.min(bounds.CeilingY, state.flightGroundY + bounds.MaxHeight)
    -- 高度上限仍取七区合同，低于安全点起飞不被第一帧抬高

    -- 空中接管 y：重力关闭（角色重建 / 外部改动后下一帧纠正）
    if not self:Gravity(player, state, false) then return end
    local y, airborne = SpecialItem.StepFlightY(wings,
        { Y = state.flightY or character.Position.y, Airborne = state.airborne },
        state.holding, dt, bounds)
    local cx, cz = SpecialItem.ClampXZ(bounds, character.Position.x, character.Position.z)
    pcall(function() character.Position = Vector3.New(cx, y, cz) end)
    state.flightY = y
    state.airborne = airborne
    if not airborne then -- 降到区地面基准：本帧即交还重力
        self:Gravity(player, state, true)
        state.flightY, state.flightGroundY = nil, nil
    end
end

-- ===== 原子吐息 =====

-- 施法校验：变身中、活着、冷却就绪；一本台账管全程（每目标按段结算、总额恰 1000）
function Mgr:CastBreath(player)
    local state = self:GetState(player)
    if state.restoring or state.effect ~= 'godzilla' then return self:Fail(player, 'breath', 'not-godzilla') end
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
    self:MirrorCooldown(state, now) -- 施法即镜像，尚未心跳就离线也不能清 CD
    state.breath = {
        castAt = now, tick = 1,
        ledger = SpecialItem.NewBreathLedger(bc),
        origin = { x = pos.x, y = pos.y, z = pos.z },
        forward = flatForward(character.Rotation),
    }
    self:Reply(player, { ok = true, action = 'breath', endsAt = now + bc.DurationSec })
    self:SendState(player)
    return true
end

-- 单段结算：走廊内每个目标经台账取本段伤害（无重复段、不超 1000），过统一伤害入口。
-- 每段颁发新命中身份：Vitals 同一身份对同一目标只结算一次（#128「DOT 下一 tick 须重新 NewHit」），
-- 整次施法共用一个身份会让每个目标只吃到第 1 段；段内去重仍由台账与该身份共同保证。
function Mgr:BreathTick(player, breath, tick)
    local bc = breathCfg()
    local hit = self.Vitals:NewHit(player, 'specialBreath')
    local function settle(target, key, pos)
        if pos and inCorridor(breath.origin, breath.forward, pos, bc) then
            local amount = SpecialItem.BreathHit(breath.ledger, key, tick)
            if amount then self.Vitals:ApplyHit(hit, target, amount) end
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
    -- 清理队列按旧状态对象登记，与 UserId 在线状态表完全分离；永不写入/删除新会话。
    for state, job in pairs(self.PendingCleanup) do
        if now >= job.nextAt then
            job.attempts = job.attempts + 1
            if self:Restore(state.player, state) then
                self.PendingCleanup[state] = nil
            elseif job.attempts >= CLEANUP_RETRIES then
                self.PendingCleanup[state] = nil
                local errors = {}
                for key, failure in pairs(state.failures or {}) do
                    errors[#errors + 1] = key .. ': ' .. tostring(failure.error)
                end
                self.CleanupFailures[#self.CleanupFailures + 1] = {
                    userId = tostring(state.player.UserId), at = now, attempts = job.attempts,
                    errors = table.concat(errors, '; '),
                }
                if #self.CleanupFailures > CLEANUP_HISTORY_LIMIT then table.remove(self.CleanupFailures, 1) end
                -- 队列已移除；摘要不含旧状态/Player/角色引用，允许销毁对象回收。
            else
                job.nextAt = now + 1
            end
        end
    end
    for _, state in pairs(self.States) do
        local player = state.player
        if player then
            self:Reconcile(player, state)
            if not state.restoring and state.effect == 'wings' then self:UpdateFlight(player, state, dt) end
            if state.breath then self:UpdateBreath(player, state, now) end
            self:MirrorCooldown(state, now)
        end
    end
end

function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or not player then return false end
    -- 引擎 Player 并非 Lua table；校验登记身份对象，既兼容引擎也拒绝伪造 / 尚未载入存档的请求
    local ok, userId = pcall(function() return player.UserId end)
    local state = ok and self.States[userId]
    if not state or state.player ~= player then return false end
    self:Reconcile(player, state) -- 请求时复核选中槽，不能利用心跳前的旧 effect 施法
    if payload.action == 'fly' then
        -- 未装备翅膀或不能行动时指令无效：holding 强制清空，杜绝「幽灵升空」
        if state.restoring or state.effect ~= 'wings' or not self:CanAct(player) then
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

function Mgr:Query(player)
    if not player then return false end
    local ok, id = pcall(function() return player.UserId end)
    local state = ok and self.States[id]
    if not state or state.player ~= player or state.leaving then return false end
    if _G.REUtil:CheckRECD(player, 'SpecialItemStateRequest', cfg().ReLimitSec) then return false end
    self:SendState(player)
    return true
end

function Mgr:Start()
    _G.REUtil:GetRE('SpecialItemStateRequest').OnServerEvent:Connect(function(player) self:Query(player) end)
    _G.REUtil:GetRE('SpecialItemAction').OnServerEvent:Connect(function(player, payload)
        -- 松开只会让角色停止上升，不限频：快速点按时松开紧跟按下，被吞掉会让 holding 卡死升到顶
        local release = type(payload) == 'table' and payload.action == 'fly' and payload.holding ~= true
        if not release and _G.REUtil:CheckRECD(player, 'SpecialItemAction', cfg().ReLimitSec) then return end
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

-- 终镜像在 SaveLeaving 序列化前调用，写入当前剩余冷却（不能依赖上一帧镜像）
function Mgr:BeforeLeave(player)
    local state = self.States[player.UserId]
    if state and state.player == player then self:MirrorCooldown(state, self:Now()) end
end

-- 摆渡钩子（MgrFerry:Teleport 前调用）：结束飞行运动状态，外观随新区下一帧调和重放
function Mgr:OnTeleport(player)
    local state = self.States[player.UserId]
    if not state then return end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    state.suspendedItem = selectedItemId(data)
    self:Restore(player, state)
    self:SendState(player)
end

function Mgr:OnPlayerRemoving(player)
    local state = self.States[player.UserId]
    if not state or state.player ~= player then return end -- 迟到的旧退出不能污染同身份新会话
    self:MirrorCooldown(state, self:Now())
    state.cleanupCharacter = player.Character -- 清理只持有旧角色，不再读取新会话角色
    if self.States[player.UserId] == state then self.States[player.UserId] = nil end
    if not self:Restore(player, state) then
        self.PendingCleanup[state] = { attempts = 0, nextAt = self:Now() + 1 }
    end
end

return Mgr
