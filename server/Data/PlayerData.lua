local GameCfg = require('common.GameCfg')

local PlayerData = {}
PlayerData.__index = PlayerData

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function integer(n, min, max)
    return type(n) == 'number' and n == n and n < math.huge
        and n == math.floor(n) and n >= min and n <= (max or math.maxinteger)
end

-- 扩展字段仅承载持久状态；库存、成长、任务等系统由各子单接入。
local function defaults(zone)
    return {
        inventory = { weapons = {}, magazines = {}, selection = { slot = nil, bait = nil,
            weapon = nil, held = { kind = nil, id = nil, slot = nil } } },
        growth = { upgrades = {}, purchases = {}, potions = {} },
        survival = { health = GameCfg.Vitals.MaxHealth, hunger = GameCfg.Vitals.MaxHunger,
            weakRemaining = 0, dyingRemaining = 0, deadRemaining = 0, dying = false, dead = false },
        collection = { weights = {}, unlocked = {} }, quest = { step = 1, count = 0 },
        story = { read = {} }, travel = { arrived = {}, zone = GameCfg.ResolveZoneId(zone), safePoint = {} },
        lottery = { pity = 0 }, achievements = {}, recovery = {}, cooldowns = {},
    }
end

-- 拒绝非序列化值、循环、过深和非有限数，不能把损坏扩展字段静默丢弃。
local function serializable(value, seen, depth)
    local kind = type(value)
    if kind == 'number' then return value == value and math.abs(value) < math.huge end
    if kind == 'string' then return #value <= 16384 end
    if kind == 'boolean' or kind == 'nil' then return true end
    if kind ~= 'table' or depth > 12 or seen[value] then return false end
    seen[value] = true
    local count = 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 4096 or (type(key) ~= 'string' and not integer(key, 1))
            or not serializable(child, seen, depth + 1) then return false end
    end
    seen[value] = nil
    return true
end

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
function PlayerData:Init(waitForLoad)
    if not self.Player or self.Inited then return end
    if waitForLoad then self.LoadState = 'pending' return end
    self.LoadState = 'ready'
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
        Weapons = {},
        SelectedSlot = nil,
        SelectedBait = nil,
        SelectedWeapon = nil,
        Progress = {},
        -- 当前区域（#89 摆渡写入，#92 存档用）：开局在 HomeZone（第一钓鱼区）
        Zone = GameCfg.Ferry.HomeZone,
    }
    self.Extra = defaults(self.Data.Zone)
    self.SaveMeta = { epoch = 0, revision = 0, sequence = 0, floor = 0, operations = {} }
    self.Inited = true
    self.Revision = 0
    self:Sync()
end

function PlayerData:CompleteLoad(snapshot)
    if not self.Player then return false end
    if snapshot ~= nil and not self:IsValidSave(snapshot) then
        self.LoadState = 'failed'
        return false
    end
    self:Init()
    if snapshot then self:ApplySave(snapshot) end
    self.LoadState = 'ready'
    return true
end

function PlayerData:Migrate(snapshot)
    if type(snapshot) ~= 'table' or (snapshot.v ~= 1 and snapshot.v ~= 2)
        or not serializable(snapshot, {}, 0) then return nil, '未知版本或不可序列化数据' end
    local saved = copy(snapshot)
    if not integer(saved.coin, 0) or not integer(saved.up, 0, #GameCfg.Items.UpgradePrices)
        or type(saved.zone) ~= 'string' or saved.zone == '' or type(saved.bait) ~= 'table' then
        return nil, '基础字段损坏'
    end
    local bait = {}
    for id, count in pairs(saved.bait) do
        local mapped = GameCfg.Items.LegacyIdMap[id] or id
        local def = GameCfg.Items.Definitions[mapped]
        if not def or def.Container ~= GameCfg.Items.ContainerId.Bait or not integer(count, 0) then
            return nil, '鱼饵字段损坏'
        end
        bait[mapped] = (bait[mapped] or 0) + count
    end
    saved.bait = bait
    local capacity = GameCfg.Items.InitialBackpackSlots + saved.up * GameCfg.Items.BackpackSlotsPerUpgrade
    if saved.up == #GameCfg.Items.UpgradePrices then capacity = GameCfg.Items.MaxBackpackSlots end
    for _, pair in ipairs({ { saved.bar, GameCfg.Items.InitialItemBarSlots + saved.up }, { saved.bp, capacity } }) do
        local packed, max = pair[1], pair[2]
        if type(packed) ~= 'table' then return nil, '库存缺失' end
        local seen, count = {}, 0
        for key, slot in pairs(packed) do
            count = count + 1
            if not integer(key, 1, max) or type(slot) ~= 'table' then return nil, '库存结构损坏' end
            slot.id = GameCfg.Items.LegacyIdMap[slot.id] or slot.id
            local def = GameCfg.Items.Definitions[slot.id]
            if not def or def.Container == GameCfg.Items.ContainerId.Bait
                or not integer(slot.i, 1, max) or seen[slot.i] or not integer(slot.n, 1, 1)
                or slot.m ~= nil and (type(slot.m) ~= 'number' or slot.m < 1 or slot.m > 2) then
                return nil, '物品实例损坏'
            end
            seen[slot.i] = true
        end
        for i = 1, count do if packed[i] == nil then return nil, '库存序列不连续' end end
    end
    if saved.v == 1 then
        saved.extra = defaults(saved.zone)
        saved.meta = { epoch = 0, revision = 0, sequence = 0, floor = 0, operations = {} }
    else
        local meta, extra = saved.meta, saved.extra
        if type(meta) ~= 'table' or not integer(meta.epoch, 0) or not integer(meta.revision, 0)
            or not integer(meta.sequence, 0) or not integer(meta.floor, 0, meta.sequence)
            or type(meta.operations) ~= 'table' or #meta.operations > 64 or type(extra) ~= 'table' then
            return nil, '持久身份损坏'
        end
        for name in pairs(defaults(saved.zone)) do
            if type(extra[name]) ~= 'table' then return nil, '扩展字段缺失 ' .. name end
        end
        if type(extra.inventory.selection) ~= 'table' or type(extra.travel.arrived) ~= 'table'
            or type(extra.travel.safePoint) ~= 'table' or type(extra.inventory.weapons) ~= 'table' then return nil, '扩展字段损坏' end
        local held = extra.inventory.selection.held
        if type(held) ~= 'table' or held.kind ~= nil and held.kind ~= 'slot' and held.kind ~= 'weapon'
            or held.id ~= nil and type(held.id) ~= 'string'
            or held.slot ~= nil and not integer(held.slot, 1, max) then return nil, '手持状态损坏' end
        for itemId, count in pairs(extra.inventory.weapons) do
            local def = GameCfg.Items.Definitions[itemId]
            if not def or def.Type ~= '近战武器' and def.Type ~= '远程武器'
                or not integer(count, 1) then return nil, '武器库存损坏' end
        end
        -- #130 成长字段：强化等级不超上限、购买次数为整数（键统一为行编号字符串）
        local growth = extra.growth
        if type(growth.upgrades) ~= 'table' or type(growth.purchases) ~= 'table' then
            return nil, '成长字段损坏'
        end
        for kind, level in pairs(growth.upgrades) do
            local spec = GameCfg.Shop.UpgradeKinds[kind]
            if not spec or not integer(level, 0, spec.MaxLevel) then return nil, '强化等级损坏' end
        end
        for key, count in pairs(growth.purchases) do
            if type(key) ~= 'string' or not integer(count, 0) then return nil, '购买次数损坏' end
        end
        local last = meta.floor
        for _, op in ipairs(meta.operations) do
            if type(op) ~= 'table' or not integer(op.sequence, last + 1, meta.sequence)
                or type(op.id) ~= 'string' or type(op.kind) ~= 'string' or type(op.result) ~= 'table'
                or op.requestKey ~= nil and type(op.requestKey) ~= 'string' then
                return nil, '操作日志损坏'
            end
            last = op.sequence
        end
    end
    saved.v = 2
    return saved
end

function PlayerData:IsValidSave(snapshot)
    return self:Migrate(snapshot) ~= nil
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
                local slot = copy(entry.saved or {})
                slot.i, slot.id, slot.n, slot.m = index, entry.itemId, entry.count, entry.mult
                out[#out + 1] = slot
            end
        end
        table.sort(out, function(a, b) return a.i < b.i end)
        return out
    end
    local bait = {}
    for itemId, count in pairs(self.Data.Bait) do bait[itemId] = count end
    self.Extra.inventory.selection.slot = self.Data.SelectedSlot
    self.Extra.inventory.selection.bait = self.Data.SelectedBait
    self.Extra.inventory.selection.weapon = self.Data.SelectedWeapon
    self.Extra.inventory.weapons = copy(self.Data.Weapons)
    self.Extra.travel.zone = GameCfg.ResolveZoneId(self.Data.Zone)
    return {
        v = 2,
        extra = copy(self.Extra),
        meta = copy(self.SaveMeta),
        coin = self.Data.FishCoin,
        bar = pack(GameCfg.Items.ContainerId.ItemBar),
        bp = pack(GameCfg.Items.ContainerId.Backpack),
        bait = bait,
        up = self.Data.UpgradeLevel,
        zone = self.Data.Zone,
    }
end

-- 先完整校验，再一次恢复；未知版本与坏档不会部分覆盖内存财产。
function PlayerData:ApplySave(snapshot)
    if not self.Inited then return false end
    local saved, reason = self:Migrate(snapshot)
    if not saved then
        print('[PlayerData] 拒绝存档', self.Player and self.Player.UserId, reason)
        return false
    end
    local function unpack(packed, containerId)
        local items = {}
        for _, slot in ipairs(packed) do
            items[slot.i] = { itemId = slot.id, count = slot.n, mult = slot.m,
                containerId = containerId, saved = copy(slot) }
        end
        return items
    end
    self.Data.FishCoin = saved.coin
    self.Data.UpgradeLevel, self.Data.Zone = saved.up, saved.zone
    self.Data.Bait = saved.bait
    self.Data.Containers = {
        [GameCfg.Items.ContainerId.ItemBar] = unpack(saved.bar, GameCfg.Items.ContainerId.ItemBar),
        [GameCfg.Items.ContainerId.Backpack] = unpack(saved.bp, GameCfg.Items.ContainerId.Backpack),
    }
    self.Extra, self.SaveMeta = saved.extra, saved.meta
    self.Data.SelectedSlot = self.Extra.inventory.selection.slot
    self.Data.SelectedBait = self.Extra.inventory.selection.bait
    self.Data.SelectedWeapon = self.Extra.inventory.selection.weapon
    self.Data.Weapons = copy(self.Extra.inventory.weapons)
    self:SanitizeHeld()
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
    -- 首领饵（#88）只展示道具栏件数；背包中的首领饵提示先转入，不能直接挂饵（#124）
    local bosses = {}
    for itemId in pairs(GameCfg.Casting.BossBait or {}) do bosses[#bosses + 1] = itemId end
    table.sort(bosses)
    for _, itemId in ipairs(bosses) do
        local count = self:ItemBarItemCount(itemId)
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
        weapons = copy(self.Data.Weapons),
        selectedWeapon = self.Data.SelectedWeapon,
        held = copy(self.Extra.inventory.selection.held),
    }
end

function PlayerData:SelectSlot(index)
    if not self.Inited or type(index) ~= 'number' or index ~= math.floor(index)
        or index < 1 or index > self:ItemBarCapacity() then return false end
    local entry = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][index]
    self.Data.SelectedSlot = self.Data.SelectedSlot ~= index and entry and entry.count > 0 and index or nil
    return true
end

-- 切手持与实际使用分两次：首次仅切手持（held），再次才算使用；同目标再点取消。
-- held 的权威存储是 extra.inventory.selection.held（随存档持久化）。
function PlayerData:HoldSlot(index)
    if not self.Inited or type(index) ~= 'number' or index ~= math.floor(index)
        or index < 1 or index > self:ItemBarCapacity() then return false end
    local held = self.Extra.inventory.selection.held
    if held.kind == 'slot' and held.slot == index then
        held.kind, held.id, held.slot = nil, nil, nil
        return true
    end
    local entry = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][index]
    if not entry or entry.count <= 0 then return false end
    held.kind, held.id, held.slot = 'slot', entry.itemId, index
    return true
end

-- 槽位/武器失效（丢弃、吃掉、耗尽、移动换物）时清空手持，避免悬空；读档恢复后同样校验。
function PlayerData:SanitizeHeld()
    local held = self.Extra.inventory.selection.held
    if held.kind == 'slot' then
        local entry = held.slot and self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][held.slot]
        if not entry or entry.count <= 0 or entry.itemId ~= held.id then
            held.kind, held.id, held.slot = nil, nil, nil
        end
    elseif held.kind == 'weapon' then
        if self:WeaponCount(held.id) < 1 then
            held.kind, held.id, held.slot = nil, nil, nil
        end
    elseif held.kind ~= nil then
        held.kind, held.id, held.slot = nil, nil, nil
    end
end

local function isWeapon(itemId)
    local definition = type(itemId) == 'string' and GameCfg.Items.Definitions[itemId]
    return definition ~= nil and (definition.Type == '近战武器' or definition.Type == '远程武器')
end

-- 商店强化等级（#130）：背包沿用 Data.UpgradeLevel，其余按种类存 extra.growth.upgrades；
-- 读取侧永不报错，未初始化/损坏一律按 0 级处理。
function PlayerData:ShopUpgradeLevel(kind)
    if kind == 'backpack' then
        return self.Inited and self.Data.UpgradeLevel or 0
    end
    if not self.Inited then return 0 end
    local level = self.Extra.growth.upgrades[kind]
    return integer(level, 0) and level or 0
end

-- 商店行已购次数（#130，extra.growth.purchases 以行编号字符串为键）；未初始化按 0 次。
function PlayerData:PurchaseCount(number)
    if not self.Inited or not integer(number, 1) then return 0 end
    return self.Extra.growth.purchases[tostring(number)] or 0
end

function PlayerData:NotePurchase(number)
    if not self.Inited or not integer(number, 1) then return false end
    local key = tostring(number)
    self.Extra.growth.purchases[key] = (self.Extra.growth.purchases[key] or 0) + 1
    return true
end

-- 逐级校验（#130）：必须恰好升一级；满级后返回 'max'，越级/重复返回 'level'，未知行返回 'bad'。
-- 只校验不生效；生效走 ApplyShopUpgrade，由 MgrShop 与扣款同一事务编排。
function PlayerData:CanShopUpgrade(upgrade)
    if type(upgrade) ~= 'table' or type(upgrade.kind) ~= 'string' then return false, 'bad' end
    local spec = GameCfg.Shop.UpgradeKinds[upgrade.kind]
    if not spec or not integer(upgrade.level, 1, spec.MaxLevel) then return false, 'bad' end
    local current = self:ShopUpgradeLevel(upgrade.kind)
    if current >= spec.MaxLevel then return false, 'max' end
    if upgrade.level ~= current + 1 then return false, 'level' end
    return true
end

-- 生效：调用方须先过 CanShopUpgrade；结果与扣款/计数同一次落账（MgrShop 编排）。
function PlayerData:ApplyShopUpgrade(upgrade)
    local ok = self:CanShopUpgrade(upgrade)
    if not ok then return false end
    if upgrade.kind == 'backpack' then
        self.Data.UpgradeLevel = upgrade.level
    else
        self.Extra.growth.upgrades[upgrade.kind] = upgrade.level
    end
    return true
end

-- 武器加成查询（#130，按基础线性叠加；弹容/未知种类返回基础值）
function PlayerData:WeaponDamageScale(kind)
    if not self.Inited then return 1 end
    return GameCfg.Shop.DamageScale(kind, self:ShopUpgradeLevel(kind)) or 1
end

function PlayerData:MagazineSize(base)
    if not self.Inited or type(base) ~= 'number' then return base end
    return GameCfg.Shop.MagazineSize(base, self:ShopUpgradeLevel('magazine'))
end

-- 武器独立计数，不占普通格；只收物品表里的近战/远程武器。
function PlayerData:GrantWeapon(itemId, count)
    if not self.Inited or not isWeapon(itemId)
        or not integer(count, 1) then return false end
    self:UpdateData(function(data)
        data.Weapons[itemId] = (data.Weapons[itemId] or 0) + count
    end, true)
    return true
end

function PlayerData:WeaponCount(itemId)
    return self.Inited and self.Data.Weapons[itemId] or 0
end

-- 已吃药水累计（#124，上限规则见 GameCfg.Items.PotionLimits）；属性效果由属性系统接入。
function PlayerData:PotionCount(itemId)
    return self.Inited and self.Extra.growth.potions[itemId] or 0
end

function PlayerData:ConsumeWeapon(itemId, count)
    if not self.Inited or not integer(count, 1) or self:WeaponCount(itemId) < count then return false end
    self:UpdateData(function(data)
        data.Weapons[itemId] = data.Weapons[itemId] - count
        if data.Weapons[itemId] == 0 then data.Weapons[itemId] = nil end
        if data.SelectedWeapon == itemId and data.Weapons[itemId] == nil then data.SelectedWeapon = nil end
    end, true)
    return true
end

function PlayerData:SelectWeapon(itemId)
    if not self.Inited then return false end
    if itemId == nil then
        self.Data.SelectedWeapon = nil
        self:PublishItemBar()
        return true
    end
    if not isWeapon(itemId) or self:WeaponCount(itemId) < 1 then return false end
    self.Data.SelectedWeapon = self.Data.SelectedWeapon ~= itemId and itemId or nil
    self:PublishItemBar()
    return true
end

-- 武器手持：独立库存校验，不占格；同武器再点取消。
function PlayerData:HoldWeapon(itemId)
    if not self.Inited then return false end
    local held = self.Extra.inventory.selection.held
    if held.kind == 'weapon' and held.id == itemId then
        held.kind, held.id, held.slot = nil, nil, nil
        return true
    end
    if not isWeapon(itemId) or self:WeaponCount(itemId) < 1 then return false end
    held.kind, held.id, held.slot = 'weapon', itemId, nil
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
    self:UpdateData(function(data) data.Zone = zone end, false)
    return true
end

-- 道具栏里某物品的件数；首领饵只从这里使用（#124）
function PlayerData:ItemBarItemCount(itemId)
    if not self.Inited then return 0 end
    local total = 0
    for _, entry in pairs(self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]) do
        if entry.itemId == itemId and entry.count > 0 then total = total + entry.count end
    end
    return total
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

-- 从道具栏扣 1 件某物品；首领饵只接受道具栏（#124），其他系统另有明确例外时由调用方说明。
function PlayerData:ConsumeItemBarItem(itemId)
    if not self.Inited then return false end
    local items = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    for index = 1, self:ItemBarCapacity() do
        local entry = items[index]
        if entry and entry.itemId == itemId and entry.count > 0 then
            self:UpdateData(function()
                items[index] = nil
            end, true)
            return true
        end
    end
    return false
end

-- 濒死自救例外：从道具栏（优先）或背包扣 1 件某物品；普通调用仍走 ConsumeItemBarItem。
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

-- 可挂饵判定：普通鱼饵 Bait 计数 ≥1；首领饵必须在道具栏有 1 件（#124）
function PlayerData:HasBait(itemId)
    if not self.Inited or type(itemId) ~= 'string' then return false end
    if hasBait(self.Data, itemId) then return true end
    local bossBait = GameCfg.Casting.BossBait
    return bossBait ~= nil and bossBait[itemId] ~= nil and self:ItemBarItemCount(itemId) >= 1
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
    -- 首领饵占道具栏格（#88）：抛竿一刻扣 1 只，钓出首领后消耗，脱钩 / 逃脱不返还
    local bossBait = GameCfg.Casting.BossBait
    if bossBait and bossBait[itemId] then
        if self:ConsumeItemBarItem(itemId) then return true, itemId end
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
    -- 武器走独立库存不占格（#124），满格也能购买
    if isWeapon(itemId) then return true end
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

-- 按物品表的 Container 放进对应容器（#47）：鱼饵加计数，武器进独立计数（#124），
-- 其余每件占一格；空格不够一件都不发
function PlayerData:GrantItem(itemId, count)
    if isWeapon(itemId) then return self:GrantWeapon(itemId, count) end
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

-- 双向拖拽只接受两个合法格位；交换同一实例，保留倍率和未识别的存档字段。
function PlayerData:MoveSlot(from, index, target, slot)
    if not self.Inited then return false end
    local ids = GameCfg.Items.ContainerId
    local function capacity(id)
        return id == ids.ItemBar and self:ItemBarCapacity() or id == ids.Backpack and self:BackpackCapacity()
    end
    local sourceMax, targetMax = capacity(from), capacity(target)
    if not sourceMax or not targetMax or not integer(index, 1, sourceMax)
        or not integer(slot, 1, targetMax) or from == target and index == slot then return false end
    local source, destination = self.Data.Containers[from], self.Data.Containers[target]
    if not source[index] then return false end
    self:UpdateData(function()
        source[index], destination[slot] = destination[slot], source[index]
        if source[index] then source[index].containerId = from end
        destination[slot].containerId = target
        if from == ids.ItemBar and self.Data.SelectedSlot == index
            or target == ids.ItemBar and self.Data.SelectedSlot == slot then
            self.Data.SelectedSlot = nil
        end
    end, true)
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
    self:UpdateData(function()
        items[index] = nil
    end, false)
    return true
end

function PlayerData:PublishItemBar()
    if self.OnItemBarChanged then
        self.OnItemBarChanged(self.Player, self)
    end
end

function PlayerData:UpdateData(updateCallBack, doSync)
    if not self.Inited or not updateCallBack then return end
    self.Touched = true -- 仅供调试观察；读档屏障不再用它跳过旧财产
    updateCallBack(self.Data)
    self.Revision = (self.Revision or 0) + 1
    local selected = self.Data.SelectedSlot
    local entry = selected and self.Data.Containers[GameCfg.Items.ContainerId.ItemBar][selected]
    if selected and (not entry or entry.count <= 0) then self.Data.SelectedSlot = nil end
    local baitId = self.Data.SelectedBait
    if baitId and not self:HasBait(baitId) then self.Data.SelectedBait = nil end
    self:SanitizeHeld()
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
    self.SaveMeta = nil
    self.Revision = nil
end

return PlayerData
