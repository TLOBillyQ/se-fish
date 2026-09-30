-- #133 图鉴写入基础：把「成功上岸」当成一次性领域事件记进图鉴。
-- 落点两处：内存快照（Snapshot，给后续图鉴 UI / 纪录读）与存档（extra.collection），
-- 后者走 #123 持久化操作协议（ResolveRequest + Execute），所以写入与结果同键落账、重进保留。
-- 幂等键 = 收线会话序号（同一存档会话内单调、一次上岸只发一个），重复投递（协议重放、写档重试、
-- 结果回调重放）不会记第二次；幂等范围限于同一次存档会话（跨会话序号会重新开始计数）。
-- 边界：盲盒/抽奖在 extra.lottery，击杀与三份掉落走 MgrLoot —— 都不经过这里，
-- 钓取次数与个人最大重量只由「上岸」推进。
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')

local Mgr = { Queues = {}, KIND = 'compendium-land', MaxQueue = 16 }

-- 浅拷贝：图鉴字段的值都是数字 / 布尔，没有嵌套表
local function copy(value)
    local out = {}
    for k, v in pairs(value or {}) do out[k] = v end
    return out
end

-- 存档里的图鉴字段是 #92 预留的 extra.collection（PlayerData 只校验它是表），
-- 嵌套键按需建立，读方一律做空表兜底。
local function collection(extra)
    local bag = extra.collection
    bag.weights = bag.weights or {}
    bag.unlocked = bag.unlocked or {}
    bag.catches = bag.catches or {}
    bag.total = bag.total or 0
    return bag
end

-- 只读入口（后续图鉴 UI / 个人纪录）：返回副本，调用方改不动权威状态
function Mgr:Snapshot(player)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    local bag = data and data.Extra and data.Extra.collection or nil
    if not bag then return { unlocked = {}, catches = {}, weights = {}, total = 0 } end
    return { unlocked = copy(bag.unlocked), catches = copy(bag.catches),
        weights = copy(bag.weights), total = bag.total or 0 }
end

-- 上榜条件只看个体重量，与售价无关；重量口径与 MgrFishUnit:Weight 同一个纯函数
function Mgr:Weight(fishId, mult)
    local species = GameCfg.Fish[fishId]
    return species and FishCatch.Weight(species, mult) or nil
end

-- 入账：先写进草稿，写入被平台确认后才发布回内存（#123 契约：失败不向玩家发布）。
local function apply(draft, event, weight)
    local bag = collection(draft.Extra)
    local previous = bag.weights[event.fishId]
    local record = previous == nil or weight > previous
    bag.unlocked[event.fishId] = true
    bag.catches[event.fishId] = (bag.catches[event.fishId] or 0) + 1
    if record then bag.weights[event.fishId] = weight end
    bag.total = bag.total + 1
    return { fishId = event.fishId, weight = weight, best = bag.weights[event.fishId],
        record = record, count = bag.catches[event.fishId], total = bag.total }
end

-- 上岸事实先入队，落账尽量当场完成。被别的写档挡住的只是一次「晚一点记」：事件留在队里，
-- 下一次 Update 补记（返回 true）。真正的拒收只有三种，都返回 false 并给原因：重放（同一条
-- 上岸已经落过账）、队列满（写档长时间不恢复）、存档不可用（宁可不记也不伪造）。
-- 玩家离线时队里还没落账的事件会丢：那是「上岸后写档被挡 + 同一瞬间断线」的窄窗口，
-- 已落账的部分由协议的操作日志去重，不会重复也不会回滚。
function Mgr:RecordLanding(player, event)
    if not player or type(event) ~= 'table' then return false, 'invalid' end
    local weight = self:Weight(event.fishId, event.mult)
    if not weight or type(event.reelSerial) ~= 'number'
        or event.reelSerial ~= math.floor(event.reelSerial) or event.reelSerial < 1 then
        return false, 'invalid'
    end
    local queue = self.Queues[player.UserId]
    if not queue or queue.player ~= player then
        queue = { player = player, events = {} }
        self.Queues[player.UserId] = queue
    end
    for _, queued in ipairs(queue.events) do
        if queued.reelSerial == event.reelSerial then return false, 'duplicate' end
    end
    if #queue.events >= self.MaxQueue then return false, 'busy' end
    queue.events[#queue.events + 1] = { reelSerial = event.reelSerial,
        fishId = event.fishId, mult = event.mult }
    -- Drain 只在「刚入队的这条当场出了结果」时回报裁决（replay：同一次上岸已落过账；
    -- invalid：存档不可用宁可不记）。排队等写档（pending）不算拒绝，稍后补记。
    local mode = self:Drain(player)
    if mode == 'replay' or mode == 'invalid' then return false, mode end
    return true
end

-- 队首事件走一次协议：'new' 落账、'replay' 说明同一次上岸已经落过账（丢掉即可）、
-- 'pending' 留到下一次 Update（写档在飞）、'invalid' 说明存档不可用，宁可不记也不伪造。
-- 返回值为队首事件的裁决（仅当队里只有这一条时），供 RecordLanding 回报受理结果。
function Mgr:Drain(player)
    local queue = self.Queues[player.UserId]
    if not queue or queue.player ~= player or #queue.events == 0 then return end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return end
    local onlyEvent = #queue.events == 1
    local event = queue.events[1]
    local operation, mode = self.Save:ResolveRequest(player, data, self.KIND, event.reelSerial)
    if not operation then
        if mode ~= 'pending' then
            table.remove(queue.events, 1)
            return onlyEvent and mode or nil
        end
        return
    end
    table.remove(queue.events, 1)
    if mode == 'replay' then return onlyEvent and 'replay' or nil end
    local weight = self:Weight(event.fishId, event.mult)
    self.Save:Execute(player, data, operation, function(draft)
        return apply(draft, event, weight)
    end, function(written, result)
        if not written then
            print('[MgrCompendium] 图鉴未落账', player.UserId, event.fishId, tostring(result))
            return
        end
        print('[MgrCompendium] 图鉴', player.UserId, result.fishId,
            'weight=' .. tostring(result.weight), 'best=' .. tostring(result.best),
            'count=' .. tostring(result.count), 'total=' .. tostring(result.total))
        -- #149 T28：只有刷新了个人最大重量的那次上岸（result.record）才通知全服纪录，
        -- 只调用、不改 #133 的个人口径；提交走 MgrRecords:NoteLanding（合并窗口 + CAS），
        -- 个人图鉴落账与全服纪录写成功是两条独立链路，后者失败不影响前者。
        if result.record and self.Records then
            self.Records:NoteLanding(player, result.fishId, result.weight)
        end
    end)
end

function Mgr:Update()
    for _, queue in pairs(self.Queues) do self:Drain(queue.player) end
end

function Mgr:OnPlayerRemoving(player)
    local queue = self.Queues[player.UserId]
    if queue and queue.player == player then self.Queues[player.UserId] = nil end
end

return Mgr
