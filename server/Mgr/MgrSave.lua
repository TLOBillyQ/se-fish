-- 存档管理器（#92）：DataStore 持久化 PlayerData:Serialize 的最小集。所有写都进 Enqueue 队列——
-- 同一玩家只保留最新快照（合并），单 Task 串行排空（消乱序：旧 SetAsync 不会盖过新 Commit）。
-- Load 由调用方包 Task:Spawn（LoadInto 已包）。失败按 GameCfg.Save 退避重试，重试耗尽只记日志、
-- 不动内存态（内存比存档新）。兑换/收船票等关键状态转换走 Commit（UpdateAsync CAS 记账），断线
-- 重连不双份发奖；普通快照走 Save（SetAsync）。Ledger 记每人写入次数与最近体积（验收③台账，
-- 跨离场保留是有意的，便于观察整局写入量）；DataStore 不可用（如未发布环境）时整模块退化为
-- 纯内存，不影响游戏。周期自动存档（Update）、关服兜底（Start 里 BindToClose 全员落档）。
local GameCfg = require('common.GameCfg')

local Mgr = { Ledger = {}, Pending = {}, Flying = {}, NextAutosaveAt = nil }

local function cfg()
    return GameCfg.Save
end

local function task()
    return game:GetService('Task')
end

function Mgr:Key(userId)
    local slot = cfg().AcceptanceSlot
    if slot == '' or slot == nil then return cfg().KeyPrefix .. tostring(userId) end
    assert(type(slot) == 'string' and #slot <= 40 and slot:match('^[%w_-]+$'),
        '验收存档槽须为 1—40 位字母、数字、下划线或连字符')
    return cfg().KeyPrefix .. tostring(userId) .. ':qa:' .. slot
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
    if not self:GetStore() or type(snapshot) ~= 'table' then return false end
    self.Pending[userId] = {
        Snapshot = snapshot,
        Reason = reason,
        Mode = mode,
        Bytes = self:EstimateSize(snapshot),
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
                        self.Store:UpdateAsync(self:Key(userId), function() return job.Snapshot end)
                    else
                        self.Store:SetAsync(self:Key(userId), job.Snapshot)
                    end
                end)
                if ok then
                    self:NoteWrite(userId, job.Bytes, job.Reason, job.Mode == 'update' and '记账落账' or '存档')
                else
                    -- 重试耗尽：内存态比存档新，丢这次写不影响当局；下一笔写仍会带上最新快照
                    print('[MgrSave] 写档放弃，内存态保留', userId, job.Reason)
                end
            end
            self.Flying[userId] = nil
        end)
    end
    return true
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
    task():Spawn(function()
        local snapshot = self:Load(player.UserId)
        if not snapshot then return end
        if not data.Inited then return end -- 读档期间玩家已离开
        if data.Touched then
            print('[MgrSave] 读档期间已有操作，跳过旧档覆盖', player.UserId)
            return
        end
        if data:ApplySave(snapshot) then
            if self.PlayerData then self.PlayerData:SendItemBar(player) end
            print('[MgrSave] 恢复完成', player.UserId)
        end
    end)
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
