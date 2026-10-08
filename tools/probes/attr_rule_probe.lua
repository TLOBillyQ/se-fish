-- #48 服务端隔离探针；不挂入玩法入口，不修改 vendor 或全局配置。
local AttrGrowth = require('common.AttrGrowth')
local BodyScale = require('common.BodyScale')
local GameCfg = require('common.GameCfg')
local Probe = {}

-- 可执行迁移映射：只生成计划，不写玩家、Controller 或存档。
-- 统一顺序为 (Base + BaseExtra) * (1 + Ratio) + Bonus，最后业务钳制。
-- 永久成长从 PotionCount / WeaponDamageScale 重建，临时效果从权威状态重建；不保存最终值或 Buff 句柄。
function Probe.Map(snapshot)
    local s = snapshot or {}
    local body = BodyScale.Plan(s.bodyPotions)
    local baseSpeed = s.baseSpeed or GameCfg.Ability.MoveSpeed.Base
    local speed = AttrGrowth.EffectiveSpeed(baseSpeed, s.speedPotions, s)
    if type(baseSpeed) ~= 'number' or baseSpeed <= 0 or baseSpeed ~= baseSpeed or baseSpeed == math.huge then
        baseSpeed = GameCfg.Ability.MoveSpeed.Base
    end
    local hunger = s.hunger or GameCfg.Vitals.MaxHunger
    assert(type(hunger) == 'number' and hunger == hunger and math.abs(hunger) < math.huge, '饥饿度须为有限数')
    hunger = math.max(0, math.min(GameCfg.Vitals.MaxHunger, math.floor(hunger)))
    local damageScale = s.damageScale or 1
    assert(type(damageScale) == 'number' and damageScale >= 1 and damageScale < math.huge, '武器加成须为有限正倍率')
    local function entry(value, base, extra, ratio, min, max, write, restore)
        return { Value = value, Components = { Base = base, BaseExtra = extra, Ratio = ratio, Bonus = 0 },
            Min = min, Max = max, Write = write, Restore = restore }
    end
    return {
        MaxHealth = entry(body.Health, GameCfg.Ability.BodyScale.HealthBase,
            body.Health - GameCfg.Ability.BodyScale.HealthBase, 0,
            GameCfg.Ability.BodyScale.HealthBase, body.MaxHealth,
            'Controller.MaxHealth；提上限不回血，降上限夹当前血；MgrVitals:RefreshMaxHealth 单点',
            'PotionCount(item168) → BodyScale.Plan；血量与生命状态仍由 MgrVitals/MgrSurvival 恢复'),
        WalkSpeed = entry(speed, baseSpeed, 0, speed / baseSpeed - 1, 0,
            baseSpeed * GameCfg.Ability.SpeedPotion.MaxFactor,
            'Controller.WalkSpeed；MgrAbility:RefreshMoveSpeed 单点',
            'PotionCount(item167)；一次捕获基础移速；成长×虚弱×霜冻，麻痹为0，再写折合 Ratio'),
        BodyScale = entry(body.Scale, GameCfg.Ability.BodyScale.Base,
            body.Scale - GameCfg.Ability.BodyScale.Base, 0, GameCfg.Ability.BodyScale.Base, body.MaxScale,
            '无 vendor Controller 映射；业务 AbilityAPI.SetBodyScale 应用 SetScale 和派生量',
            'PotionCount(item168) → BodyScale.Plan；角色重建后整体重套'),
        Hunger = entry(hunger, hunger, 0, 0, 0, GameCfg.Vitals.MaxHunger,
            '无 vendor Controller 映射；MgrVitals:SetHunger + WriteHunger，整秒递减/进食保持原入口',
            '当前饥饿是会话状态；复活回满或 ApplyRevive 最低值；离线规则须由 MgrSurvival 决定，不新增存档'),
        WeaponDamageScale = entry(damageScale, 1, 0, damageScale - 1, 1, nil,
            '无 vendor Controller 映射；MgrWeapon 各伤害入口只乘一次 WeaponDamageScale(kind)',
            'PlayerData:ShopUpgradeLevel(kind) → GameCfg.Shop.DamageScale；按种类线性相加的升级折合 Ratio'),
    }
end

local function nearly(a, b)
    return math.abs((a or 0) - (b or 0)) < 1e-9
end

-- context.Target/CreateBuffUnits 必须由调用方提供隔离对象；Run 拥有并销毁它们。
-- 只调公开根 AttrAPI；所有步骤记录，异常后仍完整清理，清理失败则整体失败。
function Probe.Run(context)
    assert(type(context) == 'table' and context.Target ~= nil and type(context.CreateBuffUnits) == 'function',
        'attr_rule_probe 需要隔离 Target 与 CreateBuffUnits')
    assert(type(context.Log) == 'function', 'attr_rule_probe 需要 Log 回调')
    assert(context.Isolated == true, 'attr_rule_probe 只接受显式隔离环境')
    local api = assert(context.AttrAPI, 'attr_rule_probe 需要公开根 AttrAPI')
    local target, buffUnit = context.Target, nil
    local bounds = { Verified = 0, Missing = {} }
    local businessClampVerified = false
    local errors = {}
    local function log(step, status, detail)
        local ok, err = pcall(context.Log, string.format('[attr_probe] %s %s %s', step, status, tostring(detail or '')))
        if not ok then errors[#errors + 1] = '日志回调失败 [' .. step .. ']: ' .. tostring(err) end
    end
    local function fail(reason) errors[#errors + 1] = reason end
    local function assertTrue(value, reason)
        if not value then error(reason, 2) end
    end
    local ok, runErr = pcall(function()
        local c = api.Enums.AttrComponentType
        log('begin', 'ok', '仅隔离对象，不碰玩法单位')
        assertTrue(api.GetAttrUnit(target) == nil, '隔离目标已有属性单位，拒绝污染')
        local first = assert(api.EnsureAttrUnit(target), '懒创建失败')
        local second = assert(api.EnsureAttrUnit(target), '重复懒创建失败')
        assertTrue(first == second, '懒创建返回了多个属性单位')
        log('lazy-create', 'ok', '重复调用复用同一属性单位')

        assertTrue(api.SetAttrComponent(target, 'WalkSpeed', c.Base, 100), 'Base 写入失败')
        assertTrue(api.SetAttrComponent(target, 'WalkSpeed', c.BaseExtra, 20), 'BaseExtra 写入失败')
        assertTrue(api.SetAttrComponent(target, 'WalkSpeed', c.Ratio, 0.5), 'Ratio 写入失败')
        assertTrue(api.SetAttrComponent(target, 'WalkSpeed', c.Bonus, 7), 'Bonus 写入失败')
        assertTrue(nearly(api.GetAttrComponent(target, 'WalkSpeed', c.Base), 100), 'Base 读回错误')
        assertTrue(nearly(api.GetAttrComponent(target, 'WalkSpeed', c.BaseExtra), 20), 'BaseExtra 读回错误')
        assertTrue(nearly(api.GetAttrComponent(target, 'WalkSpeed', c.Ratio), 0.5), 'Ratio 读回错误')
        assertTrue(nearly(api.GetAttrComponent(target, 'WalkSpeed', c.Bonus), 7), 'Bonus 读回错误')
        assertTrue(nearly(api.GetAttr(target, 'WalkSpeed'), 187), '最终值公式错误')
        log('components', 'ok', '公式=187；未配置属性按无钳制处理')
        assertTrue(target.Controller == nil or nearly(target.Controller.WalkSpeed, 187),
            'WalkSpeed 未同步 Controller；若是真实单位须记录 vendor 仅打印不返回错误')
        log('controller', 'ok', 'WalkSpeed 是 vendor 内置 Controller 映射')

        -- 只读取实际全局配置，不临时修改 vendor 配置来制造上下限证据。
        for key, config in pairs(api.GetAllAttrConfigs()) do
            if type(config.Min) == 'number' or type(config.Max) == 'number' then
                local saved = {}
                for _, component in ipairs({ c.Base, c.BaseExtra, c.Ratio, c.Bonus }) do
                    saved[component] = api.GetAttrComponent(target, key, component)
                    assertTrue(api.SetAttrComponent(target, key, component, 0), '清空分量失败')
                end
                for _, edge in ipairs({ 'Min', 'Max' }) do
                    local limit = config[edge]
                    if type(limit) == 'number' then
                        local overflow = limit + (edge == 'Min' and -100 or 100)
                        assertTrue(api.SetAttrComponent(target, key, c.Base, overflow), '越界写入失败')
                        assertTrue(nearly(api.GetAttr(target, key), limit), key .. '.' .. edge .. ' 钳制错误')
                        log('bounds', 'ok', key .. '.' .. edge .. '=' .. tostring(limit))
                    end
                end
                for component, value in pairs(saved) do api.SetAttrComponent(target, key, component, value) end
                bounds.Verified = bounds.Verified + 1
            end
        end
        if bounds.Verified == 0 then
            bounds.Missing[1] = '实际地图无带 Min/Max 的属性配置，vendor 上下限缺证'
            log('bounds', 'missing', bounds.Missing[1])
        end
        -- 饥饿无 Controller 映射：先让真实包完成公式，再按业务上限钳制。
        -- (400+100)*0.5+10=260；提前夹 Base 为300则为210，断言能区分顺序。
        assertTrue(api.GetAttrConfig('Hunger') == nil, 'Hunger 已有配置，需要按实际配置重新核对业务接缝')
        for _, row in ipairs({ { c.Base, 400 }, { c.BaseExtra, 100 }, { c.Ratio, -0.5 }, { c.Bonus, 10 } }) do
            assertTrue(api.SetAttrComponent(target, 'Hunger', row[1], row[2]), '业务顺序分量写入失败')
        end
        local raw = api.GetAttr(target, 'Hunger')
        assertTrue(nearly(raw, 260) and Probe.Map({ hunger = raw }).Hunger.Value == 260, '业务钳制先后顺序错误')
        api.SetAttrComponent(target, 'Hunger', c.Bonus, 100)
        assertTrue(Probe.Map({ hunger = api.GetAttr(target, 'Hunger') }).Hunger.Value == GameCfg.Vitals.MaxHunger,
            '业务 Max 钳制错误')
        api.SetAttrComponent(target, 'Hunger', c.Base, -1000)
        assertTrue(Probe.Map({ hunger = api.GetAttr(target, 'Hunger') }).Hunger.Value == 0, '业务 Min 钳制错误')
        businessClampVerified = true
        log('business-clamp', 'ok', '先公式260，再钳制0/300；不提前夹分量')

        assertTrue(api.SetAttrComponent(target, 'WeaponDamageScale', c.Base, 1), '武器基础倍率写入失败')
        local buffId, buffErr = api.AddAttrBuff(target, {
            { AttrKey = 'WalkSpeed', AttrComponentType = c.BaseExtra, Value = 10 },
            { AttrKey = 'WalkSpeed', AttrComponentType = c.Ratio, Value = 0.1 },
            { AttrKey = 'WeaponDamageScale', AttrComponentType = c.Ratio, Value = 0.25 },
        })
        assertTrue(buffId ~= nil, 'Buff 添加失败: ' .. tostring(buffErr))
        assertTrue(nearly(api.GetAttr(target, 'WalkSpeed'), 215), 'Buff 重算错误')
        assertTrue(nearly(api.GetAttr(target, 'WeaponDamageScale'), 1.25),
            '武器 Ratio 叠加错误，实际=' .. tostring(api.GetAttr(target, 'WeaponDamageScale')))
        log('buff-add', 'ok', '两条 WalkSpeed 与一条武器加成已重算')
        assertTrue(api.RemoveAttrBuff(target, buffId), 'Buff 移除失败')
        assertTrue(nearly(api.GetAttr(target, 'WalkSpeed'), 187), 'Buff 移除残留')
        assertTrue(nearly(api.GetAttr(target, 'WeaponDamageScale'), 1),
            '武器加成移除残留，实际=' .. tostring(api.GetAttr(target, 'WeaponDamageScale')))
        log('buff-remove', 'ok', '各分量已按记录撤回')

        local created = assert(context.CreateBuffUnits(), '隔离 Buff 单位创建失败')
        buffUnit = created[1]
        buffUnit.Parent = target -- 加成单位按包约定挂在隔离目标下，与 AttrUnit 并列
        -- 引擎默认 MaxHealth=100；样例显式以公开 API 建立300基线。
        assertTrue(api.SetAttrComponent(target, 'MaxHealth', c.Base, 300), 'MaxHealth 基线写入失败')
        assertTrue(nearly(api.GetAttr(target, 'MaxHealth'), 300), 'MaxHealth 基线前置不满足')
        -- 真实预设可能已用空表初始化；Init 对已初始化实例不会覆盖配置。
        -- 只设置本轮隔离 Buff 实例属性，不修改预设或 vendor。
        local buffConfigs = { { AttrKey = 'MaxHealth', AttrComponentType = c.Bonus, Value = 30 } }
        buffUnit:SetAttribute('AttrBuffConfigs', buffConfigs)
        assertTrue(api.InitAttrBuffUnit(buffUnit, { AttrBuffConfigs = buffConfigs }), 'Buff 单位初始化失败')
        local actualConfigs = buffUnit:GetAttribute('AttrBuffConfigs')
        assertTrue(actualConfigs and #actualConfigs == 1 and actualConfigs[1].Value == 30, '隔离 Buff 实例配置未生效')
        log('buff-precondition', 'ok', '显式300基线与隔离实例Bonus=30；Init不覆盖已初始化配置')
        assertTrue(api.SetAttrBuffTargetUnit(buffUnit, target), 'Buff 单位挂接失败')
        assertTrue(api.GetAttrBuffTargetUnit(buffUnit) == target, 'Buff 目标读回错误')
        assertTrue(api.GetAttrBuffUnit(target) == buffUnit, 'Buff 单位查找错误')
        assertTrue(nearly(api.GetAttr(target, 'MaxHealth'), 330), 'Buff 单位未应用 MaxHealth')
        log('buff-unit', 'ok', 'MaxHealth=330，挂接可迁移')
        assertTrue(api.SetAttrBuffTargetUnit(buffUnit, nil), 'Buff 单位解绑失败')
        assertTrue(nearly(api.GetAttr(target, 'MaxHealth'), 300), 'Buff 单位解绑残留')
        log('buff-unit-detach', 'ok', '解绑后回到 300')
    end)
    if not ok then
        log('abort', 'error', runErr)
        fail(tostring(runErr))
    end
    local cleanupErrors = {}
    if buffUnit then
        local destroyed, err = pcall(buffUnit.Destroy, buffUnit)
        if not destroyed then cleanupErrors[#cleanupErrors + 1] = 'BuffUnit:' .. tostring(err) end
    end
    local destroyed, err = pcall(target.Destroy, target)
    if not destroyed then cleanupErrors[#cleanupErrors + 1] = 'Target:' .. tostring(err) end
    for _, item in ipairs(cleanupErrors) do
        log('cleanup', 'error', item)
        fail('清理失败: ' .. item)
    end
    log('cleanup', #cleanupErrors == 0 and 'ok' or 'error', #cleanupErrors == 0 and '隔离对象已销毁' or table.concat(cleanupErrors, '; '))
    return { Ok = ok and #errors == 0, Error = #errors > 0 and table.concat(errors, '; ') or nil,
        Cleaned = #cleanupErrors == 0, Evidence = context.Evidence or 'runtime',
        Bounds = bounds, BusinessClampVerified = businessClampVerified }
end

return Probe
