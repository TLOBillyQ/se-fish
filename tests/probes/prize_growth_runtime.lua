-- #139 [专项探针]：真实服务器上的成长、四类持续效果与十五件武器配置取证。
-- 用 exec -p server --file 执行；临时修改会话内成长计数后恢复，不代表真实存档重进验收。
-- 不自动发奖、不提交存档、不模拟多人；拾取/钓鱼/摆渡及真实枪击/挥砍另列真机遗留。
local cfg = require('common.GameCfg')
local ability = require('server.Mgr.MgrAbility')
local pd = require('server.Mgr.MgrPlayerData')
local vitals = require('server.Mgr.MgrVitals')
local survival = require('server.Mgr.MgrSurvival')
local players, task = game:GetService('Players'), game:GetService('Task')
local player = players:GetPlayers()[1]
local data = player and pd:GetDataInst(player)
if not data or not player.Character or not player.Character.Controller then
    print('PRIZE139 ABORT 玩家或存档未就绪') return
end
local function log(...) print('PRIZE139', '[专项探针]', ...) end
local growth = data.Extra.growth.potions
local oldSpeed, oldBody = growth.item167, growth.item168
local state = survival:GetState(player)
local oldWeak = state and state.weakUntil
local key = 'p:' .. tostring(player.UserId)
local oldEffects = ability.Effects[key]
local controller = player.Character.Controller
local function attrs(label)
    log(label, 'speed=' .. tostring(controller.WalkSpeed), 'maxHealth=' .. tostring(controller.MaxHealth),
        'planScale=' .. tostring(ability:BodyPlan(player).Scale), 'canAct=' .. tostring(vitals:CanAct(player)))
end
for n = 152, 166 do
    local id = 'item' .. tostring(n)
    local entry = cfg.Ability.MeleeWeapons[id] or cfg.Ability.Guns[id]
    log('武器配置', id, 'damage=' .. tostring(entry.Damage), 'interval=' .. tostring(entry.IntervalSec),
        'magazine=' .. tostring(entry.Magazine), 'effect=' .. tostring(entry.Effect and entry.Effect.Kind),
        'splash=' .. tostring(entry.Splash and entry.Splash.Damage))
end
task:Spawn(function()
    local ok, err = pcall(function()
        ability.Effects[key] = nil
        if state then state.weakUntil = nil end
        growth.item167, growth.item168 = 20, 10
        ability:ApplyGrowth(player)
        attrs('成长20/10')
        growth.item167, growth.item168 = 21, 11
        ability:ApplyGrowth(player)
        attrs('夹值21/11（非饮用通道）')
        growth.item167, growth.item168 = 20, 10
        if state then survival:ApplyWeak(state, 60); attrs('虚弱'); survival:ClearWeak(state); attrs('虚弱消退') end
        for _ = 1, 6 do
            ability:ApplyWeaponEffect(player, player, { Kind = 'poison' })
            ability:ApplyWeaponEffect(player, player, { Kind = 'burn' })
        end
        local effects = ability.Effects[key]
        log('层上限', 'poison=' .. tostring(effects.poison.stacks), 'burn=' .. tostring(effects.burn.stacks))
        ability:ApplyWeaponEffect(player, player, { Kind = 'frost' })
        ability:ApplyWeaponEffect(player, player, { Kind = 'frost' })
        attrs('霜冻重复')
        ability:ApplyWeaponEffect(player, player, { Kind = 'paralyze' })
        attrs('麻痹')
        task:Wait(0.7)
        attrs('麻痹到期')
        task:Wait(3)
        attrs('效果到期')
        log('效果清理', tostring(ability.Effects[key] == nil))
    end)
    growth.item167, growth.item168 = oldSpeed, oldBody
    if state then state.weakUntil = oldWeak end
    ability.Effects[key] = oldEffects
    ability:ApplyGrowth(player)
    log('恢复完成', 'ok=' .. tostring(ok), 'error=' .. tostring(err))
end)
