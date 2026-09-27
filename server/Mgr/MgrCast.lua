local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local FishCatch = require('common.FishCatch')
local MgrPlayerData = require('server.Mgr.MgrPlayerData')
local REUtil = require('common.REUtil')
local MgrFishUnit = require('server.Mgr.MgrFishUnit')

local Mgr = { Sessions = {}, FishUnit = MgrFishUnit }
MathWaterJudge.Build(GameCfg.Water.Zones)

local function selectedRod(data, payload)
    local selected = data.Data.SelectedSlot
    local entry = selected and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    if not entry or entry.count < 1 or entry.itemId ~= GameCfg.Items.Id.StarterRod
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

function Mgr:Cast(player, payload)
    local data = MgrPlayerData:GetDataInst(player)
    local character = player and player.Character
    if not data or not character or self.Sessions[player.UserId] then return end
    if self.FishUnit and not self.FishUnit:CanCast(player) then return end
    local selected, entry = selectedRod(data, payload)
    if not entry then return end
    local landing, zone = castLanding(character)
    if not landing then return end
    if REUtil:CheckRECD(player, 'CastAction', GameCfg.Casting.ActionCooldownSec) then return end
    local baitOk, baitId = data:ConsumeSelectedBait()
    if not baitOk then return end
    self.NextCastId = (self.NextCastId or 0) + 1
    local session = {
        castId = self.NextCastId,
        phase = 'cast',
        landing = landing,
        zoneId = zone and zone.Id or nil,
        baitId = baitId,
        slot = selected,
        rodLevel = GameCfg.Items.Definitions[entry.itemId].Level or 1,
        hookAt = zone and (self.World:GetServerTime() + GameCfg.Casting.HookDelaySec) or nil,
    }
    self.Sessions[player.UserId] = { player = player, session = session }
    self:SendState(player, session)
    print('[MgrCast] 抛竿', player.UserId, session.zoneId or 'land', baitId or 'none')
    -- 新手任务「水边抛竿」事实（#52）：只有落点判进水区才算，陆地抛竿不报
    if session.zoneId and self.Quest then
        self.Quest:Notify('CastWater', player, { itemId = baitId,
            eventId = 'cast:' .. tostring(player.UserId) .. ':' .. tostring(session.castId) })
    end
end

-- 一次钓鱼结束（收竿 / 脱钩 / 上岸停留完）：清会话，归位到抛竿时选中的鱼竿
function Mgr:EndSession(player, current, notify)
    if self.Sessions[player.UserId] ~= current then return end
    self.Sessions[player.UserId] = nil
    if notify == false then return end
    local slot = current.session.slot
    local data = slot and MgrPlayerData:GetDataInst(player)
    if data and data.Data.SelectedSlot ~= slot
        and data:RestoreSlot(slot) then
        MgrPlayerData:SendItemBar(player)
    end
    self:SendState(player)
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
    if current and current.player == player then self.Sessions[player.UserId] = nil end
end

function Mgr:Update()
    local now = self.World:GetServerTime()
    for _, current in pairs(self.Sessions) do
        local session = current.session
        if session.phase == 'landed' and session.idleAt and now >= session.idleAt then
            self:EndSession(current.player, current)
        elseif session.phase == 'cast' and session.hookAt and now >= session.hookAt then
            local rows = GameCfg.Casting.Zones[session.zoneId]
            local fishId = FishCatch.Select(rows, session.rodLevel, session.baitId, math.random)
            if fishId then
                session.phase = 'hooked'
                session.fishId = fishId
                session.mult = FishCatch.Multiplier(math.random)
                self.NextReelId = (self.NextReelId or 0) + 1
                session.reelSession = tostring(self.NextReelId) .. ':' .. tostring(current.player.UserId)
                if self.ReelIn:Begin(current.player, session.reelSession, now)
                    and self.Sessions[current.player.UserId] == current and session.phase == 'hooked' then
                    self:SendState(current.player, session)
                    print('[MgrCast] 上钩', current.player.UserId, fishId, session.mult)
                end
            end
        end
    end
end

return Mgr
