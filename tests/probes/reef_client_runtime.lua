-- #37 真实客户端取证：试玩后在客户端执行全文，再服务端运行 reef_runtime.lua。
-- 正常钓鱼时截图空中来源/企鹅水来源/鱼线，打开图鉴再关闭应继续收线表现。
-- 截图投掷落体与锁点圈，input 走出落点；日志应一对 lock/clear，cleanup 后本地对象为空。
-- 再次执行先断旧探针，不替换任何业务 handler 或 RemoteEvent。
if _G.Reef37ClientConns then
    for _,conn in ipairs(_G.Reef37ClientConns) do conn:Disconnect() end
end
local re=require('common.REUtil')
_G.Reef37ClientConns={
    re:GetRE('GarBiteNotice').OnClientEvent:Connect(function(p)
        if p.move=='airThrow' or p.move=='airDive' or (type(p.fishId)=='number' and p.fishId<0) then
            print('REEF37_CLIENT_NOTICE',p.kind,p.fishId,p.ownerFishId,p.move,p.position,p.reason)
        end
    end),
    re:GetRE('CastState').OnClientEvent:Connect(function(p)
        print('REEF37_CLIENT_CAST',p.phase,p.fishId,p.catchSource,p.hookPosition)
    end),
}
print('REEF37_CLIENT_READY')
