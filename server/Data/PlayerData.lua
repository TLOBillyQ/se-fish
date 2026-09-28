local GameCfg = require('common.GameCfg')

local PlayerData = {}
PlayerData.__index = PlayerData

local function hasIndividualMult(itemId)
    if GameCfg.Fish[itemId] then return true end
    for _, fish in pairs(GameCfg.Fish) do
        for _, drop in ipairs(fish.Drops or {}) do
            if drop.ItemId == itemId then return true end
        end
    end
    return false
end

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
        -- 当前区域（#89 摆渡写入，#92 存档用）：开局在 HomeZone（第一钓鱼区）
        Zone = GameCfg.Ferry.HomeZone,
    }
    self.Inited = true
    self.Revision = 0
    self:Sync()
end

function PlayerData:IsValidSave(snapshot)
    local function int(n, min, max)
        return type(n) == 'number' and n == math.floor(n) and n >= min and n <= max
    end
    if type(snapshot) ~= 'table' or snapshot.v ~= 1
        or not int(snapshot.coin, 0, math.maxinteger)
        or not int(snapshot.up, 0, #GameCfg.Items.UpgradePrices)
        or type(snapshot.zone) ~= 'string' or snapshot.zone == ''
        or type(snapshot.bait) ~= 'table' then return false end
    for id, count in pairs(snapshot.bait) do
        local def = GameCfg.Items.Definitions[id]
        if not def or def.Container ~= GameCfg.Items.ContainerId.Bait
            or not int(count, 1, math.maxinteger) then return false end
    end
    local capacity = GameCfg.Items.InitialBackpackSlots + snapshot.up * GameCfg.Items.BackpackSlotsPerUpgrade
    if snapshot.up == #GameCfg.Items.UpgradePrices then capacity = GameCfg.Items.MaxBackpackSlots end
    for _, pair in ipairs({ { snapshot.bar, GameCfg.Items.InitialItemBarSlots + snapshot.up },
        { snapshot.bp, capacity } }) do
        local packed, max = pair[1], pair[2]
        if type(packed) ~= 'table' then return false end
        local seen, count = {}, 0
        for key, slot in pairs(packed) do
            count = count + 1
            local def = type(slot) == 'table' and GameCfg.Items.Definitions[slot.id]
            if not int(key, 1, max) or not def or def.Container == GameCfg.Items.ContainerId.Bait
                or not int(slot.i, 1, max) or seen[slot.i] or not int(slot.n, 1, 1)
                or slot.m ~= nil and (type(slot.m) ~= 'number' or slot.m < 1 or slot.m > 2) then
                return false
            end
            seen[slot.i] = true
        end
        for index = 1, count do
            if packed[index] == nil then return false end
        end
    end
    return true
end

-- 存档序列化（#92）：最小集——金币、道具栏/背包物品（含格子位置与个体倍率）、鱼饵计数、
-- 升级等级、当前区域；v 版本号预留扩展（图鉴/强化/药水随各自系统进存档）。
-- 键名缩写为体积考量：bar/bp=道具栏/背包格位表（i=格号 id=物品 n=件数 m=倍率）、up=升级等级。
function PlayerData:Serialize()
    if not self.Inited then return nil end
    local function pack(containerId)
        local out = {}
        for index, entry in pairs(self.Data.Containers[containerId]) do
            if entry and entry.count > 0 then
                out[#out + 1] = { i = index, id = entry.itemId, n = entry.count, m = entry.mult }
            end
        end
        table.sort(out, function(a, b) return a.i < b.i end)
        return out
    end
    local bait = {}
    for itemId, count in pairs(self.Data.Bait) do bait[itemId] = count end
    return {
        v = 1,
        coin = self.Data.FishCoin,
        bar = pack(GameCfg.Items.ContainerId.ItemBar),
        bp = pack(GameCfg.Items.ContainerId.Backpack),
        bait = bait,
        up = self.Data.UpgradeLevel,
        zone = self.Data.Zone,
    }
end

-- 读档灌入（#92）：逐项校验——未知物品/坏计数/越界格位丢弃并记日志，金币负数钳 0、
-- 升级等级钳到升满，区域只收非空字符串；任一字段脏不影响其余字段恢复。
function PlayerData:ApplySave(snapshot)
    if not self.Inited or type(snapshot) ~= 'table' then return false end
    local function positiveInt(n)
        return type(n) == 'number' and n >= 1 and n == math.floor(n)
    end
    local defs = GameCfg.Items.Definitions
    local userId = self.Player and self.Player.UserId
    if snapshot.v ~= 1 then
        print('[PlayerData] 存档版本未知，按 v1 尽力恢复', userId, tostring(snapshot.v))
    end
    local coin = snapshot.coin
    if type(coin) == 'number' then
        self.Data.FishCoin = math.max(0, math.floor(coin))
    end
    local up = snapshot.up
    if type(up) == 'number' and up == math.floor(up) then
        self.Data.UpgradeLevel = math.min(math.max(0, up), #GameCfg.Items.UpgradePrices)
    end
    if type(snapshot.zone) == 'string' and snapshot.zone ~= '' then
        self.Data.Zone = snapshot.zone
    end
    local bait = {}
    if type(snapshot.bait) == 'table' then
        for itemId, count in pairs(snapshot.bait) do
            local def = defs[itemId]
            if def and def.Container == GameCfg.Items.ContainerId.Bait and positiveInt(count) then
                bait[itemId] = count
            else
                print('[PlayerData] 存档鱼饵无效，丢弃', userId, itemId, count)
            end
        end
    end
    self.Data.Bait = bait
    local function unpack(packed, containerId, capacity)
        local items = {}
        if type(packed) ~= 'table' then return items end
        for _, slot in ipairs(packed) do
            local index = type(slot) == 'table' and slot.i or nil
            local itemId = type(slot) == 'table' and slot.id or nil
            local count = type(slot) == 'table' and slot.n or nil
            if type(index) == 'number' and index == math.floor(index) and index >= 1 and index <= capacity
                and defs[itemId] and positiveInt(count) then
                items[index] = { itemId = itemId, count = count, containerId = containerId,
                    mult = type(slot.m) == 'number' and slot.m or nil }
            else
                print('[PlayerData] 存档格位无效，丢弃', userId, tostring(index), tostring(itemId))
            end
        end
        return items
    end
    self.Data.Containers[GameCfg.Items.ContainerId.ItemBar] =
        unpack(snapshot.bar, GameCfg.Items.ContainerId.ItemBar, self:ItemBarCapacity())
    self.Data.Containers[GameCfg.Items.ContainerId.Backpack] =
        unpack(snapshot.bp, GameCfg.Items.ContainerId.Backpack, self:BackpackCapacity())
    self.Data.SelectedSlot = nil
    self.Data.SelectedBait = nil
    self.Revision = (self.Revision or 0) + 1
    self:Sync()
    return true
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

-- GM 局部补丁先在副本上校验最终容量，再一次替换权威状态。
function PlayerData:ApplyGMPatch(patch)
    if not self.Inited or type(patch) ~= 'table' then return false, '状态尚未就绪' end
    local function int(n, min, max)
        return type(n) == 'number' and n == math.floor(n) and n >= min and n <= max
    end
    local coin = patch.coin == nil and self.Data.FishCoin or patch.coin
    local level = patch.upgradeLevel == nil and self.Data.UpgradeLevel or patch.upgradeLevel
    if not int(coin, 0, math.maxinteger) or not int(level, 0, #GameCfg.Items.UpgradePrices) then
        return false, '金币或扩容等级无效'
    end
    if patch.slots ~= nil and type(patch.slots) ~= 'table' then return false, '格位操作无效' end
    local ids = GameCfg.Items.ContainerId
    local containers = {}
    for _, id in ipairs({ ids.ItemBar, ids.Backpack }) do
        local copy = {}
        for index, entry in pairs(self.Data.Containers[id]) do copy[index] = entry end
        containers[id] = copy
    end
    local barCount = GameCfg.Items.InitialItemBarSlots + level
    local backpackCount = GameCfg.Items.InitialBackpackSlots + level * GameCfg.Items.BackpackSlotsPerUpgrade
    if level == #GameCfg.Items.UpgradePrices then backpackCount = GameCfg.Items.MaxBackpackSlots end
    local seen = {}
    for key, edit in pairs(patch.slots or {}) do
        if type(key) ~= 'number' or not int(key, 1, 100) or type(edit) ~= 'table' then
            return false, '格位操作无效'
        end
        local id = edit.container
        local max = id == ids.ItemBar and barCount or id == ids.Backpack and backpackCount
        local oldMax = id == ids.ItemBar and self:ItemBarCapacity()
            or id == ids.Backpack and self:BackpackCapacity()
        if not max or not int(edit.index, 1, edit.clear == true and math.max(max, oldMax) or max) then
            return false, '格号无效'
        end
        local unique = id .. ':' .. edit.index
        if seen[unique] then return false, '格号重复' end
        seen[unique] = true
        if edit.clear == true and edit.itemId == nil and edit.count == nil and edit.mult == nil then
            containers[id][edit.index] = nil
        else
            local definition = type(edit.itemId) == 'string' and GameCfg.Items.Definitions[edit.itemId]
            if edit.clear ~= nil or not definition or definition.Container == ids.Bait
                or not int(edit.count, 1, 1) then return false, '格位物品或件数无效' end
            local mult = edit.mult
            if mult ~= nil and (type(mult) ~= 'number' or mult < 1 or mult > 2
                or math.abs(mult * 100 - math.floor(mult * 100 + 0.5)) > 1e-7
                or not hasIndividualMult(edit.itemId)) then return false, '个体倍率无效' end
            containers[id][edit.index] = { itemId = edit.itemId, count = 1, containerId = id, mult = mult }
        end
    end
    for _, pair in ipairs({ { ids.ItemBar, barCount }, { ids.Backpack, backpackCount } }) do
        for index, entry in pairs(containers[pair[1]]) do
            if entry and (type(index) ~= 'number' or index > pair[2]) then
                return false, '缩容将挤掉已有物品'
            end
        end
    end
    self:ChangeCoin(coin - self.Data.FishCoin, function(data)
        data.UpgradeLevel = level
        data.Containers = containers
    end, 'gm-state')
    return true
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
    -- 首领饵（#88）以件数挂进 bait 表，客户端挂饵按钮据此显示数量与可选态；没有就不列
    for itemId in pairs(GameCfg.Casting.BossBait or {}) do
        local count = self:ItemCount(itemId)
        if count >= 1 then bait[itemId] = count end
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

-- 写入当前区域（#89 摆渡，#92 存档读取）；只接受非空字符串
function PlayerData:SetZone(zone)
    if not self.Inited or type(zone) ~= 'string' or zone == '' then return false end
    self.Touched = true
    self.Data.Zone = zone
    return true
end

-- 道具栏 + 背包里某物品的总件数（每格一件，不堆叠）
function PlayerData:ItemCount(itemId)
    if not self.Inited then return 0 end
    local total = 0
    for _, container in pairs(self.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId and entry.count > 0 then total = total + entry.count end
        end
    end
    return total
end

-- 从道具栏（优先）或背包扣 1 件某物品；用于首领饵这类占格鱼饵（#88）
function PlayerData:ConsumeItem(itemId)
    if not self.Inited then return false end
    for _, container in ipairs({
        { GameCfg.Items.ContainerId.ItemBar, self:ItemBarCapacity() },
        { GameCfg.Items.ContainerId.Backpack, self:BackpackCapacity() },
    }) do
        local items = self.Data.Containers[container[1]]
        for index = 1, container[2] do
            local entry = items[index]
            if entry and entry.itemId == itemId and entry.count > 0 then
                self:UpdateData(function()
                    items[index] = nil
                end, true)
                return true
            end
        end
    end
    return false
end

-- 可挂饵判定：Bait 计数 ≥1，或是首领饵（占格）且库存 ≥1（#88）
function PlayerData:HasBait(itemId)
    if not self.Inited or type(itemId) ~= 'string' then return false end
    if hasBait(self.Data, itemId) then return true end
    local bossBait = GameCfg.Casting.BossBait
    return bossBait ~= nil and bossBait[itemId] ~= nil and self:ItemCount(itemId) >= 1
end

function PlayerData:SelectBait(itemId)
    if not self.Inited then return false end
    if itemId == nil then
        self.Data.SelectedBait = nil
        return true
    end
    if type(itemId) ~= 'string' or not self:HasBait(itemId) then return false end
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
    -- 首领饵占道具栏/背包格（#88）：抛竿一刻扣 1 只，钓出首领后消耗，脱钩 / 逃脱不返还
    local bossBait = GameCfg.Casting.BossBait
    if bossBait and bossBait[itemId] then
        if self:ConsumeItem(itemId) then return true, itemId end
        self.Data.SelectedBait = nil
        self:PublishItemBar()
        return false, nil
    end
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

-- 信物兑换（#87，GameSpec §8.1）：把道具栏 slot 格的信物换成 product x1。空格不够（被换的这格不算空格，
-- 与「背包与道具栏全满时拒绝」一致）就拒绝、不消耗；扣除与发放一次落地，发放失败回滚被扣的格。
function PlayerData:ExchangeSlot(slot, product)
    local items = self.Inited and self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    local kept = type(slot) == 'number' and items and items[slot]
    if not kept or kept.count <= 0 or type(product) ~= 'string' then return false, 'bad' end
    if not self:CanGrant(product, 1) then return false, 'full' end
    self:UpdateData(function(d)
        d.Containers[GameCfg.Items.ContainerId.ItemBar][slot] = nil
    end, false)
    if not self:AddItem(product) then
        self:UpdateData(function(d)
            d.Containers[GameCfg.Items.ContainerId.ItemBar][slot] = kept
        end, true)
        print('[PlayerData] 兑换发放失败，已退回原物品', self.Player and self.Player.UserId, kept.itemId, product)
        return false, 'full'
    end
    return true
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
    self.Touched = true
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
    self.Touched = true -- 进图后已有操作（#92 读档竞态会话锁：MgrSave 据此跳过旧档覆盖）
    updateCallBack(self.Data)
    self.Revision = (self.Revision or 0) + 1
    local selected = self.Data.SelectedSlot
    local entry = selected and self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    if selected and (not entry or entry.count <= 0) then self.Data.SelectedSlot = nil end
    local baitId = self.Data.SelectedBait
    if baitId and not self:HasBait(baitId) then self.Data.SelectedBait = nil end
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
