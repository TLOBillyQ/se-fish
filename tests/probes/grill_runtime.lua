-- #137 烧烤真实试玩探针：只走公开请求（MgrGrill:Handle 与正常格位选择），不改时间/坐标。
-- 前置：玩家背包或道具栏里有未烤鱼获（食物/极品食物）；最好另有一条未烤信物演示确认流程；
-- 人站在三区起任一烧烤点 2.5 米内。GM 发放与传送只是环境准备，烤的流程全走真实通道。
-- 试玩就绪后：editor-cli exec -p server --file <本文件绝对路径> --json。
-- 场景 A：信物优先——不确认先收 token-warn、确认后开烤，约 2 秒取出，日志给倍率（期望 1.50）。
-- 没有信物时退化为普通鱼开烤取出。
-- 场景 B：非信物鱼开烤后不取出，等烤糊：burnt 推送、烤糊前后血量差（3 米内 30）、只损毁一次。
-- 注意：开烤/取出经 #123 持久协议，会话在异步落账回调里建立，所以全程在协程里轮询等待。
local cfg = require('common.GameCfg')
local grill = require('server.Mgr.MgrGrill')
local pd = require('server.Mgr.MgrPlayerData')
local curve = require('common.GrillCurve')
local world, task = game:GetService('World'), game:GetService('Task')
local player = game:GetService('Players'):GetPlayers()[1]
if not player then print('GRILL137 ABORT 没有玩家') return end
local data = pd:GetDataInst(player)
if not data then print('GRILL137 ABORT 存档未就绪') return end
_G.Grill137 = _G.Grill137 or { token = 0, seq = 137000 }
local rt = _G.Grill137
rt.token, rt.seq = rt.token + 1, rt.seq + 1
local token = rt.token
local tag = 'G137-' .. tostring(math.floor(world:GetServerTime()))
local function log(...) print('GRILL137', tag, ...) end
local function nextSeq() rt.seq = rt.seq + 1 return rt.seq end

local anchorName, anchor = grill:InRange(player)
if not anchor then
    log('ABORT 不在烧烤点范围内，请先走到三区起任一烧烤点 2.5 米内再跑探针')
    return
end
log('烤位', anchorName, tostring(anchor.Position))

local function isToken(itemId)
    for _, chain in ipairs(cfg.Content.Exchanges) do -- 与 MgrGrill 同一判定表
        if chain.EliteToken == itemId or chain.BossToken == itemId then return true end
    end
    return false -- 显式返回：尾调用展开会把「无返回值」变成 tostring() 零参数报错
end

-- 找一条未烤鱼获；wantToken=true 时只要信物，=false 时只要非信物，nil 不限
local function grillableSlot(wantToken)
    for containerId, container in pairs(data.Data.Containers) do
        for index, entry in pairs(container) do
            local def = entry.itemId and cfg.Items.Definitions[entry.itemId]
            if entry.count > 0 and def and (def.Type == '食物' or def.Type == '极品食物')
                and cfg.Items.CookRate(entry) == nil
                and (wantToken == nil or isToken(entry.itemId) == wantToken) then
                return containerId, index, entry
            end
        end
    end
end

local function selectEntry(containerId, index)
    if containerId == cfg.Items.ContainerId.ItemBar then
        data:SelectSlot(index)
    else
        data:MoveSlot(containerId, index, cfg.Items.ContainerId.ItemBar, 1)
        data:SelectSlot(1)
    end
end

local function health()
    local c = player.Character and player.Character.Controller
    return c and c.Health
end

local function findCooked(itemId)
    for _, container in pairs(data.Data.Containers) do
        for _, e in pairs(container) do
            if e.itemId == itemId and e.count > 0 and e.cooked ~= nil then return e end
        end
    end
end

-- 轮询等会话建立（持久协议异步回调）；返回会话或 nil
local function waitSession()
    for _ = 1, 30 do
        local session = grill:GetSession(player)
        if session then return session end
        task:Wait(0.1)
    end
end

-- 场景 A 开烤：信物先发未确认（期望 token-warn）再确认；普通鱼直接开烤
local cidA, idxA, entryA = grillableSlot(true)
local tokenA = entryA ~= nil
if not entryA then cidA, idxA, entryA = grillableSlot(false) end
if not entryA then log('ABORT 没有未烤鱼获，请先钓鱼') return end
selectEntry(cidA, idxA)
log('场景A 投入', entryA.itemId, 'mult=' .. tostring(entryA.mult), 'token=' .. tostring(tokenA))
if tokenA then
    grill:Handle(player, { action = 'Start', seq = nextSeq() })
    log('场景A 信物未确认请求已发（期望 token-warn 且不扣物）')
    task:Wait(0.3)
    log('场景A 信物仍在库存', data:ItemCount(entryA.itemId))
end
grill:Handle(player, { action = 'Start', seq = nextSeq(), confirm = true })

task:Spawn(function()
    local session = waitSession()
    log('场景A 会话', session and session.state, session and session.itemId)
    if not session then log('ABORT 开烤未成立') return end
    local startedAt = session.startedAt
    local waitA = 2 - (world:GetServerTime() - startedAt)
    if waitA > 0 then task:Wait(waitA) end
    grill:Handle(player, { action = 'Takeout', seq = nextSeq() })
    task:Wait(0.5) -- 取出同样是异步落账
    local elapsed = world:GetServerTime() - startedAt
    local back = findCooked(entryA.itemId)
    log('场景A 取出', 'elapsed=' .. curve.Format(elapsed),
        '曲线倍率=' .. curve.Format(curve.Rate(elapsed, cfg.Grill) or -1),
        '格位cooked=' .. tostring(back and back.cooked),
        'saved.k=' .. tostring(back and back.saved and back.saved.k),
        '选中格=' .. tostring(data.Data.SelectedSlot))

    -- 场景 B：烤糊（非信物）
    local cidB, idxB, entryB = grillableSlot(false)
    if not entryB then log('场景B 跳过：没有第二条未烤的非信物鱼获') log('观察结束') return end
    selectEntry(cidB, idxB)
    log('场景B 投入', entryB.itemId)
    grill:Handle(player, { action = 'Start', seq = nextSeq() })
    local sessionB = waitSession()
    if not sessionB then log('场景B ABORT 开烤未成立') log('观察结束') return end
    local before = health()
    log('场景B 等烤糊', '血量前=' .. tostring(before))
    local waitB = cfg.Grill.BurnSec + 0.5 - (world:GetServerTime() - sessionB.startedAt)
    if waitB > 0 then task:Wait(waitB) end
    task:Wait(1) -- 再多等一秒，确认只损毁一次
    local after = health()
    log('场景B 烤糊后', '血量后=' .. tostring(after),
        '差值=' .. tostring(before and after and (before - after)),
        '会话=' .. tostring(grill:GetSession(player) and '仍在' or '已清'),
        '库存残留=' .. tostring(data:ItemCount(entryB.itemId)),
        '待恢复=' .. tostring(data.Extra.recovery.grill ~= nil))
    log('观察结束')
end)
