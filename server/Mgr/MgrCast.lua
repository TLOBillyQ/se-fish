local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local FishCatch = require('common.FishCatch')
local MgrPlayerData = require('server.Mgr.MgrPlayerData')
local REUtil = require('common.REUtil')

local Mgr = { Sessions = {} }
MathWaterJudge.Build(GameCfg.Water.Zones)

function Mgr:SendState(player, session)
    REUtil:GetRE('CastState'):FireClient(player, session and {
        phase = session.phase,
        landing = session.landing,
        zoneId = session.zoneId,
        fishId = session.fishId,
        mult = session.mult,
    } or { phase = 'idle' })
end

function Mgr:Cast(player, payload)
    local data = MgrPlayerData:GetDataInst(player)
    local character = player and player.Character
    if not data or not character or self.Sessions[player.UserId] then return end
    local selected = data.Data.SelectedSlot
    local entry = selected and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    if not entry or entry.count < 1 or entry.itemId ~= GameCfg.Items.Id.StarterRod
        or payload.slot ~= selected or payload.itemId ~= entry.itemId then return end
    local origin, rotation = character.Position, character.Rotation
    if not origin or not rotation then return end
    local forward = rotation:GetForward()
    local length = math.sqrt(forward.x * forward.x + forward.z * forward.z)
    if length < 0.01 then return end
    local x = origin.x + GameCfg.Casting.Distance * forward.x / length
    local z = origin.z + GameCfg.Casting.Distance * forward.z / length
    local zone
    for _, candidate in ipairs(GameCfg.Water.Zones) do
        if MathWaterJudge.InZone(candidate, { x = x, y = candidate.SurfaceY, z = z }) then
            zone = candidate
            break
        end
    end
    if REUtil:CheckRECD(player, 'CastAction', GameCfg.Casting.ActionCooldownSec) then return end
    local baitOk, baitId = data:ConsumeSelectedBait()
    if not baitOk then return end
    local session = {
        phase = 'cast',
        landing = { x = x, y = zone and zone.SurfaceY or origin.y, z = z },
        zoneId = zone and zone.Id or nil,
        baitId = baitId,
        rodLevel = data.Data.RodLevel,
        hookAt = zone and (self.World:GetServerTime() + GameCfg.Casting.HookDelaySec) or nil,
    }
    self.Sessions[player.UserId] = { player = player, session = session }
    self:SendState(player, session)
    print('[MgrCast] 抛竿', player.UserId, session.zoneId or 'land', baitId or 'none')
end

function Mgr:Reel(player)
    local current = self.Sessions[player.UserId]
    if not current or current.player ~= player or current.session.phase ~= 'cast' then return end
    if REUtil:CheckRECD(player, 'CastAction', GameCfg.Casting.ActionCooldownSec) then return end
    self.Sessions[player.UserId] = nil
    self:SendState(player)
    print('[MgrCast] 收竿', player.UserId)
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
            elseif payload.action == 'Reel' then self:Reel(player) end
        end),
        REUtil:GetRE('RequestCastState').OnServerEvent:Connect(function(player)
            local current = self.Sessions[player.UserId]
            self:SendState(player, current and current.player == player and current.session or nil)
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
        if session.phase == 'cast' and session.hookAt and now >= session.hookAt then
            local rows = GameCfg.Casting.Zones[session.zoneId]
            local fishId = FishCatch.Select(rows, session.rodLevel, session.baitId, math.random)
            if fishId then
                session.phase = 'hooked'
                session.fishId = fishId
                session.mult = FishCatch.Multiplier(math.random)
                self:SendState(current.player, session)
                print('[MgrCast] 上钩', current.player.UserId, fishId, session.mult)
            end
        end
    end
end

return Mgr
