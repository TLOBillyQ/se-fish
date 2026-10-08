-- #50 服务端隔离探针；不自动加载、不挂 manager、不改正式鱼或配置。
-- 由获准的运行环境 loadfile 后调用 Probe.Run(context)，本轮禁止执行编辑器。
local Probe = {}

local retained = {
    eel = '放电次数、睡眠、乱甩与 eel_discharge 锚点伤害',
    gar = '仇恨累积、锁定预警、绕后咬空、头部弱点',
    shrimp = '左右双击、尾刺击飞、活动/眩晕周期',
    dragon = '啄击、俯冲轨迹、落地眩晕、头部弱点',
    kingCrab = '前方乱刺、多次命中去重、活动/眩晕周期',
    crabBoss = '双击、冲撞、旋转三招互斥与接触伤害',
    swordfish = '左右挥头、翻滚接触、高跃轨迹与命中去重',
    shark = '扫头、翻滚接触、高跃轨迹与命中去重',
    walrus = '甩头、直线突击轨迹与命中去重',
    orca = '爪击、虎啸、甩尾、鲸跃四招互斥与伤害',
}

-- 逐项遍历实际配置，包含尚未 implemented 的条目；未知行为明确标出，不能缩减范围。
function Probe.monsterMappings(cfg)
    local rows = {}
    local ability = cfg.Ability or {}
    for id, fish in pairs(cfg.Fish) do
        local flight = ability.Flight and ability.Flight.Species and ability.Flight.Species[id]
        local boss = ability.BossPhase and ability.BossPhase.Species and ability.BossPhase.Species[id]
        local behavior, official, keep
        if boss then
            behavior, official = '阶段首领', { 'ChaseTarget', 'StopMove', 'CastAbilityByKey' }
            keep = 'BossPhase 阈值与跳阶段、入水/上岸轨迹、吐息、叼人 CarryMount、阶段伤害'
        elseif flight then
            behavior = flight.Mode == 'leap' and '跃起携带' or '飞行俯冲'
            official = { 'StopMove', 'CastAbilityByKey' }
            keep = 'FlightPath 三维巡航/俯冲/跃起、边界钳制、目标追踪与伤害去重'
            if flight.ThrowIntervalSec then keep = keep .. '、周期投掷与落地范围' end
            if flight.Mode == 'leap' then keep = keep .. '、咬中/接触伤害、CarryMount 叼走入海与释放' end
        elseif fish.Grade == 'normal' or fish.Grade == 'rare' then
            behavior, official = '逃跑', { 'MoveToPos', 'MoveDirection', 'StopMove' }
            keep = 'MgrFishUnit 最近水域、地块边界、逃跑时限、举鱼/放下状态与逃脱结算'
        elseif retained[fish.Combat] then
            behavior = fish.Combat
            official = { 'ChaseTarget', 'StopMove', 'CastAbility', 'BasicCommand' }
            keep = retained[fish.Combat]
        else
            behavior, official = '未登记行为', { 'ChaseTarget', 'StopMove' }
            keep = '需补业务行为登记：' .. tostring(fish.SourceDescription or fish.Combat or id)
        end
        rows[#rows + 1] = { id = id, name = fish.Name, grade = fish.Grade,
            source = fish.source, implemented = fish.implemented, behavior = behavior,
            official = official, retained = keep .. '；仇恨注入、控制中断及 MgrVitals 权威结算保留',
            status = '待试玩验证' }
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

-- 探针入口。context 必须注入隔离对象与观测边界；Run 结束后单位与临时状态必须清理。
function Probe.Run(context)
    assert(context ~= nil and context.ai ~= nil and context.createUnit ~= nil
        and context.destroyUnit ~= nil and context.players ~= nil and context.now ~= nil,
        'official_ai_probe 需要隔离 context')
    local unit = context.createUnit()
    local log = context.logger or print
    local ok, result = pcall(function()
        log('[official_ai_probe] 创建隔离单位 unit=' .. tostring(unit and unit.UnitId))
        return { unit = unit, evidence = {} }
    end)
    local cleanupOk, cleanupErr = pcall(context.destroyUnit, unit)
    if not cleanupOk then
        context.unit = nil
        error('official_ai_probe 清理失败: ' .. tostring(cleanupErr), 0)
    end
    context.unit = nil
    if not ok then error(result, 0) end
    return result
end

-- 交接门卫：每次切换先撤销旧方写入权并停官方 AI；回调必须各自判断接收到的 token。
function Probe.newHandoff(ai, unit, applyPosition, applyHit, log)
    log = log or print
    local gate = { generation = 0, owner = nil, appliedHits = {} }
    function gate:Switch(mode)
        self.generation = self.generation + 1
        if ai ~= nil and ai.StopAI ~= nil then ai.StopAI(unit) end
        local token = { mode = mode, generation = self.generation }
        self.owner = token
        log(string.format('[official_ai_probe] 轨迹交接 mode=%s generation=%d', mode, self.generation))
        return token
    end
    function gate:IsActive(token) return token ~= nil and token.generation == self.generation end
    function gate:Write(token, position)
        if not self:IsActive(token) or self.owner.mode == 'controlled' then
            log('[official_ai_probe] 拒绝失效写入 token=' .. tostring(token and token.generation))
            return false
        end
        applyPosition(position)
        return true
    end
    function gate:Hit(token, key, damage)
        if not self:IsActive(token) or self.appliedHits[key] then return false end
        self.appliedHits[key] = true
        applyHit(damage)
        return true
    end
    return gate
end

return Probe
