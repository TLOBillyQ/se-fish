-- #90 迁移：电鳗技能装配失败路径（原 tests/gameplay/eel_ability_failure_test.lua，6 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（单类，方法按字典序）。
-- #86 装配失败方式：AddAbility/属性/锚点抛错遗留半初始化对象；销毁失败丢失重试入口。
--
-- 迁移纪律：
--   * 全部走 pcall 失败路径，断言的就是「失败之后清理做到哪一步」，因此不改成功路径、不放宽断言；
--   * 旧 setUp 一开始就记下全局 game 与 package.loaded['server.AbilityAPI']，teardown 原样放回。
--     这里改成逐案例 before_each/after_each：已验证 Busted 在 before_each 抛错时仍执行 after_each
--     （探针记录见 issue-90-mapping.md），所以「夹具建到一半失败也清理」与 LuaUnit 语义一致；
--     after_each 只读快照里已有的字段，不会把没替换过的环境写成别的值。
--   * 夹具对象全部是 describe 的局部变量，不新增任何全局（旧文件靠 `env = self` 复用一个 upvalue，
--     迁移后由 ctx 直接承载，销毁计数与 failDestroy 开关都在 ctx 上，跨案例互不残留）。
--   * 每例用 loadfile 重新取一份 MgrAbility，得到全新管理器实例；本文件不碰 vendor 包
--     （server/packages/），只替换 server.AbilityAPI 这条业务接缝。
local saved

describe('TestEelAbilityFailure', function()
    local ctx
    before_each(function()
        saved = { game = rawget(_G, 'game'), api = package.loaded['server.AbilityAPI'] }
        ctx = { jobs = {}, destroyed = 0 }
        ctx.manager = { Destroy = function()
            if ctx.failDestroy then error('destroy-failed') end
            ctx.destroyed = ctx.destroyed + 1
        end }
        ctx.world = { CreateAsset = function() return { ctx.manager } end }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return ctx.world end
            if name == 'Task' then return {
                Spawn = function(_, fn) ctx.jobs[#ctx.jobs + 1] = fn end,
                Wait = function(_, seconds) return coroutine.yield(seconds) end,
            } end
        end }
        ctx.api = { AddAbility = function() error('add-failed') end }
        package.loaded['server.AbilityAPI'] = ctx.api
        ctx.mgr = assert(loadfile('server/Mgr/MgrAbility.lua'))()
        ctx.fish = { Id = 1, FishId = 'eel', Carrier = { Receiver = {} } }
    end)
    after_each(function()
        _G.game = saved.game
        package.loaded['server.AbilityAPI'] = saved.api
    end)

    -- AddAbility 直接抛错：半初始化的 manager 必须被销毁，鱼身上不留技能记录。
    it('test_add_failure_cleans_partial_manager', function()
        ctx.mgr:EquipFish(ctx.fish)
        assert.is_true(pcall(ctx.jobs[1]))
        assert.is_nil(ctx.fish.AbilityRecord)
        assert.same(1, ctx.destroyed)
    end)

    -- 锚点挂接失败：先清锚点再清 manager，顺序是「后建的先销毁」。
    it('test_anchor_attach_failure_cleans_anchor_then_manager', function()
        local cleaned = {}
        local anchor = {
            SetAttribute = function() end,
            Destroy = function() cleaned[#cleaned + 1] = 'anchor' end,
        }
        ctx.api.AddAbility = function() return { SetAttribute = function() end } end
        ctx.api.AttachAnchor = function() error('anchor-attach-failed') end
        ctx.manager.Destroy = function() cleaned[#cleaned + 1] = 'manager' end
        ctx.mgr:EquipFish(ctx.fish)
        ctx.world.CreateAsset = function() return { anchor } end
        assert.is_true(pcall(ctx.jobs[1]))
        assert.is_nil(ctx.fish.AbilityRecord)
        assert.same({ 'anchor', 'manager' }, cleaned)
        assert.is_nil(next(ctx.mgr.PendingFishCleanup))
    end)

    -- 锚点资源建不出来：manager 销毁干净，不留待重试队列。
    it('test_anchor_creation_failure_cleans_partial_manager', function()
        ctx.api.AddAbility = function() return { SetAttribute = function() end } end
        ctx.mgr:EquipFish(ctx.fish)
        ctx.world.CreateAsset = function() error('anchor-create-failed') end
        assert.is_true(pcall(ctx.jobs[1]))
        assert.is_nil(ctx.fish.AbilityRecord)
        assert.same(1, ctx.destroyed)
        assert.is_nil(next(ctx.mgr.PendingFishCleanup))
    end)

    -- SetAttribute 抛错（技能对象已建出来）：同样要回收 manager。
    it('test_attribute_failure_cleans_partial_manager', function()
        ctx.api.AddAbility = function() return { SetAttribute = function() error('attribute-failed') end } end
        ctx.mgr:EquipFish(ctx.fish)
        assert.is_true(pcall(ctx.jobs[1]))
        assert.is_nil(ctx.fish.AbilityRecord)
        assert.same(1, ctx.destroyed)
    end)

    -- 等待间隙被取消：恢复协程后不得继续装配，也不能多销毁一次。
    it('test_cancel_during_wait_does_not_resume_equipping', function()
        local attempts = 0
        ctx.api.AddAbility = function()
            attempts = attempts + 1
            return nil, 'manager-not-ready'
        end
        ctx.mgr:EquipFish(ctx.fish)
        local job = coroutine.create(ctx.jobs[1])
        local ok, delay = coroutine.resume(job)
        assert.is_true(ok)
        assert.same(0.1, delay)
        assert.same('suspended', coroutine.status(job))
        assert.same(1, attempts)
        ctx.mgr:RemoveFish(ctx.fish)
        assert.is_nil(ctx.fish.AbilityRecord)
        assert.same(1, ctx.destroyed)
        assert.is_true(coroutine.resume(job))
        assert.same('dead', coroutine.status(job))
        assert.same(1, attempts)
        assert.same(1, ctx.destroyed)
    end)

    -- 销毁失败必须留在重试入口，Update 再试一次才清干净。
    it('test_failed_destroy_is_retried_by_update', function()
        ctx.mgr:EquipFish(ctx.fish)
        ctx.failDestroy = true
        ctx.mgr:RemoveFish(ctx.fish)
        assert.is_not_nil(ctx.fish.AbilityRecord)
        ctx.failDestroy = false
        ctx.mgr:Update()
        assert.is_nil(ctx.fish.AbilityRecord)
        assert.same(1, ctx.destroyed)
        ctx.jobs[1]()
        assert.same(1, ctx.destroyed)
    end)
end)
