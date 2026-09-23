local PlayerData = require('server.Data.PlayerData')
local GameCfg = require('common.GameCfg')
local Mgr = {}
local DataMap = {}
local RodMounts = {}
local CharacterLinks = {}

function Mgr:GetDataInst(player)
    local data = player and DataMap[player.UserId]
    if data and data.Player == player and data.Inited then return data end
end

function Mgr:ClearHeldRod(player, character)
    local held = RodMounts[player.UserId]
    if not held or (character and held.Character ~= character) then return end
    RodMounts[player.UserId] = nil
    if held.Model then pcall(function() held.Model:Destroy() end) end
    if held.Mount then pcall(function() held.Mount:Destroy() end) end
end

function Mgr:RefreshHeldRod(player, character)
    local data = self:GetDataInst(player)
    if not data then return end
    character = character or player.Character
    local selected = data.Data.SelectedSlot
    local entry = selected and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    local shouldHold = character and entry and entry.count > 0
        and entry.itemId == GameCfg.Items.Id.StarterRod
    if not shouldHold then
        self:ClearHeldRod(player)
        return
    end
    local held = RodMounts[player.UserId]
    if held and held.Character == character then return end
    self:ClearHeldRod(player)
    local cfg = GameCfg.Items.RodVisual
    local world = game:GetService('World')
    local okMount, mount = pcall(world.CreateUnit, world, 'SkeletalSocketMount', {
        Name = 'HeldRodMount_' .. tostring(player.UserId),
        Parent = character,
        SocketName = cfg.Socket,
    })
    if not okMount or not mount then
        print('[MgrPlayerData] 左手挂点创建失败', player.UserId, mount)
        return
    end
    local okModel, model = pcall(world.CreateUnit, world, 'WorldUnit', {
        Name = 'HeldRod_' .. tostring(player.UserId),
        Parent = mount,
        RenderMeshId = cfg.Mesh,
        Scale = Vector3.New(cfg.Scale.x, cfg.Scale.y, cfg.Scale.z),
        PhysicsActive = false,
        CanCollide = false,
        CanTouch = false,
        CanTrigger = false,
        CanQuery = false,
        ModelVisible = true,
    })
    if not okModel or not model then
        pcall(function() mount:Destroy() end)
        print('[MgrPlayerData] 左手鱼竿模型创建失败', player.UserId, model)
        return
    end
    RodMounts[player.UserId] = { Character = character, Mount = mount, Model = model }
end

function Mgr:SendItemBar(player)
    local data = self:GetDataInst(player)
    if not data then return end
    self:RefreshHeldRod(player)
    _G.REUtil:GetRE('ItemBarState'):FireClient(player, data:GetItemBarSnapshot())
end

function Mgr:OnPlayerAdded(player)
    local current = DataMap[player.UserId]
    if current and current.Player == player then return end
    if current then self:OnPlayerRemoving(current.Player) end
    local data = PlayerData.New(player, function(owner, source)
        if self:GetDataInst(owner) == source then self:SendItemBar(owner) end
    end)
    DataMap[player.UserId] = data
    data:Init()
    CharacterLinks[player.UserId] = {
        Added = player.CharacterAdded:Connect(function(character)
            if self:GetDataInst(player) then self:RefreshHeldRod(player, character) end
        end),
        Removing = player.CharacterRemoving:Connect(function(character)
            if self:GetDataInst(player) then self:ClearHeldRod(player, character) end
        end),
    }
    self:SendItemBar(player)
end

function Mgr:OnPlayerRemoving(player)
    local data = DataMap[player.UserId]
    if data and data.Player == player then
        local links = CharacterLinks[player.UserId]
        CharacterLinks[player.UserId] = nil
        if links then
            links.Added:Disconnect()
            links.Removing:Disconnect()
        end
        self:ClearHeldRod(player)
        DataMap[player.UserId] = nil
        data:Destroy()
    end
end

function Mgr:Start()
    _G.REUtil:GetRE('RequestItemBar').OnServerEvent:Connect(function(player)
        self:SendItemBar(player)
    end)
    local actions = {
        SelectSlot = 'SelectSlot',
        SelectBait = 'SelectBait',
        EatBait = 'EatBait',
        DiscardSlot = 'DiscardSlot',
    }
    _G.REUtil:GetRE('ItemBarAction').OnServerEvent:Connect(function(player, payload)
        local data = self:GetDataInst(player)
        if not data or type(payload) ~= 'table' then return end
        local action = payload.action
        local method = type(action) == 'string' and actions[action]
        if not method then return end
        local value = payload.value
        if action == 'SelectSlot' or action == 'DiscardSlot' then
            if type(value) ~= 'number' or value ~= math.floor(value)
                or value < 1 or value > GameCfg.Items.ItemBarSlots then return end
        elseif action == 'SelectBait' then
            if value ~= nil and (type(value) ~= 'string' or data.Data.Bait[value] == nil) then return end
        elseif type(value) ~= 'string' or data.Data.Bait[value] == nil then
            return
        end
        if _G.REUtil:CheckRECD(player, 'ItemBarAction', GameCfg.Items.ActionCooldownSec) then return end
        if data[method](data, value) and method ~= 'EatBait' then
            self:SendItemBar(player)
        end
    end)
end

_G.MgrPlayerData = Mgr
return Mgr
