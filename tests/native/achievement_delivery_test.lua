-- #88 迁移：通关成就补交（原 tests/gameplay/achievement_delivery_test.lua，3 例）。
-- #38 失败方式（先列后写）：本地未保存就提交平台、未配置ID伪成功、异常后丢任务、
-- 重试累加进度重复授予、重进漏补交、旧玩家回调串到新会话。
-- 接缝：真实PlayerData序列化与管理器公开Update；ArchiveService由引擎替身提供。
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- 断言映射：assertEquals 的 table 深比较语义由 assert.same 承接（非 table 退化为 ==）；
-- assertTrue/assertFalse 是严格 true/false，映射 is_true/is_false。
local Cfg = require('common.GameCfg')

describe('TestAchievementDelivery', function()
    local env, savedId

    -- 逐例夹具：旧 LuaUnit 每个方法都跑 setUp/tearDown，这里同样用 before_each/after_each。
    -- before_each 第一件事是保存平台ID原值，因此夹具中途抛错时 after_each 仍能恢复，
    -- 不把本例改过的平台ID泄漏给后续案例。
    before_each(function()
        savedId = Cfg.Achievements.final.PlatformId
        env = { now = 0, calls = 0, completed = false }
        Cfg.Achievements.final.PlatformId = 3801
        env.player = { UserId = 38, SetAttribute = function() end }
        local data = assert(loadfile('server/Data/PlayerData.lua'))().New(env.player, function() end)
        data:Init()
        env.data = data
        env.mgr = assert(loadfile('server/Mgr/MgrAchievements.lua'))()
        env.mgr.PlayerData = { GetDataInst = function(_, p) return p == env.player and env.data end }
        env.mgr.Players = { GetPlayers = function() return { env.player } end }
        env.mgr.World = { GetServerTime = function() return env.now end }
        env.mgr.Archive = {
            IsAchievementCompleted = function()
                if env.unavailable then error('平台暂不可用') end
                return env.completed
            end,
            SetAchievementProgress = function(_, p, id, count)
                assert.same(env.player, p)
                assert.same(3801, id)
                assert.same(1, count)
                env.calls = env.calls + 1
            end,
        }
    end)
    after_each(function()
        Cfg.Achievements.final.PlatformId = savedId
        env = nil
    end)

    it('test_completed_local_mark_retries_absolute_progress_and_only_acknowledges_platform_confirmation', function()
        env.mgr:Update()
        assert.same(0, env.calls)
        env.data.Extra.achievements.final = true
        env.unavailable = true; env.mgr:Update()
        env.unavailable = false; env.now = 20; env.mgr:Update()
        assert.same(1, env.calls)
        assert.is_nil(env.data.Extra.achievementDelivered and env.data.Extra.achievementDelivered.final)
        env.completed = true; env.now = 40; env.mgr:Update()
        assert.is_true(env.data.Extra.achievementDelivered.final)
        env.now = 60; env.mgr:Update()
        assert.same(1, env.calls)
        local saved = env.data:Serialize()
        env.data:ApplySave(saved)
        env.mgr:OnPlayerRemoving(env.player)
        env.now = 80; env.mgr:Update()
        assert.same(1, env.calls)
    end)

    it('test_missing_platform_id_keeps_local_completion_pending', function()
        env.data.Extra.achievements.final = true
        Cfg.Achievements.final.PlatformId = nil
        env.mgr:Update()
        assert.same(0, env.calls)
        assert.is_nil(env.data.Extra.achievementDelivered)
    end)

    -- 存档入口同步拒绝不调用回调，不能锁住之后的真实补交。
    it('test_save_busy_rejection_retries_platform_confirmation_later', function()
        env.data.Extra.achievements.final = true
        env.completed = true
        local attempts = 0
        env.mgr.Save = {
            NextOperation = function() return { id = '38:1' } end,
            Execute = function(_, player, data, operation, transform, done)
                attempts = attempts + 1
                if attempts == 1 then return false, 'pending' end
                transform(data); done(true, { ok = true }); return true
            end,
        }
        env.mgr:Update()
        env.now = 20; env.mgr:Update()
        assert.is_true(env.data.Extra.achievementDelivered and env.data.Extra.achievementDelivered.final)
        assert.same(2, attempts)
    end)
end)
