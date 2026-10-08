-- #49 服务端隔离探针：加载无副作用，禁止以真实玩家或玩法单位作为 owner/source。
-- 从仓库外手动装载；本文件不在部署树，不注册 manager、不改预设或存档。
local Probe = {}

function Probe.BuildMappings(cfg)
    local effects = cfg.Ability.StatusEffects
    local result = {}
    for _, kind in ipairs({ 'poison', 'burn', 'frost', 'paralyze', 'weak' }) do
        local entry = effects[kind]
        result[kind] = {
            duration = entry and entry.DurationSec or cfg.Survival.WeakSec,
            -- Stackable=false 会拒绝重复获得；只刷新也必须开启重获，再禁止增层。
            stackable = true, stackCountStep = 1,
            maxStackCount = entry and entry.MaxStacks or 1,
            stackCountMode = (kind == 'poison' or kind == 'burn') and 2 or 0,
            stackDurationMode = 1, sameSourceStack = false,
            attrConfigs = {}, obtainPerformanceList = {}, lostPerformanceList = {},
        }
    end
    return result
end

-- 旧档明确是剩余秒数，不使用 weakUntil，也不减去墙钟离线时长。
-- 濒死/死亡旧档优先交给现存复活结算，不能凭该函数抢先恢复虚弱。
function Probe.WeakRemaining(data, maximum)
    local mark = data and data.Extra and data.Extra.survival
    if type(mark) ~= 'table' or mark.dying or mark.dead then return 0 end
    local value = mark.weakRemaining
    if type(value) ~= 'number' or value ~= value or value == math.huge or value <= 0 then return 0 end
    return math.min(value, maximum)
end

-- context：api=server.ModifierAPI；owner/source/source2 均为本轮专属新建单位；
-- isolated=true 是调用者明确承诺；isIsolated(unit) 必须验证其归属及非玩家性质。
-- assets 含五个不同效果预设 AssetKey；cfg=GameCfg；wait(seconds) 在协程等待；
-- dispose() 销毁本轮全部隔离单位（包含失败创建后未注册的子实体）。
-- log(line) 留证；evidence='engine' 仅限真实 SE server，否则必须标 'offline'。
-- 无自动调用入口：当前编辑器 preflight 阻塞，不可执行本探针。
function Probe.Run(context)
    local c = context or {}
    assert(c.isolated == true and type(c.isIsolated) == 'function', '必须明确隔离对象归属')
    for _, unit in ipairs({ c.owner, c.source, c.source2 }) do
        assert(c.isIsolated(unit), '目标必须是非玩家隔离单位')
    end
    assert(c.owner and c.source and c.source2 and c.owner ~= c.source and c.source ~= c.source2,
        '隔离单位必须齐全且互不相同')
    assert(type(c.dispose) == 'function' and type(c.wait) == 'function' and type(c.log) == 'function',
        '必须提供清理、等待与日志边界')
    assert(c.evidence == 'engine' or c.evidence == 'offline', '必须标明证据类型')
    local api, connections = c.api, {}
    local report = { evidence = c.evidence, checks = {}, errors = {}, cleaned = false }
    local function log(message)
        c.log('[modifier_probe][' .. c.evidence .. '] ' .. message)
    end
    local function check(label, condition, value)
        report.checks[#report.checks + 1] = { name = label, passed = condition == true, value = value }
        log(label .. ' passed=' .. tostring(condition == true) .. ' value=' .. tostring(value))
        assert(condition, label .. ': ' .. tostring(value))
    end
    local function near(a, b) return math.abs(a - b) <= (c.tolerance or 0.15) end
    local function listen(entity, name, callback)
        local event = entity:FindFirstChild(name)
        assert(event, '预设事件缺失: ' .. name)
        connections[#connections + 1] = event:Connect(callback)
    end
    local function one(key)
        local units = api.GetUnitModifiers(c.owner, key)
        assert(#units == 1, '效果实例应唯一: ' .. key .. ' count=' .. #units)
        return units[1]
    end
    local ok, err = pcall(function()
        local mappings, seen = Probe.BuildMappings(c.cfg), {}
        for _, kind in ipairs({ 'poison', 'burn', 'frost', 'paralyze', 'weak' }) do
            local key = c.assets and c.assets[kind]
            assert(type(key) == 'string' and key ~= '' and not seen[key], '五效果需要不同预设: ' .. kind)
            seen[key] = true
        end
        check('初始隔离单位无效果', #api.GetUnitModifiers(c.owner) == 0)
        for _, kind in ipairs({ 'poison', 'burn', 'frost', 'paralyze', 'weak' }) do
            local key, conf = c.assets[kind], mappings[kind]
            conf.source = c.source
            check(kind .. '.新增', api.AddModifier(c.owner, key, conf) == api.Enums.CreateResult.Added)
            local entity = one(key)
            check(kind .. '.实体激活', entity:GetAttribute('IsActive') == true)
            check(kind .. '.拥有者', api.GetModifierOwner(entity) == c.owner)
            check(kind .. '.来源', api.GetSourceByKey(c.owner, key) == c.source)
            local finish, loss, reobtain, pauses, resumes = 0, 0, 0, 0, 0
            listen(entity, 'DurationFinish', function() finish = finish + 1 end)
            listen(entity, 'ModifierLoss', function() loss = loss + 1 end)
            listen(entity, 'ModifierReobtain', function() reobtain = reobtain + 1 end)
            listen(entity, 'Pause', function() pauses = pauses + 1 end)
            listen(entity, 'Resume', function() resumes = resumes + 1 end)
            c.wait(conf.duration * 0.25)
            local before = api.GetRemainingTimeByKey(c.owner, key)
            for _ = 1, conf.maxStackCount + 1 do
                check(kind .. '.重获', api.AddModifier(c.owner, key, conf) == api.Enums.CreateResult.Reobtained)
            end
            check(kind .. '.重获事件', reobtain == conf.maxStackCount + 1, reobtain)
            check(kind .. '.同一实体', one(key) == entity)
            check(kind .. '.层数上限或只刷新', entity:GetAttribute('CurrCount') == conf.maxStackCount,
                entity:GetAttribute('CurrCount'))
            local refreshed = api.GetRemainingTimeByKey(c.owner, key)
            check(kind .. '.刷新而非累加', refreshed > before and near(refreshed, conf.duration), refreshed)
            -- 异源重获不会换掉原来源；未来业务须明确首来源归属或自行按层管理来源。
            conf.source = c.source2
            check(kind .. '.异源重获', api.AddModifier(c.owner, key, conf) == api.Enums.CreateResult.Reobtained)
            check(kind .. '.保留首来源', api.GetSourceByKey(c.owner, key) == c.source)
            check(kind .. '.Pause', api.Pause(c.owner, key, entity.UnitId) == true)
            local frozen = api.GetRemainingTimeByKey(c.owner, key)
            c.wait(conf.duration + 0.2)
            check(kind .. '.暂停冻结', near(api.GetRemainingTimeByKey(c.owner, key), frozen))
            check(kind .. '.暂停无到期', finish == 0 and api.IsInModifier(c.owner, key))
            check(kind .. '.Resume', api.Resume(c.owner, key, entity.UnitId) == true)
            check(kind .. '.暂停恢复事件', pauses == 1 and resumes == 1)
            check(kind .. '.恢复剩余', near(api.GetRemainingTimeByKey(c.owner, key), frozen))
            check(kind .. '.设层数', api.SetModifierStackCount(entity, 1) == true)
            api.AddModifierStackCount(entity, 1) -- vendor 文档说返回层数，当前实现实为 boolean；以实体为准。
            check(kind .. '.增层', entity:GetAttribute('CurrCount') == math.min(2, conf.maxStackCount))
            api.AddModifierStackCount(entity, -1)
            if conf.maxStackCount == 1 then
                check(kind .. '.减至零移除', not api.IsInModifier(c.owner, key))
                check(kind .. '.显式移除不冒充到期', finish == 0 and loss == 1)
                check(kind .. '.重新新增', api.AddModifier(c.owner, key, conf) == api.Enums.CreateResult.Added)
                entity = one(key)
                finish, loss = 0, 0
                listen(entity, 'DurationFinish', function() finish = finish + 1 end)
                listen(entity, 'ModifierLoss', function() loss = loss + 1 end)
            end
            check(kind .. '.设置剩余', api.SetModifierRemainTime(entity, 0.4) == true)
            check(kind .. '.延时', api.AddModifierDurationByInstance(entity, 0.3) == true)
            check(kind .. '.时长查询', near(api.GetRemainingTimeByKey(c.owner, key), 0.7))
            c.wait(0.9)
            check(kind .. '.到期移除', not api.IsInModifier(c.owner, key))
            check(kind .. '.到期事件一次', finish == 1 and loss == 1, finish .. '/' .. loss)
            check(kind .. '.清理幂等', api.ClearUnitModifiers(c.owner, key) == 0)
        end
        -- 虚弱断线不能靠 Pause 保留已销毁实体：保存剩余秒数，重进重建实例。
        local key, conf = c.assets.weak, mappings.weak
        conf.source = c.source
        local remaining = Probe.WeakRemaining(c.legacyData, conf.duration)
        if remaining == 0 then remaining = 17 end -- 人工旧档样例，不读取真实玩家存档。
        check('weak.旧档重建', api.AddModifier(c.owner, key, conf) == api.Enums.CreateResult.Added)
        local entity = one(key)
        api.SetModifierRemainTime(entity, remaining)
        api.Pause(c.owner, key, entity.UnitId)
        local mark = { Extra = { survival = { weakRemaining = math.ceil(api.GetRemainingTimeByKey(c.owner, key)) } } }
        check('weak.退出清理', api.ClearUnitModifiers(c.owner, key) == 1)
        c.wait(2) -- 离线墙钟仅流逝，不更改持久剩余秒数。
        check('weak.重进重建', api.AddModifier(c.owner, key, conf) == api.Enums.CreateResult.Added)
        entity = one(key)
        local restored = Probe.WeakRemaining(mark, conf.duration)
        api.SetModifierRemainTime(entity, restored)
        check('weak.离线不扣时间', near(api.GetRemainingTimeByKey(c.owner, key), remaining), restored)
        check('weak.RemoveModifier', api.RemoveModifier(entity) == true)
        check('weak.实例移除', not api.IsInModifier(c.owner, key))
    end)
    if not ok then report.errors[#report.errors + 1] = tostring(err) end
    -- 每项独立收尾，某一项失败不能阻止后续单位销毁。
    local function cleanup(label, fn)
        local success, failure = pcall(fn)
        if not success then report.errors[#report.errors + 1] = label .. ': ' .. tostring(failure) end
    end
    cleanup('清空效果', function() api.ClearUnitModifiers(c.owner) end)
    for _, connection in ipairs(connections) do cleanup('断开连接', function() connection:Disconnect() end) end
    cleanup('销毁隔离单位', c.dispose)
    report.cleaned = #report.errors == 0
    report.ok = ok and report.cleaned
    log('完成 ok=' .. tostring(report.ok) .. ' cleaned=' .. tostring(report.cleaned))
    for _, failure in ipairs(report.errors) do log('失败 ' .. failure) end
    return report
end

return Probe
