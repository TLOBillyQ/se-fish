local REUtil = require('common.REUtil')
local RateLimit = require('common.RateLimit')
local ReelProgress = require('common.ReelProgress')
local GameCfg = require('common.GameCfg')

local Mgr = { Sessions = {}, Connections = {} }
Mgr.CHANNEL = 'ReelInRE'

function Mgr:Begin(player, id, now)
    local previous = self.Sessions[player.UserId]
    if previous and previous.Player == player and previous.Id == id then return true end
    if previous then self:Finish(previous, 'unhooked') end
    if self.Sessions[player.UserId] then return false end
    local current = self.Cast.Sessions[player.UserId]
    if not current or current.player ~= player or current.session.phase ~= 'hooked'
        or current.session.reelSession ~= id then return false end
    local cfg = GameCfg.HighFreqInput
    local receiver = RateLimit.NewReceiver({ WindowSec = cfg.WindowSec, MaxCount = cfg.MaxCount })
    receiver:SetSession(id)
    local session = { Player = player, Id = id, Receiver = receiver,
        Progress = ReelProgress.New(now, GameCfg.ReelIn) }
    self.Sessions[player.UserId] = session
    self:Reply(session, 'started')
    return self.Sessions[player.UserId] == session
end

function Mgr:Reply(session, action, accepted)
    self.RE:FireClient(session.Player, { action = action, session = session.Id,
        progress = session.Progress.Progress, accepted = accepted })
end

function Mgr:Finish(session, outcome, notify)
    if self.Sessions[session.Player.UserId] ~= session then return end
    self.Sessions[session.Player.UserId] = nil
    session.Receiver:EndSession()
    self.Cast:FinishReel(session.Player, session.Id, outcome, notify)
    if notify ~= false then self:Reply(session, outcome) end
end

function Mgr:Accept(player, payload)
    local session = player and self.Sessions[player.UserId]
    if not session or session.Player ~= player or type(payload) ~= 'table' then return end
    local current = self.Cast.Sessions[player.UserId]
    if not current or current.player ~= player or current.session.phase ~= 'hooked'
        or current.session.reelSession ~= session.Id then return end
    local now = self.World:GetServerTime()
    local result = session.Receiver:Accept(now, payload)
    if result.Status ~= RateLimit.Result.Ok then return end
    local outcome = session.Progress:Advance(now, result.Accepted, GameCfg.HighFreqInput.AggregateSec)
    if outcome then self:Finish(session, outcome)
    else self:Reply(session, 'progress', result.Accepted) end
end

function Mgr:Close(player, payload)
    local session = player and self.Sessions[player.UserId]
    if not session or session.Player ~= player or type(payload) ~= 'table'
        or payload.session ~= session.Id then return end
    session.Progress:Advance(self.World:GetServerTime())
    self:Finish(session, session.Progress.Result or 'unhooked')
end

function Mgr:OnPlayerAdded(player)
    local prior = self.Connections[player.UserId]
    if prior and prior.Player == player then return end
    if prior then self:OnPlayerRemoving(prior.Player) end
    local links = { Player = player }
    local function characterGone()
        local session = self.Sessions[player.UserId]
        if session and session.Player == player then self:Finish(session, 'unhooked') end
    end
    local function bind(character)
        if links.Died then links.Died:Disconnect() end
        links.Died = nil
        local controller = character and character.Controller
        if controller and controller.Died then
            links.Died = controller.Died:Connect(characterGone)
        end
    end
    if player.CharacterRemoving then links.Removing = player.CharacterRemoving:Connect(characterGone) end
    if player.CharacterAdded then links.Added = player.CharacterAdded:Connect(bind) end
    bind(player.Character)
    self.Connections[player.UserId] = links
end

function Mgr:OnPlayerRemoving(player)
    local session = self.Sessions[player.UserId]
    if session and session.Player == player then self:Finish(session, 'unhooked', false) end
    local links = self.Connections[player.UserId]
    if not links or links.Player ~= player then return end
    self.Connections[player.UserId] = nil
    for name, connection in pairs(links) do
        if name ~= 'Player' then connection:Disconnect() end
    end
end

function Mgr:Stop()
    if self.REConnection then self.REConnection:Disconnect() end
    if self.CloseConnection then self.CloseConnection:Disconnect() end
    self.REConnection = nil
    self.CloseConnection = nil
    for _, links in pairs(self.Connections) do
        for name, connection in pairs(links) do
            if name ~= 'Player' then connection:Disconnect() end
        end
    end
    self.Connections = {}
    for _, session in pairs(self.Sessions) do
        self:Finish(session, 'unhooked', false)
    end
    self.Sessions = {}
    self.World = nil
    self.RE = nil
end

function Mgr:Start()
    if self.REConnection then return end
    self.World = game:GetService('World')
    self.RE = REUtil:GetRE(self.CHANNEL)
    self.REConnection = self.RE.OnServerEvent:Connect(function(player, payload)
        self:Accept(player, payload)
    end)
    self.CloseConnection = REUtil:GetRE('CloseReelIn').OnServerEvent:Connect(function(player, payload)
        self:Close(player, payload)
    end)
    local players = game:GetService('Players')
    if players then
        for _, player in ipairs(players:GetPlayers()) do self:OnPlayerAdded(player) end
    end
end

function Mgr:Update()
    if not self.World then return end
    local now = self.World:GetServerTime()
    for _, session in pairs(self.Sessions) do
        local outcome = session.Progress:Advance(now - GameCfg.HighFreqInput.AggregateSec)
        if outcome then
            self:Finish(session, outcome)
        elseif not session.LastReport or now - session.LastReport >= GameCfg.HighFreqInput.AggregateSec then
            session.LastReport = now
            self:Reply(session, 'progress', 0)
        end
    end
end

return Mgr
