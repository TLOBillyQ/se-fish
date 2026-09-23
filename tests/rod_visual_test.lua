local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local Mgr = require('server.Mgr.MgrPlayerData')

TestRodVisual = {}

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            callbacks[#callbacks + 1] = fn
            return { Disconnect = function() for i, cb in ipairs(callbacks) do
                if cb == fn then callbacks[i] = nil end
            end end }
        end,
        Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
    }
end

function TestRodVisual:setUp()
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.savedGrantDebug = require('common.GameCfg').Debug
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
    self.oldGame, self.oldVector3, self.oldREUtil = _G.game, _G.Vector3, _G.REUtil
    self.failKind = nil
    self.created = {}
    local world = { CreateUnit = function(_, kind, props)
        if self.failKind == kind then return nil end
        local unit = { Kind = kind, Destroyed = false }
        for key, value in pairs(props) do unit[key] = value end
        function unit:Destroy() self.Destroyed = true end
        self.created[#self.created + 1] = unit
        return unit
    end }
    _G.game = { GetService = function(_, name) if name == 'World' then return world end end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    self.events = {}
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = {
                OnServerEvent = signal(),
                FireClient = function(_, player, state) player.lastState = state end,
            }
        end
        return self.events[name]
    end }
    self.player = { UserId = 34001, Character = { Name = 'Eggy' },
        CharacterAdded = signal(), CharacterRemoving = signal() }
    function self.player:SetAttribute() end
    Mgr:Start()
    Mgr:OnPlayerAdded(self.player)
end

function TestRodVisual:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
    Mgr:OnPlayerRemoving(self.player)
    _G.game, _G.Vector3, _G.REUtil = self.oldGame, self.oldVector3, self.oldREUtil
end

function TestRodVisual:select(index)
    self.events.ItemBarAction.OnServerEvent:Fire(self.player, { action = 'SelectSlot', value = index })
end

function TestRodVisual:test_selection_spawns_server_mount_and_idempotent_refresh()
    self:select(1)
    lu.assertEquals(#self.created, 2)
    local mount, model = self.created[1], self.created[2]
    lu.assertEquals(mount.Kind, 'SkeletalSocketMount')
    lu.assertIs(mount.Parent, self.player.Character)
    lu.assertEquals(mount.SocketName, 'l_weapon')
    lu.assertEquals(model.Kind, 'WorldUnit')
    lu.assertIs(model.Parent, mount)
    lu.assertEquals(model.RenderMeshId, 'official://mesh/50450')
    lu.assertEquals(model.Scale, { x = 0.2, y = 0.25, z = 0.2 })
    lu.assertFalse(model.PhysicsActive)
    lu.assertFalse(model.CanCollide)
    Mgr:SendItemBar(self.player)
    lu.assertEquals(#self.created, 2)
    self:select(1)
    lu.assertTrue(mount.Destroyed)
    lu.assertTrue(model.Destroyed)
end

function TestRodVisual:test_empty_slot_discard_and_external_depletion_cleanup()
    self:select(1)
    local mount, model = self.created[1], self.created[2]
    self:select(8)
    lu.assertTrue(mount.Destroyed)
    lu.assertTrue(model.Destroyed)
    self:select(1)
    self.events.ItemBarAction.OnServerEvent:Fire(self.player, { action = 'DiscardSlot', value = 1 })
    lu.assertTrue(self.created[3].Destroyed)
    lu.assertTrue(self.created[4].Destroyed)
    lu.assertNil(self.player.lastState.selectedSlot)
end

function TestRodVisual:test_external_depletion_and_respawn_cleanup()
    self:select(1)
    local firstMount = self.created[1]
    local oldCharacter = self.player.Character
    self.player.CharacterRemoving:Fire(oldCharacter)
    lu.assertTrue(firstMount.Destroyed)
    self.player.Character = { Name = 'Respawn' }
    self.player.CharacterAdded:Fire(self.player.Character)
    lu.assertEquals(#self.created, 4)
    lu.assertIs(self.created[3].Parent, self.player.Character)
    Mgr:GetDataInst(self.player):UpdateData(function(data)
        data.Containers[GameCfg.Items.ContainerId.ItemBar][1].count = 0
    end, true)
    lu.assertTrue(self.created[3].Destroyed)
    lu.assertTrue(self.created[4].Destroyed)
    lu.assertNil(self.player.lastState.selectedSlot)
end

function TestRodVisual:test_disconnect_and_partial_spawn_failure_cleanup()
    self:select(1)
    local mount, model = self.created[1], self.created[2]
    Mgr:OnPlayerRemoving(self.player)
    lu.assertTrue(mount.Destroyed)
    lu.assertTrue(model.Destroyed)
    self.player.CharacterAdded:Fire({ Name = 'late' })
    lu.assertEquals(#self.created, 2)
    Mgr:OnPlayerAdded(self.player)
    self.failKind = 'WorldUnit'
    self:select(1)
    lu.assertTrue(self.created[3].Destroyed)
    lu.assertEquals(#self.created, 3)
    self.failKind = nil
    Mgr:SendItemBar(self.player)
    lu.assertEquals(#self.created, 5)
    lu.assertFalse(self.created[4].Destroyed)
    lu.assertFalse(self.created[5].Destroyed)
end

function TestRodVisual:test_players_hold_independent_rods()
    local other = { UserId = 34002, Character = { Name = 'Other' },
        CharacterAdded = signal(), CharacterRemoving = signal() }
    function other:SetAttribute() end
    Mgr:OnPlayerAdded(other)
    self:select(1)
    self.events.ItemBarAction.OnServerEvent:Fire(other, { action = 'SelectSlot', value = 1 })
    lu.assertEquals(#self.created, 4)
    lu.assertIs(self.created[1].Parent, self.player.Character)
    lu.assertIs(self.created[3].Parent, other.Character)
    self:select(1)
    lu.assertTrue(self.created[1].Destroyed)
    lu.assertFalse(self.created[3].Destroyed)
    Mgr:OnPlayerRemoving(other)
    lu.assertTrue(self.created[3].Destroyed)
end

function TestRodVisual:test_selected_before_character_spawns_on_character_added()
    self.player.Character = nil
    self:select(1)
    lu.assertEquals(#self.created, 0)
    lu.assertEquals(self.player.lastState.selectedSlot, 1)
    self.player.Character = { Name = 'Late' }
    self.player.CharacterAdded:Fire(self.player.Character)
    lu.assertEquals(#self.created, 2)
    lu.assertIs(self.created[1].Parent, self.player.Character)
end
