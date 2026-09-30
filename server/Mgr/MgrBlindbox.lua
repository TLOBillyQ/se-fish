-- 盲盒（#147 T26，GameSpec §15 与地图盲盒表）：商店盲盒页的单抽（10 金豆）/十连（90 金豆）服务端
-- 结算。收费归平台适配层（MgrPlatform）：先拉起购买 flow，购买成功才在一个持久操作里逐抽结算
-- （common/BlindboxDraw），取消/失败/超时不发奖、不动保底计数。抽样、发奖与 pity 计数同键落账
-- （#123 持久操作协议），落账后才回包与推库存；同 seq 重放或携带完整 operation 重试只回原结果，
-- 不重复扣费（不再拉起购买）、不重复发奖、不重复落地。连续未中奖计数存 Extra.lottery.pity，
-- 重进读档保留，客户端经 BlindboxStateRequest / OnPlayerAdded 的 State 回包同步。
-- 满格按区落地（#126 SpawnItem 口径，计入各区掉落预算）：抽中物优先入库，放不下的落在玩家
-- 面前地上、其他玩家可拾取；落地在落账后的 done 回调执行，重放路径不重复落地。落地失败
-- （预算耗尽等）只记日志留对账线索，补发归 #148。
-- 生产构建（Debug 关）且商品 ID 未交付时购买入口明确 unavailable，不发付费权益。
local GameCfg = require('common.GameCfg')
local BlindboxDraw = require('common.BlindboxDraw')

local Mgr = { LastSeq = {} }

local function blindboxCfg()
    return GameCfg.Blindbox
end

-- 抽数 → 商品行（单抽 10 金豆 / 十连 90 金豆，价目集中 GameCfg.Platform.Goods）
local function goodsKeyOf(count)
    return count == 10 and 'blindboxTen' or 'blindboxSingle'
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('BlindboxResult'):FireClient(player, payload)
end

function Mgr:PityOf(data)
    local extra = data and data.Extra
    local lottery = extra and extra.lottery
    return lottery and lottery.pity or 0
end

-- 在一次持久操作的 draft 上逐抽结算（#123 transform 只改隔离 draft）：
-- 读 draft 里的 pity → DrawMany 逐抽（中途大奖立即重置）→ 每件抽中物入库或记落地 → 写回 pity。
-- 返回 result 或 nil, reason；任何拒绝都不改库存与计数。随机数经 self.Random 注入（默认 math.random）。
function Mgr:Settle(draft, count)
    local rng = type(self.Random) == 'function' and self.Random or math.random
    local pityBefore = self:PityOf(draft)
    local draws, pityAfter = BlindboxDraw.DrawMany(count, pityBefore, rng)
    if not draws then return nil, 'roll' end
    local grounded = 0
    for _, draw in ipairs(draws) do
        -- 倍率固定 1（GameSpec §15）；放不下的记落地，由 done 回调经 Loot:SpawnItem 落地
        if draft:AddItem(draw.itemKey, 1) then
            draw.landed = false
        else
            draw.landed = true
            grounded = grounded + 1
        end
        draw.pityBefore, draw.index = nil, nil -- 回包瘦身：逐抽 pity 推进见 pityAfter 链
    end
    draft.Extra.lottery.pity = pityAfter
    return { ok = true, action = 'Draw', count = count, draws = draws,
        pityBefore = pityBefore, pityAfter = pityAfter, grounded = grounded }
end

-- 落账后的发布（#123 done 才发布副作用）：回包 + 推库存 + 落地。
-- 只在 fresh 落账路径调用；重放路径走 resolve 只回包，不重复落地。
function Mgr:Publish(player, result)
    print('[MgrBlindbox] 盲盒落账', player.UserId, 'count=' .. result.count,
        'pity=' .. result.pityBefore .. '->' .. result.pityAfter, 'grounded=' .. result.grounded)
    if self.PlayerData and self.PlayerData.SendItemBar then self.PlayerData:SendItemBar(player) end
    self:Reply(player, result)
    if result.grounded > 0 and self.Loot then
        local origin = player.Character and player.Character.Position
        for _, draw in ipairs(result.draws) do
            if draw.landed then
                local spawned = origin and self.Loot:SpawnItem(draw.itemKey, 1, nil,
                    origin and { x = origin.x, y = origin.y, z = origin.z + 2 } or nil)
                if not spawned then
                    print('[MgrBlindbox] 落地失败（待 #148 对账）', player.UserId, draw.itemKey)
                end
            end
        end
    end
end

-- 同 seq/operation 重放：原结果已在落账时发奖落地，这里只回包同一份结果（recovered 标记）。
local function resolve(mgr, player, data, payload)
    local operation, mode = mgr.Save:ResolveRequest(player, data, 'blindbox', payload.seq)
    if not operation then return nil, mode end
    if mode ~= 'replay' then return operation, mode end
    mgr.Save:Execute(player, data, operation, function() return nil, 'expired' end,
        function(ok, result)
            if ok and type(result) == 'table' then
                result.recovered = true
                result.operation = operation
                mgr:Reply(player, result)
            end
        end)
    return nil, 'replay'
end

-- 处理一次抽盲盒请求；最终结果经 BlindboxResult 回包。
-- 顺序：校验 → 占操作序号（重放短路，未落账的序号不记账）→ 平台购买 flow → 成功才逐抽结算落账。
function Mgr:Handle(player, payload)
    if type(payload) ~= 'table' or payload.action ~= 'Draw' then return false end
    local count, seq = payload.count, payload.seq
    if (count ~= 1 and count ~= 10)
        or type(seq) ~= 'number' or seq ~= math.floor(seq) or seq < 1 or seq > 2147483647 then
        return false
    end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data or not self.Save or not self.Platform then return false end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then
        -- 同 seq 只有「已落账的重放」有意义；未落账的旧序号（上次支付未完成）不允许复用
        local operation, mode = resolve(self, player, data, payload)
        return operation == nil and mode == 'replay'
    end
    local operation, mode = resolve(self, player, data, payload)
    if operation == nil then
        if mode == 'replay' then return true end -- 已回包原结果
        if mode == 'pending' then
            self:Reply(player, { ok = false, reason = 'pending' })
            return true
        end
        return false
    end
    self.LastSeq[player.UserId] = seq
    -- 先收费后发货：购买成功才在持久操作里逐抽结算；取消/失败/超时只回包原因，不动库存与计数
    local accepted, reason = self.Platform:Purchase(player, goodsKeyOf(count), 'blindbox',
        function(outcome)
            if outcome ~= 'success' then
                self:Reply(player, { ok = false, reason = outcome })
                return
            end
            self.Save:Execute(player, data, operation, function(draft)
                return self:Settle(draft, count)
            end, function(written, result)
                if not written then
                    self:Reply(player, { ok = false, reason = result })
                    return
                end
                result.operation = operation
                self:Publish(player, result)
            end)
        end)
    if not accepted then
        self:Reply(player, { ok = false, reason = reason or 'unavailable' })
    end
    return true
end

-- 断线重进握手：回包当前保底计数（State），客户端据此刷新盲盒页计数展示
function Mgr:PushState(player)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return end
    self:Reply(player, { ok = true, action = 'State', pity = self:PityOf(data),
        guaranteeAt = blindboxCfg().Pity and blindboxCfg().Pity.afterMisses + 1 or nil })
end

function Mgr:OnPlayerAdded(player)
    self:PushState(player)
end

function Mgr:Start()
    _G.REUtil:GetRE('BlindboxAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'BlindboxAction', blindboxCfg().ActionCooldownSec) then return end
        self:Handle(player, payload)
    end)
    _G.REUtil:GetRE('BlindboxStateRequest').OnServerEvent:Connect(function(player)
        self:PushState(player)
    end)
end

function Mgr:OnPlayerRemoving(player)
    self.LastSeq[player.UserId] = nil
end

return Mgr
