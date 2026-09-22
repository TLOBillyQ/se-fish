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

-- 技能包（ability_system）在本图的接入配置。
-- 预设本体存在图里、不进 git，这里只记 key；预设的建法与完整命令记录见 issue #7 / #8——
-- 本编辑器不认包内的 ---@export_prefab_type 自定义预设类型（见 #7 结论），所以：
--   技能管理器（官方叫技能背包）= 复制官方「技能背包」模板（u014968…）
--   技能 = 复制官方「技能」模板（uc57b9…）；加速技能重写过壳源码（官方文档的「手工创建方式」），
--         挥砍技能沿用模板原壳
--   锚点 = 复制官方「锚点」模板（uccfb9d…），壳改成只声明属性（壳会在 Parent=World 时抢跑），
--         挂接由根 AbilityAPI.AttachAnchor 补做
-- 注意：change-asset-value 改不动「壳里已声明的属性」，实例拿到的是预设单位数据里的旧值，
-- 所以加速技能用的是模板默认 CastTime=0.5 秒（加速窗口只有 0.5 秒），详见 issue #7；
-- 锚点的关键实例值改由 AnchorAttributes 在挂接前 SetAttribute 覆盖（含 Duration，melee_hit 要求 > 0）。
-- melee_hit 的命中盒用包内硬编码的官方网格 57450——已实测它是平台级资源，本图直接可用（issue #8）。
GameCfg.Ability = {
    -- 角色进图时实例化到角色下的技能背包预设
    ManagerPreset = "map://preset/ubdb4a7e737d4eddb87729e9055ba375",
    -- 进图后装的初始技能：AssetId=技能预设，Index=槽位（0 基），
    -- Anchor=锚点预设，AnchorBehavior=锚点行为模块名（anchors/ 下的文件名），
    -- AnchorAttributes=挂接前覆盖到锚点实例的属性（{x,y,z} 表会转成 Vector3）
    InitialAbilities = {
        {
            AssetId = "map://preset/uf7fac66639546e2aa376151835cf3a6",
            Index = 0,
            Anchor = "map://preset/uaf2781161d6460990a4941b12ad30c2",
            AnchorBehavior = "speed_add",
        },
        -- 挥砍：玩家的攻击（手持武器发起，见 CONTEXT.md「战斗」），道具按钮触发
        {
            AssetId = "map://preset/u0d0b1993faa482b93e806d23715b73e",
            Index = 1,
            Anchor = "map://preset/ucc500ac3aac4b749fd9bee03b57e4d5",
            AnchorBehavior = "melee_hit",
            AnchorAttributes = {
                -- 命中盒存活窗口；必须 ≤ 施法窗口（技能模板默认 CastTime=0.5，已声明属性预设侧改不动，见 issue #7 坑 2）
                Duration = 0.3,
                ABILITY_ANOSTATE_HITBOX_OFFSET = { x = 0, y = 1, z = 2 }, -- 面前 2 米
                ABILITY_ANOSTATE_HITBOX_SCALE = { x = 3, y = 2, z = 3 },
                ABILITY_ANOSTATE_BULLET_DAMAGE = 25.0,
                ABILITY_ANOSTATE_HITPOWER = 0.0, -- 验证期不击退，便于观察扣血
            },
        },
    },
}

return GameCfg
