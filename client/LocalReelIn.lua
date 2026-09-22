-- 收线（ReelIn）通道客户端半：把点击聚合成 {s,n,q} 打给服务端，并接服务端下发的结果。
--
-- 聚合窗口（100ms）与滑动窗（1s ≤10）的算法在 `common/RateLimit.lua`（模块线）：
-- 这里不重复实现，只留一个「怎么攒包」的接入点——`SetAggregator(agg)`。
-- 没有接入聚合器时，`RequestReel` 退化成「一次点击一个包」，只用于 M0 的通道取证，
-- M1 落地时必须在启动阶段注入真聚合器（否则上限行为与 C-2 不符）。

local REUtil = require("common.REUtil")

local LocalReelIn = {}

LocalReelIn.CHANNEL = "ReelInRE"

-- 单调序号（C-3 的 q 字段），从 1 起
LocalReelIn.Seq = 0
-- 当前会话 id：只接受服务端下发的（交接约束 3）
LocalReelIn.SessionId = nil
-- 可选聚合器：[客户端聚合器] = { Click = fn(now), Collect = fn(now) -> payload|nil }
LocalReelIn.Aggregator = nil

function LocalReelIn:SetAggregator(agg)
	self.Aggregator = agg
end

function LocalReelIn:SetSession(sessionId)
	if type(sessionId) ~= "string" or sessionId == "" then
		return false
	end
	self.SessionId = sessionId
	if self.Aggregator and self.Aggregator.SetSession then
		self.Aggregator:SetSession(sessionId)
	end
	return true
end

-- 攒包入口：有聚合器走聚合器，没有就现攒一个单点击包（M0 取证用）
function LocalReelIn:BuildPayload(count)
	if self.Aggregator then
		local World = game:GetService("World")
		local now = World and World:GetServerTime() or 0
		self.Aggregator:Click(now)
		local payload = self.Aggregator:Collect(now)
		if payload then
			self.Seq = payload.q
		end
		return payload
	end
	local n = count or 1
	local payload = { s = self.SessionId or "local", n = n, q = self.Seq + 1 }
	self.Seq = payload.q
	return payload
end

function LocalReelIn:RequestReel(count, sessionId)
	local re = self.RE or REUtil:GetRE(self.CHANNEL)
	if not re then
		print("[LocalReelIn] 通道不可用: " .. tostring(self.CHANNEL))
		return false
	end
	if sessionId then
		self:SetSession(sessionId)
	end
	local payload = self:BuildPayload(count)
	if not payload then
		return false
	end
	re:FireServer(payload)
	return true, payload
end

function LocalReelIn:Start()
	local re = REUtil:GetRE(self.CHANNEL)
	if not re then
		print("[LocalReelIn] 通道建立失败: " .. tostring(self.CHANNEL))
		return
	end
	self.RE = re
	re.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		-- 会话切换由服务端下发
		if payload.session then
			self:SetSession(payload.session)
		end
		LocalReelIn.LastResult = payload
		print("[LocalReelIn] 收到结果 action=" .. tostring(payload.action)
			.. " session=" .. tostring(payload.session)
			.. " progress=" .. tostring(payload.progress))
	end)
	print("[LocalReelIn] 通道就绪 " .. self.CHANNEL)
end

return LocalReelIn
