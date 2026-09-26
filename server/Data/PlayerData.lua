local GameCfg = require('common.GameCfg')

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.New(player, onItemBarChanged)
    return setmetatable({ Player = player, Inited = false, OnItemBarChanged = onItemBarChanged }, PlayerData)
end

-- 进图白送只在调试开关打开时发放（#49）；重复 Init 不会重置已有库存。
function PlayerData:Init()
    if not self.Player or self.Inited then return end
    local items = {}
    local backpack = {}
    local bait = {}
    local debug = GameCfg.Debug
    for _, grant in ipairs(debug and debug.Enabled and debug.InitialGrants or {}) do
        if grant.containerId == GameCfg.Items.ContainerId.ItemBar then
            local target = #items < GameCfg.Items.InitialItemBarSlots and items or backpack
            target[#target + 1] = {
                itemId = grant.itemId,
                count = grant.count,
                containerId = target == items and GameCfg.Items.ContainerId.ItemBar or GameCfg.Items.ContainerId.Backpack,
            }
        elseif grant.containerId == GameCfg.Items.ContainerId.Bait then
            bait[grant.itemId] = (bait[grant.itemId] or 0) + grant.count
        end
    end
    self.Data = {
        FishCoin = 0,
        Containers = { [GameCfg.Items.ContainerId.ItemBar] = items, [GameCfg.Items.ContainerId.Backpack] = backpack },
        UpgradeLevel = 0,
        Bait = bait,
        SelectedSlot = nil,
        SelectedBait = nil,
        Progress = {},
    }
    self.Inited = true
    self:Sync()
end

function PlayerData:ItemBarCapacity()
    return GameCfg.Items.InitialItemBarSlots + self.Data.UpgradeLevel
end

function PlayerData:BackpackCapacity()
    local level = self.Data.UpgradeLevel
    local capacity = GameCfg.Items.InitialBackpackSlots + level * GameCfg.Items.BackpackSlotsPerUpgrade
    if level == #GameCfg.Items.UpgradePrices then capacity = GameCfg.Items.MaxBackpackSlots end
    return capacity
end

local function copySlots(items, capacity)
    local slots = {}
    for index = 1, capacity do
        local entry = items[index]
        if entry and entry.count > 0 then
            slots[index] = { itemId = entry.itemId, count = entry.count,
                containerId = entry.containerId, mult = entry.mult }
        end
    end
    return slots
end

function PlayerData:GetItemBarSnapshot()
    if not self.Inited then return nil end
    local bait = {}
    for itemId, count in pairs(self.Data.Bait) do
        bait[itemId] = count
    end
    return {
        slots = copySlots(self.Data.Containers[GameCfg.Items.ContainerId.ItemBar], self:ItemBarCapacity()),
        slotCount = self:ItemBarCapacity(),
        backpack = copySlots(self.Data.Containers[GameCfg.Items.ContainerId.Backpack], self:BackpackCapacity()),
        backpackCount = self:BackpackCapacity(),
        upgradeLevel = self.Data.UpgradeLevel,
        bait = bait,
        coin = self.Data.FishCoin,
        selectedSlot = self.Data.SelectedSlot,
        selectedBait = self.Data.SelectedBait,
    }
end

function PlayerData:SelectSlot(index)
    if not self.Inited or type(index) ~= 'number' or index ~= math.floor(index)
        or index < 1 or index > self:ItemBarCapacity() then return false end
    local entry = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][index]
    self.Data.SelectedSlot = self.Data.SelectedSlot ~= index and entry and entry.count > 0 and index or nil
    return true
end

-- 钓鱼结束后归位：该格仍是鱼竿才选中它（不像 SelectSlot 那样切换取消）
function PlayerData:RestoreSlot(index)
    if not self.Inited or type(index) ~= 'number' then return false end
    local entry = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][index]
    if not entry or entry.count < 1 or entry.itemId ~= GameCfg.Items.Id.StarterRod then return false end
    self.Data.SelectedSlot = index
    return true
end

local function hasBait(data, itemId)
    local count = data.Bait[itemId]
    return type(count) == 'number' and count >= 1
end

function PlayerData:SelectBait(itemId)
    if not self.Inited then return false end
    if itemId == nil then
        self.Data.SelectedBait = nil
        return true
    end
    if type(itemId) ~= 'string' or not hasBait(self.Data, itemId) then return false end
    self.Data.SelectedBait = itemId
    return true
end

function PlayerData:EatBait(itemId)
    if not self.Inited or type(itemId) ~= 'string' or not hasBait(self.Data, itemId) then return false end
    self:UpdateData(function(data)
        data.Bait[itemId] = data.Bait[itemId] - 1
    end, true)
    return true
end

-- 吃掉选中的道具栏格（#53）：只吃物品表配了 EatPercent 的物品（鱼获），吃掉整格；返回被吃的物品 id
function PlayerData:EatSlot(index)
    if not self.Inited or type(index) ~= 'number' or index ~= self.Data.SelectedSlot then return nil end
    local items = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    local entry = items[index]
    local definition = entry and entry.count > 0 and GameCfg.Items.Definitions[entry.itemId]
    if not definition or type(definition.EatPercent) ~= 'number' then return nil end
    self:UpdateData(function(data)
        data.Containers[GameCfg.Items.ContainerId.ItemBar][index] = nil
    end, true)
    return entry.itemId
end

function PlayerData:ConsumeSelectedBait()
    if not self.Inited then return false, nil end
    local itemId = self.Data.SelectedBait
    if not itemId then return true, nil end
    if not hasBait(self.Data, itemId) then
        self.Data.SelectedBait = nil
        self:PublishItemBar()
        return false, nil
    end
    self:UpdateData(function(data)
        data.Bait[itemId] = data.Bait[itemId] - 1
    end, true)
    return true, itemId
end

-- 优先填道具栏，再填背包；满格时不改动库存。
function PlayerData:AddItem(itemId, mult)
    if not self.Inited or type(itemId) ~= 'string' then return false end
    for _, container in ipairs({
        { GameCfg.Items.ContainerId.ItemBar, self:ItemBarCapacity() },
        { GameCfg.Items.ContainerId.Backpack, self:BackpackCapacity() },
    }) do
        local items = self.Data.Containers[container[1]]
        for index = 1, container[2] do
            local entry = items[index]
            if not entry or entry.count <= 0 then
                self:UpdateData(function()
                    items[index] = { itemId = itemId, count = 1, containerId = container[1], mult = mult }
                end, true)
                return true
            end
        end
    end
    return false
end

-- 鱼饵进计数库存（#45）：不占道具栏格、没有满格限制；只收物品表里已有的鱼饵
function PlayerData:AddBait(itemId, count)
    local definition = type(itemId) == 'string' and GameCfg.Items.Definitions[itemId]
    if not self.Inited or not definition or definition.Container ~= GameCfg.Items.ContainerId.Bait
        or type(count) ~= 'number' or count < 1 or count ~= math.floor(count) then return false end
    self:UpdateData(function(data)
        data.Bait[itemId] = (data.Bait[itemId] or 0) + count
    end, true)
    return true
end

-- 能否整批放下（#47 / #48）：鱼饵计数没有上限，其余每件占一格；返回 true 或 false, 原因（bad / full）
function PlayerData:CanGrant(itemId, count)
    local definition = type(itemId) == 'string' and GameCfg.Items.Definitions[itemId]
    if not self.Inited or not definition or type(count) ~= 'number' or count < 1
        or count ~= math.floor(count) then return false, 'bad' end
    if definition.Container == GameCfg.Items.ContainerId.Bait then return true end
    local free = 0
    for _, container in ipairs({
        { GameCfg.Items.ContainerId.ItemBar, self:ItemBarCapacity() },
        { GameCfg.Items.ContainerId.Backpack, self:BackpackCapacity() },
    }) do
        local items = self.Data.Containers[container[1]]
        for index = 1, container[2] do
            if not items[index] or items[index].count <= 0 then free = free + 1 end
        end
    end
    if free < count then return false, 'full' end
    return true
end

-- 按物品表的 Container 放进对应容器（#47）：鱼饵加计数，其余每件占一格；空格不够一件都不发
function PlayerData:GrantItem(itemId, count)
    local ok, reason = self:CanGrant(itemId, count)
    if not ok then return false, reason end
    if GameCfg.Items.Definitions[itemId].Container == GameCfg.Items.ContainerId.Bait then
        return self:AddBait(itemId, count)
    end
    for _ = 1, count do self:AddItem(itemId) end
    return true
end

local function isPositiveInt(n)
    return type(n) == 'number' and n >= 1 and n == math.floor(n)
end

-- 金币唯一写入口（#44 / #47）：喂食、购买、GM 都经这里，余额不会为负；apply 在同一次更新里
-- 扣掉换钱的物品或发放买到的物品，与金币一起落地并同步 FishCoin。每笔按收入 / 支出打日志供对账
function PlayerData:ChangeCoin(delta, apply, reason)
    if not self.Inited then return false end
    local balance = self.Data.FishCoin + delta
    if balance < 0 then
        print('[PlayerData] 金币不足', self.Player and self.Player.UserId, reason, delta, 'FishCoin=' .. tostring(self.Data.FishCoin))
        return false
    end
    self:UpdateData(function(data)
        if apply then apply(data) end
        data.FishCoin = balance
    end, true)
    print('[PlayerData] 金币' .. (delta >= 0 and '收入' or '支出'), self.Player and self.Player.UserId, reason,
        (delta >= 0 and '+' or '') .. tostring(delta), 'FishCoin=' .. tostring(balance))
    return true
end

function PlayerData:AddCoin(amount, apply, reason)
    if not isPositiveInt(amount) then return false end
    return self:ChangeCoin(amount, apply, reason)
end

function PlayerData:SpendCoin(amount, apply, reason)
    if not isPositiveInt(amount) then return false end
    return self:ChangeCoin(-amount, apply, reason)
end

function PlayerData:MoveToItemBar(index)
    if not self.Inited or type(index) ~= 'number' or index ~= math.floor(index)
        or index < 1 or index > self:BackpackCapacity() then return false end
    local backpack = self.Data.Containers[GameCfg.Items.ContainerId.Backpack]
    local entry = backpack[index]
    if not entry then return false end
    local bar = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    for slot = 1, self:ItemBarCapacity() do
        if not bar[slot] or bar[slot].count <= 0 then
            self:UpdateData(function()
                backpack[index] = nil
                bar[slot] = entry
                entry.containerId = GameCfg.Items.ContainerId.ItemBar
            end, true)
            return true
        end
    end
    return false
end

function PlayerData:UpgradeStorage()
    local price = GameCfg.Items.UpgradePrices[self.Data.UpgradeLevel + 1]
    if not self.Inited or not price then return false, 'max' end
    if not self:SpendCoin(price, function(data)
        data.UpgradeLevel = data.UpgradeLevel + 1
    end, 'storage-upgrade') then return false, 'coin' end
    return true, price
end

function PlayerData:DiscardSlot(index)
    if not self.Inited or type(index) ~= 'number' or index ~= math.floor(index)
        or index < 1 or index > self:ItemBarCapacity() then return false end
    local items = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    if not items[index] then return false end
    items[index] = nil
    if self.Data.SelectedSlot == index then self.Data.SelectedSlot = nil end
    return true
end

function PlayerData:PublishItemBar()
    if self.OnItemBarChanged then
        self.OnItemBarChanged(self.Player, self)
    end
end

function PlayerData:UpdateData(updateCallBack, doSync)
    if not self.Inited or not updateCallBack then return end
    updateCallBack(self.Data)
    local selected = self.Data.SelectedSlot
    local entry = selected and self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    if selected and (not entry or entry.count <= 0) then self.Data.SelectedSlot = nil end
    local baitId = self.Data.SelectedBait
    if baitId and not hasBait(self.Data, baitId) then self.Data.SelectedBait = nil end
    if doSync then
        self:Sync()
        self:PublishItemBar()
    end
end

function PlayerData:Sync()
    if not self.Player or not self.Inited then return end
    self.Player:SetAttribute('FishCoin', self.Data.FishCoin)
end

function PlayerData:Destroy()
    self.Player = nil
    self.Data = nil
    self.OnItemBarChanged = nil
    self.Inited = false
end

return PlayerData
