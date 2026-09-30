-- 抽奖机（#138 T17，GameSpec §14）：投入一件道具栏里的未烤制极品食物（极品鱼获或信物，
-- 资格判定归 common/LotteryEligibility），三轴独立抽样；三同优先仅得对应大奖（武器组内
-- 均匀随机一件，行为归 #139/#140，这里只发放与落位），恰两同得投入物实际价值 × 对应倍数的
-- 金币，无两同无奖励。占格大奖回到投入物释放的格位，武器进独立库存。
-- 注入 Save 时只改隔离 draft，扣物/发奖与结果同键落账后才回包与推库存（#123 持久操作协议）；
-- 同 seq 重放或携带响应中的完整 operation 重试只回原结果。玩家重进时若最近一次持久操作是
-- 抽奖，补推唯一结果供展示（recovered），不重复发奖。未注入 Save 的独立纯逻辑模式保留同步结算。
-- 动画不决定奖项：停轴顺序与时长只是客户端表现（GameCfg.Lottery.SpinSec / AxisOrder）。
local GameCfg = require('common.GameCfg')
local Eligibility = require('common.LotteryEligibility')
local Draw = require('common.LotteryDraw')

local Mgr = { LastSeq = {} }

local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

-- 同通道相同 seq 重放原结果；完整 operation 可跨重连重试，身份校验归 Save。
local function resolve(mgr, player, data, payload)
    local requestId = payload.operation
    if requestId ~= nil and type(requestId) ~= 'table' then return nil, false end
    if requestId == nil then requestId = payload.seq end
    local operation, mode = mgr.Save:ResolveRequest(player, data, 'lottery', requestId)
    if not operation then return nil, false end
    if mode ~= 'replay' then return operation end
    local accepted = mgr.Save:Execute(player, data, operation, function() return nil, 'expired' end,
        function(ok, result)
            if ok then result.operation = operation mgr:Reply(player, result) end
        end)
    return nil, accepted
end

local function execute(mgr, player, data, operation, transform, done)
    if not operation then return false end
    return mgr.Save:Execute(player, data, operation, transform, function(ok, result)
        if ok then result.operation = operation end
        done(ok, result, operation)
    end)
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('LotteryResult'):FireClient(player, payload)
end

-- 七区抽奖机锚点（#125 场景合同的 Lottery 实体）；范围复验与商店/钓鱼佬同一套 Radius/Slack 口径
function Mgr:MachinePoint()
    local cfg = GameCfg.Lottery
    return { AnchorNames = cfg.MachineAnchors(), Radius = cfg.Radius, Slack = cfg.Slack }
end

-- 结算一次抽奖（live/draft 通用，#123）：资格复验 → 实际价值定价 → 三轴抽样 → 扣投入 → 发奖。
-- 返回 result 或 nil, reason；任何拒绝都不改库存与金币。随机数经 self.Random 注入（默认 math.random）。
function Mgr:Settle(target, slot)
    if type(slot) ~= 'number' or slot ~= math.floor(slot)
        or slot < 1 or slot > target:ItemBarCapacity() then return nil, 'slot' end
    local items = target.Data.Containers[ITEM_BAR]
    local entry = items[slot]
    if not entry or entry.count <= 0 then return nil, 'slot' end
    local eligible, reason = Eligibility.Check(entry)
    if not eligible then return nil, reason end
    -- 实际价值 = 未烤回收价（含个体倍率）；烤制物已被资格拒绝，不存在烤熟价口径
    local price = GameCfg.Items.SalePrice(entry.itemId, entry.mult)
    if not price or price < 1 then return nil, 'bad-item' end
    local axes = Draw.RollAxes(self.Random)
    if not axes then return nil, 'roll' end
    local outcome = Draw.Evaluate(axes)
    local definition = GameCfg.Items.Definitions[entry.itemId]
    local result = { ok = true, action = 'Draw', slot = slot, itemId = entry.itemId,
        itemName = definition and definition.Name or entry.itemId, betValue = price,
        axes = axes, outcome = outcome.outcome, coinBefore = target.Data.FishCoin }
    items[slot] = nil
    if outcome.outcome == 'pair' then
        local pattern = GameCfg.Lottery.Patterns[outcome.pattern]
        local coins = price * pattern.pairMultiplier
        target:AddCoin(coins, nil, 'lottery:pair')
        result.coins, result.multiplier, result.patternName = coins, pattern.pairMultiplier, pattern.name
    elseif outcome.outcome == 'triple' then
        local pattern = GameCfg.Lottery.Patterns[outcome.pattern]
        local reward = pattern.tripleReward
        if reward.kind == 'weaponChoice' then
            local itemId = Draw.ChooseWeapon(pattern, self.Random)
            if not itemId then
                items[slot] = entry -- 组内抽样失败是配置事故：退回投入，不结算
                return nil, 'roll'
            end
            target:GrantWeapon(itemId, 1)
            local prizeDef = GameCfg.Items.Definitions[itemId]
            result.prize = { kind = 'weapon', itemId = itemId,
                name = prizeDef and prizeDef.Name or itemId }
        else
            -- 占格大奖优先回到投入物释放的格位（策划案：奖品放在原来放极品鱼的道具栏格子）
            items[slot] = { itemId = reward.itemKey, count = 1, containerId = ITEM_BAR }
            result.prize = { kind = 'item', itemId = reward.itemKey, name = reward.itemName }
        end
        result.patternName = pattern.name
    end
    result.coinAfter = target.Data.FishCoin
    return result
end

function Mgr:Draw(player, data, slot, operation)
    if not self.Interact:InRange(player, self:MachinePoint()) then
        self:Reply(player, { ok = false, reason = 'range' })
        return false
    end
    -- 快速预检（live 状态）：畸形/空槽/资格在占操作序号之前拒绝；持久模式仍在 draft 上复验
    local items = data.Data.Containers[ITEM_BAR]
    local entry = type(slot) == 'number' and slot == math.floor(slot)
        and slot >= 1 and slot <= data:ItemBarCapacity() and items[slot]
    if not entry or entry.count <= 0 then
        self:Reply(player, { ok = false, reason = 'slot' })
        return false
    end
    local eligible, reason = Eligibility.Check(entry)
    if not eligible then
        self:Reply(player, { ok = false, reason = reason })
        return false
    end
    if self.Save then
        return execute(self, player, data, operation, function(draft)
            return self:Settle(draft, slot)
        end, function(written, result, op)
            if not written then self:Reply(player, { ok = false, reason = result }) return end
            print('[MgrLottery] 抽奖落账', player.UserId, op.id, result.itemId,
                'betValue=' .. result.betValue, 'axes=' .. table.concat(result.axes, '/'),
                result.outcome, 'coinBefore=' .. result.coinBefore, 'coinAfter=' .. result.coinAfter,
                result.prize and (result.prize.kind .. ':' .. result.prize.itemId) or '')
            self.PlayerData:SendItemBar(player)
            self:Reply(player, result)
        end)
    end
    local result, failure = self:Settle(data, slot)
    if not result then
        self:Reply(player, { ok = false, reason = failure })
        return false
    end
    data:UpdateData(function() end, true)
    print('[MgrLottery] 抽奖', player.UserId, result.itemId, 'betValue=' .. result.betValue,
        result.outcome, 'FishCoin=' .. tostring(data.Data.FishCoin))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, result)
    return true
end

-- 处理一次抽奖请求；持久模式返回是否接收，最终结果经 LotteryResult 回包。
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or payload.action ~= 'Draw' then return false end
    local seq = payload.seq
    if (not self.Save or payload.operation == nil)
        and (type(seq) ~= 'number' or seq ~= math.floor(seq) or seq < 1 or seq > 2147483647) then
        return false
    end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return false end
    local operation
    if self.Save then
        local replayed
        operation, replayed = resolve(self, player, data, payload)
        if not operation then return replayed end
    end
    local last = self.LastSeq[player.UserId]
    if last and seq and seq <= last then return false end
    local slot = payload.slot
    if type(slot) ~= 'number' or slot ~= math.floor(slot) then return false end
    self.LastSeq[player.UserId] = seq
    return self:Draw(player, data, slot, operation)
end

-- 断线/关动画恢复：若最近一次持久操作是抽奖，补推同一份结果（recovered 标记，仅展示）；
-- 扣物与发奖早在落账时完成，这里不重复结算。两个入口：玩家就绪（OnPlayerAdded，可能早于客户端
-- 连接回包丢失）与客户端主动拉取（LotteryStateRequest，照 RequestItemBar 握手先例），
-- 客户端按 operation.id 去重，同一份结果不会展示两次。
function Mgr:PushRecovered(player)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local meta = data and data.SaveMeta
    local operations = meta and meta.operations
    local last = operations and operations[#operations]
    if not last or last.kind ~= 'lottery' or last.sequence ~= meta.sequence
        or type(last.result) ~= 'table' or not last.result.ok then return end
    local result = copy(last.result)
    result.recovered = true
    result.operation = { id = last.id, sequence = last.sequence, kind = last.kind,
        requestKey = last.requestKey }
    self:Reply(player, result)
end

function Mgr:OnPlayerAdded(player)
    self:PushRecovered(player)
end

function Mgr:Start()
    _G.REUtil:GetRE('LotteryAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'LotteryAction', GameCfg.Lottery.ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
    _G.REUtil:GetRE('LotteryStateRequest').OnServerEvent:Connect(function(player)
        self:PushRecovered(player)
    end)
end

function Mgr:OnPlayerRemoving(player)
    self.LastSeq[player.UserId] = nil
end

return Mgr
