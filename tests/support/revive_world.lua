-- 濒死复活引擎边界夹具（#89 从 tests/gameplay/revive_callback_test.lua 迁移，本模块在修复 acceptance 接缝时下沉）。
-- 抽出的原因：旧 LuaUnit 套件同时被 busted 车道与 tools/acceptance/platform_steps.lua 的
-- 验收步骤复用（dofile + setmetatable 借用全局类方法）。迁移到原生后测试文件不再是全局类，
-- 旧文件已随迁移删除，验收侧的 dofile 目标因此断裂；与 #87 的 blindbox_world 同法，
-- 把「搭世界」这一段下沉为共享夹具，测试与验收各自 new() 一个实例。
-- 只搭环境、不含任何断言；业务行为一律走真实管理器公共接口。
-- seam：真实 MgrVitals + MgrSurvival（#147 T26 PlatformRevive / FullRevive / Update 暂停分支），
--   Platform 替身脚本化回调（成功/取消/失败/超时/迟到由调用方驱动），REUtil 模块缓存替身收 SurvivalResult。
local GameCfg = require('common.GameCfg')

local M = {}

local function signal()
  local s = { handlers = {} }
  function s:Connect(fn)
    self.handlers[#self.handlers + 1] = fn
    return { Disconnect = function() end }
  end
  function s:Fire(...)
    for _, fn in ipairs(self.handlers) do
      fn(...)
    end
  end
  return s
end

local function newPlayer(id)
  local c = { Health = 300, MaxHealth = 300, WalkSpeed = 10, HealthChanged = signal(),
    Died = signal(), OnReborn = signal() }
  function c:TakeDamage(n)
    self.Health = math.max(0, self.Health - n)
    self.HealthChanged:Fire(self.Health)
    if self.Health <= 0 then self.Died:Fire() end
  end
  local p = { UserId = id, Name = 'p' .. id, attrs = {}, CharacterAdded = signal(),
    Character = { Controller = c, Position = { x = id, y = 0, z = 0 } } }
  function p:SetAttribute(k, v) self.attrs[k] = v end
  return p
end

-- 平台替身：记录拉起参数，回调由调用方脚本化驱动（含迟到回调）
local function newPlatform(state)
  return {
    calls = {},
    ShowAd = function(_, player, adKey, purpose, onResult)
      local call = { kind = 'ad', adKey = adKey, purpose = purpose, onResult = onResult }
      state.platform.calls[#state.platform.calls + 1] = call
      if state.platformUnavailable then return false, 'unavailable' end
      state.platformFlow = call
      return true
    end,
    Purchase = function(_, player, goodsKey, purpose, onResult)
      local call = { kind = 'goods', goodsKey = goodsKey, purpose = purpose, onResult = onResult }
      state.platform.calls[#state.platform.calls + 1] = call
      if state.platformUnavailable then return false, 'unavailable' end
      state.platformFlow = call
      return true
    end,
  }
end

local World = {}
World.__index = World

--- 尚未搭世界；调用方负责在案例结束时 tearDown()。
function M.new()
  return setmetatable({}, World)
end

--- 抓一次模块缓存快照并搭好世界。快照只在这里抓，install 里重装不再改它，
--- 因此循环内换管理器也能把 REUtil 恢复到进入案例前的状态。
function World:setUp()
  self.savedRE = package.loaded['common.REUtil']
  self.changed = true
  self:install()
end

--- 装一套全新的 MgrVitals / MgrSurvival / Platform 替身与玩家，可反复调用。
function World:install()
  local state = self
  self.now = 100
  self.messages = {}
  package.loaded['common.REUtil'] = {
    GetRE = function(_, name)
      state.messages[name] = state.messages[name] or {}
      return { FireClient = function(_, player, value)
        table.insert(state.messages[name], { player = player, value = value })
      end, OnServerEvent = signal() }
    end,
    CheckRECD = function() return false end,
  }
  self.platformUnavailable = false
  self.platformFlow = nil
  self.platform = newPlatform(self)
  self.v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
  self.v.Now = function() return state.now end
  self.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
  self.s.Now = function() return state.now end
  require('tests.support.modifier_runtime').AttachSurvival(self.s, function() return state.now end)
  self.s.Vitals = self.v
  self.s.Platform = self.platform
  self.v:SetLifeHooks(self.s:Hooks())
  self.player = newPlayer(1473)
  self.attacker = newPlayer(2)
  self.v:OnPlayerAdded(self.player)
  self.s:OnPlayerAdded(self.player)
end

--- 恢复 REUtil 模块缓存；对半途失败或重复调用幂等。
function World:tearDown()
  if self.changed then
    package.loaded['common.REUtil'] = self.savedRE
    self.changed = nil
  end
end

function World:ctrl()
  return self.player.Character.Controller
end

function World:results()
  return self.messages['SurvivalResult'] or {}
end

function World:lastResult()
  local results = self:results()
  return results[#results] and results[#results].value or nil
end

-- 打到濒死再让死亡倒计时走完，进入 dead 相位（不含断言，校验交给调用方）。
function World:enterDead()
  self:ctrl().Health = 50
  self.v:ApplyHit(self.v:NewHit(self.attacker, 'fishAttack'), self.player, 100) -- 锁血进濒死
  self.now = self.now + GameCfg.Survival.DownedSec
  self.s:Update()
end

return M
