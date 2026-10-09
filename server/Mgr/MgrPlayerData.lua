local PlayerData = require('server.Data.PlayerData')
local GameCfg = require('common.GameCfg')
local Mgr = {}
local DataMap = {}
local RodMounts = {}
local CharacterLinks = {}

function Mgr:GetDataInst(player)
    local data = player and DataMap[player.UserId]
    if data and data.Player == player and data.Inited and data.LoadState == 'ready' then return data end
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
    if self.Vitals and self.Vitals.RefreshHeldDamage then self.Vitals:RefreshHeldDamage(player, data) end
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
    data:Init(self.Save ~= nil)
    if self.Save then self.Save:LoadInto(player, data) end
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
        if self.Save then self.Save:SaveLeaving(player, data) end
        data:Destroy()
        if self.Save then self.Save:ReleaseSession(player.UserId, player) end
    end
end

local function validActionValue(action, value, data)
    if action == 'SelectSlot' or action == 'DiscardSlot' or action == 'EatSlot' then
        return type(value) == 'number' and value == math.floor(value)
            and value >= 1 and value <= data:ItemBarCapacity()
    end
    if action == 'MoveToItemBar' then
        return type(value) == 'number' and value == math.floor(value)
            and value >= 1 and value <= data:BackpackCapacity()
    end
    if action == 'SelectBait' and value == nil then return true end
    return type(value) == 'string' and data:HasBait(value)
end

local function eatBait(mgr, player, data, value)
    if mgr.Vitals and not mgr.Vitals:CanEat(player, value) then return end
    if data:EatBait(value) and mgr.Vitals then mgr.Vitals:Eat(player, value) end
end

-- 吃选中的鱼获（#53）：只吃选中格；先问 Vitals 能不能吃（死亡期间不能），再扣格、再恢复。
-- EatSlot 成功后 PlayerData 内部已同步并推送，无需再 SendItemBar。
-- #137：烤制倍率随格位带给 Vitals，烤过的按倍率恢复；走 CookRate 统一口径（含旧布尔档）
local function eatSlot(mgr, player, data, value)
    if not mgr.Vitals then return end
    local slot = data.Data.SelectedSlot
    local entry = value == slot and data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][slot]
    if not entry or entry.count <= 0 or not mgr.Vitals:CanEat(player, entry.itemId) then return end
    local cooked = GameCfg.Items.CookRate(entry)
    local itemId = data:EatSlot(slot)
    if itemId then mgr.Vitals:Eat(player, itemId, cooked) end
end

-- #124 统一分发：吃/药水/丢弃/攻击经同一入口。切手持与实际使用分两次——
-- 首次只切手持（held），手持匹配才算再次并执行真实行为；重复点击、空格都有明确回包。
-- 有 Save 时走持久操作协议（ResolveRequest+Execute，两步语义整体落在隔离 draft）；
-- 丢弃走 T05 地面物品接口：PrepareDrop 预留成功才扣件，CommitDrop 在持久成功回调生成；
-- 接口未接入时拒绝且不扣物；攻击实际结算归 #128，占位明确未接错误。
function Mgr:Operate(player, data, payload)
    local function finish(result, operation)
        if operation then result.operation = operation end
        _G.REUtil:GetRE('ItemBarResult'):FireClient(player, result)
    end
    local function cancelDrop(reservation, drop)
        if reservation and self.Loot and self.Loot.CancelDrop then
            pcall(function() self.Loot:CancelDrop(player, reservation, drop) end)
        end
    end
    local op = payload.op
    local weapon = payload.weapon
    if op ~= 'eat' and op ~= 'discard' and op ~= 'attack' then
        finish({ ok = false, reason = 'unknown-op' })
        return
    end
    local slot = payload.slot
    local items = data.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    local entry
    if op == 'attack' then
        -- 预检（新请求才做，重放不得被中间态拦截）：武器必须在独立库存里
        if type(weapon) ~= 'string' or data:WeaponCount(weapon) < 1 then
            finish({ ok = false, reason = 'bad-weapon' })
            return
        end
    else
        if type(slot) ~= 'number' or slot ~= math.floor(slot)
            or slot < 1 or slot > data:ItemBarCapacity() then
            finish({ ok = false, reason = 'bad-slot' })
            return
        end
        entry = items[slot]
    end
    local dropApi = op == 'discard' and self.Loot
        and type(self.Loot.PrepareDrop) == 'function' and type(self.Loot.CommitDrop) == 'function'
    local drop = op == 'discard' and entry
        and { itemId = entry.itemId, mult = entry.mult, cooked = entry.cooked, slot = slot } or nil
    -- 预检（新请求才做，重放不得被中间态拦截）：格空与禁食直接回包
    local function precheck()
        if op == 'attack' then return true end
        if not entry or entry.count <= 0 then
            finish({ ok = false, reason = 'empty' })
            return false
        end
        if op == 'eat' and self.Vitals and not self.Vitals:CanEat(player, entry.itemId) then
            finish({ ok = false, reason = 'cannot-eat' })
            return false
        end
        return true
    end
    -- 丢弃预留：held 已匹配（本次将真正丢件）才先向地面物品接口预留；
    -- 生成被拒时不扣物，首次切手持不触碰世界接口
    local heldNow = data.Extra.inventory.selection.held
    local willDrop = op == 'discard' and heldNow.kind == 'slot' and heldNow.slot == slot
    local function reserveDrop()
        if not willDrop then return true, nil end
        if not dropApi then return true, nil end
        local reservation, reason = self.Loot:PrepareDrop(player, drop)
        if not reservation then
            finish({ ok = false, op = 'discard', reason = 'drop-rejected' })
            return false, tostring(reason)
        end
        return true, reservation
    end
    -- 丢弃上屏：CommitDrop 生成失败（实例已失）时它已把物品按原属性退回库存，这里回明确的丢弃失败，
    -- 不谎报成功；幂等重入与「已取消」不算失败。
    local function commitDrop(reservation)
        if not reservation then return true end
        local committed, failure = self.Loot:CommitDrop(player, reservation, drop)
        if committed then return true end
        if tostring(failure) == 'spawn-failed' then
            print('[MgrPlayerData] 丢弃落物未上屏，物品已退回', player.UserId, tostring(drop.itemId))
            return false
        end
        return true
    end
    local function settleEffects(result)
        -- 只有「吃」结算进食；丢弃同样带 itemId，但它不带 action，按 op 判定避免丢弃也喂饱玩家
        if op == 'eat' and result.itemId and result.action ~= 'potion' and self.Vitals then
            self.Vitals:Eat(player, result.itemId, result.cooked)
        end
        -- #132 T11 / #139：吃了药水就地整体重算成长（体型 + 血量上限 + 移速；幂等：每次都从存档里的
        -- 累计数推计划），失败只打日志不影响本次操作结果——药水已经持久化了。超限被拒不会走到这里。
        local apply = self.Ability and (self.Ability.ApplyGrowth or self.Ability.ApplyBodyScale)
        if result.action == 'potion' and apply then
            local ok, applied = pcall(apply, self.Ability, player)
            if not ok or not applied.Ok then
                print('[MgrPlayerData] 成长应用失败', player.UserId, tostring(applied))
            end
        end
    end
    local function transform(target)
        local held = target.Extra.inventory.selection.held
        if op == 'attack' then
            if held.kind == 'weapon' and held.id == weapon then
                return nil, 'combat-pending' -- #128 接入战斗结算；切换语义已就位
            end
            if not target:HoldWeapon(weapon) then return nil, 'bad-weapon' end
            return { ok = true, op = 'attack', held = true }
        end
        if held.kind ~= 'slot' or held.slot ~= slot then
            -- 首次：只切手持，不消费
            if not target:HoldSlot(slot) then return nil, 'empty' end
            return { ok = true, op = op, held = true }
        end
        -- 再次：实际使用
        local heldEntry = target.Data.Containers[GameCfg.Items.ContainerId.ItemBar][slot]
        if not heldEntry or heldEntry.count <= 0 then return nil, 'empty' end
        if op == 'discard' then
            if not dropApi then return nil, 'drop-unavailable' end
            target:UpdateData(function(d)
                local it = d.Containers[GameCfg.Items.ContainerId.ItemBar][slot]
                if it.count > 1 then it.count = it.count - 1
                else d.Containers[GameCfg.Items.ContainerId.ItemBar][slot] = nil end
            end, true)
            return { ok = true, op = 'discard', held = false, itemId = heldEntry.itemId }
        end
        local definition = GameCfg.Items.Definitions[heldEntry.itemId]
        if definition and definition.Type == '属性道具' then
            -- 药水：按 PotionLimits 累计；超限拒绝且不扣格
            local limit = GameCfg.Items.PotionLimits[heldEntry.itemId]
            local count = target.Extra.growth.potions[heldEntry.itemId] or 0
            if limit and count >= limit then return nil, 'potion-capped' end
            target.Extra.growth.potions[heldEntry.itemId] = count + 1
            target:SelectSlot(slot)
            target:UpdateData(function(d)
                d.Containers[GameCfg.Items.ContainerId.ItemBar][slot] = nil
            end, true)
            return { ok = true, op = 'eat', held = false, itemId = heldEntry.itemId, action = 'potion' }
        end
        -- EatSlot 只吃选中格（#53）：分发已验槽位有效，先切选中再吃掉整格
        -- #137：烤制倍率随结果带出，结算进食时同倍率恢复；走 CookRate 统一口径（含旧布尔档）
        target:SelectSlot(slot)
        local itemId = target:EatSlot(slot)
        if not itemId then return nil, 'empty' end
        return { ok = true, op = 'eat', held = false, itemId = itemId, cooked = GameCfg.Items.CookRate(heldEntry) }
    end
    if self.Save then
        local requestId = payload.operation
        if requestId ~= nil and type(requestId) ~= 'table' then
            finish({ ok = false, reason = 'bad-operation' })
            return
        end
        if requestId == nil then requestId = payload.seq end
        local operation, mode = self.Save:ResolveRequest(player, data, 'operate:' .. op, requestId)
        if not operation then
            finish({ ok = false, reason = tostring(mode) })
            return
        end
        if mode ~= 'replay' and not precheck() then return end
        if mode == 'replay' then
            -- 同键重放：Execute 按操作日志回原结果，不再执行 transform
            self.Save:Execute(player, data, operation, function() return nil, 'expired' end,
                function(written, result)
                    if written then finish(result) else finish({ ok = false, reason = tostring(result) }) end
                end)
            return
        end
        local reserved, reservation = reserveDrop()
        if not reserved then return end
        local accepted, failure = self.Save:Execute(player, data, operation, transform,
            function(written, result)
                if not written then
                    cancelDrop(reservation, drop)
                    finish({ ok = false, reason = tostring(result) })
                    return
                end
                -- 世界副作用只在持久成功回调结算，失败无副作用
                if not commitDrop(reservation) then
                    finish({ ok = false, op = 'discard', reason = 'drop-rejected' })
                    return
                end
                settleEffects(result)
                finish(result)
            end)
        if not accepted then
            cancelDrop(reservation, drop)
            finish({ ok = false, reason = tostring(failure) })
        end
        return
    end
    if not precheck() then return end
    local reserved, reservation = reserveDrop()
    if not reserved then return end
    local result, reason = transform(data)
    if not result then
        cancelDrop(reservation, drop)
        finish({ ok = false, op = op, reason = reason })
        return
    end
    if not commitDrop(reservation) then
        finish({ ok = false, op = 'discard', reason = 'drop-rejected' })
        return
    end
    settleEffects(result)
    finish(result)
end

local function notifyEquippedBait(mgr, player, method, value)
    if method ~= 'SelectBait' or value == nil or not mgr.Quest then return end
    mgr.NextFactId = (mgr.NextFactId or 0) + 1
    mgr.Quest:Notify('EquipBait', player, { itemId = value,
        eventId = 'bait:' .. tostring(player.UserId) .. ':' .. tostring(mgr.NextFactId) })
end

function Mgr:Start()
    _G.REUtil:GetRE('RequestItemBar').OnServerEvent:Connect(function(player)
        self:SendItemBar(player)
    end)
    local actions = {
        SelectSlot = 'SelectSlot',
        SelectBait = 'SelectBait',
        EatBait = 'EatBait',
        EatSlot = 'EatSlot',
        DiscardSlot = 'DiscardSlot',
        MoveToItemBar = 'MoveToItemBar',
    }
    _G.REUtil:GetRE('ItemBarAction').OnServerEvent:Connect(function(player, payload)
        local data = self:GetDataInst(player)
        if not data or type(payload) ~= 'table' then return end
        local action = payload.action
        -- 拾取鱼获（#43）走同一动作通道，由鱼获管理器复验并发放
        if action == 'Pickup' then
            if self.Loot and not _G.REUtil:CheckRECD(player, 'ItemBarAction', GameCfg.Items.ActionCooldownSec) then
                self.Loot:Pickup(player, payload.value)
            end
            return
        end
        -- #124 双向拖拽：MoveSlot 换格/移动，服务端复验容器与槽位
        if action == 'MoveSlot' then
            local ids = GameCfg.Items.ContainerId
            local from, index, target, slot = payload.from, payload.index, payload.target, payload.slot
            local valid = (from == ids.ItemBar or from == ids.Backpack)
                and (target == ids.ItemBar or target == ids.Backpack)
                and type(index) == 'number' and index == math.floor(index) and index >= 1
                and type(slot) == 'number' and slot == math.floor(slot) and slot >= 1
            if not valid then return end
            if _G.REUtil:CheckRECD(player, 'ItemBarAction', GameCfg.Items.ActionCooldownSec) then return end
            if data:MoveSlot(from, index, target, slot) then self:SendItemBar(player) end
            return
        end
        -- #124 统一分发：吃/丢弃等操作两次语义（切手持再使用），经 ItemBarResult 回包
        if action == 'Operate' then
            if _G.REUtil:CheckRECD(player, 'ItemBarAction', GameCfg.Items.ActionCooldownSec) then return end
            self:Operate(player, data, payload)
            return
        end
        local method = type(action) == 'string' and actions[action]
        if not method then return end
        local value = payload.value
        if not validActionValue(action, value, data) then return end
        if _G.REUtil:CheckRECD(player, 'ItemBarAction', GameCfg.Items.ActionCooldownSec) then return end
        if method == 'EatBait' then
            eatBait(self, player, data, value)
            return
        end
        if method == 'EatSlot' then
            eatSlot(self, player, data, value)
            return
        end
        if data[method](data, value) then
            self:SendItemBar(player)
            notifyEquippedBait(self, player, method, value)
        end
    end)
end

_G.MgrPlayerData = Mgr
return Mgr
