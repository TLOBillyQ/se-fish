local Util = {}
function Util:Teleport()
end

function Util:SimpleTeleport(player, pos)
    --待处理：镜头快速跟随？朝向？
    if not player or not player.Character then
        print("[TeleportUtil] SimpleTeleport() no player character")
        return
    end
    
    --强制等待character加载后再尝试传送？
    print("[TeleportUtil] SimpleTeleport()", pos)
    player.Character.Position =  pos
end

_G.TeleportUtil = Util

return Util