-- GM 发放（#47，#28 规格）：服务端单点裁决，只在 GameCfg.Debug.Enabled 打开时接受请求。
-- 客户端发 GMAction{action, target, ...}；target 缺省是发起者自己，给数字 UserId 则发给在线的那名玩家，
-- 查不到就失败、不落到别人身上。加 / 扣币走 PlayerData:AddCoin / SpendCoin 这一唯一入口（扣不成负数），
-- 发物品走 PlayerData:GrantItem 按物品表的 Container 路由（鱼竿进道具栏、蚯蚓进鱼饵库存）。
-- 设血量 / 饥饿度（#53）走 MgrVitals:SetHealth / SetHunger。
local GameCfg = require('common.GameCfg')

local Mgr = { AttackBonuses = {} }

local AttackStep = 25
local BaseAttack = GameCfg.Ability.InitialAbilities[2].AnchorAttributes.ABILITY_ANOSTATE_BULLET_DAMAGE

function Mgr:GetMeleeDamage(player, base)
    return base + (player and self.AttackBonuses[player.UserId] or 0)
end

function Mgr:AddAttack(_, _, target)
    local previous = self.AttackBonuses[target.UserId] or 0
    if previous > math.maxinteger - AttackStep - BaseAttack then return false, '伤害数值已达到可表示范围' end
    self.AttackBonuses[target.UserId] = previous + AttackStep
    return true
end

function Mgr:OnPlayerRemoving(player)
    self.AttackBonuses[player.UserId] = nil
end

local MaxItemCount = 99

local function isInt(n)
    return type(n) == 'number' and n == math.floor(n)
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('GMResult'):FireClient(player, payload)
end

function Mgr:ResolveTarget(player, target)
    if target == nil then return player end
    if not isInt(target) then return nil end
    for _, other in ipairs(game:GetService('Players'):GetPlayers()) do
        if other.UserId == target then return other end
    end
end

function Mgr:Coin(data, payload)
    local amount = payload.amount
    if not isInt(amount) or amount == 0 then return false end
    if amount > 0 then return data:AddCoin(amount, nil, 'gm') end
    return data:SpendCoin(-amount, nil, 'gm')
end

function Mgr:Item(data, payload)
    local count = payload.count
    if type(payload.itemId) ~= 'string' or not GameCfg.Items.Definitions[payload.itemId] then
        return false, '物品 ID 不在白名单中'
    end
    if not isInt(count) or count < 1 or count > MaxItemCount then
        return false, '数量须为 1—99 的整数'
    end
    local ok, reason = data:GrantItem(payload.itemId, count)
    if not ok then return false, reason == 'full' and '空格不足，整批未发放' or '物品状态无效' end
    return true
end

-- 设血量 / 饥饿度（#53）：走 MgrVitals 的同名入口（调低血量经 ApplyDamage 单点），越界值拒绝
function Mgr:SetHealth(_, payload, target)
    return self.Vitals ~= nil and self.Vitals:SetHealth(target, payload.value)
end

function Mgr:SetHunger(_, payload, target)
    return self.Vitals ~= nil and self.Vitals:SetHunger(target, payload.value)
end

function Mgr:NextFish(_, payload, target)
    local fishId = payload.fishId
    if type(fishId) ~= 'string' or not GameCfg.Fish[fishId] then
        return false, '鱼种 ID 不在白名单中'
    end
    if not self.Cast then return false, '钓鱼管理器未就绪' end
    self.Cast:SetNextFish(target, fishId)
    return true
end

local Actions = { Coin = 'Coin', Item = 'Item', SetHealth = 'SetHealth', SetHunger = 'SetHunger',
    NextFish = 'NextFish', AddAttack = 'AddAttack', GetAttack = 'GetAttack',
    ApplyState = 'ApplyState', SaveState = 'SaveState', ReadState = 'ReadState',
    SelectSaveSlot = 'SelectSaveSlot', GetState = 'GetState' }

function Mgr:GetAttack()
    return true
end

-- 处理一次 GM 请求；发放成功返回 true
function Mgr:Handle(player, payload)
    if not (GameCfg.Debug and GameCfg.Debug.Enabled) then
        print('[MgrGM] 调试开关关闭，拒绝', player and player.UserId)
        self:Reply(player, { ok = false, action = type(payload) == 'table' and payload.action or nil,
            reason = '调试开关已关闭' })
        return false
    end
    if type(payload) ~= 'table' then return false end
    local method = Actions[payload.action]
    local target = method and self:ResolveTarget(player, payload.target)
    local data = target and self.PlayerData and self.PlayerData:GetDataInst(target)
    if data and self.Save and (method == 'ApplyState' or method == 'SaveState'
        or method == 'ReadState' or method == 'SelectSaveSlot' or method == 'GetState') then
        local function finish(ok, reason)
            if ok and (method == 'ApplyState' or method == 'ReadState') then
                self.PlayerData:SendItemBar(target)
            end
            self:Reply(player, { ok = ok, action = payload.action, target = target.UserId,
                reason = reason, status = self.Save:Status(target.UserId),
                snapshot = data:GetItemBarSnapshot() })
        end
        if method == 'GetState' then finish(true) return true end
        if method == 'ApplyState' then
            return self.Save:ApplyTemporary(target.UserId, data, payload, finish)
        end
        if method == 'SaveState' then
            local ok, reason = self.Save:SaveExplicit(target.UserId, data, finish)
            if not ok then finish(false, reason) end
            return ok
        end
        if method == 'ReadState' then
            local ok, reason = self.Save:ReadExplicit(target.UserId, data, finish)
            if not ok then finish(false, reason) end
            return ok
        end
        local ok, reason = self.Save:SelectNextSlot(target.UserId, payload.slot, finish)
        if not ok then finish(false, reason) end
        return ok
    end
    local ok, reason = false, '请求或目标无效'
    if data then ok, reason = self[method](self, data, payload, target) end
    print('[MgrGM]', ok and '发放' or '拒绝', player and player.UserId, '->', target and target.UserId,
        tostring(payload.action), tostring(payload.amount or payload.itemId or payload.value or payload.scene or payload.fishId), tostring(payload.count or ''))
    if ok and method ~= 'NextFish' and method ~= 'AddAttack' and method ~= 'GetAttack' then
        self.PlayerData:SendItemBar(target)
    end
    self:Reply(player, { ok = ok, action = payload.action, target = target and target.UserId,
        damage = ok and (method == 'AddAttack' or method == 'GetAttack') and self:GetMeleeDamage(target, BaseAttack) or nil,
        reason = not ok and (reason or '请求未通过') or nil })
    return ok
end

function Mgr:Start()
    _G.REUtil:GetRE('GMAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'GMAction', GameCfg.Items.ActionCooldownSec) then
            self:Reply(player, { ok = false, action = type(payload) == 'table' and payload.action or nil,
                reason = '操作过于频繁' })
            return
        end
        self:Handle(player, payload)
    end)
end

return Mgr
