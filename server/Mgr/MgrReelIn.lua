-- 收线（ReelIn）通道：M0-V5 的「通道那一半」。
--
-- 只做两件事：建通道（`common/REUtil.lua:GetRE`）、把载荷过一遍「身份 + 类型」两层校验，
-- 然后把批次原样转给订阅者。频率校验（滑动窗 1s ≤10、超限 clamp 不报错）与聚合窗口的解包
-- 归高频输入骨架（`common/RateLimit.lua`，模块线），本模块不自己发明规则，只留 Subscribe 接缝。
--
-- 载荷口径（来源 issue #14 调研 + 模块线交接）：
--   { s = 会话id（非空字符串）, n = 窗口内点击数（≥1 的有限整数）, q = 单调序号（≥1 的有限整数）}
-- 官方对 RemoteEvent 的频率 / 包大小 / 超限行为都没有数值（R-1/R-7），只有两条硬约束：
-- 一次只传一个 Any 载荷、不支持直接传 CFrame（`docs/research/remoteevent-limits.md` §2.2），
-- 所以字段固定三个、客户端只发这张表，不追加字段（R-7 的字节上界就是按三个字段推的）。

local REUtil = require("common.REUtil")

local Mgr = {}

-- 通道名是常量：换名等于换通道，两端必须同时改。
Mgr.CHANNEL = "ReelInRE"

-- [userId] = 服务端下发的会话 id（会话切换只由服务端发起，见交接约束 3）
Mgr.Sessions = {}

-- 订阅者名单：fn(player, batch, raw) → 是否已处理
Mgr.Subscribers = {}

-- 取证计数：通过校验并转给订阅者的批次数
Mgr.AcceptedBatches = 0
-- 取证计数：被「身份/类型」校验挡下的包数（频率层不算）
Mgr.RejectedBatches = 0

function Mgr:Subscribe(fn)
	if type(fn) ~= "function" then
		return false
	end
	self.Subscribers[#self.Subscribers + 1] = fn
	return true
end

function Mgr:SetSession(player, sessionId)
	if not player or type(sessionId) ~= "string" or sessionId == "" then
		return false
	end
	self.Sessions[player.UserId] = sessionId
	return true
end

local function isCount(v)
	if type(v) ~= "number" then
		return false
	end
	-- nan / inf 一律不当数（math.floor(nan) 在 Lua 5.4 会直接抛错）
	if v ~= v or v == math.huge or v == -math.huge then
		return false
	end
	if v < 1 or v ~= math.floor(v) then
		return false
	end
	return true
end

-- 类型层：只认 {s,n,q} 三个字段，形状不对直接丢（不报错、不回包——超限行为无官方口径，R-5）
local function checkPayload(payload)
	if type(payload) ~= "table" then
		return false, "not-table"
	end
	if type(payload.s) ~= "string" or payload.s == "" then
		return false, "session-not-string"
	end
	if not isCount(payload.n) then
		return false, "bad-count"
	end
	if not isCount(payload.q) then
		return false, "bad-seq"
	end
	return true
end

function Mgr:Start()
	local re = REUtil:GetRE(self.CHANNEL)
	if not re then
		print("[MgrReelIn] 通道建立失败: " .. tostring(self.CHANNEL))
		return
	end
	self.RE = re

	re.OnServerEvent:Connect(function(player, payload)
		-- 身份层：player 只能来自事件实参，不信客户端自报
		if not player then
			return
		end
		local ok, reason = checkPayload(payload)
		if not ok then
			self.RejectedBatches = self.RejectedBatches + 1
			return
		end
		local batch = {
			SessionId = payload.s,
			Count = payload.n,
			Seq = payload.q,
			Player = player,
		}
		-- 业务条件层留给订阅者（是否在收线会话里、是否在钓点……）
		for _, fn in ipairs(self.Subscribers) do
			pcall(fn, player, batch, payload)
		end
		self.AcceptedBatches = self.AcceptedBatches + 1
	end)

	-- 结果下发层：服务端权威判定后回包，客户端只做表现（R-5：不能假设超限会有错误回执）
	local Players = game:GetService("Players")
	if Players then
		Players.PlayerRemoving:Connect(function(player)
			self.Sessions[player.UserId] = nil
		end)
	end

	print("[MgrReelIn] 通道就绪 " .. self.CHANNEL)
end

function Mgr:OnPlayerAdded(player)
	self.Sessions[player.UserId] = nil
end

function Mgr:OnPlayerRemoving(player)
	self.Sessions[player.UserId] = nil
end

function Mgr:Update(deltaTime)
end

return Mgr
