-- 属性唯一投影接缝：存档仍归PlayerData，attr_rule持有五类运行期分量。
-- 业务键避开vendor ControllerAttrMap：分量重算不写引擎，中间值不会污染生命/移速。
local AttrAPI = require('server.AttrAPI')
local Model = require('common.AttrModel')
local BodyScale = require('common.BodyScale')
local GameCfg = require('common.GameCfg')
local Mgr = { AttrAPI = AttrAPI, States = {} }

function Mgr:State(player)
    local state = self.States[player.UserId]
    if not state then state = { player = player } self.States[player.UserId] = state end
    if state.character ~= player.Character then
        if state.unit and state.owned then state.unit:Destroy() end
        state.character, state.unit, state.baseSpeed = player.Character, nil, nil
        state.owned = false
    end
    return state
end
function Mgr:CaptureBaseSpeed(player)
    local state = self:State(player)
    if state.baseSpeed then return end
    local controller = state.character and state.character.Controller
    local speed = controller and controller.WalkSpeed
    state.baseSpeed = type(speed) == 'number' and speed > 0 and speed < math.huge and speed or GameCfg.Ability.MoveSpeed.Base
end
function Mgr:Input(player)
    self:CaptureBaseSpeed(player)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local multiplier = self.MoveMultiplierProvider and self.MoveMultiplierProvider(player) or 1
    return { bodyPotions = data and data:PotionCount(GameCfg.Ability.BodyScale.PotionItem) or 0,
        speedPotions = data and data:PotionCount(GameCfg.Ability.SpeedPotion.Item) or 0,
        baseSpeed = self:State(player).baseSpeed, moveMultiplier = multiplier }
end
function Mgr:Project(player, key, components)
    local state = self:State(player)
    if not state.character then return false, 'no-character' end
    local api = self.AttrAPI
    if not state.unit then
        local existing = api.GetAttrUnit(state.character)
        local unit, err = api.EnsureAttrUnit(state.character)
        if not unit then return false, err end
        state.unit, state.owned = unit, existing == nil
    end
    for _, name in ipairs({ 'Base', 'BaseExtra', 'Ratio', 'Bonus' }) do
        local ok, err = api.SetAttrComponent(state.character, key, api.Enums.AttrComponentType[name], components[name])
        if not ok then return false, err end
    end
    return true, api.GetAttr(state.character, key)
end
function Mgr:Plan(player)
    return Model.Plan(self:Input(player))
end
function Mgr:BodyPlan(player)
    local plan = self:Plan(player)
    local ok, scale = self:Project(player, 'PlayerBodyScale', plan.Attributes.PlayerBodyScale)
    if not ok then return nil, scale end
    plan.Body.Scale = BodyScale.Sanitize(scale)
    return plan.Body
end
function Mgr:MaxHealth(player)
    local plan = self:Plan(player)
    local ok, value = self:Project(player, 'PlayerMaxHealth', plan.Attributes.PlayerMaxHealth)
    if not ok then error('[MgrAttr] 血量上限投影失败: ' .. tostring(value)) end
    return math.max(1, math.min(GameCfg.Ability.BodyScale.HealthMax, value))
end
function Mgr:RefreshMoveSpeed(player)
    local plan = self:Plan(player)
    local ok, speed = self:Project(player, 'PlayerWalkSpeed', plan.Attributes.PlayerWalkSpeed)
    if not ok then return false, speed end
    local controller = player.Character and player.Character.Controller
    if not controller then return false, 'no-controller' end
    local written, err = pcall(function() controller.WalkSpeed = math.max(0, speed) end)
    if not written then print('[MgrAttr] 移速写入失败', player.UserId, tostring(err)) return false, tostring(err) end
    return true
end
function Mgr:ApplyBodyScale(player)
    local plan, err = self:BodyPlan(player)
    if not plan then return { Ok = false, Error = err } end
    local derived = BodyScale.Derive(plan.Scale)
    local ok, writeErr = pcall(function()
        player.Character:SetScale(Vector3.New(plan.Scale, plan.Scale, plan.Scale))
        player.Character:SetAttribute('CameraDistance', derived.CameraDistance)
        player.Character:SetAttribute('InteractRange', derived.InteractRange)
        player.Character:SetAttribute('BodyScaleCapped', plan.Capped)
    end)
    if not ok then print('[MgrAttr] 体型写入失败', player.UserId, tostring(writeErr)) end
    return { Ok = ok, Error = not ok and tostring(writeErr) or nil, Scale = plan.Scale,
        Health = self:MaxHealth(player), Capped = plan.Capped, Derived = derived }
end
function Mgr:ApplyGrowth(player)
    local applied = self:ApplyBodyScale(player)
    local errors = {}
    if not applied.Ok then errors[#errors + 1] = tostring(applied.Error) end
    if self.Vitals and self.Vitals:GetState(player) then
        local ok, err = self.Vitals:RefreshMaxHealth(player)
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    local ok, err = self:RefreshMoveSpeed(player)
    if not ok then errors[#errors + 1] = tostring(err) end
    applied.Ok = #errors == 0
    if not applied.Ok then applied.Error = table.concat(errors, '; ') end
    return applied
end
function Mgr:ProjectHunger(player, value)
    local input = { hunger = value }
    local ok, result = self:Project(player, 'PlayerHunger', Model.Plan(input).Attributes.PlayerHunger)
    if not ok then return false, result end
    return true, math.max(0, math.min(GameCfg.Vitals.MaxHunger, math.floor(result)))
end
function Mgr:WeaponDamageScale(player, kind)
    if kind ~= 'melee' and kind ~= 'ranged' and kind ~= 'explosive' then return 1 end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local scale = GameCfg.Shop.DamageScale(kind, data and data:ShopUpgradeLevel(kind) or 0) or 1
    local ok, result = self:Project(player, 'PlayerWeaponDamage_' .. kind, { Base = 1, BaseExtra = 0, Ratio = scale - 1, Bonus = 0 })
    if not ok then error('[MgrAttr] 武器属性投影失败: ' .. tostring(result)) end
    return result
end
function Mgr:OnPlayerAdded(player)
    local ok, err = pcall(self.ApplyGrowth, self, player)
    if not ok or not err.Ok then
        print('[MgrAttr] 初始化待重试', player.UserId, tostring(ok and err.Error or err))
        self:State(player).pending = true
    end
end
function Mgr:OnPlayerRemoving(player)
    local state = self.States[player.UserId]
    if not state then return end
    if state.unit and state.owned then state.unit:Destroy() end
    self.States[player.UserId] = nil
end
function Mgr:Update()
    for _, state in pairs(self.States) do
        if state.pending then
            local ok, result = pcall(self.ApplyGrowth, self, state.player)
            if ok and result.Ok then state.pending = nil end
        end
    end
end
function Mgr:Start() end
return Mgr
