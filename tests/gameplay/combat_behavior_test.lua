-- #128：武器命中与电鳗范围命中必须经统一伤害入口；同一判定段重放不双扣。
-- #129：玩家挥砍只认 AbilityAPI 挥砍登记（伤害/射程来自 GameCfg 表），未登记不结算。
local lu = require('luaunit')

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		self.handlers[#self.handlers + 1] = fn
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, fn in ipairs(self.handlers) do fn(...) end
	end
	return s
end
local function vec(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b)
		return vec(a.x + b.x, a.y + b.y, a.z + b.z)
	end })
end

TestMeleeHitEntry = {}
function TestMeleeHitEntry:setUp()
	self.saved = {
		game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion'),
		vitals = package.loaded['server.Mgr.MgrVitals'],
		carrier = package.loaded['server.Mgr.MgrFishCarrier'],
		gm = package.loaded['server.Mgr.MgrGM'],
		api = package.loaded['server.AbilityAPI'],
	}
	_G.Vector3 = { New = vec }
	_G.Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
	self.ownerPlayer = { UserId = 7 }
	self.owner = { UnitId = 70, Position = vec(0, 0, 0) }
	self.ownerPlayer.Character = self.owner
	self.controllerCalls = 0
	self.target = { UnitId = 80, UnitType = 'EggyUnit', Position = vec(1, 0, 0), Controller = {
		TakeDamage = function() self.controllerCalls = self.controllerCalls + 1 end,
	} }
	self.carrier = { Receiver = self.target }
	self.hits = {}
	-- #129：玩家挥砍只认 AbilityAPI 登记值；测试用假登记模块，不经真实包链
	self.swingStaged = {}
	package.loaded['server.AbilityAPI'] = {
		TakeSwing = function(userId)
			local s = self.swingStaged[userId]
			self.swingStaged[userId] = nil
			return s
		end,
	}
	package.loaded['server.Mgr.MgrVitals'] = {
		NewHit = function(_, source, category)
			local hit = { source = source, category = category, id = 1 }
			self.createdHit = hit
			return hit
		end,
		ApplyHit = function(_, hit, target, amount)
			self.hits[#self.hits + 1] = { hit, target, amount }
			return true, amount
		end,
	}
	package.loaded['server.Mgr.MgrFishCarrier'] = {
		ResolveCarrier = function(_, target) return target == self.target and self.carrier or nil end,
	}
	package.loaded['server.Mgr.MgrGM'] = { GetMeleeDamage = function(_, _, damage) return damage end }
	self.created = {}
	local env = self
	_G.game = { GetService = function(_, name)
		if name == 'RunService' then return { IsServer = function() return true end } end
		if name == 'World' then return { CreateUnit = function(_, unitType, values)
			local unit = { UnitId = 500 + #env.created, UnitType = unitType, OnTriggerEnter = signal() }
			for k, v in pairs(values or {}) do unit[k] = v end
			env.created[#env.created + 1] = unit
			return unit
		end, CreateAsset = function() return {} end } end
		if name == 'Players' then return { GetPlayerFromCharacter = function(_, unit)
			return unit == env.owner and env.ownerPlayer or nil
		end } end
		if name == 'PhysicsService' then return { GetPartsInPart = function() return {} end } end
		if name == 'TimerService' then return { CreateTimer = function() end } end
	end }
end
function TestMeleeHitEntry:tearDown()
	_G.game = self.saved.game
	_G.Vector3 = self.saved.Vector3
	_G.Quaternion = self.saved.Quaternion
	package.loaded['server.Mgr.MgrVitals'] = self.saved.vitals
	package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
	package.loaded['server.Mgr.MgrGM'] = self.saved.gm
	package.loaded['server.AbilityAPI'] = self.saved.api
end
function TestMeleeHitEntry:buildAnchor(attrs)
	local manager = { Parent = self.owner }
	local ability = { Parent = manager }
	local anchor = { Parent = ability, AnchorStart = signal(), Destroying = signal() }
	function anchor:FindFirstChild(name) return self[name] end
	function anchor:GetAttribute(name) return attrs[name] end
	local behavior = assert(loadfile('server/AbilityBehaviors/melee_hit.lua'))()
	behavior.Attach(anchor)
	return anchor
end
function TestMeleeHitEntry:baseAttrs()
	return {
		Duration = 0.2,
		ABILITY_ANOSTATE_HITBOX_OFFSET = vec(0, 0, 1),
		ABILITY_ANOSTATE_HITBOX_SCALE = vec(2, 2, 2),
		ABILITY_ANOSTATE_BULLET_DAMAGE = 25,
		ABILITY_ANOSTATE_HITPOWER = 0,
		ABILITY_ANOSTATE_USE_PERFAB = '',
		ABILITY_ANOSTATE_ANIMKEY = '',
	}
end

-- #129：玩家挥砍经 AbilityAPI 登记（MgrWeapon 按 GameCfg 表登记伤害/射程），
-- 命中盒由登记射程推导，伤害不再回落到预设属性 25；命中身份与去重口径不变。
function TestMeleeHitEntry:test_fish_hit_uses_staged_swing_not_attribute_25()
	self.swingStaged[7] = { damage = 12, range = 4 }
	self:buildAnchor(self:baseAttrs()).AnchorStart:Fire()
	local hitBox = self.created[#self.created]
	lu.assertEquals(hitBox.Scale.z, 4)   -- 命中盒射程 = 登记射程
	lu.assertEquals(hitBox.Scale.x, 2)
	hitBox.OnTriggerEnter:Fire(self.target)
	hitBox.OnTriggerEnter:Fire(self.target)
	lu.assertEquals(self.controllerCalls, 0)
	lu.assertEquals(#self.hits, 1)
	lu.assertEquals(self.hits[1][1], self.createdHit)
	lu.assertEquals(self.hits[1][1].source, self.ownerPlayer)
	lu.assertEquals(self.hits[1][1].category, 'weapon')
	lu.assertEquals(self.hits[1][2], self.target)
	lu.assertEquals(self.hits[1][3], 12)
end

-- 未经登记的玩家挥砍（伪造 RequestCast）：不建命中盒、不结算伤害，只播表现
function TestMeleeHitEntry:test_unregistered_player_swing_deals_nothing()
	self:buildAnchor(self:baseAttrs()).AnchorStart:Fire()
	lu.assertEquals(#self.created, 0)
	lu.assertEquals(#self.hits, 0)
end

-- 非玩家单位（鱼类施法）没有登记概念：沿用预设属性，行为不变
function TestMeleeHitEntry:test_non_player_owner_keeps_attribute_fallback()
	self.ownerPlayer.Character = nil -- GetPlayerFromCharacter 不再认 owner
	local attrs = self:baseAttrs()
	attrs.ABILITY_ANOSTATE_HITBOX_SCALE = vec(3, 2, 3)
	self:buildAnchor(attrs).AnchorStart:Fire()
	local hitBox = self.created[#self.created]
	lu.assertEquals(hitBox.Scale, vec(3, 2, 3))
	hitBox.OnTriggerEnter:Fire(self.target)
	lu.assertEquals(#self.hits, 1)
	lu.assertEquals(self.hits[1][3], 25)
	self.ownerPlayer.Character = self.owner
end

-- #128：server/main.lua 必须完成战斗接线，否则运行时各管理器拿不到统一入口。
TestMainCombatWiring = {}
local function readSource(path)
	local parts = {}
	for line in io.lines(path) do
		parts[#parts + 1] = line
	end
	return table.concat(parts, "\n")
end
function TestMainCombatWiring:test_combat_managers_are_wired_to_unified_entry()
	local src = readSource('server/main.lua')
	lu.assertStrContains(src, 'MgrMap.MgrAbility.Vitals = MgrMap.MgrVitals')
	lu.assertStrContains(src, 'MgrMap.MgrFishUnit.Vitals = MgrMap.MgrVitals')
	lu.assertStrContains(src, 'MgrMap.MgrVitals.FishCarrier = MgrMap.MgrFishCarrier')
	lu.assertStrContains(src, 'MgrMap.MgrCast.Vitals = MgrMap.MgrVitals')
	lu.assertStrContains(src, 'MgrMap.MgrFishCarrier.DamageListener')
	-- 有效鱼受击伤害要回报仇恨：监听里必须经 FindByCarrier 找回鱼并 NoteDamage
	lu.assertStrContains(src, 'FindByCarrier')
	lu.assertStrContains(src, 'NoteDamage')
end

TestEelDischargeEntry = {}
function TestEelDischargeEntry:setUp()
	self.saved = { game = rawget(_G, 'game'),
		vitals = package.loaded['server.Mgr.MgrVitals'],
		carrier = package.loaded['server.Mgr.MgrFishCarrier'] }
	self.hits = {}
	self.seenHits = {}
	self.hitSerial = 0
	package.loaded['server.Mgr.MgrVitals'] = {
		NewHit = function(_, source, category)
			self.hitSerial = self.hitSerial + 1
			return { id = self.hitSerial, source = source, category = category }
		end,
		ApplyHit = function(_, hit, player, amount)
			local key = tostring(hit.id) .. ':' .. tostring(player.UserId)
			if self.seenHits[key] then return false end
			self.seenHits[key] = true
			self.hits[#self.hits + 1] = { hit, player, amount }
			return true, amount
		end,
	}
	self.owner = { Position = vec(0, 0, 0) }
	self.carrier = { Receiver = self.owner }
	package.loaded['server.Mgr.MgrFishCarrier'] = {
		ResolveCarrier = function(_, unit) return unit == self.owner and self.carrier or nil end,
	}
	self.inside = { UserId = 1, Character = { Position = vec(1, 0, 0), Controller = { Health = 300 } } }
	self.outside = { UserId = 2, Character = { Position = vec(9, 0, 0), Controller = { Health = 300 } } }
	local env = self
	_G.game = { GetService = function(_, name)
		if name == 'Players' then return { GetPlayers = function() return { env.inside, env.outside } end } end
	end }
end
function TestEelDischargeEntry:tearDown()
	_G.game = self.saved.game
	package.loaded['server.Mgr.MgrVitals'] = self.saved.vitals
	package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
end
function TestEelDischargeEntry:test_discharge_uses_fish_hit_and_replay_does_not_double_apply()
	local behavior = assert(loadfile('server/AbilityBehaviors/eel_discharge.lua'))()
	lu.assertEquals(behavior.Discharge(self.owner, 5, 15), 1)
	lu.assertEquals(#self.hits, 1)
	lu.assertEquals(self.hits[1][1].source, self.carrier)
	lu.assertEquals(self.hits[1][1].category, 'fishAttack')
	lu.assertEquals(self.hits[1][2], self.inside)
	local replay = { id = 99, source = self.carrier, category = 'fishAttack' }
	lu.assertEquals(behavior.Discharge(self.owner, 5, 15, replay), 1)
	lu.assertEquals(behavior.Discharge(self.owner, 5, 15, replay), 0)
	lu.assertEquals(#self.hits, 2)
end
