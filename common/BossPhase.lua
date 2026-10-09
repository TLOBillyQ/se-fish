-- #132 T11 高风险能力原型 · 能力 D：首领分阶段状态机。
-- 数值来源：GameSpec §12 哥斯拉（25000 血；每 2 秒爪击 50、每 6 秒甩尾 50、正前 10 米原子吐息秒杀；
-- 低于 60% 入水、改咬击 1000；低于 20% 重新上岸、伤害 +50%、吐息改为每 10 秒）。
-- 配置见 GameCfg.Ability.BossPhase。
--
-- 阶段与攻击的确定性契约（真机动画与命中仍须编辑器窗口试玩，见 issue #132 待办清单）：
--   * 阈值只升级不倒退：低于 60% 入水、低于 20% 狂暴；正好 60%/20% 不切（正文是「低于」）；
--     回血不退回上一阶段——避免在阈值线上反复横跳，是否允许倒退待策划确认。
--   * 一帧跨两个阈值只进最终合法阶段，中间被跳过的阶段记进 Log[i].Skipped 与 Stats.Skipped，
--     不补演中间阶段的招式、也不漏掉最终阶段。
--   * 攻击按阶段招式集（AttackSets）与固定书写顺序取唯一一个到期招式，同一帧最多落地一个。
--   * 失目标：不出招；起手中的吐息立即撤销并重新计时（目标回来不能白赚一次秒杀）。
--   * 死亡：撤销起手、清空待发，之后不再有任何攻击落地；打断只计一次。
local GameCfg = require('common.GameCfg')

local M = {}

local function cfg()
    return GameCfg.Ability.BossPhase
end

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

local function isPoint(p)
    return type(p) == 'table' and not isBadNumber(p.x) and not isBadNumber(p.y) and not isBadNumber(p.z)
end

local function copy(p)
    return { x = p.x, y = p.y, z = p.z }
end

local function now_(v)
    if isBadNumber(v) then return 0 end
    return v
end

-- 阶段链：normal → 各阈值（配置里按百分比降序 = 升级顺序）
local function chain(bossCfg)
    local list = { { Phase = 'normal' } }
    for _, threshold in ipairs(bossCfg.Thresholds) do
        list[#list + 1] = threshold
    end
    return list
end

local function phaseIndex(bossCfg, phase)
    local list = chain(bossCfg)
    for index, entry in ipairs(list) do
        if entry.Phase == phase then return index end
    end
    return 1
end

-- 当前阶段条目（normal 没有专属条目）
local function phaseEntry(state)
    local list = chain(state.Cfg)
    return list[phaseIndex(state.Cfg, state.Phase)]
end

local function attackSet(state)
    local set = state.Cfg.AttackSets and state.Cfg.AttackSets[state.Phase]
    return set or state.Cfg.AttackSets.normal
end

-- 招式间隔：狂暴阶段的吐息用阶段条目的 10 秒，其余用 Attacks 里的基准值
local function intervalOf(state, name)
    local entry = phaseEntry(state)
    if name == 'breath' and entry and not isBadNumber(entry.BreathIntervalSec) then
        return entry.BreathIntervalSec
    end
    local attack = state.Cfg.Attacks[name]
    if not attack or isBadNumber(attack.IntervalSec) then return 1 end
    return attack.IntervalSec
end

-- 招式伤害：入水咬击取阶段条目的 BiteDamage；狂暴阶段整体 ×(1 + DamageBonusPercent/100)
local function damageOf(state, name)
    local entry = phaseEntry(state)
    local attack = state.Cfg.Attacks[name] or {}
    local damage = attack.Damage
    if name == 'bite' and entry and not isBadNumber(entry.BiteDamage) then
        damage = entry.BiteDamage
    end
    if isBadNumber(damage) then damage = 0 end
    if entry and not isBadNumber(entry.DamageBonusPercent) then
        damage = damage * (1 + entry.DamageBonusPercent / 100)
    end
    return damage
end

local function resetCooldowns(state, now)
    state.Cooldown = {}
    for _, name in ipairs(attackSet(state)) do
        state.Cooldown[name] = now + intervalOf(state, name)
    end
    state.Pending = nil
end

-- 水平距离：吐息是「正前 10 米」，宿主与目标常不在同一高度
local function withinRange(state, name)
    local attack = state.Cfg.Attacks[name]
    if not attack or isBadNumber(attack.Range) then return true end
    if not state.Target then return false end
    local dx, dz = state.Target.x - state.Pos.x, state.Target.z - state.Pos.z
    return math.sqrt(dx * dx + dz * dz) <= attack.Range
end

---新建首领阶段状态。
---@param bossCfg? table
---@param now? number
---@param pos? table 首领位置（吐息射程判定用）
function M.New(bossCfg, now, pos)
    bossCfg = bossCfg or cfg()
    local state = {
        Cfg = bossCfg, Phase = 'normal', Alive = true, Target = nil, Pending = nil,
        Percent = 100, Pos = pos and copy(pos) or { x = 0, y = 0, z = 0 },
        Cooldown = {}, Log = {}, AttackLog = {},
        Stats = { Frames = 0, Transitions = 0, Skipped = 0, Attacks = 0, Interrupts = 0 },
    }
    resetCooldowns(state, now_(now))
    return state
end

---血量百分比；MaxHealth 非法时返回 nil（本帧不做阶段判定，也不清空已有阶段）
function M.PercentOf(health, maxHealth)
    if isBadNumber(health) or isBadNumber(maxHealth) or maxHealth <= 0 then return nil end
    local percent = health / maxHealth * 100
    if percent < 0 then percent = 0 end
    if percent > 100 then percent = 100 end
    return percent
end

---推进一帧。
---@param state table
---@param now number
---@param dt number
---@param input table { Health, MaxHealth, Alive, Target, Pos? }
---@return table events { Phase, PhaseChanged?, From?, To?, Skipped?, Percent, Attack?, Interrupted?, Reason? }
function M.Update(state, now, dt, input)
    now = now_(now)
    input = input or {}
    state.Stats.Frames = state.Stats.Frames + 1
    local events = { Phase = state.Phase, Percent = state.Percent, Interrupted = false }

    -- 死亡：起手撤销、待发清空，之后不再有任何攻击
    if input.Alive == false then
        if state.Pending then
            events.Interrupted = true
            events.Reason = 'death'
            state.Stats.Interrupts = state.Stats.Interrupts + 1
            state.Log[#state.Log + 1] = { At = now, Kind = 'interrupt', Reason = 'death',
                Attack = state.Pending.Name }
        end
        state.Pending = nil
        state.Alive = false
        return events
    end
    state.Alive = true
    state.Target = isPoint(input.Target) and copy(input.Target) or nil
    if isPoint(input.Pos) then state.Pos = copy(input.Pos) end

    -- 血量 → 阶段（只升级；一帧跨多个阈值只记最终阶段，被跳过的记进 Skipped）
    local percent = M.PercentOf(input.Health, input.MaxHealth)
    if percent then
        state.Percent = percent
        local target = 1
        for index, threshold in ipairs(state.Cfg.Thresholds) do
            if percent < threshold.Percent then target = index + 1 end
        end
        local current = phaseIndex(state.Cfg, state.Phase)
        if target > current then
            local list = chain(state.Cfg)
            local skipped = {}
            for index = current + 1, target - 1 do
                skipped[#skipped + 1] = list[index].Phase
            end
            events.PhaseChanged = true
            events.From = state.Phase
            events.To = list[target].Phase
            events.Skipped = skipped
            state.Phase = list[target].Phase
            state.Stats.Transitions = state.Stats.Transitions + 1
            state.Stats.Skipped = state.Stats.Skipped + #skipped
            state.Log[#state.Log + 1] = { At = now, Kind = 'phase', From = events.From,
                To = events.To, Percent = percent, Skipped = skipped }
            resetCooldowns(state, now)
        end
    end
    events.Phase = state.Phase
    events.Percent = state.Percent

    -- 失目标：撤销起手并重新计时（目标回来不能立刻落地一次秒杀）
    if state.Pending and not state.Target then
        local name = state.Pending.Name
        state.Pending = nil
        events.Interrupted = true
        events.Reason = 'lostTarget'
        state.Stats.Interrupts = state.Stats.Interrupts + 1
        state.Cooldown[name] = now + intervalOf(state, name)
        state.Log[#state.Log + 1] = { At = now, Kind = 'interrupt', Reason = 'lostTarget', Attack = name }
    end
    if not state.Target then return events end

    -- 起手完成后落地（原子吐息是秒杀，没有数值伤害）
    if state.Pending then
        if now >= state.Pending.ReadyAt then
            local pending = state.Pending
            state.Pending = nil
            state.Cooldown[pending.Name] = now + intervalOf(state, pending.Name)
            events.Attack = M.Land(state, now, pending)
        end
        return events
    end

    -- 取本帧唯一一个到期招式（按 AttackSets 的书写顺序，保证确定性）
    for _, name in ipairs(attackSet(state)) do
        local readyAt = state.Cooldown[name] or 0
        if now >= readyAt and withinRange(state, name) then
            local attack = state.Cfg.Attacks[name] or {}
            if not isBadNumber(attack.WindupSec) and attack.WindupSec > 0 then
                state.Pending = { Name = name, ReadyAt = now + attack.WindupSec,
                    Damage = damageOf(state, name), Lethal = attack.OneShot == true }
            else
                state.Cooldown[name] = now + intervalOf(state, name)
                events.Attack = M.Land(state, now, { Name = name, Damage = damageOf(state, name),
                    Lethal = attack.OneShot == true })
            end
            return events
        end
    end
    return events
end

---记录一次落地的攻击（供探针与台账取「攻击序列」）。
function M.Land(state, now, attack)
    local landed = { At = now, Name = attack.Name, Damage = attack.Damage, Lethal = attack.Lethal == true }
    state.Stats.Attacks = state.Stats.Attacks + 1
    if #state.AttackLog < 64 then state.AttackLog[#state.AttackLog + 1] = landed end
    return landed
end

---当前阶段是否在起手（探针/调试用）。
function M.Winding(state)
    return state.Pending ~= nil
end

return M
