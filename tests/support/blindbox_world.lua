-- 盲盒服务端结算引擎边界夹具（#87 从 tests/gameplay/blindbox_settle_test.lua 抽出）。
-- 抽出的原因：旧 LuaUnit 套件同时被 busted 车道与 tools/acceptance/platform_steps.lua 的
-- 验收步骤复用（dofile + setmetatable 借用类方法）。迁移到原生后测试文件不再是全局类，
-- 因此把「搭世界」这一段下沉为共享夹具，测试与验收各自 new() 一个实例。
-- 只搭环境、不含任何断言；业务行为一律走真实管理器公共接口。
-- seam：真实 MgrSave + MgrPlayerData + MgrPlatform + MgrBlindbox（#123 持久操作协议），
--   替换引擎边界（game / REUtil / DataStore / 时钟）；随机数经 MgrBlindbox.Random 注入。
local GameCfg = require("common.GameCfg")

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

local World = {}
World.__index = World

--- 搭建一次结算世界；调用方负责在案例结束时 tearDown()。
function M.new()
  return setmetatable({}, World)
end

function World:setUp()
  -- 逐项记录「改过什么」，让 cleanup 对半途失败的 setUp 幂等。
  self.changed = { goodsIds = false, debug = false, globals = false }
  self.oldGame, self.oldRE = _G.game, _G.REUtil
  self.changed.globals = true
  self.oldDebug = GameCfg.Debug
  self.changed.debug = true
  self.oldGoodsIds = {}
  self.changed.goodsIds = true
  for key, row in pairs(GameCfg.Platform.Goods) do
    self.oldGoodsIds[key] = row.goodsId
  end
  GameCfg.Debug = { Enabled = true } -- 未配置商品走 pending flow + 测试驱动器
  self.now = 1000
  self.values, self.queue, self.events = {}, {}, {}
  local env = self
  self.spawned = {} -- Loot 替身落地记录
  self.goodsSignal = signal()
  local store = {
    GetAsync = function(_, key)
      return env.values[key]
    end,
    UpdateAsync = function(_, key, transform)
      if env.failWrites then
        error("测试真实持久写失败")
      end
      local value = transform(env.values[key])
      if value then
        env.values[key] = value
      end
      return value
    end,
    SetAsync = function(_, key, value)
      env.values[key] = value
    end,
  }
  _G.game = {
    GetService = function(_, name)
      if name == "Task" then
        return {
          Spawn = function(_, fn)
            env.queue[#env.queue + 1] = fn
          end,
          Wait = function() end,
        }
      end
      if name == "DataStoreService" then
        return { GetDataStore = function() return store end }
      end
      if name == "World" then
        return { GetServerTime = function() return env.now end }
      end
      if name == "Players" then
        return { GetPlayers = function() return {} end }
      end
      if name == "CommodityService" then
        return {
          ShowGoodsPurchasePanel = function() end,
          GoodsPurchaseCompleted = env.goodsSignal,
        }
      end
    end,
  }
  _G.REUtil = {
    GetRE = function(_, name)
      return {
        FireClient = function(_, player, value)
          env.events[#env.events + 1] = { name = name, player = player, value = value }
        end,
        OnServerEvent = signal(),
      }
    end,
    CheckRECD = function()
      return false
    end,
  }
  self.save = assert(loadfile("server/Mgr/MgrSave.lua"))()
  self.players = assert(loadfile("server/Mgr/MgrPlayerData.lua"))()
  self.platform = assert(loadfile("server/Mgr/MgrPlatform.lua"))()
  self.blindbox = assert(loadfile("server/Mgr/MgrBlindbox.lua"))()
  self.players.Save, self.save.PlayerData = self.save, self.players
  self.platform.Save, self.platform.PlayerData = self.save, self.players
  self.blindbox.Save, self.blindbox.PlayerData, self.blindbox.Platform = self.save, self.players, self.platform
  self.blindbox.Loot = {
    DeliveryEpoch = "test-world",
    SpawnDelivery = function(_, key, itemId, mult, cooked, pos)
      env.delivered = env.delivered or {}
      if env.delivered[key] then
        return env.delivered[key]
      end
      local loot = env.blindbox.Loot:SpawnItem(itemId, mult, cooked, pos)
      env.delivered[key] = loot
      return loot
    end,
    SpawnItem = function(_, itemId, mult, cooked, pos)
      env.spawned[#env.spawned + 1] = { itemId = itemId, mult = mult, cooked = cooked, pos = pos }
      return { Id = "loot" .. #env.spawned }
    end,
  }
  self.rolls = {}
  -- 随机数注入点：模块字段 MgrBlindbox.Random，不触碰全局 math.random。
  self.blindbox.Random = function()
    local roll = table.remove(env.rolls, 1)
    assert(roll, "测试脚本 RNG 序列耗尽")
    return roll
  end
  self.platform.Now = function()
    return env.now
  end
  self.platform:Start()
  self.blindbox:Start()
  self.player = {
    UserId = 1472,
    Character = { Position = { x = 3, y = 0, z = 5 } },
    CharacterAdded = signal(),
    CharacterRemoving = signal(),
    SetAttribute = function() end,
  }
  self.players:OnPlayerAdded(self.player)
  self:drain()
  self.data = self.players:GetDataInst(self.player)
  self:persistReady()
end

--- 恢复全局与配置；setUp 半途失败时按已记录的改动项恢复，未改的跳过。
function World:tearDown()
  if self.changed then
    if self.changed.globals then
      _G.game, _G.REUtil = self.oldGame, self.oldRE
    end
    if self.changed.debug then
      GameCfg.Debug = self.oldDebug
    end
    if self.changed.goodsIds then
      for key, row in pairs(GameCfg.Platform.Goods) do
        row.goodsId = self.oldGoodsIds[key]
      end
    end
    self.changed = nil
  end
end

function World:drain()
  while #self.queue > 0 do
    table.remove(self.queue, 1)()
  end
end

function World:messages(name)
  local values = {}
  for _, event in ipairs(self.events) do
    if event.name == name then
      values[#values + 1] = event.value
    end
  end
  return values
end

function World:persistReady()
  assert(self.save:SaveExplicit(self.player.UserId, self.data, function(ok)
    assert(ok)
  end))
  self:drain()
  self.events = {}
end

-- 脚本化抽一发（count=1 或 10）：发起 → 驱动购买成功 → 跑完持久队列
function World:draw(count, seq, outcome)
  local accepted = self.blindbox:Handle(self.player,
    { action = "Draw", count = count, seq = seq })
  self:drain() -- 支付意图先持久化，再建立测试 flow
  if accepted and outcome then
    assert(self.platform:HandleTestAction(self.player,
      { action = "ResolveFlow", outcome = outcome }))
    self:drain()
  end
  return accepted
end

function World:lastResult()
  local results = self:messages("BlindboxResult")
  return results[#results]
end

-- 必须走 Removing、释放会话和新 Player 身份，禁止同对象 Added 充当恢复证据。
function World:reconnect()
  local old = self.player
  self.blindbox:OnPlayerRemoving(old)
  self.platform:OnPlayerRemoving(old)
  self.players:OnPlayerRemoving(old)
  self:drain()
  self.player = {
    UserId = old.UserId,
    Character = old.Character,
    CharacterAdded = signal(),
    CharacterRemoving = signal(),
    SetAttribute = function() end,
  }
  self.players:OnPlayerAdded(self.player)
  self:drain()
  self.data = self.players:GetDataInst(self.player)
end

return M
