-- #149 T28 全服纪录服务：把「上岸」这一游戏事实汇总成每个鱼种的全服最大重量与保持者。
-- 与「个人最大重量」（#133 的 extra.collection.weights）是两套数据，这里只加全服那一层，不重造个人图鉴。
--
-- 一致性：候选写成 { w = 放大整数, u = UserID, n = 显示名 } 三元组，一次 CAS 同时落地，
-- 读也只读整条三元组——所以「重量更新了、名字还是旧的」在结构上不可能出现，
-- 不需要靠刷新顺序或重试去补救。
--
-- 写频：上岸只入队（NoteLanding），按 FlushIntervalSec 的窗口合并，一个窗口内同鱼种最多一次写；
-- 缓存里已知更强的纪录时连写请求都不发（纪录只涨不跌，缓存值一定是下界）。
--
-- 重试：写失败按 RetryDelaySec 退避重试，重试**重新走一次 CAS**而不是重放旧字节流，
-- 所以退避期间别的服务器刷新了更大的纪录时，过期候选自动落选，不会盖掉新纪录。
--
-- 降级：读失败时保留上一次可信值并标 stale；从没读到过就报 'unavailable'，
-- 既不显示假数字，也不把「读不到」说成「没有纪录」。
local GameCfg = require('common.GameCfg')
local Records = require('common.Records')
local Adapter = require('server.Data.RecordsAdapter')

local Mgr = {
    Adapter = Adapter,         -- 可替换：测试与本地假实现注入这里
    Cache = {},                -- fishId -> { entry = 三元组或 nil, at = 秒, failed = 错误类别或 nil }
    Pending = {},              -- fishId -> { entry = 待写候选, attempts = 已失败次数, dueAt = 秒, Writing = 飞行中 }
    Reading = {},              -- fishId -> 等待同一鱼种读结果的回调表（并发读合并成一次）
    LastSeq = {},              -- player.UserId -> 已受理的最大请求序号
    Stats = { Writes = 0, Merged = 0, Failures = 0, Retries = 0, Dropped = 0, Rejected = 0 },
}

local function cfg() return GameCfg.Records end
local function task() return game:GetService('Task') end

local function now()
    local ok, value = pcall(function() return game:GetService('World'):GetServerTime() end)
    return ok and tonumber(value) or 0
end

local function validPlayerId(player)
    local userId = player and player.UserId
    return Records.ValidUserId(userId)
end

local function reject(self, player, fishId, detail, reason)
    self.Stats.Rejected = self.Stats.Rejected + 1
    print('[MgrRecords] 全服纪录拒收', player and player.UserId, tostring(fishId), detail, tostring(reason))
    return false, reason
end

-- 上岸事实入队。上船的唯一写入口就是这里，所以盲盒/抽奖/击杀都提交不了纪录：
-- 没有「直接提交一条纪录」的接口，只有「某玩家某鱼种上了岸、个体重量多少」。
function Mgr:NoteLanding(player, fishId, weight)
    if type(fishId) ~= 'string' or not GameCfg.Fish[fishId] then
        return reject(self, player, fishId, 'unknown-fish', 'fish')
    end
    if not validPlayerId(player) then
        return reject(self, player, fishId, 'bad-player', 'player')
    end
    local scaled, reason = Records.Scale(weight)
    if not scaled then
        return reject(self, player, fishId, 'weight=' .. tostring(weight), reason)
    end
    local entry = Records.Entry(scaled, player.UserId, player.Name)
    if not entry then return reject(self, player, fishId, 'entry', 'invalid') end
    local pending = self.Pending[fishId]
    if pending and pending.entry then
        -- 合并：窗口内只留更强的那条候选，较弱的那次上岸不产生写
        self.Stats.Merged = self.Stats.Merged + 1
        if Records.Wins(entry, pending.entry) then pending.entry = entry end
        return true, 'merged'
    end
    if pending then
        -- 上一次写还在飞：这条候选取代（或强化）飞行中的那条，落地下次窗口再发
        pending.entry, pending.attempts = entry, 0
        pending.dueAt = now() + cfg().FlushIntervalSec
        return true, 'queued'
    end
    self.Pending[fishId] = { entry = entry, attempts = 0, dueAt = now() + cfg().FlushIntervalSec }
    return true, 'queued'
end

function Mgr:Update()
    local current = now()
    for fishId, pending in pairs(self.Pending) do
        if pending.entry and current >= pending.dueAt then self:Flush(fishId) end
    end
end

function Mgr:CacheSet(fishId, entry, failed)
    self.Cache[fishId] = { entry = Records.Valid(entry), at = now(), failed = failed }
end

-- 缓存是否新鲜：有值用 HolderCacheTtlSec，没值（暂无纪录或读失败）用更短的 MissCacheTtlSec
function Mgr:Fresh(cached)
    local age = now() - (cached.at or 0)
    if cached.failed or not cached.entry then return age < cfg().MissCacheTtlSec end
    return age < cfg().HolderCacheTtlSec
end

-- 把一条候选交给平台（CAS）。飞行期间新到的候选写进 pending.entry，落地后下个窗口再发。
function Mgr:Flush(fishId)
    local pending = self.Pending[fishId]
    if not pending or not pending.entry or pending.Writing then return end
    local entry = pending.entry
    pending.entry = nil
    local cached = self.Cache[fishId]
    if cached and not cached.failed and not Records.Wins(entry, cached.entry) then
        -- 缓存里的现有纪录更强：直接丢弃候选，一个写请求都不发
        if not pending.entry then self.Pending[fishId] = nil end
        return
    end
    pending.Writing = true
    task():Spawn(function()
        local ok, won, saved, kind = self.Adapter:Submit(fishId, function(current)
            if not Records.Wins(entry, current) then return nil end
            return entry
        end)
        pending.Writing = false
        if ok then
            self.Stats.Writes = self.Stats.Writes + (won and 1 or 0)
            pending.attempts = 0
            if saved then self:CacheSet(fishId, saved, nil) end
            if pending.entry then
                pending.dueAt = now() + cfg().FlushIntervalSec
            else
                self.Pending[fishId] = nil
            end
            return
        end
        self.Stats.Failures = self.Stats.Failures + 1
        pending.attempts = pending.attempts + 1
        if not pending.entry or Records.Wins(entry, pending.entry) then pending.entry = entry end
        if pending.attempts > cfg().MaxRetries then
            self.Stats.Dropped = self.Stats.Dropped + 1
            self.Pending[fishId] = nil
            print('[MgrRecords] 全服纪录提交放弃（重试耗尽）', fishId, entry.w, entry.u, tostring(kind))
            return
        end
        self.Stats.Retries = self.Stats.Retries + 1
        pending.dueAt = now() + cfg().RetryDelaySec
        print('[MgrRecords] 全服纪录提交失败，稍后重试', fishId, entry.w, entry.u, tostring(kind))
    end)
end

-- 只读缓存，不发 I/O：图鉴渲染用。三种状态互不等价，调用方必须分开处理。
function Mgr:State(fishId)
    local cached = self.Cache[fishId]
    if not cached then return { state = 'unavailable', fishId = fishId, error = 'cold' } end
    if cached.entry then
        local state = Records.State(cached.entry)
        state.fishId, state.stale = fishId, cached.failed ~= nil
        return state
    end
    if cached.failed then return { state = 'unavailable', fishId = fishId, error = cached.failed } end
    return { state = 'missing', fishId = fishId }
end

-- 读一条鱼的全服纪录：缓存内直接回；过期走适配器；同一鱼种的并发读合并成一次平台调用。
-- 读失败时保留上一次可信值（标 stale），没有可信值就报 'unavailable'——不显示伪纪录。
function Mgr:Read(fishId, done)
    if type(fishId) ~= 'string' or not GameCfg.Fish[fishId] then
        if done then done({ state = 'unavailable', fishId = fishId, error = 'unknown-fish' }) end
        return
    end
    local cached = self.Cache[fishId]
    if cached and self:Fresh(cached) then
        if done then done(self:State(fishId)) end
        return
    end
    local waiting = self.Reading[fishId]
    if waiting then
        if done then waiting[#waiting + 1] = done end
        return
    end
    self.Reading[fishId] = done and { done } or {}
    task():Spawn(function()
        local ok, entry, kind = self.Adapter:Read(fishId)
        local waiters = self.Reading[fishId] or {}
        self.Reading[fishId] = nil
        if ok then
            self:CacheSet(fishId, entry, nil)
        else
            local previous = self.Cache[fishId]
            -- 已有可信值：留着并标 failed（展示为 stale），不要用一个读失败把纪录抹掉
            self:CacheSet(fishId, previous and previous.entry or nil, kind)
            print('[MgrRecords] 全服纪录读取失败', fishId, tostring(kind))
        end
        local state = self:State(fishId)
        for _, callback in ipairs(waiters) do callback(state) end
    end)
end

function Mgr:OnPlayerRemoving(player)
    if player then self.LastSeq[player.UserId] = nil end
end

-- #149 T28：图鉴查询协议。客户端只给 { fishId, seq }，回包一律以服务端真实读到的状态为准：
-- 读到什么回什么（含 'unavailable'），绝不回客户端臆造或本地缓存里已经过期的「确定值」。
-- seq 单调递增才受理：重放/乱序的旧包不产生第二次回包。
function Mgr:Handle(player, payload)
    if not validPlayerId(player) or type(payload) ~= 'table' then return end
    local fishId, seq = payload.fishId, payload.seq
    if type(seq) ~= 'number' or seq ~= math.floor(seq) or seq < 1 or seq > 2147483647 then return end
    local last = self.LastSeq[player.UserId]
    if last and seq <= last then return end
    self.LastSeq[player.UserId] = seq
    self:Read(fishId, function(state)
        state.seq = seq
        self:Reconcile(player, state)
        local re = _G.REUtil and _G.REUtil:GetRE('RecordsState')
        if re then re:FireClient(player, state) end
    end)
end

-- 查询触发的对账：玩家个人最大重量高于刚读到的全服纪录时（上一次提交被平台失败丢掉、
-- 或换服重进后本服缓存还没热），补交一次。补交同样走 NoteLanding + CAS：
-- 只可能比当前纪录更高才补，且落地时重新和平台最新值比一次，所以不会用过期候选盖新纪录。
-- 平台读不到（unavailable）时不补：连当前纪录都不知道，不猜、不写。
function Mgr:Reconcile(player, state)
    if state.state == 'unavailable' then return end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local best = data and data.PersonalBestScaled and data:PersonalBestScaled(state.fishId)
    if not best then return end
    if state.state == 'ok' and best <= state.scaled then return end
    self:NoteLanding(player, state.fishId, Records.Unscale(best))
end

function Mgr:Start()
    local re = _G.REUtil:GetRE('RecordsRequest')
    re.OnServerEvent:Connect(function(player, payload)
        if _G.REUtil:CheckRECD(player, 'RecordsRequest', cfg().RequestCooldownSec) then return end
        self:Handle(player, payload)
    end)
end

return Mgr
