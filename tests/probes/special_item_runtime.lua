-- #140 [专项探针] 单人真实角色飞行接缝与吐息冷却；不作为普通通关证据。
-- 环境准备临时占用道具栏一格，结束恢复原槽与选中；不改服务器时刻。
local mgr = require('server.Mgr.MgrSpecialItem')
local pd = require('server.Mgr.MgrPlayerData')
local cfg = require('common.GameCfg')
local world, task = game:GetService('World'), game:GetService('Task')
local player = game:GetService('Players'):GetPlayers()[1]
local function log(...) print('SPECIAL140', '[专项探针]', ...) end
if not player then log('ABORT 无玩家') return end
local data = pd:GetDataInst(player)
if not data then log('ABORT 存档未就绪') return end
local ch = player.Character
local bar = data.Data.Containers[cfg.Items.ContainerId.ItemBar]
local oldEntry, oldSlot = bar[1], data.Data.SelectedSlot
local initial = ch.Position
local function equip(id)
    bar[1] = id and { itemId = id, count = 1 } or nil
    data:SelectSlot(id and 1 or nil)
end
local function observe(label)
    local s = mgr.States[player.UserId]
    local p = ch.Position
    log(label, 'y=' .. tostring(p.y), 'x=' .. tostring(p.x), 'z=' .. tostring(p.z),
        'gravity=' .. tostring(ch.Controller.GravityEnabled), 'airborne=' .. tostring(s and s.airborne),
        'effect=' .. tostring(s and s.effect))
end
log('READY', 'user=' .. tostring(player.UserId), '翼资源=' .. tostring(cfg.Ability.SpecialItem.Wings.AppearanceAssetId),
    '变身资源=' .. tostring(cfg.Ability.SpecialItem.Godzilla.AppearanceAssetId))
task:Spawn(function()
    local ok, err = pcall(function()
        equip('item169') task:Wait(0.3) observe('地面待机')
        mgr:Handle(player, { action = 'fly', holding = true })
        task:Wait(1) observe('长按1秒')
        task:Wait(5) observe('长按6秒封顶')
        mgr:Handle(player, { action = 'fly', holding = false })
        task:Wait(1) observe('松开1秒')
        task:Wait(8) observe('缓降9秒')
        mgr:Handle(player, { action = 'fly', holding = true })
        task:Wait(0.5)
        equip('carp') task:Wait(0.3) observe('空中切走')
        equip('item170') task:Wait(0.3)
        local cast = mgr:Handle(player, { action = 'breath' })
        log('吐息施法', tostring(cast))
        task:Wait(4)
        local s = mgr.States[player.UserId]
        log('吐息4秒后', '已结束=' .. tostring(s.breath == nil),
            'remaining=' .. tostring(data.Extra.cooldowns.godzillaBreath))
        equip('carp') task:Wait(0.2) equip('item170') task:Wait(0.2)
        log('切换后再次吐息', tostring(mgr:Handle(player, { action = 'breath' })))
    end)
    bar[1] = oldEntry
    data:SelectSlot(oldSlot)
    mgr:OnTeleport(player)
    ch.Position = initial
    log('DONE', tostring(ok), tostring(err))
end)
