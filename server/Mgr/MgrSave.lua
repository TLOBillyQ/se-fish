-- 存档管理器（#92 / #115）：普通写经 Enqueue 串行合并；GM 显式读写在同一玩家队列排空后执行。
-- 同一玩家只保留最新快照（合并），单 Task 串行排空（消乱序：旧 SetAsync 不会盖过新 Commit）。
-- Load 由调用方包 Task:Spawn（LoadInto 已包）。失败按 GameCfg.Save 退避重试，重试耗尽只记日志、
-- 不动内存态（内存比存档新）。兑换/收船票等关键状态转换走 Commit（UpdateAsync CAS 记账），断线
-- 重连不双份发奖；普通快照走 Save（SetAsync）。Ledger 记每人写入次数与最近体积（验收③台账，
-- 跨离场保留是有意的，便于观察整局写入量）；DataStore 不可用（如未发布环境）时整模块退化为
-- 纯内存，不影响游戏。周期自动存档（Update）、关服兜底（Start 里 BindToClose 全员落档）。
local GameCfg = require('common.GameCfg')

local Mgr = { Ledger = {}, Pending = {}, Flying = {}, Sessions = {}, Waiters = {}, NextAutosaveAt = nil }

local function cfg()
    return GameCfg.Save
end

local function task()
    return game:GetService('Task')
end

function Mgr:Key(userId)
    if not self.SlotPinned then
        local slot = cfg().AcceptanceSlot
        assert(slot == nil or slot == '' or
            (type(slot) == 'string' and #slot <= 40 and slot:match('^[%w_-]+$')),
            '验收存档槽须为 1—40 位字母、数字、下划线或连字符')
        self.AcceptanceSlot = slot or ''
        self.SlotPinned = true
    end
    local key = cfg().KeyPrefix .. tostring(userId)
    local session = self.Sessions[userId]
    local slot = session and session.Current or self.AcceptanceSlot
    if slot == '' then return key end
    return key .. ':qa:' .. slot
end

local function validSlot(slot)
    return type(slot) == 'string' and #slot >= 1 and #slot <= 40 and slot:match('^[%w_-]+$') ~= nil
end

function Mgr:Session(userId)
    self:Key(userId)
    if not self.Sessions[userId] then
        self.Sessions[userId] = { Current = self.AcceptanceSlot, Next = self.AcceptanceSlot, Paused = false }
    end
    return self.Sessions[userId]
end

function Mgr:Status(userId)
    local session = self:Session(userId)
    return { currentSlot = session.Current, nextSlot = session.Next, autosavePaused = session.Paused }
end

function Mgr:IsPaused(userId)
    local session = self.Sessions[userId]
    return session and (session.Paused or session.Transition) or false
end

function Mgr:AfterIdle(userId, fn)
    if not self.Flying[userId] then fn() return end
    self.Waiters[userId] = self.Waiters[userId] or {}
    self.Waiters[userId][#self.Waiters[userId] + 1] = fn
end

function Mgr:Finish(userId)
    self.Flying[userId] = nil
    local callbacks = self.Waiters[userId] or {}
    self.Waiters[userId] = nil
    for _, fn in ipairs(callbacks) do fn() end
end

-- 取 DataStore；服务都没有时不走重试（谈不上限流），缓存结论避免刷屏
function Mgr:GetStore()
    if self.StoreChecked then return self.Store end
    self.StoreChecked = true
    local ok, store = pcall(function()
        return game:GetService('DataStoreService'):GetDataStore(cfg().Store)
    end)
    if not ok or not store then
        print('[MgrSave] DataStore 不可用，退化为纯内存', tostring(store))
        self.Store = nil
        return nil
    end
    self.Store = store
    return store
end

-- 同步重试执行；调用方须在允许 yield 的上下文（排空循环内）。返回 ok, 结果
function Mgr:WithRetry(label, fn)
    local maxTries = cfg().MaxRetries
    for attempt = 1, maxTries do
        local ok, result = pcall(fn)
        if ok then return true, result end
        print('[MgrSave]', label, '失败（第' .. tostring(attempt) .. '/' .. tostring(maxTries) .. '次）', tostring(result))
        if attempt < maxTries then task():Wait(cfg().RetryDelaySec) end
    end
    return false, nil
end

function Mgr:Load(userId)
    local store = self:GetStore()
    if not store then return nil end
    local ok, value = self:WithRetry('读档 ' .. tostring(userId), function()
        return store:GetAsync(self:Key(userId))
    end)
    if not ok or value == nil then
        if ok then print('[MgrSave] 无存档，新档开局', userId) end
        return nil
    end
    print('[MgrSave] 读档成功', userId)
    return value
end

-- 递归粗估字节数：字符串按长度、数字 8、其他 1、表每键值 2 开销（台账口径，不是精确编码）
function Mgr:EstimateSize(t)
    local kind = type(t)
    if kind == 'string' then return #t end
    if kind == 'number' then return 8 end
    if kind ~= 'table' then return 1 end
    local total = 2
    for k, v in pairs(t) do
        total = total + self:EstimateSize(k) + self:EstimateSize(v) + 2
    end
    return total
end

function Mgr:NoteWrite(userId, bytes, reason, label)
    local ledger = self.Ledger[userId] or { Writes = 0 }
    ledger.Writes = ledger.Writes + 1
    ledger.Bytes = bytes
    ledger.LastReason = reason
    self.Ledger[userId] = ledger
    print('[MgrSave]', label, userId, reason, 'bytes=' .. tostring(bytes), 'writes=' .. tostring(ledger.Writes))
end

-- 写入口：同一玩家只保留最新 job（旧快照作废），单 Task 排空保证按入队顺序落账。
-- mode 'set' 用 SetAsync，'update' 用 UpdateAsync CAS（关键记账）。返回是否受理。
function Mgr:Enqueue(userId, snapshot, reason, mode)
    local session = self.Sessions[userId]
    if session and (session.Paused or session.Transition) then return false end
    if not self:GetStore() or type(snapshot) ~= 'table' then return false end
    self.Pending[userId] = {
        Snapshot = snapshot,
        Reason = reason,
        Mode = mode,
        Bytes = self:EstimateSize(snapshot),
        Key = self:Key(userId),
    }
    if not self.Flying[userId] then
        self.Flying[userId] = true
        task():Spawn(function()
            while self.Pending[userId] do
                local job = self.Pending[userId]
                self.Pending[userId] = nil
                local label = (job.Mode == 'update' and '记账 ' or '存档 ') .. tostring(userId) .. ' ' .. tostring(job.Reason)
                local ok = self:WithRetry(label, function()
                    if job.Mode == 'update' then
                        self.Store:UpdateAsync(job.Key, function() return job.Snapshot end)
                    else
                        self.Store:SetAsync(job.Key, job.Snapshot)
                    end
                end)
                if ok then
                    self:NoteWrite(userId, job.Bytes, job.Reason, job.Mode == 'update' and '记账落账' or '存档')
                else
                    -- 重试耗尽：内存态比存档新，丢这次写不影响当局；下一笔写仍会带上最新快照
                    print('[MgrSave] 写档放弃，内存态保留', userId, job.Reason)
                end
            end
            self:Finish(userId)
        end)
    end
    return true
end

-- 挡住新自动写入，等旧队列（含在途请求）排空后再改本局状态。
function Mgr:ApplyTemporary(userId, data, patch, done)
    local session = self:Session(userId)
    if session.Transition then
        done(false, '存档操作进行中')
        return false, '存档操作进行中'
    end
    session.Transition = true
    local accepted, failure = true, nil
    self:AfterIdle(userId, function()
        local ok, reason = data:ApplyGMPatch(patch)
        accepted, failure = ok, reason
        if ok then session.Paused = true end
        session.Transition = false
        done(ok, reason)
    end)
    return accepted, failure
end

function Mgr:SaveExplicit(userId, data, done)
    local session = self:Session(userId)
    if session.Transition then return false, '存档操作进行中' end
    session.Transition = true
    local key = self:Key(userId)
    local requestedSnapshot = data:Serialize()
    self:AfterIdle(userId, function()
        self.Flying[userId] = true
        task():Spawn(function()
            local store = self:GetStore()
            local ok, reason = false, '存档写入失败或服务不可用'
            for _ = 1, 3 do
                local snapshot = data.Inited and data:Serialize() or requestedSnapshot
                local revision = data.Revision
                if not store or not snapshot then break end
                local written = self:WithRetry('GM 保存 ' .. tostring(userId), function()
                    store:SetAsync(key, snapshot)
                end)
                if not written then break end
                self:NoteWrite(userId, self:EstimateSize(snapshot), 'gm', '存档')
                if not data.Inited or data.Revision == revision then
                    ok = true
                    break
                end
                reason = '保存期间本局状态持续变化，请重试'
            end
            if ok then
                session.Paused = false
            else
                session.Paused = true
            end
            session.Transition = false
            self:Finish(userId)
            done(ok, ok and nil or reason)
        end)
    end)
    return true
end

function Mgr:ReadExplicit(userId, data, done)
    local session = self:Session(userId)
    if session.Transition then return false, '存档操作进行中' end
    session.Transition = true
    local key = self:Key(userId)
    self:AfterIdle(userId, function()
        self.Flying[userId] = true
        task():Spawn(function()
            local store = self:GetStore()
            local revision = data.Revision
            local ok, value = false, nil
            if store then
                ok, value = self:WithRetry('GM 读取 ' .. tostring(userId), function()
                    return store:GetAsync(key)
                end)
            end
            local valid = ok and value ~= nil and data.Inited
                and data.Revision == revision and data:IsValidSave(value)
            if valid then data:ApplySave(value) end
            session.Transition = false
            self:Finish(userId)
            done(valid or false, not valid and (not store and '存档服务不可用'
                or not ok and '读取失败' or value == nil and '当前槽没有存档'
                or data.Revision ~= revision and '读取期间本局状态已变化' or '存档数据无效') or nil)
        end)
    end)
    return true
end

function Mgr:SelectNextSlot(userId, slot, done)
    if slot ~= '' and not validSlot(slot) then return false, '存档槽须为 1—40 位字母、数字、下划线或连字符' end
    local session = self:Session(userId)
    if session.SlotChoosing then return false, '存档槽选择进行中' end
    local store = self:GetStore()
    if not store then return false, '存档服务不可用' end
    session.SlotChoosing = true
    task():Spawn(function()
        local ok = self:WithRetry('GM 槽选择 ' .. tostring(userId), function()
            store:SetAsync(cfg().KeyPrefix .. tostring(userId) .. ':gm-slot', slot)
        end)
        if ok then session.Next = slot end
        session.SlotChoosing = false
        local waiters = session.SlotWaiters or {}
        session.SlotWaiters = nil
        for _, callback in ipairs(waiters) do callback() end
        done(ok, ok and nil or '存档槽选择未保存')
    end)
    return true
end

function Mgr:ReleaseSession(userId)
    self.Sessions[userId] = nil
end

function Mgr:Save(userId, snapshot, reason)
    return self:Enqueue(userId, snapshot, reason, 'set')
end

-- 记账式落账（UpdateAsync CAS）：兑换/船票等关键状态转换后立即调用；进队列异步执行不阻塞结算。
-- transform 直接返回最新快照：单人单键、本服务器唯一写入者，CAS 重算时仍取同一快照。
function Mgr:Commit(userId, snapshot, reason)
    return self:Enqueue(userId, snapshot, reason, 'update')
end

-- 进图异步恢复：读到存档就灌入并推送栏位；没有存档保持 InitialGrants 开局，不额外推送。
-- 读档期间玩家已操作（Touched，见 PlayerData:UpdateData）则跳过旧档覆盖，避免吞掉进图后的动作。
function Mgr:LoadInto(player, data)
    local userId = player.UserId
    local previous = self.Sessions[userId]
    local session = { Current = self.AcceptanceSlot or cfg().AcceptanceSlot or '',
        Next = self.AcceptanceSlot or cfg().AcceptanceSlot or '', Paused = false, Transition = true }
    self.Sessions[userId] = session
    local function load()
        task():Spawn(function()
            self:AfterIdle(userId, function()
                local store = self:GetStore()
                if store then
                    local ok, slot = self:WithRetry('读取槽选择 ' .. tostring(userId), function()
                        return store:GetAsync(cfg().KeyPrefix .. tostring(userId) .. ':gm-slot')
                    end)
                    if ok and validSlot(slot) then session.Current, session.Next = slot, slot end
                    if ok and slot == '' then session.Current, session.Next = '', '' end
                end
                if not data.Inited then return end
                local snapshot = self:Load(userId)
                session.Transition = false
                if not snapshot or not data.Inited then return end
                if data.Touched then
                    print('[MgrSave] 读档期间已有操作，跳过旧档覆盖', userId)
                    return
                end
                if data:ApplySave(snapshot) then
                    if self.PlayerData then self.PlayerData:SendItemBar(player) end
                    print('[MgrSave] 恢复完成', userId)
                end
            end)
        end)
    end
    if previous and previous.SlotChoosing then
        previous.SlotWaiters = previous.SlotWaiters or {}
        previous.SlotWaiters[#previous.SlotWaiters + 1] = load
    else
        load()
    end
end

-- 离场兜底落档：先取快照再入队（PlayerRemoving 事件回调里不允许 yield，DataStore 全异步）
function Mgr:SaveLeaving(player, data)
    if not data or not data.Inited then return end
    local snapshot = data:Serialize()
    if not snapshot then return end
    self:Save(player.UserId, snapshot, 'leave')
end

-- 周期自动存档：每 AutosaveSec 给在线玩家拍快照入队（入队自带合并，频繁写只会留最新）
function Mgr:Update()
    local interval = cfg().AutosaveSec
    if not interval or interval <= 0 then return end
    local now = game:GetService('World'):GetServerTime()
    if not self.NextAutosaveAt then
        self.NextAutosaveAt = now + interval
        return
    end
    if now < self.NextAutosaveAt then return end
    self.NextAutosaveAt = now + interval
    if not self.PlayerData then return end
    for _, player in ipairs(game:GetService('Players'):GetPlayers()) do
        local data = self.PlayerData:GetDataInst(player)
        if data and data.Inited then
            self:Save(player.UserId, data:Serialize(), 'autosave')
        end
    end
end

-- 关服兜底：引擎关服前回调（最长等 30 秒），全员落档 + 排空剩余队列
function Mgr:Start()
    local ok, err = pcall(function()
        game:BindToClose(function()
            if self.PlayerData then
                for _, player in ipairs(game:GetService('Players'):GetPlayers()) do
                    local data = self.PlayerData:GetDataInst(player)
                    if data and data.Inited then
                        self:Save(player.UserId, data:Serialize(), 'shutdown')
                    end
                end
            end
        end)
    end)
    if not ok then print('[MgrSave] BindToClose 不可用，跳过关服兜底', tostring(err)) end
end

return Mgr
