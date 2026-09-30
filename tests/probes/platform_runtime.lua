-- #147 一轮本地平台试玩探针：server 端执行，全部收费用 Debug 测试 flow，绝非真实支付证据。
-- editor-cli exec -p server --file <本文件绝对路径> --json；随后运行 platform_client.lua。
-- 不预置保底计数、不清库存；模拟成功单抽会正常发奖并推进持久计数，按真实权重 RNG 抽样。
-- flow 失败/成功走公开 HandleTestAction；超时由单测/feature 脚本化时钟覆盖。
local cfg = require('common.GameCfg')
local platform = require('server.Mgr.MgrPlatform')
local blindbox = require('server.Mgr.MgrBlindbox')
local players = require('server.Mgr.MgrPlayerData')
local save = require('server.Mgr.MgrSave')
local survival = require('server.Mgr.MgrSurvival')
local world, task = game:GetService('World'), game:GetService('Task')
local p = game:GetService('Players'):GetPlayers()[1]
if not p then print('PLATFORM147 ABORT 无玩家') return end
local data = players:GetDataInst(p)
if not data then print('PLATFORM147 ABORT 存档未就绪') return end
if not cfg.Debug or cfg.Debug.Enabled ~= true then print('PLATFORM147 ABORT 调试关闭') return end
local tag = 'P147-' .. tostring(math.floor(world:GetServerTime()))
local function log(...) print('PLATFORM147', tag, ...) end
_G.Platform147Seq = (_G.Platform147Seq or 147000) + 10
local seq = _G.Platform147Seq
local function ready()
    for _ = 1, 100 do
        if not save.Flying[p.UserId] and not save.Pending[p.UserId] then return true end
        task:Wait(0.1)
    end
    return false
end
task:Spawn(function()
    if platform:HasFlow(p) then log('ABORT 已有平台flow') return end
    local before = blindbox:PityOf(data)
    assert(blindbox:Handle(p, { action = 'Draw', count = 1, seq = seq }))
    if not ready() then log('ABORT 支付意图未落账') return end
    assert(platform:HandleTestAction(p, { action = 'ResolveFlow', outcome = 'cancel' }))
    log('取消不发奖', 'pity=' .. blindbox:PityOf(data), 'before=' .. before)
    assert(blindbox:PityOf(data) == before)
    assert(blindbox:Handle(p, { action = 'Draw', count = 1, seq = seq + 1 }))
    if not ready() then log('ABORT 支付意图未落账') return end
    assert(platform:HandleTestAction(p, { action = 'ResolveFlow', outcome = 'success' }))
    if not ready() then log('ABORT 单抽落账未就绪') return end
    local after = blindbox:PityOf(data)
    log('模拟单抽落账', 'pity=' .. before .. '->' .. after)
    assert(blindbox:Handle(p, { action = 'Draw', count = 1, seq = seq + 1 }))
    log('原序号重试', '无新flow=' .. tostring(not platform:HasFlow(p)), 'pity=' .. blindbox:PityOf(data))
    assert(not platform:HasFlow(p) and blindbox:PityOf(data) == after)
    local old = cfg.Debug.Enabled
    cfg.Debug.Enabled = false
    local ok, why = platform:Purchase(p, 'blindboxSingle', 'blindbox', function() end)
    local driven = platform:HandleTestAction(p, { action = 'ResolveFlow', outcome = 'success' })
    cfg.Debug.Enabled = old
    log('生产守卫', tostring(ok), tostring(why), '测试驱动=' .. tostring(driven))
    assert(not ok and why == 'unavailable' and not driven)
    log('复活入口状态', survival:Phase(p))
    log('DONE 本地模拟取证；真实平台归#148')
end)
