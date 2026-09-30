-- 平台适配管理器（#147 T26，GameSpec §7/§11/§15，docs/技术难点识别.md §4）：
-- 商品购买（金豆价目）与激励广告的唯一服务端入口，业务（盲盒 / 满血复活 / 肾上腺素）只依赖本模块。
-- 真实商品 ID / 广告标签 / 金币汇率是商业化后台交付参数（#148）：未交付时一切购买入口明确不可用、
-- 不发付费权益；Debug 开关打开时同一路径转为「pending flow + 测试驱动器（PlatformTestAction）结算」，
-- 生产构建（GameCfg.Debug.Enabled=false）测试驱动器整体拒绝，不存在伪造支付成功的入口。
-- 已知平台边界（不宣称已解决，归 #148 真实验收）：
--   * GoodsPurchaseCompleted 只有 goodsId/goodsNum/player，没有订单 ID，官方教程禁止拼 UserId+goodsId
--     防重——本模块不做伪防重：每个购买完成信号按一笔真实购买处理，跨会话防重 / 补发 / 对账待平台能力；
--   * 购买没有取消 / 失败事件，广告 failEvent 也不保证触发：flow 统一按 FlowTimeoutSec 超时兜底结算；
--   * ShowGoodsPurchasePanel 的 showTime 语义未查证，调用不传；广告成功以平台发放商品奖励
--     （同一 GoodsPurchaseCompleted 信号）为准，真实事件名接线未查证。
local GameCfg = require('common.GameCfg')

local Mgr = { Flows = {}, GrantSeq = {}, PendingGrants = {}, NextFlowId = 0 }

local function cfg()
    return GameCfg.Platform
end

function Mgr:Now()
    self.World = self.World or game:GetService('World')
    return self.World:GetServerTime()
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('PlatformResult'):FireClient(player, payload)
end

local function service(name)
    local ok, svc = pcall(function() return game:GetService(name) end)
    return ok and svc or nil
end

local function debugEnabled()
    return GameCfg.Debug and GameCfg.Debug.Enabled == true
end

-- 商品行已交付后台 ID 才可用真实购买
local function configured(row)
    return type(row) == 'table' and type(row.goodsId) == 'string' and row.goodsId ~= ''
end

function Mgr:HasFlow(player)
    local flow = player and self.Flows[player.UserId]
    return flow ~= nil and flow.player == player
end

-- 结算在飞 flow：清空后回调 onResult(outcome, payload)，回调报错只记日志
local function resolve(mgr, player, flow, outcome, payload)
    if mgr.Flows[player.UserId] == flow then mgr.Flows[player.UserId] = nil end
    print('[MgrPlatform] flow 结算', player.UserId, flow.kind, tostring(flow.goods or flow.ad), outcome)
    if type(flow.onResult) == 'function' then
        local ok, err = pcall(flow.onResult, outcome, payload)
        if not ok then print('[MgrPlatform] flow 回调失败', player.UserId, tostring(err)) end
    end
end

-- 建立一个平台流程：真实（已配置 + 服务可达）或测试（Debug 开）；否则返回 false, 'unavailable'。
-- intent = { kind='purchase', goods=key } 或 { kind='ad', ad=key }；onResult(outcome, payload)。
local function openFlow(self, player, intent, onResult)
    if not player or not player.UserId then return false, 'invalid' end
    if self:HasFlow(player) then return false, 'busy' end
    local real, goodsId
    if intent.kind == 'purchase' then
        local row = cfg().Goods[intent.goods]
        if type(row) ~= 'table' then return false, 'invalid' end
        if configured(row) and service('CommodityService') then
            real, goodsId = true, row.goodsId
        end
    else
        local row = cfg().Ads[intent.ad]
        if type(row) ~= 'table' then return false, 'invalid' end
        if configured(row) and service('AdvertisementService') then
            real, goodsId = true, row.goodsId
        end
    end
    if not real and not debugEnabled() then return false, 'unavailable' end
    self.NextFlowId = self.NextFlowId + 1
    local now = self:Now()
    local flow = { id = self.NextFlowId, player = player, kind = intent.kind, goods = intent.goods,
        ad = intent.ad, purpose = intent.purpose, goodsId = goodsId, real = real or nil,
        onResult = onResult, startedAt = now, deadline = now + cfg().FlowTimeoutSec }
    if real then
        local ok, err
        if intent.kind == 'purchase' then
            -- showTime 语义未查证（技术难点 §4），不传
            ok, err = pcall(function() service('CommodityService'):ShowGoodsPurchasePanel(player, goodsId) end)
        else
            local adRow = cfg().Ads[intent.ad]
            ok, err = pcall(function()
                service('AdvertisementService'):ShowRewardedVideoAd(player, goodsId,
                    adRow.successEvent, adRow.failEvent, adRow.adTag)
            end)
        end
        if not ok then
            print('[MgrPlatform] 平台调用失败', player.UserId, intent.kind, tostring(err))
            return false, 'unavailable'
        end
    end
    self.Flows[player.UserId] = flow
    print('[MgrPlatform] flow 建立', player.UserId, intent.kind, tostring(intent.goods or intent.ad),
        real and '真实' or '测试', 'flow=' .. tostring(flow.id))
    return true
end

-- 购买一件商品；onResult('success', { goodsId, num }) 或 ('cancel'/'fail'/'timeout')
function Mgr:Purchase(player, goodsKey, purpose, onResult)
    return openFlow(self, player, { kind = 'purchase', goods = goodsKey, purpose = purpose }, onResult)
end

-- 播放激励广告；onResult 口径同上（成功载荷来自平台发放的商品奖励信号）
function Mgr:ShowAd(player, adKey, purpose, onResult)
    return openFlow(self, player, { kind = 'ad', ad = adKey, purpose = purpose }, onResult)
end

-- 业务主动取消（如免费复活抢先结算）：清 flow 不回调，返回是否有 flow 被清
function Mgr:CancelFlow(player)
    if not self:HasFlow(player) then return false end
    print('[MgrPlatform] flow 被业务取消', player.UserId)
    self.Flows[player.UserId] = nil
    return true
end

-- 肾上腺素购买入口（MgrSurvival 濒死无药时拉起）：两份报价由客户端选择后各自走 Purchase；
-- 未配置且非 Debug → 明确回包不可用（客户端展示「平台复活即将开放」口径）
function Mgr:OpenAdrenalineShop(player)
    local rows = cfg().Goods
    local available = debugEnabled() or (configured(rows.adrenaline1) and configured(rows.adrenaline5))
    if not available then
        self:Reply(player, { ok = false, action = 'AdrenalineShop', reason = 'unavailable' })
        return false
    end
    self:Reply(player, { ok = true, action = 'AdrenalineShop', offers = {
        { key = 'adrenaline1', beans = rows.adrenaline1.beans, count = rows.adrenaline1.count,
            name = rows.adrenaline1.name },
        { key = 'adrenaline5', beans = rows.adrenaline5.beans, count = rows.adrenaline5.count,
            name = rows.adrenaline5.name },
    } })
    return true
end

-- 地图商店金币页（ScreenShop 入口）：金币汇率与商品 ID 未交付，一律明确不可用
function Mgr:OpenCoinShop(player)
    local row = cfg().Goods.coinPack
    if not configured(row) then
        self:Reply(player, { ok = false, action = 'CoinShop', reason = 'unavailable' })
        return false
    end
    return self:Purchase(player, 'coinPack', 'coins', function(outcome)
        if outcome ~= 'success' then
            self:Reply(player, { ok = false, action = 'CoinShop', reason = outcome })
        end
        -- 金币包发货需汇率（后台交付），成功回调的发货实现归 #148
    end)
end

-- 占格商品发货（持久操作，#123 协议）：每个购买完成信号按一笔真实购买处理（无订单 ID 不防重，
-- 见模块头注释）；存档忙时入 PendingGrants 由 Update 重试，宁可晚发不丢单。
function Mgr:GrantGoods(player, goodsKey, num)
    local row = cfg().Goods[goodsKey]
    if not row or not row.itemId then return false end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data or not self.Save then return false end
    self.GrantSeq[player.UserId] = (self.GrantSeq[player.UserId] or 0) + 1
    local operation, mode = self.Save:ResolveRequest(player, data, 'platform:grant',
        self.GrantSeq[player.UserId])
    if not operation then
        if mode == 'pending' then
            local queue = self.PendingGrants[player.UserId]
            if not queue or queue.player ~= player then
                queue = { player = player, jobs = {} }
                self.PendingGrants[player.UserId] = queue
            end
            queue.jobs[#queue.jobs + 1] = { goods = goodsKey, num = num }
            print('[MgrPlatform] 发货排队', player.UserId, goodsKey)
            return true
        end
        print('[MgrPlatform] 发货被拒', player.UserId, goodsKey, tostring(mode))
        return false
    end
    local total = row.count * math.max(1, num or 1)
    return self.Save:Execute(player, data, operation, function(draft)
        local granted = 0
        for _ = 1, total do
            if not draft:AddItem(row.itemId) then break end -- 空格不够发几件是几件，余下落地
            granted = granted + 1
        end
        return { ok = true, goods = goodsKey, itemId = row.itemId, total = total, granted = granted,
            overflow = total - granted }
    end, function(written, result)
        if not written then
            print('[MgrPlatform] 发货未落账', player.UserId, goodsKey, tostring(result))
            return
        end
        print('[MgrPlatform] 发货落账', player.UserId, goodsKey,
            'granted=' .. tostring(result.granted), 'overflow=' .. tostring(result.overflow))
        if self.PlayerData.SendItemBar then self.PlayerData:SendItemBar(player) end
        self:Reply(player, { ok = true, action = 'Grant', goods = goodsKey,
            granted = result.granted, overflow = result.overflow })
        -- 满格溢出落地（与盲盒同一口径，计入全区预算）；无 Loot 注入时只记日志留对账线索
        if result.overflow > 0 then
            local origin = player.Character and player.Character.Position
            for _ = 1, result.overflow do
                local spawned = self.Loot and origin
                    and self.Loot:SpawnItem(row.itemId, nil, nil,
                        { x = origin.x, y = origin.y, z = origin.z + 2 })
                if not spawned then
                    print('[MgrPlatform] 溢出落地失败（待对账）', player.UserId, row.itemId)
                end
            end
        end
    end)
end

-- 购买完成信号（真实平台回调；测试里可直接调用）：goodsId → 商品/广告行。
-- 先匹配在飞 flow（本次购买是我们发起的），否则按购买事实直接发货（玩家也可能从平台商店直接买）。
function Mgr:OnGoodsPurchaseCompleted(goodsId, num, player)
    if type(goodsId) ~= 'string' or not player or not player.UserId then return end
    print('[MgrPlatform] 购买完成信号', player.UserId, goodsId, tostring(num))
    local flow = self.Flows[player.UserId]
    if flow and flow.player == player and flow.goodsId == goodsId then
        resolve(self, player, flow, 'success', { goodsId = goodsId, num = num })
        return
    end
    for key, row in pairs(cfg().Goods) do
        if configured(row) and row.goodsId == goodsId then
            if row.itemId then self:GrantGoods(player, key, num)
            else print('[MgrPlatform] 无发货映射（待 #148）', player.UserId, goodsId, key) end
            return
        end
    end
    print('[MgrPlatform] 未配置商品的购买信号，不发货', player.UserId, goodsId)
end

-- 仅测试可用的回调驱动器：生产构建整体拒绝（验收：生产不能进入测试支付成功入口）。
-- Debug 开时把 outcome（success/cancel/fail）结算到调用者当前在飞 flow。
function Mgr:HandleTestAction(player, payload)
    if not debugEnabled() then
        print('[MgrPlatform] 生产构建拒绝测试驱动器', player and player.UserId)
        return false
    end
    if type(payload) ~= 'table' or payload.action ~= 'ResolveFlow'
        or (payload.outcome ~= 'success' and payload.outcome ~= 'cancel' and payload.outcome ~= 'fail') then
        return false
    end
    local flow = player and self.Flows[player.UserId]
    if not flow or flow.player ~= player then return false end
    resolve(self, player, flow, payload.outcome, { driver = true })
    return true
end

-- 客户端平台操作通道：打开肾上腺素 / 金币购买入口，或发起肾上腺素购买
function Mgr:HandleAction(player, payload)
    if type(payload) ~= 'table' then return false end
    if payload.action == 'OpenAdrenaline' then return self:OpenAdrenalineShop(player) end
    if payload.action == 'OpenCoinShop' then return self:OpenCoinShop(player) end
    if payload.action == 'Purchase' then
        local goodsKey = payload.goods
        local row = cfg().Goods[goodsKey]
        -- 客户端只能直接发起占格商品（肾上腺素）购买；盲盒/复活由对应管理器服务端发起
        if not row or not row.itemId then return false end
        return self:Purchase(player, goodsKey, 'adrenaline', function(outcome)
            if outcome == 'success' then
                self:GrantGoods(player, goodsKey, 1)
            else
                self:Reply(player, { ok = false, action = 'Purchase', goods = goodsKey, reason = outcome })
            end
        end)
    end
    return false
end

function Mgr:Update()
    local now = self:Now()
    for userId, flow in pairs(self.Flows) do
        if now >= flow.deadline then
            resolve(self, flow.player, flow, 'timeout') -- 平台无取消/失败事件，超时是唯一兜底
        end
    end
    for userId, queue in pairs(self.PendingGrants) do
        if queue.player and #queue.jobs > 0 then
            local job = queue.jobs[1]
            if self:GrantGoods(queue.player, job.goods, job.num) then
                table.remove(queue.jobs, 1)
            else
                self.PendingGrants[userId] = nil -- 存档不可用：记日志保线索，不无限重试
                print('[MgrPlatform] 发货重试放弃（待对账）', userId, job.goods)
            end
        else
            self.PendingGrants[userId] = nil
        end
    end
end

function Mgr:OnPlayerRemoving(player)
    self.Flows[player.UserId] = nil
    self.GrantSeq[player.UserId] = nil
    self.PendingGrants[player.UserId] = nil
end

function Mgr:Start()
    local commodity = service('CommodityService')
    if commodity and commodity.GoodsPurchaseCompleted then
        local ok, err = pcall(function()
            commodity.GoodsPurchaseCompleted:Connect(function(goodsId, goodsNum, player)
                self:OnGoodsPurchaseCompleted(goodsId, goodsNum, player)
            end)
        end)
        if not ok then print('[MgrPlatform] 订阅购买完成信号失败', tostring(err)) end
    else
        print('[MgrPlatform] CommodityService 不可用，平台购买入口全部降级为不可用')
    end
    _G.REUtil:GetRE('PlatformAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'PlatformAction', cfg().ActionCooldownSec) then return end
        self:HandleAction(player, payload)
    end)
    _G.REUtil:GetRE('PlatformTestAction').OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'PlatformTestAction', 0.2) then return end
        self:HandleTestAction(player, payload)
    end)
end

return Mgr
