-- #48：公开探针与映射接缝；失败方式先记录于仓库外 attr/notes.txt。
-- 真实 vendor 运算，仅 World/Unit/Controller 是引擎边界替身，不是地图实测。
local lu = require('luaunit')
local Probe = require('tools.probes.attr_rule_probe')

-- 每个用例使用独立模块环境，避免污染全量测试的 package.loaded / game。
local function fixture(options)
    options = options or {}
    local all, logs, cache = {}, {}, {}
    local world = {}
    local function unit(kind, parent, prefab)
        local u = { Parent = parent, Controller = kind == 'Target' and { WalkSpeed = 7, MaxHealth = 300 } or nil }
        local attrs = {}
        function u:GetAttribute(key) return attrs[key] end
        function u:SetAttribute(key, value) attrs[key] = value end
        function u:IsA(name) return name == kind end
        function u:GetChildren()
            local children = {}
            for _, child in ipairs(all) do if child.Parent == self then children[#children + 1] = child end end
            return children
        end
        function u:FindFirstChildOfClass(name)
            if name == 'PresetLink' and prefab then return { GetAttribute = function() return prefab end } end
        end
        function u:Destroy()
            if options.destroyError and kind == 'Target' then error('模拟销毁失败') end
            for _, child in ipairs(self:GetChildren()) do child:Destroy() end
            self.Parent, self.destroyed = nil, true
        end
        all[#all + 1] = u
        return u
    end
    function world:CreateAsset(key)
        if options.missing then return nil end
        return { unit('Script', world, key:find('u801ef') and 'AttrUnit' or 'AttrBuffUnit') }
    end
    local env = setmetatable({ game = { GetService = function() return world end } }, { __index = _G })
    env.require = function(name)
        if cache[name] ~= nil then return cache[name] end
        cache[name] = assert(loadfile(name:gsub('%.', '/') .. '.lua', 't', env))()
        return cache[name]
    end
    local api = env.require('server.AttrAPI')
    local target = unit('Target', world)
    return { AttrAPI = api, Target = target, Isolated = true,
        CreateBuffUnits = function() return world:CreateAsset('map://preset/u95e3ac002304b8483aa099a955e14a8') end,
        Log = function(line) logs[#logs + 1] = line end,
        Evidence = 'offline-engine-double' }, logs, all
end

TestAttrRuleProbe = {}

function TestAttrRuleProbe:test_real_vendor_probe_can_repeat_with_complete_cleanup()
    for _ = 1, 2 do
        local context, logs, all = fixture()
        local report = Probe.Run(context)
        if not report.Ok then print(table.concat(logs, '\n')) end
        lu.assertTrue(report.Ok)
        lu.assertEquals(report.Evidence, 'offline-engine-double')
        lu.assertTrue(report.Cleaned)
        lu.assertTrue(#logs > 8)
        for _, u in ipairs(all) do lu.assertTrue(u.destroyed) end
    end
end

function TestAttrRuleProbe:test_missing_preset_reports_error_and_still_cleans_up()
    local context, logs = fixture({ missing = true })
    local report = Probe.Run(context)
    lu.assertFalse(report.Ok)
    lu.assertStrContains(report.Error, '懒创建失败')
    lu.assertTrue(report.Cleaned)
    lu.assertStrContains(logs[#logs], 'cleanup')
end

function TestAttrRuleProbe:test_destroy_failure_is_reported_not_swallowed()
    local context = fixture({ destroyError = true })
    local report = Probe.Run(context)
    lu.assertFalse(report.Ok)
    lu.assertFalse(report.Cleaned)
    lu.assertStrContains(report.Error, '清理失败')
end

function TestAttrRuleProbe:test_dirty_isolated_target_is_rejected()
    local context, logs, all = fixture()
    lu.assertTrue(context.AttrAPI.EnsureAttrUnit(context.Target) ~= nil)
    local report = Probe.Run(context)
    lu.assertFalse(report.Ok)
    lu.assertStrContains(report.Error, '拒绝污染')
    lu.assertTrue(report.Cleaned)
end

function TestAttrRuleProbe:test_mapping_keeps_existing_growth_and_multiplicative_speed()
    local map = Probe.Map({ bodyPotions = 10, speedPotions = 20, baseSpeed = 7,
        weak = true, frost = true, hunger = 400, damageScale = 1.5 })
    lu.assertEquals(map.MaxHealth.Value, 900)
    lu.assertAlmostEquals(map.WalkSpeed.Value, 7.35, 1e-9)
    lu.assertEquals(map.BodyScale.Value, 3)
    lu.assertEquals(map.Hunger.Value, 300)
    lu.assertEquals(map.WeaponDamageScale.Value, 1.5)
    lu.assertAlmostEquals(map.WalkSpeed.Components.Ratio, 0.05, 1e-9)
end
