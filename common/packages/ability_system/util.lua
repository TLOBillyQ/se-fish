--技能系统 - common工具函数
-- 双端共享，纯函数；零引擎 API 依赖。

local AbilityConstants = require("common.packages.ability_system.constants")

local AbilityUtils = {}

-- 槽位校验

-- 槽位索引无上限：只校验"是不是真实槽位"（非 nil 且 >= SLOT_BASE）。
-- maxSlotCount 形参已废弃（保留仅为兼容旧调用），不再参与判断。
function AbilityUtils.isSlotValid(slotType, slotIndex, maxSlotCount)
	-- slotType 可选：ability 不需要 slotType，调用方传 nil 即可
	if slotIndex == nil then
		return false
	end
	return slotIndex >= AbilityConstants.SLOT_BASE
end

function AbilityUtils.isSlotEmpty(slots, slotIndex)
	return slots[slotIndex] == nil
end

-- 已占用槽位数（无上限：只数稀疏表里已有的键）
function AbilityUtils.getOccupiedCount(slots)
	local count = 0
	for _ in pairs(slots) do
		count = count + 1
	end
	return count
end

-- 槽位查找

-- 从 startIndex 起找第一个空槽：无上限，恒返回可用索引
function AbilityUtils.getFirstAvailableSlot(slots, startIndex)
	local i = startIndex or AbilityConstants.SLOT_BASE
	while slots[i] ~= nil do
		i = i + 1
	end
	return i
end

-- 排序

function AbilityUtils.sortByIndex(slots)
	local result = {}
	for _, abilityScript in pairs(slots) do
		table.insert(result, abilityScript)
	end
	table.sort(result, function(a, b)
		local ia = a:GetAttribute("Index") or AbilityConstants.SLOT_INDEX_UNASSIGNED
		local ib = b:GetAttribute("Index") or AbilityConstants.SLOT_INDEX_UNASSIGNED
		return ia < ib
	end)
	return result
end

function AbilityUtils.sortByLevel(slots)
	local result = {}
	for _, abilityScript in pairs(slots) do
		table.insert(result, abilityScript)
	end
	table.sort(result, function(a, b)
		local la = a:GetAttribute("Level") or 1
		local lb = b:GetAttribute("Level") or 1
		return la < lb
	end)
	return result
end

-- 切换策略指针计算

-- Sequential: 0..N-1 循环
function AbilityUtils.nextSequential(activeIndex, count)
	if count == 0 then
		return 1
	end
	return (activeIndex % count) + 1
end

-- 确定性伪随机数发生器（Park-Miller 最小标准 LCG）：纯算术、双端与多次运行结果一致。
-- 逻辑随机一律走本实现，禁止使用 math.random（§12.2 确定性）。
---@param seed integer 稳定种子（同种子必得同一序列）
---@return table rng 含 nextInt(min, max)
function AbilityUtils.newRandom(seed)
	local state = math.floor(seed or 1) % 2147483647
	if state <= 0 then
		state = state + 2147483646
	end
	local rng = {}
	---@param min integer 下界（含）
	---@param max integer 上界（含）
	---@return integer 区间内整数
	function rng.nextInt(min, max)
		state = (state * 48271) % 2147483647
		local span = max - min + 1
		return min + (state - 1) % span
	end
	return rng
end

-- 时间工具

-- 服务端时间来源：默认返回 0；调用方应通过 setServerTimeFn 注入（如 World:GetServerTime()）
AbilityUtils._getServerTimeFn = function()
	return 0
end

function AbilityUtils.setServerTimeFn(fn)
	AbilityUtils._getServerTimeFn = fn
end

function AbilityUtils.getServerTime()
	return AbilityUtils._getServerTimeFn()
end

-- 计算剩余 CD 时间
function AbilityUtils.getRemainingCD(cdFinishTime, currentServerTime)
	if not cdFinishTime then
		return 0
	end
	local remaining = cdFinishTime - (currentServerTime or AbilityUtils.getServerTime())
	return remaining > 0 and remaining or 0
end

return AbilityUtils
