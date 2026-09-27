local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local FishCatch = require('common.FishCatch')
local MgrPlayerData = require('server.Mgr.MgrPlayerData')
local REUtil = require('common.REUtil')
local MgrFishUnit = require('server.Mgr.MgrFishUnit')

local Mgr = { Sessions = {}, NextFish = {}, NextFishSerial = 0, FishUnit = MgrFishUnit }
MathWaterJudge.Build(GameCfg.Water.Zones)

-- 选中格是鱼竿（物品表带 Level 的竿种，#90 起不限新手竿）且与客户端声明一致才受理
local function selectedRod(data, payload)
    local selected = data.Data.SelectedSlot
    local entry = selected and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    local definition = entry and entry.count >= 1 and GameCfg.Items.Definitions[entry.itemId]
    if not definition or type(definition.Level) ~= 'number'
        or payload.slot ~= selected or payload.itemId ~= entry.itemId then return end
    return selected, entry
end

local function waterZone(x, z)
    for _, candidate in ipairs(GameCfg.Water.Zones) do
        if MathWaterJudge.InZone(candidate, { x = x, y = candidate.SurfaceY, z = z }) then
            return candidate
        end
    end
end

local function castLanding(character)
    local origin, rotation = character.Position, character.Rotation
    if not origin or not rotation then return end
    local forward = rotation:GetForward()
    local length = math.sqrt(forward.x * forward.x + forward.z * forward.z)
    if length < 0.01 then return end
    local x = origin.x + GameCfg.Casting.Distance * forward.x / length
    local z = origin.z + GameCfg.Casting.Distance * forward.z / length
    local zone = waterZone(x, z)
    return { x = x, y = zone and zone.SurfaceY or origin.y, z = z }, zone
end

-- holding：头上顶着的活鱼 {fishId, mult}（#41），客户端 2 号位据此切到「放下」
function Mgr:SendState(player, session, snapshot)
    local holding = self.FishUnit and self.FishUnit:HeldInfo(player) or nil
    REUtil:GetRE('CastState'):FireClient(player, session and {
        phase = session.phase,
        snapshot = snapshot == true,
        castId = session.castId,
        landing = session.landing,
        zoneId = session.zoneId,
        fishId = session.fishId,
        mult = session.mult,
        reelSession = session.reelSession,
        holding = holding,
    } or { phase = 'idle', holding = holding })
end

-- 状态有变（举起 / 放下）时按当前会话重发一次
function Mgr:PushState(player)
    local current = self.Sessions[player.UserId]
    self:SendState(player, current and current.player == player and current.session or nil, true)
end

-- 单次失败反馈不进入会话或快照；已有会话时不附 phase，避免误清等待状态。
function Mgr:SendFailure(player, reason, landing, active)
    local result = { reason = reason, landing = landing }
    REUtil:GetRE('CastState'):FireClient(player, active and { result = result }
        or { phase = 'idle', result = result })
end

function Mgr:Cast(player, payload)
    local current = self.Sessions[player.UserId]
    if current then
        self:SendFailure(player, 'alreadyCasting', nil, true)
        return
    end
    local data = MgrPlayerData:GetDataInst(player)
    local character = player.Character
    if not data or not character then
        self:SendFailure(player, 'unavailable')
        return
    end
    if self.FishUnit and not self.FishUnit:CanCast(player) then
        self:SendFailure(player, 'holding')
        return
    end
    local selected, entry = selectedRod(data, payload)
    if not entry then
        self:SendFailure(player, 'invalidRod')
        return
    end
    local ok, landing, zone = pcall(castLanding, character)
    if not ok then
        print('[MgrCast] 计算落点失败', player.UserId, tostring(landing))
        self:SendFailure(player, 'unavailable')
        return
    end
    if not landing or not zone then
        self:SendFailure(player, landing and 'invalidLanding' or 'unavailable', landing)
        return
    end
    if REUtil:CheckRECD(player, 'CastAction', GameCfg.Casting.ActionCooldownSec) then
        self:SendFailure(player, 'cooldown')
        return
    end
    local baitOk, baitId = data:ConsumeSelectedBait()
    if not baitOk then
        self:SendFailure(player, 'baitUnavailable')
        return
    end
    self.NextCastId = (self.NextCastId or 0) + 1
    local session = {
        castId = self.NextCastId,
        phase = 'cast',
        landing = landing,
        zoneId = zone.Id,
        baitId = baitId,
        slot = selected,
        rodLevel = GameCfg.Items.Definitions[entry.itemId].Level or 1,
        hookAt = self.World:GetServerTime() + GameCfg.Casting.HookDelaySec,
    }
    self.Sessions[player.UserId] = { player = player, session = session }
    self:SendState(player, session)
    print('[MgrCast] 抛竿', player.UserId, session.zoneId, baitId or 'none')
    -- 新手任务「水边抛竿」事实（#52）：只有有效入水的抛竿才报。
    if self.Quest then
        self.Quest:Notify('CastWater', player, { itemId = baitId,
            eventId = 'cast:' .. tostring(player.UserId) .. ':' .. tostring(session.castId) })
    end
end

function Mgr:SetNextFish(player, fishId)
    self.NextFishSerial = self.NextFishSerial + 1
    local entry = { fishId = fishId, serial = self.NextFishSerial }
    self.NextFish[player.UserId] = entry
    local current = self.Sessions[player.UserId]
    if current and current.player == player and current.session.phase == 'hooked' then
        current.session.fishId = fishId
        current.session.forcedFishSerial = entry.serial
        self:SendState(player, current.session)
    end
end

-- 一次钓鱼结束（收竿 / 脱钩 / 上岸停留完）：清会话，归位到抛竿时选中的鱼竿
function Mgr:EndSession(player, current, notify, reason)
    if self.Sessions[player.UserId] ~= current then return end
    self.Sessions[player.UserId] = nil
    if notify == false then return end
    local slot = current.session.slot
    local data = slot and MgrPlayerData:GetDataInst(player)
    if data and data.Data.SelectedSlot ~= slot
        and data:RestoreSlot(slot) then
        MgrPlayerData:SendItemBar(player)
    end
    if reason then
        REUtil:GetRE('CastState'):FireClient(player, {
            phase = 'idle', castId = current.session.castId, result = { reason = reason },
            holding = self.FishUnit and self.FishUnit:HeldInfo(player) or nil,
        })
    else
        self:SendState(player)
    end
end

function Mgr:Reel(player)
    local current = self.Sessions[player.UserId]
    if not current or current.player ~= player or current.session.phase ~= 'cast' then return end
    if REUtil:CheckRECD(player, 'CastAction', GameCfg.Casting.ActionCooldownSec) then return end
    self:EndSession(player, current)
    print('[MgrCast] 收竿', player.UserId)
end

-- 2 号位「放下」（#42）：与抛竿 / 收竿共用操作冷却
function Mgr:Drop(player)
    if not self.FishUnit or not self.FishUnit:GetHeld(player) then return end
    if REUtil:CheckRECD(player, 'CastAction', GameCfg.Casting.ActionCooldownSec) then return end
    self.FishUnit:Drop(player)
end

-- 角色死亡（#42）：还在抛竿等上钩的会话直接结束；上钩后的断线由 MgrReelIn 处理
function Mgr:Abort(player)
    local current = self.Sessions[player.UserId]
    if not current or current.player ~= player or current.session.phase ~= 'cast' then return end
    self:EndSession(player, current)
    print('[MgrCast] 死亡断线', player.UserId)
end

function Mgr:FinishReel(player, sessionId, outcome, notify)
    local current = self.Sessions[player.UserId]
    if not current or current.player ~= player or current.session.reelSession ~= sessionId
        or current.session.phase ~= 'hooked' then return end
    if outcome == 'landed' then
        local session = current.session
        if session.forcedFishSerial and not GameCfg.Debug.Enabled then
            self.NextFish[player.UserId] = nil
            self:EndSession(player, current, notify)
            return
        end
        session.phase = 'landed'
        session.idleAt = self.World:GetServerTime() + GameCfg.Casting.LandedHoldSec
        self:Land(player, session)
        if notify ~= false then self:SendState(player, session) end
        -- 新手任务「上岸」事实（#52）：hooked → landed 只会走一次，收线会话 id 即唯一 eventId
        if self.Quest then
            self.Quest:Notify('Land', player, { itemId = session.fishId, eventId = 'reel:' .. tostring(sessionId) })
        end
    else
        self:EndSession(player, current, notify)
    end
end

-- 上岸结算：phase 已从 hooked 切到 landed，这里只会走一次；活鱼落在玩家正前方，交给活鱼单位管理器
function Mgr:Land(player, session)
    local character = player.Character
    local origin, rotation = character and character.Position, character and character.Rotation
    if not origin or not rotation then
        print('[MgrCast] 上岸但角色不在，未生成活鱼', player.UserId, session.fishId)
        return
    end
    local forward = rotation:GetForward()
    local length = math.sqrt(forward.x * forward.x + forward.z * forward.z)
    local dx, dz = 0, 0
    if length >= 0.01 then
        dx = GameCfg.Casting.LandingOffset * forward.x / length
        dz = GameCfg.Casting.LandingOffset * forward.z / length
    end
    local position = Vector3.New(origin.x + dx, origin.y + GameCfg.Casting.LandingHeight, origin.z + dz)
    local fish, err = self.FishUnit:SpawnLanded(player, { fishId = session.fishId, mult = session.mult }, position)
    if fish then
        local forced = session.forcedFishSerial and self.NextFish[player.UserId]
        if forced and forced.serial == session.forcedFishSerial then self.NextFish[player.UserId] = nil end
        print('[MgrCast] 上岸', player.UserId, session.fishId, session.mult, 'fish=' .. tostring(fish.Id))
    else
        print('[MgrCast] 上岸生成活鱼失败', player.UserId, session.fishId, tostring(err))
    end
    local ok, playErr = pcall(function()
        character.Animator:LoadAnimation(GameCfg.Casting.LandedAnimation):Play()
    end)
    if not ok then print('[MgrCast] 上岸动作播放失败', player.UserId, tostring(playErr)) end
end

function Mgr:Stop()
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    self.Connections = nil
    self.Sessions = {}
    self.NextFish = {}
end

function Mgr:Start()
    self:Stop()
    self.World = game:GetService('World')
    self.Connections = {
        REUtil:GetRE('CastAction').OnServerEvent:Connect(function(player, payload)
            if type(payload) ~= 'table' or not player then return end
            if payload.action == 'Cast' then self:Cast(player, payload)
            elseif payload.action == 'Reel' then self:Reel(player)
            elseif payload.action == 'Drop' then self:Drop(player) end
        end),
        REUtil:GetRE('RequestCastState').OnServerEvent:Connect(function(player)
            self:PushState(player)
        end),
    }
end

function Mgr:OnPlayerRemoving(player)
    local current = self.Sessions[player.UserId]
    if current and current.player == player then
        self.Sessions[player.UserId] = nil
        self.NextFish[player.UserId] = nil
    elseif not current then
        self.NextFish[player.UserId] = nil
    end
end

function Mgr:Update()
    if not GameCfg.Debug.Enabled then self.NextFish = {} end
    local now = self.World:GetServerTime()
    for _, current in pairs(self.Sessions) do
        local session = current.session
        if session.phase == 'landed' and session.idleAt and now >= session.idleAt then
            self:EndSession(current.player, current)
        elseif session.phase == 'cast' and session.hookAt and now >= session.hookAt then
            -- 首领饵必出对应首领（#88，GameSpec §12）：无视权重、鱼饵-鱼种匹配与竿级，不限水域
            local boss = session.baitId and GameCfg.Casting.BossBait
                and GameCfg.Casting.BossBait[session.baitId]
            local forced = GameCfg.Debug.Enabled and self.NextFish[current.player.UserId]
            -- GM 指定鱼种优先于首领饵和抽签；仅成功生成上岸活鱼后清除。
            local fishId = forced and forced.fishId or boss
            if not fishId then
                local rows = GameCfg.Casting.Zones[session.zoneId]
                fishId = FishCatch.Select(rows, session.rodLevel, session.baitId, math.random)
            end
            if fishId then
                session.phase = 'hooked'
                session.fishId = fishId
                session.forcedFishSerial = forced and forced.serial
                session.mult = FishCatch.Multiplier(math.random)
                self.NextReelId = (self.NextReelId or 0) + 1
                session.reelSession = tostring(self.NextReelId) .. ':' .. tostring(current.player.UserId)
                if self.ReelIn:Begin(current.player, session.reelSession, now)
                    and self.Sessions[current.player.UserId] == current and session.phase == 'hooked' then
                    self:SendState(current.player, session)
                    print('[MgrCast] 上钩', current.player.UserId, fishId, session.mult)
                end
            else
                -- 空抽保留已消费的鱼饵；结束会话时一并发送结果，避免旧反馈与新抛竿交错。
                self:EndSession(current.player, current, true, 'noFish')
                print('[MgrCast] 空抽', current.player.UserId, session.zoneId)
            end
        end
    end
end

return Mgr
