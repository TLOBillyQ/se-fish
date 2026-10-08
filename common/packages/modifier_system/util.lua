--效果系统包 - 工具方法

local util = {}

---获取服务端时间戳，单位秒，倒计时与剩余时间换算统一走该时间源
---@return number 服务端时间戳
function util.getServerTime()
	return game:GetService("World"):GetServerTime()
end

return util
