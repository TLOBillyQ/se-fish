local GameCfg = {}

GameCfg.FishMap = {
    Fish001 = {Id = "Fish001",  Name = "草鱼",  Icon = 37132,    ReqStep = 3,    Coin = 40}, --Icon = "official://image/37132"
    Fish002 = {Id = "Fish002",  Name = "小丑鱼",    Icon = 37137,    ReqStep = 2,    Coin = 25},
    Fish003 = {Id = "Fish003",  Name = "鲫鱼",  Icon = 37134,    ReqStep = 3,    Coin = 30},
    Fish004 = {Id = "Fish004",  Name = "黑鱼",  Icon = 37125,    ReqStep = 3,    Coin = 35},
    Fish005 = {Id = "Fish005",  Name = "章鱼",  Icon = 15970,    ReqStep = 4,    Coin = 80},
    Fish006 = {Id = "Fish006",  Name = "旗鱼",  Icon = 37119,    ReqStep = 4,    Coin = 70},
    Fish007 = {Id = "Fish007",  Name = "蝴蝶鱼",    Icon = 37123,    ReqStep = 4,    Coin = 90},
    Fish008 = {Id = "Fish008",  Name = "鳐鱼",  Icon = 37121,    ReqStep = 5,    Coin = 150},    --150
    Fish009 = {Id = "Fish009",  Name = "三文鱼",  Icon = 37130,    ReqStep = 5,    Coin = 160},  --160
    Fish010 = {Id = "Fish010",  Name = "大马哈鱼",  Icon = 37118,    ReqStep = 5,    Coin = 120},   --120
    Fish011 = {Id = "Fish011",  Name = "鲨鱼",  Icon = 37120,    ReqStep = 6,    Coin = 200},
    Fish012 = {Id = "Fish012",  Name = "七彩鱼",  Icon = 37129,    ReqStep = 6,    Coin = 300},
    Fish013 = {Id = "Fish013",  Name = "大章鱼",  Icon = 33706,    ReqStep = 6,    Coin = 250},
}
--35971 鱼竿
GameCfg.MaxRodLv = 5
GameCfg.RodLevelMap = {}
GameCfg.RodLevelMap[1] = {
    Cost = 100, --升级需求
    FishTime = 4,
}

GameCfg.RodLevelMap[2] = {
    Cost = 500,
    FishTime = 4.5,
}

GameCfg.RodLevelMap[3] = {
    Cost = 1000,
    FishTime = 5,
}

GameCfg.RodLevelMap[4] = {
    Cost = 10000,
    FishTime = 5.5,
}

GameCfg.RodLevelMap[5] = {
    Cost = 0,
    FishTime = 6,
}

GameCfg.MaxFishLv = 5
GameCfg.FishLevelMap = {}
GameCfg.FishLevelMap[1] = {
    Cost = 100,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
    }
}

GameCfg.FishLevelMap[2] = {
    Cost = 500,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 1,
        Fish006 = 1,
        Fish007 = 1,
    }
}

GameCfg.FishLevelMap[3] = {
    Cost = 1000,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 2,
        Fish006 = 2,
        Fish007 = 2,
        Fish008 = 1,
        Fish009 = 1,
        Fish010 = 1,
    }
}

GameCfg.FishLevelMap[4] = {
    Cost = 10000,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 2,
        Fish006 = 2,
        Fish007 = 2,
        Fish008 = 2,
        Fish009 = 2,
        Fish010 = 2,
        Fish011 = 1,
        Fish012 = 1,
        Fish013 = 1,
    }
}

GameCfg.FishLevelMap[5] = {
    Cost = 0,
    Loot = {
        Fish001 = 1,
        Fish002 = 1,
        Fish003 = 1,
        Fish004 = 1,
        Fish005 = 2,
        Fish006 = 2,
        Fish007 = 2,
        Fish008 = 3,
        Fish009 = 3,
        Fish010 = 3,
        Fish011 = 4,
        Fish012 = 4,
        Fish013 = 4,
    }
}

function GameCfg:GetLootRst(loot)
    local total = 0
    for _, v in pairs(loot) do
        total = total + v
    end

    local randomValue = math.random(total)
    for k, v in pairs(loot) do
        if randomValue > v then
            randomValue = randomValue - v
        else
            return k
        end
    end
end

return GameCfg