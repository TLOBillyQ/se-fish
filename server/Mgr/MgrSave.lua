-- #123：读档失败关闭入口；全部玩家键写入校验持久会话和修订，关键操作与结果同键落账。
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')
local Mgr = { Ledger = {}, Pending = {}, Flying = {}, Sessions = {}, Waiters = {}, NextAutosaveAt = nil }
local function cfg() return GameCfg.Save end
local function task() return game:GetService('Task') end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function callback(label, userId, fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then print('[MgrSave] 回调失败', label, userId, tostring(err)) end
end
local function validSlot(slot)
    return type(slot) == 'string' and #slot >= 1 and #slot <= 40 and slot:match('^[%w_-]+$') ~= nil
end
function Mgr:Key(userId)
    if not self.SlotPinned then
        local slot = cfg().AcceptanceSlot
        assert(slot == nil or slot == '' or validSlot(slot), '验收存档槽须为 1—40 位字母、数字、下划线或连字符')
        self.AcceptanceSlot, self.SlotPinned = slot or '', true
    end
    local session = self.Sessions[userId]
    local slot = session and session.Current or self.AcceptanceSlot
    return cfg().KeyPrefix .. tostring(userId) .. (slot ~= '' and ':qa:' .. slot or '')
end
function Mgr:Session(userId)
    self:Key(userId)
    if not self.Sessions[userId] then
        self.Sessions[userId] = { Current = self.AcceptanceSlot, Next = self.AcceptanceSlot, Paused = false }
    end
    return self.Sessions[userId]
end
function Mgr:Status(userId)
    local s = self:Session(userId)
    return { currentSlot = s.Current, nextSlot = s.Next, autosavePaused = s.Paused,
        loadState = s.State or 'pending', error = s.Error, revision = s.Revision, epoch = s.Epoch }
end
function Mgr:IsPaused(userId)
    local s = self.Sessions[userId]
    return not s or s.State ~= 'ready' or s.Paused or s.Transition or false
end
function Mgr:IsCurrent(userId, session, data)
    return self.Sessions[userId] == session and session.Data == data and data.Player == session.Player
end
function Mgr:Fail(userId, session, reason)
    if self.Sessions[userId] ~= session then return end
    session.State, session.Error = 'failed', reason
    if session.Data then
        session.Data.LoadState, session.Data.Inited = 'failed', false
        if session.Data.Player then session.Data.Player:SetAttribute('SaveState', 'failed') end
    end
    print('[MgrSave] 读写屏障关闭', userId, tostring(session.Token), reason)
end
function Mgr:AfterIdle(userId, fn)
    if not self.Flying[userId] and not self.Pending[userId] then callback('AfterIdle', userId, fn) return end
    self.Waiters[userId] = self.Waiters[userId] or {}
    table.insert(self.Waiters[userId], fn)
end
function Mgr:Finish(userId)
    self.Flying[userId] = nil
    if self.Pending[userId] then
        -- 仅重试等待才会留下队首；失败后的显式请求仍需收到结果。
        if self.Pending[userId].RetryRounds then return end
        self:Drain(userId)
        return
    end
    local callbacks = self.Waiters[userId] or {}
    self.Waiters[userId] = nil
    for _, fn in ipairs(callbacks) do callback('AfterIdle', userId, fn) end
end
function Mgr:GetStore()
    if self.StoreChecked then return self.Store end
    self.StoreChecked = true
    local ok, store = pcall(function() return game:GetService('DataStoreService'):GetDataStore(cfg().Store) end)
    if not ok or not store then
        print('[MgrSave] DataStore 不可用，保持读档失败屏障', tostring(store))
        return nil
    end
    self.Store = store
    return store
end
function Mgr:WithRetry(label, fn)
    for attempt = 1, cfg().MaxRetries do
        local ok, value = pcall(fn)
        if ok then return true, value end
        print('[MgrSave]', label, '失败', attempt, tostring(value))
        if attempt < cfg().MaxRetries then task():Wait(cfg().RetryDelaySec) end
    end
    return false, nil
end
function Mgr:Load(userId)
    local store = self:GetStore()
    if not store then return nil, 'failed' end
    local key = self:Key(userId)
    local ok, value = self:WithRetry('读档 ' .. tostring(userId), function() return store:GetAsync(key) end)
    if not ok then return nil, 'failed' end
    return value, value == nil and 'missing' or 'found'
end
function Mgr:EstimateSize(value)
    if type(value) == 'string' then return #value end
    if type(value) == 'number' then return 8 end
    if type(value) ~= 'table' then return 1 end
    local total = 2
    for k, v in pairs(value) do total = total + self:EstimateSize(k) + self:EstimateSize(v) + 2 end
    return total
end
function Mgr:WithinBudget(snapshot)
    -- 粗估不是精确 JSON 字节数；留足余量，实际平台上限仍以真 DataStore 回包为准。
    return self:EstimateSize(snapshot) <= 256 * 1024
end
function Mgr:NoteWrite(userId, snapshot, reason)
    local ledger = self.Ledger[userId] or { Writes = 0 }
    ledger.Writes, ledger.Bytes = ledger.Writes + 1, self:EstimateSize(snapshot)
    ledger.LastReason, ledger.Revision = reason, snapshot.meta.revision
    ledger.OperationCount = #snapshot.meta.operations
    self.Ledger[userId] = ledger
    print('[MgrSave] 落账', userId, reason, 'revision=' .. ledger.Revision,
        'bytes=' .. ledger.Bytes, 'writes=' .. ledger.Writes, 'ops=' .. ledger.OperationCount)
end

function Mgr:LoadInto(player, data)
    local userId = player.UserId
    local previous = self:Session(userId)
    if previous.Data and previous.Data ~= data then
        previous.Data.Inited, previous.Data.LoadState = false, 'stale'
    end
    self.Counter = (self.Counter or 0) + 1
    local s = { Current = self.AcceptanceSlot, Next = self.AcceptanceSlot, Paused = false,
        State = 'pending', Player = player, Data = data,
        Token = tostring(userId) .. ':' .. tostring(self.Counter) .. ':' .. tostring({}) .. ':' .. tostring(math.random()) }
    self.Sessions[userId] = s
    data.Inited, data.LoadState = false, 'pending'
    player:SetAttribute('SaveState', 'pending')
    local function load()
        task():Spawn(function()
            if not self:IsCurrent(userId, s, data) then return end
            local store = self:GetStore()
            if not store then self:Fail(userId, s, '存档服务不可用') return end
            local okSlot, slot = self:WithRetry('读取槽选择 ' .. userId, function()
                return store:GetAsync(cfg().KeyPrefix .. userId .. ':gm-slot')
            end)
            if not self:IsCurrent(userId, s, data) then return end
            if not okSlot or slot ~= nil and slot ~= '' and not validSlot(slot) then
                self:Fail(userId, s, '槽选择读取失败或损坏') return
            end
            if slot ~= nil then s.Current, s.Next = slot, slot end
            s.Key = self:Key(userId)
            local loaded, status = self:Load(userId)
            if not self:IsCurrent(userId, s, data) then return end
            if status == 'failed' then self:Fail(userId, s, '读取失败，不初始化新档') return end
            local candidate, reason
            if loaded == nil then
                local fresh = PlayerData.New({ UserId = userId, SetAttribute = function() end })
                fresh:Init()
                candidate = fresh:Serialize()
            else
                candidate, reason = data:Migrate(loaded)
            end
            if not candidate then self:Fail(userId, s, reason) return end
            if not self:WithinBudget(candidate) then self:Fail(userId, s, '存档容量超预算') return end
            local ok, claimed = self:WithRetry('认领会话 ' .. userId, function()
                return store:UpdateAsync(s.Key, function(current)
                    if not self:IsCurrent(userId, s, data) then return nil end
                    if current and current.meta and current.meta.session == s.Token then return current end
                    if not equal(current, loaded) then return nil end
                    local nextValue = copy(candidate)
                    nextValue.meta.epoch = nextValue.meta.epoch + 1
                    nextValue.meta.revision = nextValue.meta.revision + 1
                    nextValue.meta.session = s.Token
                    return nextValue
                end)
            end)
            if not self:IsCurrent(userId, s, data) then return end
            if not ok or not claimed or claimed.meta.session ~= s.Token then
                self:Fail(userId, s, '会话认领失败或版本冲突') return
            end
            s.State, s.Revision, s.Epoch = 'ready', claimed.meta.revision, claimed.meta.epoch
            if not data:CompleteLoad(claimed) then self:Fail(userId, s, '恢复数据无效') return end
            self:NoteWrite(userId, claimed, status == 'missing' and 'new' or 'load')
            player:SetAttribute('SaveState', 'ready')
            print('[MgrSave] ready', userId, s.Token, 'coin=' .. claimed.coin, 'sequence=' .. claimed.meta.sequence)
            if self.PlayerData then self.PlayerData:SendItemBar(player) end
            if self.OnReady then self.OnReady(player, data) end
        end)
    end
    if previous.SlotChoosing then
        previous.SlotWaiters = previous.SlotWaiters or {}
        table.insert(previous.SlotWaiters, load)
    else load() end
end

-- 每个 job 的写身份在重试间固定；即使写成功而回包丢失，也只认可同一次结果。
function Mgr:WriteJob(userId, job)
    local s = job.Session
    if self.Sessions[userId] ~= s then return false, 'stale' end
    if not job.BaseRevision then
        job.BaseRevision = s.Revision
        job.Snapshot.meta.revision = s.Revision + 1
        job.Snapshot.meta.epoch, job.Snapshot.meta.session = s.Epoch, s.Token
        s.WriteSequence = (s.WriteSequence or 0) + 1
        job.Id = s.Token .. ':write:' .. s.WriteSequence
        job.Snapshot.meta.write = job.Id
    end
    local ok, value = self:WithRetry('写档 ' .. userId .. ' ' .. job.Reason, function()
        return self.Store:UpdateAsync(job.Key, function(current)
            if self.Sessions[userId] ~= s then return nil end
            if type(current) ~= 'table' or type(current.meta) ~= 'table'
                or current.meta.session ~= s.Token or current.meta.epoch ~= s.Epoch then return nil end
            if current.meta.write == job.Id then return current end
            if current.meta.revision ~= job.BaseRevision then return nil end
            return copy(job.Snapshot)
        end)
    end)
    if self.Sessions[userId] ~= s then return false, 'stale' end
    if not ok then return false, 'retry' end
    if not value or not value.meta or value.meta.write ~= job.Id then
        self:Fail(userId, s, '写入会话或修订冲突')
        return false, 'conflict'
    end
    s.Revision = value.meta.revision
    if s.Data and s.Data.Player == s.Player then s.Data.SaveMeta = copy(value.meta) end
    self:NoteWrite(userId, value, job.Reason)
    return true, value
end
local function appendJob(current, job)
    if not current then return job end
    if not current.BaseRevision and not current.Done and not current.After then return job end
    local last = current
    while last.After do last = last.After end
    last.After = job
    return current
end
function Mgr:Drain(userId)
    if self.Flying[userId] then return end
    self.Flying[userId] = true
    task():Spawn(function()
        while self.Pending[userId] do
            local job = self.Pending[userId]
            self.Pending[userId] = nil
            local ok, result = self:WriteJob(userId, job)
            if not ok and result == 'retry' and not job.NoRetry then
                job.RetryRounds = (job.RetryRounds or 0) + 1
                if job.RetryRounds <= 3 then
                    if self.Pending[userId] then job.After = appendJob(job.After, self.Pending[userId]) end
                    self.Pending[userId] = job
                    break
                end
                print('[MgrSave] 写档重试耗尽，关闭会话', userId, job.Reason)
                self:Fail(userId, job.Session, '写档重试耗尽')
            end
            callback('写入结果', userId, job.Done, ok, result)
            if not ok and result == 'retry' and job.Session.State == 'failed' then
                local current = job.After
                while current do
                    callback('后续写入取消', userId, current.Done, false, '写档失败')
                    current = current.After
                end
                self.Pending[userId] = nil
                break
            end
            if job.After then self.Pending[userId] = appendJob(job.After, self.Pending[userId]) end
        end
        self:Finish(userId)
    end)
end
function Mgr:Enqueue(userId, snapshot, reason, done)
    local s = self.Sessions[userId]
    if not s or s.State ~= 'ready' or s.Paused or s.Transition or not self:GetStore()
        or not s.Data or not s.Data.Inited or not snapshot or not s.Data:IsValidSave(snapshot)
        or not self:WithinBudget(snapshot) or snapshot.meta.session ~= s.Token then return false end
    local job = { Session = s, Key = s.Key, Snapshot = copy(snapshot), Reason = reason or 'save', Done = done,
        NoRetry = reason == 'gm' }
    self.Pending[userId] = appendJob(self.Pending[userId], job)
    self:Drain(userId)
    return true
end
function Mgr:Save(userId, snapshot, reason) return self:Enqueue(userId, snapshot, reason) end
-- 兼容旧调用点：只承诺快照 CAS，不把事后快照包装成跨会话幂等结算。
function Mgr:Commit(userId, snapshot, reason) return self:Enqueue(userId, snapshot, reason) end

function Mgr:ResolveRequest(player, data, kind, requestId)
    local userId = player and player.UserId
    local s = userId and self.Sessions[userId]
    if not s or not self:IsCurrent(userId, s, data) or s.State ~= 'ready'
        or type(kind) ~= 'string' or #kind < 1 or #kind > 80 then return nil, 'invalid' end
    local requestKey
    if type(requestId) == 'number' and requestId == math.floor(requestId)
        and requestId >= 1 and requestId <= 2147483647 then
        requestKey = s.Token .. ':' .. kind .. ':' .. requestId
    elseif type(requestId) == 'table' and type(requestId.requestKey) == 'string'
        and type(requestId.id) == 'string' and type(requestId.sequence) == 'number'
        and requestId.kind == kind then
        requestKey = requestId.requestKey
    else return nil, 'invalid' end
    for _, recorded in ipairs(data.SaveMeta.operations) do
        if recorded.requestKey == requestKey then
            if type(requestId) == 'table' and (requestId.id ~= recorded.id
                or requestId.sequence ~= recorded.sequence or requestId.kind ~= recorded.kind) then
                return nil, 'identity-conflict'
            end
            return { id = recorded.id, sequence = recorded.sequence, kind = kind,
                requestKey = recorded.requestKey }, 'replay'
        end
    end
    if type(requestId) == 'table' then return nil, 'expired' end
    if self:IsPaused(userId) then return nil, 'pending' end
    local operation = self:NextOperation(player, kind)
    if not operation then return nil, 'pending' end
    operation.requestKey = requestKey
    return operation, 'new'
end

-- 身份由服务端颁发，调用者必须保留原身份重试；不能把客户端自报 id 当凭证。
function Mgr:NextOperation(player, kind)
    local s = self.Sessions[player.UserId]
    if not s or s.Player ~= player or self:IsPaused(player.UserId) or not s.Data.Inited
        or type(kind) ~= 'string' or #kind < 1 or #kind > 80 then return nil end
    local sequence = s.Data.SaveMeta.sequence + 1
    return { id = tostring(player.UserId) .. ':' .. sequence, sequence = sequence, kind = kind }
end

-- transform 只改隔离 draft 并返回可序列化结果；外部实体交接由调用方在成功回调按操作身份确认。
-- 扣费、发奖、恢复记录和结果一次落在同键，失败时 draft 不向玩家发布。
function Mgr:Execute(player, data, operation, transform, done)
    local userId, s = player.UserId, self.Sessions[player.UserId]
    if not s or not self:IsCurrent(userId, s, data) or self:IsPaused(userId) or not data.Inited
        or type(operation) ~= 'table' or type(operation.sequence) ~= 'number'
        or operation.sequence ~= math.floor(operation.sequence) or operation.sequence < 1
        or operation.id ~= tostring(userId) .. ':' .. operation.sequence
        or type(operation.kind) ~= 'string' or #operation.kind < 1 or #operation.kind > 80
        or operation.requestKey ~= nil and type(operation.requestKey) ~= 'string'
        or type(transform) ~= 'function' or type(done) ~= 'function' then return false, 'invalid' end
    local meta = data.SaveMeta
    for _, recorded in ipairs(meta.operations) do
        if recorded.id == operation.id then
            if recorded.kind ~= operation.kind or operation.requestKey ~= nil
                and recorded.requestKey ~= operation.requestKey then return false, 'identity-conflict' end
            callback('结果重放', userId, done, true, copy(recorded.result))
            return true
        end
    end
    if operation.sequence <= meta.sequence then return false, 'expired' end
    if operation.sequence ~= meta.sequence + 1 then return false, 'out-of-order' end
    s.Transition = true
    self:AfterIdle(userId, function()
        if not self:IsCurrent(userId, s, data) then return end
        local snapshot = data:Serialize()
        local draft = PlayerData.New({ UserId = userId, SetAttribute = function() end })
        draft:Init()
        draft:ApplySave(snapshot)
        local ok, result, reason = pcall(transform, draft)
        if not ok or type(result) ~= 'table' then
            s.Transition = false
            print('[MgrSave] 结算拒绝', userId, operation.id, operation.kind, tostring(result), tostring(reason))
            callback('结算拒绝', userId, done, false, ok and reason or tostring(result))
            return
        end
        local nextValue = draft:Serialize()
        nextValue.meta.sequence = operation.sequence
        table.insert(nextValue.meta.operations, { id = operation.id, sequence = operation.sequence,
            kind = operation.kind, requestKey = operation.requestKey, result = copy(result) })
        while #nextValue.meta.operations > 64 do
            nextValue.meta.floor = table.remove(nextValue.meta.operations, 1).sequence
        end
        if not data:IsValidSave(nextValue) or not self:WithinBudget(nextValue) then
            s.Transition = false
            callback('结算容量拒绝', userId, done, false, 'invalid-result-or-budget')
            return
        end
        data.Inited = false
        local job = { Session = s, Key = s.Key, Snapshot = nextValue, Reason = operation.kind,
            Done = function(written, value)
                if not self:IsCurrent(userId, s, data) then return end
                s.Transition = false
                if written then
                    data.Inited = true
                    data:ApplySave(value)
                    data:PublishItemBar()
                    print('[MgrSave] operation', userId, operation.id, operation.kind,
                        'coinBefore=' .. snapshot.coin, 'coinAfter=' .. value.coin,
                        'bar=' .. #value.bar, 'bp=' .. #value.bp)
                    callback('结算完成', userId, done, true, copy(result))
                else
                    self:Fail(userId, s, '结算未确认 ' .. tostring(value))
                    callback('结算失败', userId, done, false, value)
                end
            end }
        self.Pending[userId] = job
        self:Drain(userId)
    end)
    return true
end

function Mgr:ApplyTemporary(userId, data, patch, done)
    local s = self:Session(userId)
    if s.Transition or s.State ~= 'ready' or not self:IsCurrent(userId, s, data) then
        return false, '存档尚未就绪'
    end
    s.Transition = true
    local accepted, failure = true, nil
    self:AfterIdle(userId, function()
        if not self:IsCurrent(userId, s, data) then return end
        local ok, reason = data:ApplyGMPatch(patch)
        accepted, failure = ok, reason
        if ok then s.Paused = true end
        s.Transition = false
        callback('GM 临时状态', userId, done, ok, reason)
    end)
    return accepted, failure
end
function Mgr:SaveExplicit(userId, data, done)
    local s = self:Session(userId)
    if s.Transition or s.State ~= 'ready' or not self:IsCurrent(userId, s, data) then return false, '存档尚未就绪' end
    s.Transition = true
    self:AfterIdle(userId, function()
        if not self:IsCurrent(userId, s, data) then return end
        local snapshot = data:Serialize()
        s.Transition, s.Paused = false, false
        local accepted = self:Enqueue(userId, snapshot, 'gm', function(ok, result)
            if not self:IsCurrent(userId, s, data) then return end
            s.Paused = not ok
            callback('GM 保存', userId, done, ok, ok and nil or result)
        end)
        if not accepted then
            s.Paused = true
            callback('GM 保存拒绝', userId, done, false, '存档写入未受理')
        end
    end)
    return true
end
function Mgr:ReadExplicit(userId, data, done)
    local s = self:Session(userId)
    if s.Transition or s.State ~= 'ready' or not self:IsCurrent(userId, s, data) then return false, '存档尚未就绪' end
    s.Transition = true
    self:AfterIdle(userId, function()
        task():Spawn(function()
            if not self:IsCurrent(userId, s, data) then return end
            local revision = data.Revision
            local value, status = self:Load(userId)
            if not self:IsCurrent(userId, s, data) then return end
            local valid = status == 'found' and data.Revision == revision and data:IsValidSave(value)
                and value.meta and value.meta.session == s.Token and value.meta.revision == s.Revision
            if valid then data:ApplySave(value) end
            s.Transition = false
            callback('GM 读取', userId, done, valid or false,
                not valid and '读取失败、状态已变化或存档无效' or nil)
        end)
    end)
    return true
end
function Mgr:SelectNextSlot(userId, slot, done)
    if slot ~= '' and not validSlot(slot) then return false, '存档槽须为 1—40 位字母、数字、下划线或连字符' end
    local s, store = self:Session(userId), self:GetStore()
    if s.SlotChoosing or not store then return false, '槽选择进行中或服务不可用' end
    s.SlotChoosing = true
    task():Spawn(function()
        local ok = self:WithRetry('选择槽 ' .. userId, function()
            store:SetAsync(cfg().KeyPrefix .. userId .. ':gm-slot', slot)
        end)
        if ok then s.Next = slot end
        s.SlotChoosing = false
        local waiters = s.SlotWaiters or {}
        s.SlotWaiters = nil
        for _, fn in ipairs(waiters) do callback('槽选择', userId, fn) end
        if self.Sessions[userId] == s then callback('槽选择结果', userId, done, ok,
            not ok and '存档槽选择未保存' or nil) end
    end)
    return true
end
function Mgr:ReleaseSession(userId, player)
    local s = self.Sessions[userId]
    if not s or player and s.Player ~= player then return end
    -- 离场快照先排空，仍保留会话 fencing；重进替换会话后旧 job 自动失效。
    s.Leaving = true
    self:AfterIdle(userId, function() if self.Sessions[userId] == s then self.Sessions[userId] = nil end end)
end
function Mgr:SaveLeaving(player, data)
    local s = self.Sessions[player.UserId]
    if not s or s.Player ~= player or s.Data ~= data then return end
    if data and data.Inited then self:Save(player.UserId, data:Serialize(), 'leave') end
end
function Mgr:Update()
    for userId in pairs(self.Pending) do self:Drain(userId) end
    local now = game:GetService('World'):GetServerTime()
    local interval = cfg().AutosaveSec
    if not interval or interval <= 0 then return end
    if not self.NextAutosaveAt then self.NextAutosaveAt = now + interval return end
    if now < self.NextAutosaveAt then return end
    self.NextAutosaveAt = now + interval
    if self.PlayerData then
        for _, player in ipairs(game:GetService('Players'):GetPlayers()) do
            local data = self.PlayerData:GetDataInst(player)
            if data then self:Save(player.UserId, data:Serialize(), 'autosave') end
        end
    end
end
function Mgr:Start()
    local ok, err = pcall(function()
        game:BindToClose(function()
            if self.PlayerData then
                for _, player in ipairs(game:GetService('Players'):GetPlayers()) do
                    local data = self.PlayerData:GetDataInst(player)
                    if data then self:Save(player.UserId, data:Serialize(), 'shutdown') end
                end
            end
            -- 有限等待；失败记录保持可观察，不声称关服时保证网络成功。
            for _ = 1, 25 do
                if next(self.Pending) == nil and next(self.Flying) == nil then return end
                for userId in pairs(self.Pending) do self:Drain(userId) end
                task():Wait(1)
            end
            print('[MgrSave] 关服刷新未排空，请核对台账')
        end)
    end)
    if not ok then print('[MgrSave] BindToClose 绑定失败', tostring(err)) end
end
return Mgr
