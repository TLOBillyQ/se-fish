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
    local c = context or {}
    assert(c.ai and c.createUnit and c.destroyUnit and c.players and c.now and c.wait and c.vector,
        'official_ai_probe 需要隔离 context 与时间/向量边界')
    assert(c.isolated == true and type(c.isIsolated) == 'function', '需要明确隔离归属')
    assert(c.evidence == 'engine' or c.evidence == 'offline', '需要明确证据类型')
    local unit
    local report = { evidence = {}, missing = {}, errors = {}, kind = c.evidence }
    local function log(message)
        if c.logger then c.logger('[official_ai_probe][' .. c.evidence .. '] ' .. message) end
    end
    local function missing(name, reason)
        report.missing[#report.missing + 1] = { name = name, reason = reason }
        log(name .. ' 缺证 ' .. reason)
    end
    local function observe(name, field, expected, before)
        local facts = c.observe and c.observe(unit, name)
        if not facts or facts[field] == nil then missing(name, '外部观测未提供 ' .. field); return end
        local value = facts[field]
        local passed = before ~= nil and value > before or before == nil and value == expected
        report.evidence[#report.evidence + 1] = { name = name, passed = passed, value = value, at = c.now() }
        log(name .. ' passed=' .. tostring(passed) .. ' value=' .. tostring(value))
        assert(passed, name .. ' 外部观测不满足')
    end
    local ok, failure = pcall(function()
        unit = assert(c.createUnit(), '创建隔离单位失败')
        assert(c.isIsolated(unit), '拒绝非隔离单位')
        local ai, v = c.ai, c.vector
        ai.MoveDirection(unit, v(1, 0, 0), 0.3, 0)
        c.wait(0.1); observe('移动方向', 'moving', true)
        ai.StopMove(unit, 0.3)
        c.wait(0.1); observe('停止移动', 'stopped', true)
        c.wait(0.4)
        ai.MoveToPos(unit, unit:GetPosition() + v(4, 0, 0), 0.3, 0.1, 0)
        c.wait(0.1); observe('移动位置', 'moving', true)
        ai.StopAI(unit)
        c.wait(0.4); observe('指令取消', 'stopped', true)
        ai.StartAI(unit)
        if c.target then
            assert(c.isIsolated(c.target) and c.target ~= unit, '追逐目标必须隔离')
            ai.ChaseTarget(unit, c.target, 20, 0.1, 0.3, ai.Configs.CMD_JUMP, 0, 1)
            c.wait(0.1); observe('追逐目标', 'moving', true)
            ai.StopAI(unit); ai.StartAI(unit)
        else missing('追逐目标', '没有隔离 target') end
        -- players必须来自真实Players服务；context不能替换vendor使用的Players列表。
        local safe, targetVisible = true, false
        for _, player in ipairs(c.players()) do
            if not player.Character or not c.isIsolated(player.Character) then safe = false end
            if player.Character and c.target and player.Character.UnitId == c.target.UnitId then targetVisible = true end
        end
        safe = safe and targetVisible
        if safe and c.target then
            ai.SearchEnemy(unit, 20, 0, {}, {}, 0.1, ai.Configs.CMD_JUMP, nil, 20, 3)
            c.wait(ai.Configs.REACT_TICK * 2 + 0.05); observe('选敌追逐', 'moving', true)
            ai.StopAI(unit); ai.StartAI(unit)
        else missing('选敌追逐', 'Players包含非隔离对象或无目标，拒绝扫描真实玩家') end
        local facts = c.observe and c.observe(unit, '基础指令前')
        ai.BasicCommand(unit, ai.Configs.CMD_JUMP)
        c.wait(0.1)
        if facts and facts.jumps ~= nil then observe('基础跳跃', 'jumps', nil, facts.jumps)
        else missing('基础跳跃', '缺少跳跃计数观测') end
        if c.abilityKey then
            ai.CastAbilityByKey(unit, c.abilityKey, 0, c.target)
            c.wait(0.1); observe('技能指令', 'castObserved', true)
        else missing('技能指令', '无隔离技能预设与技能观测') end
        -- 交接门卫只控制业务回调；vendor取消通过停止后再次观测证明。
        local gate = Probe.newHandoff(ai, unit, function(p) unit:SetPosition(p) end,
            function(damage) if c.applyHit then c.applyHit(damage) end end, log)
        local old = gate:Switch('official')
        ai.MoveDirection(unit, v(1, 0, 0), 0, 0)
        c.wait(0.1)
        local custom = gate:Switch('custom')
        assert(not gate:Write(old, v(99, 99, 99)), '旧代次未撤权')
        assert(gate:Write(custom, unit:GetPosition()), '自定义轨迹未获得写入权')
        local control = gate:Switch('controlled')
        assert(not gate:Write(control, v(99, 99, 99)) and not gate:Hit(control, 'control', 1), '控制态未禁用写入/伤害')
        c.wait(0.2); observe('轨迹交接取消官方移动', 'stopped', true)
        gate:Switch('official')
        ai.MoveDirection(unit, v(0, 0, 1), 0.2, 0)
        c.wait(0.1); observe('控制解除恢复官方', 'moving', true)
        missing('Nav', '未提供真实 FindingPathUnit，导航与避障不能由离线向量证明')
        missing('仇恨注入', 'vendor优先级/焦点/阈值为预留接口，当前不生效；业务需维护目标')
    end)
    if not ok then report.errors[#report.errors + 1] = tostring(failure) end
    if unit then
        local stopped, stopErr = pcall(c.ai.StopAI, unit)
        if not stopped then report.errors[#report.errors + 1] = '停止AI: ' .. tostring(stopErr) end
        local cleaned, cleanupErr = pcall(c.destroyUnit, unit)
        if not cleaned then error('official_ai_probe 清理失败: ' .. tostring(cleanupErr), 0) end
    end
    c.unit = nil
    report.cleaned = true
    report.ok = ok and #report.errors == 0
    report.complete = report.ok and #report.missing == 0 -- 核心调用完成不能解锁缺证能力。
    return report
end

-- 交接门卫：每次切换先撤销旧方写入权并停官方 AI；回调必须各自判断接收到的 token。
function Probe.newHandoff(ai, unit, applyPosition, applyHit, log)
    log = log or print
    local gate = { generation = 0, owner = nil, appliedHits = {} }
    function gate:Switch(mode)
        assert(mode == 'official' or mode == 'custom' or mode == 'controlled', '未知交接模式')
        self.generation = self.generation + 1
        self.owner = nil -- 先撤权，接口失败也不能保留旧写入权。
        self.appliedHits = {}
        ai.StopAI(unit)
        if mode == 'official' then ai.StartAI(unit) end
        local token = { mode = mode, generation = self.generation }
        self.owner = token
        log(string.format('[official_ai_probe] 轨迹交接 mode=%s generation=%d', mode, self.generation))
        return token
    end
    function gate:IsActive(token) return token ~= nil and token == self.owner and token.generation == self.generation end
    function gate:Write(token, position)
        if not self:IsActive(token) or self.owner.mode == 'controlled' then
            log('[official_ai_probe] 拒绝失效写入 token=' .. tostring(token and token.generation))
            return false
        end
        applyPosition(position)
        return true
    end
    function gate:Hit(token, key, damage)
        if not self:IsActive(token) or token.mode == 'controlled' or self.appliedHits[key] then return false end
        self.appliedHits[key] = true
        applyHit(damage)
        return true
    end
    return gate
end

return Probe
