--胜利规则 - client端api
--面向地图脚本的客户端结算监听入口。

local winRule = require("client.packages.win_rule.win_rule")

---初始化客户端结算监听：连接服务端结算事件并驱动本端面板，重复调用安全
local function Init()
	winRule.init()
end

return {
	Funcs = {
		Init = Init,
	},
}
