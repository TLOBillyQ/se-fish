-- 迁移自 tests/gameplay/gar_bite_warning_test.lua（#85）；行为契约原文见 #134、#141。
-- #134 鳄雀鳝上钩预警客户端表现（client/LocalGarBite.lua）。
-- 只测纯表现层自身能坏的生命周期；摆放坐标 / 旋转 / 缩放是否正确只能试玩看，不在这里复刻公式。
-- 失败方式：
--   1. 同一条鱼连续起咬叠出多个特效，或 clear 后特效不收；
--   2. clear 丢失（迟加入 / 丢包）时特效永久残留；旧一轮的超时兜底把新一轮预警收掉；
--   3. 非法载荷（NaN 坐标）进引擎；CreateAsset 失败后本条鱼后续预警再也出不来。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

describe('鳄雀鳝上钩预警表现（LocalGarBite）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {
      game = rawget(_G, 'game'),
      Vector3 = rawget(_G, 'Vector3'),
      Quaternion = rawget(_G, 'Quaternion'),
      LocalGarBite = package.loaded['client.LocalGarBite'],
    }
    env = { effects = {}, delays = {}, fail = false }
    package.loaded['client.LocalGarBite'] = nil
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
    env.warn = require('client.LocalGarBite')
    env.N = require('common.GarBiteNotice')
    env.cfg = require('common.GameCfg').FishCombat.gar
  end)

  after_each(function()
    package.loaded['client.LocalGarBite'] = restore and restore.LocalGarBite
    if restore then
      _G.game, _G.Vector3, _G.Quaternion = restore.game, restore.Vector3, restore.Quaternion
    end
    env = nil
    restore = nil
  end)

  local function lock(fishId, fx, fz)
    return env.N.Lock(fishId, { x = 1, y = 2, z = 3 }, fx, fz, env.cfg.BiteRange, env.cfg.HeadHalfAngleDeg,
      env.cfg.BiteCooldownSec)
  end

  it('test_invalid_payload_ignored_and_asset_failure_does_not_block_next_round', function()
    env.warn:Show(nil)
    env.warn:Show(env.N.Lock(5, { x = 0 / 0, y = 0, z = 0 }, 1, 0, 2.5, 90, 1.5))
    assert.same(0, #env.effects)
    env.fail = true
    env.warn:Show(lock(5, 1, 0))
    assert.is_nil(env.warn.Active[5])
    env.fail = false
    env.warn:Show(lock(5, 1, 0))
    assert.same(env.effects[1], env.warn.Active[5].Effect)
  end)

  it('test_jump_circle_consumer_places_full_landing_warning_and_clears', function()
    -- #141 圆形落点必须由生产消费者创建整圆预设，缩放按官方半径10米，clear 收起。
    for _, radius in ipairs({ 5, 10 }) do
      local payload = env.N.Lock(141, { x = 15, y = 2, z = 30 }, 0, 1, radius, 180, 1.5)
      payload.move, payload.shape = 'jump', 'circle'
      env.warn:Show(payload)
      local effect = env.effects[#env.effects]
      assert.same('official://preset/7191', effect.AssetId)
      assert.same({ x = 15, y = 2.1, z = 30 }, effect.Position)
      assert.same(radius == 5 and 0.5 or 1, effect.Scale.x)
      assert.same(radius == 5 and 0.5 or 1, effect.Scale.z)
      env.warn:Show(env.N.Clear(141, 'cancel'))
      assert.is_true(effect.Destroyed)
      assert.is_nil(env.warn.Active[141])
    end
  end)

  it('test_rain_effect_is_distinct_and_cleared_with_warning', function()
    local payload = lock(8, 0, 1)
    payload.move = 'rain'
    env.warn:Show(payload)
    assert.same(require('common.GameCfg').FishCombat.dragon.RainEffect, env.effects[2].AssetId)
    env.warn:Show(env.N.Clear(8, 'rain-end'))
    assert.is_true(env.effects[1].Destroyed)
    assert.is_true(env.effects[2].Destroyed)
  end)

  it('test_relock_replaces_and_clear_hides', function()
    env.warn:Show(lock(5, 0, 1))
    env.warn:Show(lock(5, 0, -1))
    assert.is_true(env.effects[1].Destroyed)
    assert.is_nil(env.effects[2].Destroyed)
    env.warn:Show(env.N.Clear(5, 'miss'))
    assert.is_true(env.effects[2].Destroyed)
    assert.is_nil(env.warn.Active[5])
  end)

  it('test_timeout_fallback_only_hides_its_own_round', function()
    env.warn:Show(lock(5, 0, 1))
    local first = env.delays[1]
    env.warn:Show(lock(5, 0, -1))
    first[2]()
    assert.is_nil(env.effects[2].Destroyed)
    env.delays[2][2]()
    assert.is_true(env.effects[2].Destroyed)
  end)
end)
