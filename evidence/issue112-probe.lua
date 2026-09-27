-- 在 SE 试玩开始后通过 editor-cli exec --platform server --file 提交。
-- 每次空抽只暂时替换鱼表，鱼饵库存取真实道具栏快照。
local cfg = require('common.GameCfg')
local cast = require('server.Mgr.MgrCast')
local player = game:GetService('Players'):GetPlayers()[1]
local data = _G.MgrPlayerData:GetDataInst(player)
local task = game:GetService('Task')
local zone = 'WaterCircle2'
local original = cfg.Casting.Zones[zone]
local function baitCount()
    return data:GetItemBarSnapshot().bait.worm or 0
end
local slot
for i, entry in pairs(data.Data.Containers.itemBar) do
    if entry and entry.itemId == 'starterRod' then slot = i end
end
if not slot then
    data:GrantItem('starterRod', 1)
    for i, entry in pairs(data.Data.Containers.itemBar) do
        if entry and entry.itemId == 'starterRod' then slot = i end
    end
end
assert(slot, 'starterRod unavailable')
if baitCount() < 2 then data:GrantItem('worm', 2) end
if data.Data.SelectedSlot ~= slot then data:SelectSlot(slot) end
data:SelectBait('worm')
player.Character.Position = Vector3.New(-11.75, 2.2, 22.75)
player.Character.Rotation = Quaternion.FromEulerAngles(0, 0, 0)
local current = cast.Sessions[player.UserId]
if current and current.session.phase == 'hooked' then
    cast:FinishReel(player, current.session.reelSession, 'escaped')
elseif current then
    cast:EndSession(player, current)
end
local before = baitCount()
cfg.Casting.Zones[zone] = {}
cast:Cast(player, { slot = slot, itemId = 'starterRod' })
print('PROBE112 CAST', tostring(cast.Sessions[player.UserId] ~= nil),
    'before=' .. before, 'after=' .. baitCount())
task:Delay(cfg.Casting.HookDelaySec + 0.5, function()
    cfg.Casting.Zones[zone] = original
    print('PROBE112 EMPTY', tostring(cast.Sessions[player.UserId] == nil),
        'bait=' .. baitCount())
    task:Delay(2, function()
        cast:Cast(player, { slot = slot, itemId = 'starterRod' })
        print('PROBE112 RECAST', tostring(cast.Sessions[player.UserId] ~= nil),
            'bait=' .. baitCount())
        task:Delay(cfg.Casting.HookDelaySec + 0.5, function()
            local active = cast.Sessions[player.UserId]
            print('PROBE112 HOOK', tostring(active and active.session.phase),
                tostring(active and active.session.fishId))
        end)
    end)
end)
