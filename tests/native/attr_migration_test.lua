-- #89 迁移（原 tests/gameplay/attr_migration_test.lua）：
-- 失败方式：永久成长重复累加、默认100污染、重复乘区、写入失败误报、重建/退出残留。
-- 接缝：MgrAttr公开刷新/读取，真实根AttrAPI/vendor，仅Unit/World为离线引擎替身。
-- fixture 用独立 env + 自己的 require 缓存 loadfile 出整套沙盒，不写 _G 也不写 package.loaded，
-- 因此旧套件没有 setUp/tearDown、原生侧同样不需要逐例恢复。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
local function fixture(logs)
    local all, cache = {}, {}
    local world = {}
    local function unit(kind, parent)
        local u = { Parent = parent, attrs = {}, Controller = kind == 'Character' and { WalkSpeed = 7, MaxHealth = 100, Health = 100 } or nil }
        function u:GetAttribute(k) return self.attrs[k] end
        function u:SetAttribute(k, v) self.attrs[k] = v end
        function u:IsA(k) return k == kind end
        function u:GetChildren() local out = {} for _, v in ipairs(all) do if v.Parent == self then out[#out + 1] = v end end return out end
        function u:FindFirstChildOfClass(k) if k == 'PresetLink' and kind == 'Script' then return { GetAttribute = function() return 'AttrUnit' end } end end
        function u:Destroy() self.Parent = nil self.destroyed = true end
        function u:SetScale(v) self.scale = v.x end
        all[#all + 1] = u return u
    end
    function world:CreateAsset() return { unit('Script', world) } end
    local env = setmetatable({ game = { GetService = function() return world end }, Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end } }, { __index = _G })
    if logs then env.print = function(...) local values = { ... }; for i, v in ipairs(values) do values[i] = tostring(v) end logs[#logs + 1] = table.concat(values, ' ') end end
    env.require = function(name)
        if cache[name] then return cache[name] end
        cache[name] = assert(loadfile(name:gsub('%.', '/') .. '.lua', 't', env))() return cache[name]
    end
    local mgr = env.require('server.Mgr.MgrAttr')
    local player = { UserId = 51, Character = unit('Character', world) }
    local data = { body = 2, speed = 3, level = 2 }
    function data:PotionCount(id) return id == 'item167' and self.speed or self.body end
    function data:ShopUpgradeLevel() return self.level end
    mgr.PlayerData = { GetDataInst = function() return data end }
    mgr.MoveMultiplierProvider = function() return 0.35 end
    return mgr, player, data, all, unit, world
end

describe('TestAttrMigration', function()
    -- 封顶成长与麻痹清零不留残留
    it('test_capped_growth_and_paralysis_clear_without_residue', function()
        local mgr, p, data = fixture()
        data.body, data.speed = 1000, 1000
        mgr.MoveMultiplierProvider = function() return 0 end
        assert.is_true(mgr:ApplyGrowth(p).Ok)
        assert.same(900, mgr:MaxHealth(p))
        assert.same(3, p.Character.scale)
        assert.same(0, p.Character.Controller.WalkSpeed)
        mgr.MoveMultiplierProvider = function() return 1 end
        assert.is_true(mgr:RefreshMoveSpeed(p))
        assert.same(21, p.Character.Controller.WalkSpeed)
    end)

    -- 角色重建与离开都释放自己拥有的属性单位
    it('test_character_rebuild_and_leave_release_owned_attr_units', function()
        local mgr, p, _, all, unit, world = fixture()
        assert.is_true(mgr:ApplyGrowth(p).Ok)
        local first = mgr.AttrAPI.GetAttrUnit(p.Character)
        p.Character = unit('Character', world)
        p.Character.Controller.WalkSpeed = 8
        assert.is_true(mgr:ApplyGrowth(p).Ok)
        assert.is_true(first.destroyed)
        assert.near(3.64, p.Character.Controller.WalkSpeed, 1e-8)
        local current = mgr.AttrAPI.GetAttrUnit(p.Character)
        mgr:OnPlayerRemoving(p)
        assert.is_true(current.destroyed)
    end)

    -- 饥饿与武器伤害走 vendor，不新开存档权威
    it('test_hunger_and_weapon_use_vendor_without_new_save_authority', function()
        local mgr, p, data = fixture()
        local ok, hunger = mgr:ProjectHunger(p, 1000)
        assert.is_true(ok)
        assert.same(300, hunger)
        assert.same(0, select(2, mgr:ProjectHunger(p, -2)))
        assert.near(1.2, mgr:WeaponDamageScale(p, 'melee'), 1e-8)
        data.level = 3
        assert.near(1.3, mgr:WeaponDamageScale(p, 'melee'), 1e-8)
        assert.near(1.3, mgr:WeaponDamageScale(p, 'melee'), 1e-8)
    end)

    -- 角色迟到时重试捕获真实基准速
    it('test_missing_character_retry_captures_real_base_when_character_arrives', function()
        local mgr, p, _, _, unit, world = fixture()
        p.Character = nil
        mgr:OnPlayerAdded(p)
        p.Character = unit('Character', world)
        p.Character.Controller.WalkSpeed = 10
        mgr:Update()
        assert.near(4.55, p.Character.Controller.WalkSpeed, 1e-8)
    end)

    -- 真实 vendor 成长幂等，移动只组合一个乘区
    it('test_real_vendor_growth_is_idempotent_and_combines_one_move_multiplier', function()
        local mgr, p = fixture()
        local a = mgr:ApplyGrowth(p)
        assert.message(a.Error).is_true(a.Ok)
        assert.same(420, mgr:MaxHealth(p))
        assert.near(3.185, p.Character.Controller.WalkSpeed, 1e-8)
        assert.same(1.4, p.Character.scale)
        assert.same(require('common.BodyScale').Derive(1.4).InteractRange, p.Character.attrs.InteractRange)
        assert.is_true(mgr:ApplyGrowth(p).Ok)
        assert.near(3.185, p.Character.Controller.WalkSpeed, 1e-8)
    end)

    -- 重试只报告变化了的 vendor 错误，成功后重新武装
    it('test_retry_reports_changed_vendor_errors_and_rearms_after_success', function()
        local logs = {}
        local mgr, p, _, _, unit, world = fixture(logs)
        p.Character = nil
        mgr:OnPlayerAdded(p)
        p.Character = unit('Character', world)
        local broken = true
        local children = p.Character.GetChildren
        function p.Character:GetChildren() if broken then error('vendor-owner-unavailable') end return children(self) end
        local before = #logs
        mgr:Update()
        assert.same(before + 1, #logs)
        assert.matches('[MgrAttr] 属性重试失败 51', logs[#logs], nil, true)
        assert.matches('vendor-owner-unavailable', logs[#logs], nil, true)
        mgr:Update()
        assert.same(before + 1, #logs)
        broken = false
        local config = { Min = 0 }
        mgr.AttrAPI.GetAttrConfig = function() return config end
        mgr:Update()
        assert.same(before + 2, #logs)
        assert.matches('业务属性键不允许地图钳制配置', logs[#logs], nil, true)
        config = nil
        mgr:Update()
        assert.near(3.185, p.Character.Controller.WalkSpeed, 1e-8)
        config = { Min = 0 }
        mgr:RefreshAfterRevive(p)
        local nextBefore = #logs
        mgr:Update()
        assert.same(nextBefore + 1, #logs)
        mgr:OnPlayerRemoving(p)
        mgr:Update()
        assert.same(nextBefore + 1, #logs)
    end)

    -- 生命/进食/复活都用投影后的血量与饥饿
    it('test_vitals_food_and_revive_use_projected_health_and_hunger', function()
        local mgr, p, data = fixture()
        data.body = 10
        local vitals = assert(loadfile('server/Mgr/MgrVitals.lua'))()
        vitals.Now = function() return 100 end
        vitals.Attr = mgr mgr.Vitals = vitals
        vitals.MaxHealthProvider = function(player) return mgr:MaxHealth(player) end
        assert.is_true(mgr:ApplyGrowth(p).Ok)
        vitals:OnPlayerAdded(p)
        assert.same(900, p.Character.Controller.Health)
        p.Character.Controller.Health = 300
        assert.is_true(vitals:SetHunger(p, 100))
        assert.is_true(vitals:Eat(p, 'goldfish'))
        assert.same(570, p.Character.Controller.Health)
        assert.same(190, vitals:GetState(p).hunger)
        assert.same(190, mgr.AttrAPI.GetAttr(p.Character, 'PlayerHunger'))
        local state = vitals:GetState(p) state.dead = true
        p.Character.scale = 1 p.Character.Controller.WalkSpeed = 7
        vitals:Revive(state, 'test')
        assert.same(3, p.Character.scale)
        assert.near(3.185, p.Character.Controller.WalkSpeed, 1e-8)
        assert.same(900, p.Character.Controller.Health)
        assert.same(300, mgr.AttrAPI.GetAttr(p.Character, 'PlayerHunger'))
    end)

    -- 写入失败要报出来，刷新按当前投影重试
    it('test_write_failure_is_reported_and_refresh_retries_current_projection', function()
        local mgr, p, data = fixture()
        local values = { WalkSpeed = 7, MaxHealth = 100, Health = 100 }
        local deny = true
        p.Character.Controller = setmetatable({}, { __index = values, __newindex = function(_, k, v)
            if deny and k == 'WalkSpeed' then error('write-denied') end values[k] = v
        end })
        local result = mgr:ApplyGrowth(p)
        assert.is_false(result.Ok)
        assert.matches('write-denied', result.Error, nil, true)
        data.speed = 20 deny = false
        mgr.MoveMultiplierProvider = function() return 1 end
        assert.is_true(mgr:ApplyGrowth(p).Ok)
        assert.same(21, values.WalkSpeed)
    end)
end)
