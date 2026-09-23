local GameCfg = require('common.GameCfg')

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.New(player)
    return setmetatable({ Player = player, Inited = false }, PlayerData)
end

-- 本局只有这里发放初始物品；重复 Init 不会重置已有库存。
function PlayerData:Init()
    if not self.Player or self.Inited then return end
    local items = {}
    local bait = {}
    for _, grant in ipairs(GameCfg.Items.InitialGrants) do
        if grant.containerId == GameCfg.Items.ContainerId.ItemBar then
            items[#items + 1] = {
                itemId = grant.itemId,
                count = grant.count,
                containerId = grant.containerId,
            }
        elseif grant.containerId == GameCfg.Items.ContainerId.Bait then
            bait[grant.itemId] = (bait[grant.itemId] or 0) + grant.count
        end
    end
    self.Data = {
        FishCoin = 0,
        FishCount = 0,
        FishLevel = 1,
        RodLevel = 1,
        Containers = { [GameCfg.Items.ContainerId.ItemBar] = items },
        Bait = bait,
        Progress = {},
    }
    self.Inited = true
    self:Sync()
end

function PlayerData:GetItemBarSnapshot()
    if not self.Inited then return nil end
    local snapshot = {}
    local items = self.Data.Containers[GameCfg.Items.ContainerId.ItemBar]
    for index, entry in ipairs(items) do
        snapshot[index] = {
            itemId = entry.itemId,
            count = entry.count,
            containerId = entry.containerId,
        }
    end
    -- 蚯蚓在鱼饵库存里计数，道具栏仅展示同一库存的入口。
    local wormId = GameCfg.Items.Id.Worm
    snapshot[#snapshot + 1] = {
        itemId = wormId,
        count = self.Data.Bait[wormId] or 0,
        containerId = GameCfg.Items.ContainerId.Bait,
    }
    return snapshot
end

function PlayerData:UpdateData(updateCallBack, doSync)
    if not self.Inited or not updateCallBack then return end
    updateCallBack(self.Data)
    if doSync then self:Sync() end
end

function PlayerData:Sync()
    if not self.Player or not self.Inited then return end
    for _, key in ipairs({ 'FishCoin', 'FishCount', 'FishLevel', 'RodLevel' }) do
        self.Player:SetAttribute(key, self.Data[key])
    end
end

function PlayerData:Destroy()
    self.Player = nil
    self.Data = nil
    self.Inited = false
end

return PlayerData
