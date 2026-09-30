-- #149 T28 全服纪录的平台适配器：把 DataStore 访问收敛到这一层，便于替换与失败注入。
-- 真实 DataStore 的限流、错误码文本与跨服可见性在编辑器内**不可实测**（归 T27），这里只保证：
--   1. 一切平台调用都被 pcall 包住，失败翻译成稳定的错误类别（unavailable/throttled/timeout/unknown），
--      调用方据此降级，不会把「读不到」当成「没有纪录」；
--   2. 保持者三元组用 UpdateAsync 的 CAS 变换写入：并发时由变换函数看到当前值再决定，
--      跨服竞态由 Records.Wins 的确定性规则裁决，不是「谁最后写谁赢」；
--   3. 这里不重试（重试、退避与合并写入归 MgrRecords，写频才好观测与压测）。
-- 测试用内存假实现替换（MgrRecords.Adapter 可注入），语义必须与本文件的 CAS 一致：
-- decide(current) 返回 nil 表示放弃本次更新，此时不产生任何写入。
local GameCfg = require('common.GameCfg')
local Records = require('common.Records')

local Adapter = {}

local function cfg() return GameCfg.Records end

-- 错误分类：真实错误码文本未查证（[未查证]，技术难点 §5 只给了错误码没有文案），
-- 所以只按关键字粗分，认不出一律 'unknown'——调用方对这几类都走同一条降级路径。
local function classify(err)
    local text = tostring(err):lower()
    if text:find('throttl', 1, true) or text:find('limit', 1, true) or text:find('429', 1, true) then
        return 'throttled'
    end
    if text:find('timeout', 1, true) or text:find('timed out', 1, true) then return 'timeout' end
    return 'unknown'
end

-- 取服务只做一次；不可用时返回 nil，调用方按「暂不可用」处理，不写假值。
function Adapter:Store()
    if self.Checked then return self.Holder end
    self.Checked = true
    local ok, store = pcall(function() return game:GetService('DataStoreService'):GetDataStore(cfg().Store) end)
    if not ok or not store then
        print('[RecordsAdapter] DataStore 不可用，全服纪录按暂不可用处理', tostring(store))
        return nil
    end
    self.Holder = store
    return store
end

function Adapter:Key(fishId) return cfg().KeyPrefix .. fishId end

-- 读一条鱼的全服纪录。返回 (ok, 三元组或 nil, 错误类别)：
--   ok = true 且值为 nil → 服务可用，这条鱼还没有纪录（"missing"）；
--   ok = false          → 读不到，必须按"暂不可用"处理，不能当成没有纪录。
-- 值损坏（缺重量或缺身份）按没有纪录处理：读不出可信的三元组，就不展示，也不猜。
function Adapter:Read(fishId)
    local store = self:Store()
    if not store then return false, nil, 'unavailable' end
    local key = self:Key(fishId)
    local ok, value = pcall(function() return store:GetAsync(key) end)
    if not ok then return false, nil, classify(value) end
    return true, Records.Valid(value), nil
end

-- 提交候选：decide(current) 在 CAS 变换里执行。返回 (ok, won, 当前值, 错误类别)：
--   won = true  → 本次候选已写入，第三个返回的是写入后的三元组；
--   won = false → 候选没赢（已有更大纪录，或同重量按 UserID 决胜输了），第三个返回的是当时看到的当前值。
function Adapter:Submit(fishId, decide)
    local store = self:Store()
    if not store then return false, nil, nil, 'unavailable' end
    local key = self:Key(fishId)
    local seen, won
    local ok, value = pcall(function()
        return store:UpdateAsync(key, function(current)
            local valid = Records.Valid(current)
            seen = valid
            local next_ = decide(valid)
            if not next_ then return nil end -- 放弃：不产生写入
            won = true
            return next_
        end)
    end)
    if not ok then return false, nil, nil, classify(value) end
    if won then return true, true, Records.Valid(value), nil end
    return true, false, seen, nil
end

return Adapter
