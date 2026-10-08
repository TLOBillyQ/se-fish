-- 五效果的业务装配：层数、持续与到期归 modifier_system；这里只保存 DOT 相位和末次业务来源。
local ModifierAPI = require('server.ModifierAPI')
local GameCfg = require('common.GameCfg')
local Mgr = { ModifierAPI = ModifierAPI, Targets = {}, Characters = {}, Departing = {} }
local kinds = { 'poison', 'burn', 'frost', 'paralyze', 'weak' }

function Mgr:Now()
    return game:GetService('World'):GetServerTime()
end

function Mgr:Resolve(target)
    if not target then return end
    if target.UserId then return 'p:' .. tostring(target.UserId), target, target.Character end
    local players = game:GetService('Players')
    if players and players.GetPlayerFromCharacter then
        local player = players:GetPlayerFromCharacter(target)
        if player then return 'p:' .. tostring(player.UserId), player, player.Character end
    end
    local carrier = target.Carrier
    if not carrier and self.Vitals and self.Vitals.FishCarrier then
        carrier = self.Vitals.FishCarrier:ResolveCarrier(target)
    end
    if carrier then return carrier, target, carrier.Receiver or carrier.Body, carrier end
end

function Mgr:Changed(entry)
    if entry.ref.UserId and not self.Departing[entry.ref.UserId] and self.Ability then
        self.Ability:RefreshMoveSpeed(entry.ref)
    end
end

function Mgr:Drain(entry, kind, st)
    local cfg = GameCfg.Ability.StatusEffects[kind]
    if not cfg or not cfg.TickSec or st.entity:GetAttribute('IsPaused') then return end
    local finish = st.entity:GetAttribute('EndTime')
    local count = st.entity:GetAttribute('CurrCount') or 0
    local now = self:Now()
    while st.nextTickAt and st.nextTickAt <= now and st.nextTickAt <= finish do
        if entry.carrier and entry.carrier.Dead then return end
        if self.Targets[entry.key] ~= entry or entry.effects[kind] ~= st then return end
        -- 先推进相位，伤害回调重入不能重复结算本跳。
        st.nextTickAt = st.nextTickAt + cfg.TickSec
        if self.Vitals then
            local hit = self.Vitals:NewHit(st.source, 'dot')
            self.Vitals:ApplyHit(hit, entry.ref, count * cfg.DamagePerStack)
        end
    end
end

function Mgr:Apply(source, target, kind, seconds)
    local cfg = GameCfg.Ability.StatusEffects[kind]
    if kind ~= 'weak' and not cfg then return false end
    local preset = (self.Presets or GameCfg.Ability.ModifierPresets or {})[kind]
    if type(preset) ~= 'string' or preset == '' then
        print('[MgrModifier] 效果预设未绑定', kind)
        return false, 'modifier-preset-missing:' .. kind
    end
    local key, ref, owner, carrier = self:Resolve(target)
    if not key or not owner or (carrier and carrier.Dead) then return false, 'no-effect-owner' end
    local entry = self.Targets[key]
    if entry and entry.owner ~= owner then self:ClearTarget(target); entry = nil end
    if not entry then
        entry = { key = key, ref = ref, owner = owner, carrier = carrier, effects = {} }
        self.Targets[key] = entry
    end
    local old = entry.effects[kind]
    -- 先补齐旧实例到期边界，避免同帧重获继承已过期层数。
    if old and self:Now() >= old.entity:GetAttribute('EndTime') then
        self:Drain(entry, kind, old)
        self.ModifierAPI.RemoveModifier(old.entity)
        old = nil
        self.Targets[key] = entry
    end
    local duration = seconds or (cfg and cfg.DurationSec) or GameCfg.Survival.WeakSec
    local result = self.ModifierAPI.AddModifier(owner, preset, {
        duration = duration, stackable = true, maxStackCount = cfg and cfg.MaxStacks or 1,
        stackCountStep = 1, stackCountMode = cfg and cfg.MaxStacks and 2 or 0,
        stackDurationMode = 1, sameSourceStack = false,
        source = source and (source.Character or source), attrConfigs = {},
        obtainPerformanceList = {}, lostPerformanceList = {},
    })
    if result ~= self.ModifierAPI.Enums.CreateResult.Added and result ~= self.ModifierAPI.Enums.CreateResult.Reobtained then
        print('[MgrModifier] 获得效果失败', kind, tostring(result))
        if not next(entry.effects) then self.Targets[key] = nil end
        return false, tostring(result)
    end
    local entity = self.ModifierAPI.GetUnitModifiers(owner, preset)[1]
    if not entity then return false, 'modifier-instance-missing' end
    if old then old.source = source
    else
        local st = { entity = entity, source = source, connections = {},
            nextTickAt = cfg and cfg.TickSec and (self:Now() + cfg.TickSec) }
        entry.effects[kind] = st
        local function listen(name, callback)
            local event = entity:FindFirstChild(name)
            assert(event, '效果预设事件缺失:' .. name)
            st.connections[#st.connections + 1] = event:Connect(callback)
        end
        listen('DurationFinish', function() self:Drain(entry, kind, st) end)
        listen('ModifierLoss', function()
            if entry.effects[kind] ~= st then return end
            entry.effects[kind] = nil
            for _, connection in ipairs(st.connections) do connection:Disconnect() end
            if not next(entry.effects) and self.Targets[key] == entry then self.Targets[key] = nil end
            self:Changed(entry)
        end)
        listen('Pause', function() st.pausedAt = self:Now() end)
        listen('Resume', function()
            if st.nextTickAt and st.pausedAt then st.nextTickAt = st.nextTickAt + self:Now() - st.pausedAt end
            st.pausedAt = nil
        end)
    end
    self:Changed(entry)
    return true
end

function Mgr:ApplyWeaponEffect(source, target, effect)
    return self:Apply(source, target, effect and effect.Kind)
end

function Mgr:GetRemaining(target, kind)
    local key = self:Resolve(target)
    local entry = key and self.Targets[key]
    local st = entry and entry.effects[kind]
    if not st then return 0 end
    return math.max(0, self.ModifierAPI.GetRemainingTimeByKey(entry.owner, st.entity:GetAttribute('ModifierKey')))
end

function Mgr:IsControlled(target)
    return self:GetRemaining(target, 'paralyze') > 0
end

function Mgr:GetMoveMultiplier(target)
    if self:IsControlled(target) then return 0 end
    local value = self:GetRemaining(target, 'weak') > 0 and GameCfg.Survival.WeakSpeedScale or 1
    if self:GetRemaining(target, 'frost') > 0 then
        value = value * (1 - GameCfg.Ability.StatusEffects.frost.SlowPercent / 100)
    end
    return value
end

function Mgr:Clear(target, kind)
    local key = self:Resolve(target)
    local entry = key and self.Targets[key]
    local st = entry and entry.effects[kind]
    if st then self.ModifierAPI.RemoveModifier(st.entity) end
end

function Mgr:ClearTarget(target, keepWeak)
    local key = self:Resolve(target)
    local entry = key and self.Targets[key]
    if not entry then return end
    for _, kind in ipairs(kinds) do
        if not (keepWeak and kind == 'weak') then self:Clear(target, kind) end
    end
end

function Mgr:Update()
    for _, entry in pairs(self.Targets) do
        if entry.carrier and entry.carrier.Dead then self:ClearTarget(entry.ref)
        else
            for _, kind in ipairs({ 'poison', 'burn' }) do
                local st = entry.effects[kind]
                if st then self:Drain(entry, kind, st) end
            end
        end
    end
end

function Mgr:OnCharacterAdded(player)
    local left = self:GetRemaining(player, 'weak')
    self:ClearTarget(player)
    if left > 0 then self:Apply(nil, player, 'weak', left) end
end

function Mgr:OnPlayerAdded(player)
    self.Departing[player.UserId] = nil
    if self.Characters[player.UserId] then return end
    if player.CharacterAdded then
        self.Characters[player.UserId] = player.CharacterAdded:Connect(function()
            self:OnCharacterAdded(player)
        end)
    end
end

function Mgr:OnPlayerRemoving(player)
    self.Departing[player.UserId] = true
    local connection = self.Characters[player.UserId]
    if connection then connection:Disconnect(); self.Characters[player.UserId] = nil end
    self:ClearTarget(player)
    for _, entry in pairs(self.Targets) do
        for _, kind in ipairs(kinds) do
            local st = entry.effects[kind]
            if st and st.source == player then self:Clear(entry.ref, kind) end
        end
    end
end

function Mgr:Start() end
return Mgr
