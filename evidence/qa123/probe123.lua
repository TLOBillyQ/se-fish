-- #123 只读身份探针：由主会话独占编辑器时 exec -p server --file 调用。
-- 同槽退出/重进前后分别执行，比较 coin、bar、bp、sequence 与 operation 行。
-- 不创建新档、不发奖、不改槽，不把此探针当真实存储竞态证明。
local save = require('server.Mgr.MgrSave')
local players = game:GetService('Players'):GetPlayers()
for _, player in ipairs(players) do
    local status = save:Status(player.UserId)
    local data = _G.MgrPlayerData:GetDataInst(player)
    print('PROBE123 state', player.UserId, status.loadState, status.currentSlot,
        'epoch=' .. tostring(status.epoch), 'revision=' .. tostring(status.revision))
    if data then
        local snapshot = data:Serialize()
        print('PROBE123 identity', player.UserId, snapshot.meta.session,
            'coin=' .. snapshot.coin, 'bar=' .. #snapshot.bar, 'bp=' .. #snapshot.bp,
            'sequence=' .. snapshot.meta.sequence, 'floor=' .. snapshot.meta.floor,
            'bytes=' .. save:EstimateSize(snapshot))
        for _, container in ipairs({ snapshot.bar, snapshot.bp }) do
            for _, item in ipairs(container) do
                print('PROBE123 item', player.UserId, item.i, item.id, item.n, item.m)
            end
        end
        for _, operation in ipairs(snapshot.meta.operations) do
            print('PROBE123 operation', player.UserId, operation.id, operation.kind, operation.sequence)
        end
    end
end
print('PROBE123 DONE')
