-- GM 发放（#47，#28 规格）：服务端单点裁决，只在 GameCfg.Debug.Enabled 打开时接受请求。
-- 客户端发 GMAction{action, target, ...}；target 缺省是发起者自己，给数字 UserId 则发给在线的那名玩家，
-- 查不到就失败、不落到别人身上。加 / 扣币走 PlayerData:AddCoin / SpendCoin 这一唯一入口（扣不成负数），
-- 发物品走 PlayerData:GrantItem 按物品表的 Container 路由（鱼竿进道具栏、蚯蚓进鱼饵库存）。
-- 设血量 / 饥饿度（#53）走 MgrVitals:SetHealth / SetHunger。
local GameCfg = require('common.GameCfg')

local Mgr = {}

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

-- 验收准备只补齐条件，扩容、转入、食用与拾取仍由原玩法入口处理。
function Mgr:PrepareStorage(data, payload)
    local snapshot = data:GetItemBarSnapshot()
    if not snapshot then return false, '玩家状态尚未就绪' end
    local scene = payload.scene
    if scene == 'first' or scene == 'six' or scene == 'poor' or scene == 'purchase' then
        if (scene == 'first' or scene == 'poor') and snapshot.upgradeLevel ~= 0 then
            return false, '首级验收需要等级 0，请重新试玩'
        end
        local targetCoin = 0
        if scene == 'first' then targetCoin = GameCfg.Items.UpgradePrices[1]
        elseif scene == 'purchase' then targetCoin = 100
        elseif scene == 'six' then
            for level = snapshot.upgradeLevel + 1, #GameCfg.Items.UpgradePrices do
                targetCoin = targetCoin + GameCfg.Items.UpgradePrices[level]
            end
            if targetCoin == 0 then return false, '已经升满，请到钓场商店确认不能继续扣金币' end
        end
        local delta = targetCoin - snapshot.coin
        if delta > 0 then return data:AddCoin(delta, nil, 'gm-storage-prepare') end
        if delta < 0 and scene == 'poor' then return data:SpendCoin(-delta, nil, 'gm-storage-prepare') end
        return true
    end
    if scene ~= 'transfer' and scene ~= 'full' then return false, '未知验收场景' end
    local function freeSlots(slots, capacity)
        local free = 0
        for index = 1, capacity do
            if not slots[index] or slots[index].count <= 0 then free = free + 1 end
        end
        return free
    end
    local freeBar = freeSlots(snapshot.slots, snapshot.slotCount)
    local freeBackpack = freeSlots(snapshot.backpack, snapshot.backpackCount)
    local count = freeBar + freeBackpack
    if scene == 'transfer' then
        if freeBackpack == 0 then return false, '背包已满，请先腾出一格再准备转入' end
        count = freeBar + 1
    end
    if count == 0 then return false, '道具栏与背包已经满格，无需重复发放' end
    return self:Item(data, { itemId = GameCfg.Items.Id.Tilapia, count = count })
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
    PrepareStorage = 'PrepareStorage', NextFish = 'NextFish' }

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
    local ok, reason = false, '请求或目标无效'
    if data then ok, reason = self[method](self, data, payload, target) end
    print('[MgrGM]', ok and '发放' or '拒绝', player and player.UserId, '->', target and target.UserId,
        tostring(payload.action), tostring(payload.amount or payload.itemId or payload.value or payload.scene or payload.fishId), tostring(payload.count or ''))
    if ok and method ~= 'NextFish' then self.PlayerData:SendItemBar(target) end
    self:Reply(player, { ok = ok, action = payload.action, target = target and target.UserId,
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
