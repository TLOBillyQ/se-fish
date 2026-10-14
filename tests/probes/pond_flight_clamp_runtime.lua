-- #65 P0「鱼塘 Boundary 批次」试玩探针：风神之翼（item169）横向钳制与高度上限。
-- 复跑（验收槽隔离，不动正式存档）：
--   lua tools/cli.lua acceptance-slot new && lua tools/cli.lua deploy
--   editor-cli play start --wait-ready --json
--   editor-cli exec --platform server --file <本文件绝对路径> --timeout 60 --json
--   editor-cli log grep CLAMP65 --play-session <session> --json
--   editor-cli play stop && lua tools/cli.lua acceptance-slot off && lua tools/cli.lua deploy
--
-- 口径声明：本探针断言的是**运行时数学边界**（GameCfg.Zones[1].Scene.Boundary 经
-- GameCfg 末尾布局变换后的绝对值），不是实体空气墙面。实体墙的顶底与位置由编辑器侧
-- 只读探针另行回读；两者是否同一空间合同属 #65 P1/P3，本探针不作判断。
-- 探针临时占用道具栏第 1 格并改钓鱼区，结束恢复；失败路径也走恢复段。
local mgr = require('server.Mgr.MgrSpecialItem')
local pd = require('server.Mgr.MgrPlayerData')
local cfg = require('common.GameCfg')
local FlightPath = require('common.FlightPath')
local task = game:GetService('Task')
local player = game:GetService('Players'):GetPlayers()[1]
local function log(...) print('CLAMP65', ...) end
if not player then log('ABORT 无玩家') return end
local data = pd:GetDataInst(player)
if not data then log('ABORT 存档未就绪') return end

local zoneId = cfg.Zones[1].Id
local scene = nil
for _, zone in ipairs(cfg.Zones) do
    if zone.Id == zoneId then scene = zone.Scene end
end
local bounds = scene and FlightPath.BoundsOf(scene, cfg.Ability.Flight)
if not bounds then log('ABORT 无边界') return end
log('BOUNDS', 'zone=' .. tostring(zoneId),
    'MinX=' .. tostring(bounds.MinX), 'MaxX=' .. tostring(bounds.MaxX),
    'MinZ=' .. tostring(bounds.MinZ), 'MaxZ=' .. tostring(bounds.MaxZ),
    'GroundY=' .. tostring(bounds.GroundY), 'CeilingY=' .. tostring(bounds.CeilingY))

local origZone = data.Data.Zone
if origZone ~= zoneId then
    log('SETZONE', tostring(origZone) .. '->' .. tostring(zoneId), tostring(data:SetZone(zoneId)))
end
local ch = player.Character
local bar = data.Data.Containers[cfg.Items.ContainerId.ItemBar]
local oldEntry, oldSlot = bar[1], data.Data.SelectedSlot
local initial = ch.Position
local safe = scene.SafePoint

-- PlayerData:SelectSlot 是切换语义（当前已选该槽时再调一次会清成 nil），
-- 探针要的是「确保选中」而不是「切一次」，因此显式对齐到目标槽。
local function setSelection(want)
    if data.Data.SelectedSlot == want then return true end
    if data.Data.SelectedSlot ~= nil then data:SelectSlot(data.Data.SelectedSlot) end
    if want ~= nil then data:SelectSlot(want) end
    if data.Data.SelectedSlot ~= want then data.Data.SelectedSlot = want end -- 槽位被拒（空槽 / 超容量）时兜底
    return data.Data.SelectedSlot == want
end

local function pos()
    local p = ch.Position
    return p.x, p.y, p.z
end
local function check(label, got, want, tol)
    local ok = type(got) == 'number' and math.abs(got - want) <= (tol or 0.5)
    log('CHECK', label, 'got=' .. tostring(got), 'want=' .. tostring(want), ok and 'PASS' or 'FAIL')
    return ok
end

task:Spawn(function()
    local ok, err = pcall(function()
        ch.Position = Vector3.New(safe.x, safe.y + 1, safe.z)
        task:Wait(0.3)
        bar[1] = { itemId = 'item169', count = 1 }
        setSelection(1)
        task:Wait(0.5)
        local st = mgr.States[player.UserId]
        log('EQUIP', 'selected=' .. tostring(data.Data.SelectedSlot),
            'effect=' .. tostring(st and st.effect),
            'canAct=' .. tostring(mgr:CanAct(player)))
        log('FLY_START', tostring(mgr:Handle(player, { action = 'fly', holding = true })))
        task:Wait(0.3)
        local _, y0 = pos()
        log('Y0', tostring(y0))

        -- 高度上限：ClimbSpeed 8 m/s，长按 3.5 秒的积分远超 20 米上限，应停在 flightGroundY + 20
        -- （起飞地面基准由 MgrSpecialItem 在首帧取当帧 y，不能用本探针读到的爬升中 y 推算）
        task:Wait(3.5)
        local _, yTop = pos()
        local ground = (mgr.States[player.UserId] or {}).flightGroundY or bounds.GroundY
        log('CEILING_BASE', 'flightGroundY=' .. tostring(ground))
        check('CEILING_Y', yTop, ground + bounds.MaxHeight, 1.5)

        -- 横向钳制：把角色直接写到围栏外，等飞行心跳把位置夹回边界
        local cases = {
            { 'EAST', 200, 0, bounds.MaxX },
            { 'WEST', -200, 0, bounds.MinX },
            { 'NORTH', 0, 200, bounds.MaxZ },
            { 'SOUTH', 0, -200, bounds.MinZ },
        }
        for _, c in ipairs(cases) do
            local _, y = pos()
            ch.Position = Vector3.New(c[2], y, c[3])
            task:Wait(0.4)
            local gx, _, gz = pos()
            local got = (c[1] == 'EAST' or c[1] == 'WEST') and gx or gz
            check(c[1], got, c[4], 0.5)
        end
    end)
    mgr:Handle(player, { action = 'fly', holding = false })
    task:Wait(0.4)
    bar[1] = oldEntry
    setSelection(oldSlot)
    if origZone ~= zoneId then data:SetZone(origZone) end
    mgr:OnTeleport(player)
    ch.Position = initial
    log('RESTORED', 'slot=' .. tostring(oldSlot),
        'entry=' .. tostring(oldEntry and oldEntry.itemId),
        'zone=' .. tostring(data.Data.Zone))
    log('DONE', tostring(ok), tostring(err))
end)
