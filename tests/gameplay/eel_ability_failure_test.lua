-- #86 装配失败方式：AddAbility/属性/锚点抛错遗留半初始化对象；销毁失败丢失重试入口。
local lu = require('luaunit')
TestEelAbilityFailure = {}
function TestEelAbilityFailure:setUp()
    self.oldGame = game
    self.oldAPI = package.loaded['server.AbilityAPI']
    self.jobs, self.destroyed = {}, 0
    local env = self
    self.manager = { Destroy = function()
        if env.failDestroy then error('destroy-failed') end
        env.destroyed = env.destroyed + 1
    end }
    self.world = { CreateAsset = function() return { env.manager } end }
    game = { GetService = function(_, name)
        if name == 'World' then return env.world end
        if name == 'Task' then return {
            Spawn = function(_, fn) env.jobs[#env.jobs + 1] = fn end,
            Wait = function(_, seconds) return coroutine.yield(seconds) end,
        } end
    end }
    self.api = { AddAbility = function() error('add-failed') end }
    package.loaded['server.AbilityAPI'] = self.api
    self.mgr = assert(loadfile('server/Mgr/MgrAbility.lua'))()
    self.fish = { Id = 1, FishId = 'eel', Carrier = { Receiver = {} } }
end
function TestEelAbilityFailure:tearDown()
    game = self.oldGame
    package.loaded['server.AbilityAPI'] = self.oldAPI
end
function TestEelAbilityFailure:test_add_failure_cleans_partial_manager()
    self.mgr:EquipFish(self.fish)
    lu.assertTrue(pcall(self.jobs[1]))
    lu.assertNil(self.fish.AbilityRecord)
    lu.assertEquals(self.destroyed, 1)
end
function TestEelAbilityFailure:test_attribute_failure_cleans_partial_manager()
    self.api.AddAbility = function() return { SetAttribute = function() error('attribute-failed') end } end
    self.mgr:EquipFish(self.fish)
    lu.assertTrue(pcall(self.jobs[1]))
    lu.assertNil(self.fish.AbilityRecord)
    lu.assertEquals(self.destroyed, 1)
end
function TestEelAbilityFailure:test_failed_destroy_is_retried_by_update()
    self.mgr:EquipFish(self.fish)
    self.failDestroy = true
    self.mgr:RemoveFish(self.fish)
    lu.assertNotNil(self.fish.AbilityRecord)
    self.failDestroy = false
    self.mgr:Update()
    lu.assertNil(self.fish.AbilityRecord)
    lu.assertEquals(self.destroyed, 1)
    self.jobs[1]()
    lu.assertEquals(self.destroyed, 1)
end

function TestEelAbilityFailure:test_cancel_during_wait_does_not_resume_equipping()
    local attempts = 0
    self.api.AddAbility = function()
        attempts = attempts + 1
        return nil, 'manager-not-ready'
    end
    self.mgr:EquipFish(self.fish)
    local job = coroutine.create(self.jobs[1])
    local ok, delay = coroutine.resume(job)
    lu.assertTrue(ok)
    lu.assertEquals(delay, 0.1)
    lu.assertEquals(coroutine.status(job), 'suspended')
    lu.assertEquals(attempts, 1)
    self.mgr:RemoveFish(self.fish)
    lu.assertNil(self.fish.AbilityRecord)
    lu.assertEquals(self.destroyed, 1)
    lu.assertTrue(coroutine.resume(job))
    lu.assertEquals(coroutine.status(job), 'dead')
    lu.assertEquals(attempts, 1)
    lu.assertEquals(self.destroyed, 1)
end

function TestEelAbilityFailure:test_anchor_creation_failure_cleans_partial_manager()
    self.api.AddAbility = function() return { SetAttribute = function() end } end
    self.mgr:EquipFish(self.fish)
    self.world.CreateAsset = function() error('anchor-create-failed') end
    lu.assertTrue(pcall(self.jobs[1]))
    lu.assertNil(self.fish.AbilityRecord)
    lu.assertEquals(self.destroyed, 1)
    lu.assertNil(next(self.mgr.PendingFishCleanup))
end

function TestEelAbilityFailure:test_anchor_attach_failure_cleans_anchor_then_manager()
    local cleaned = {}
    local anchor = {
        SetAttribute = function() end,
        Destroy = function() cleaned[#cleaned + 1] = 'anchor' end,
    }
    self.api.AddAbility = function() return { SetAttribute = function() end } end
    self.api.AttachAnchor = function() error('anchor-attach-failed') end
    self.manager.Destroy = function() cleaned[#cleaned + 1] = 'manager' end
    self.mgr:EquipFish(self.fish)
    self.world.CreateAsset = function() return { anchor } end
    lu.assertTrue(pcall(self.jobs[1]))
    lu.assertNil(self.fish.AbilityRecord)
    lu.assertEquals(cleaned, { 'anchor', 'manager' })
    lu.assertNil(next(self.mgr.PendingFishCleanup))
end
