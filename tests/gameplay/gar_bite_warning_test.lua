-- #134 鳄雀鳝咬预警客户端表现（client/LocalGarBite.lua）。
-- 只测纯表现层自身能坏的生命周期；摆放坐标 / 旋转 / 缩放是否正确只能试玩看，不在这里复刻公式。
-- 失败方式：
--   1. 同一条鱼连续起咬叠出多个特效，或 clear 后特效不收；
--   2. clear 丢失（迟加入 / 丢包）时特效永久残留；旧一轮的超时兜底把新一轮预警收掉；
--   3. 非法载荷（NaN 坐标）进引擎；CreateAsset 失败后本条鱼后续预警再也出不来。
local lu = require('luaunit')

TestGarBiteWarning = {}

function TestGarBiteWarning:setUp()
    local env = self
    self.saved = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion') }
    self.module = package.loaded['client.LocalGarBite']
    package.loaded['client.LocalGarBite'] = nil
    self.effects, self.delays, self.fail = {}, {}, false
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { CreateAsset = function(_, id)
            if env.fail then error('asset-missing') end
            local e = { AssetId = id, Destroy = function(self) self.Destroyed = true end }
            env.effects[#env.effects + 1] = e
            return { e }
        end } end
        if name == 'Task' then return { Delay = function(_, sec, fn) env.delays[#env.delays + 1] = { sec, fn } end } end
    end }
    self.warn = require('client.LocalGarBite')
    self.N = require('common.GarBiteNotice')
    self.cfg = require('common.GameCfg').FishCombat.gar
end

function TestGarBiteWarning:tearDown()
    package.loaded['client.LocalGarBite'] = self.module
    _G.game, _G.Vector3, _G.Quaternion = self.saved.game, self.saved.Vector3, self.saved.Quaternion
end

local function lock(self, fishId, fx, fz)
    return self.N.Lock(fishId, { x = 1, y = 2, z = 3 }, fx, fz, self.cfg.BiteRange, self.cfg.HeadHalfAngleDeg,
        self.cfg.BiteCooldownSec)
end

-- #141 圆形落点必须由生产消费者创建整圆预设，缩放按官方半径10米，clear 收起。
function TestGarBiteWarning:test_jump_circle_consumer_places_full_landing_warning_and_clears()
    for _, radius in ipairs({ 5, 10 }) do
        local payload = self.N.Lock(141, { x = 15, y = 2, z = 30 }, 0, 1, radius, 180, 1.5)
        payload.move, payload.shape = 'jump', 'circle'
        self.warn:Show(payload)
        local effect = self.effects[#self.effects]
        lu.assertEquals(effect.AssetId, 'official://preset/7191')
        lu.assertEquals(effect.Position, { x = 15, y = 2.1, z = 30 })
        lu.assertEquals(effect.Scale.x, radius == 5 and 0.5 or 1)
        lu.assertEquals(effect.Scale.z, radius == 5 and 0.5 or 1)
        self.warn:Show(self.N.Clear(141, 'cancel'))
        lu.assertTrue(effect.Destroyed)
        lu.assertNil(self.warn.Active[141])
    end
end

function TestGarBiteWarning:test_rain_effect_is_distinct_and_cleared_with_warning()
    local payload = lock(self, 8, 0, 1)
    payload.move = 'rain'
    self.warn:Show(payload)
    lu.assertEquals(self.effects[2].AssetId, require('common.GameCfg').FishCombat.dragon.RainEffect)
    self.warn:Show(self.N.Clear(8, 'rain-end'))
    lu.assertTrue(self.effects[1].Destroyed)
    lu.assertTrue(self.effects[2].Destroyed)
end

function TestGarBiteWarning:test_relock_replaces_and_clear_hides()
    self.warn:Show(lock(self, 5, 0, 1))
    self.warn:Show(lock(self, 5, 0, -1))
    lu.assertTrue(self.effects[1].Destroyed)
    lu.assertNil(self.effects[2].Destroyed)
    self.warn:Show(self.N.Clear(5, 'miss'))
    lu.assertTrue(self.effects[2].Destroyed)
    lu.assertNil(self.warn.Active[5])
end

function TestGarBiteWarning:test_timeout_fallback_only_hides_its_own_round()
    self.warn:Show(lock(self, 5, 0, 1))
    local first = self.delays[1]
    self.warn:Show(lock(self, 5, 0, -1))
    first[2]()
    lu.assertNil(self.effects[2].Destroyed)
    self.delays[2][2]()
    lu.assertTrue(self.effects[2].Destroyed)
end

function TestGarBiteWarning:test_invalid_payload_ignored_and_asset_failure_does_not_block_next_round()
    self.warn:Show(nil)
    self.warn:Show(self.N.Lock(5, { x = 0 / 0, y = 0, z = 0 }, 1, 0, 2.5, 90, 1.5))
    lu.assertEquals(#self.effects, 0)
    self.fail = true
    self.warn:Show(lock(self, 5, 1, 0))
    lu.assertNil(self.warn.Active[5])
    self.fail = false
    self.warn:Show(lock(self, 5, 1, 0))
    lu.assertEquals(self.warn.Active[5].Effect, self.effects[1])
end
