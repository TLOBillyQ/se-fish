-- #44 内置素材占位；正式交付后替换配置中的 URI，不改玩法与判定参数。
local Assets = {
    Grades = {
        normal = { 255, 255, 255, 255 },
        rare = { 255, 205, 65, 255 },
        elite = { 255, 130, 65, 255 },
        boss = { 240, 80, 80, 255 },
    },
    Categories = {
        ['食物'] = { Icon = 'official://image/13008', Mesh = 'official://mesh/7000557', Scale = { x = 0.3, y = 0.3, z = 0.3 } },
        ['极品食物'] = { Icon = 'official://image/11164', Mesh = 'official://mesh/7000557', Scale = { x = 0.3, y = 0.3, z = 0.3 } },
        ['鱼饵'] = { Icon = 'official://image/14066', Mesh = 'official://mesh/7000571', Scale = { x = 0.3, y = 0.3, z = 0.3 } },
        ['鱼竿'] = { Icon = 'official://image/12024', Mesh = 'official://mesh/50450', Scale = { x = 0.2, y = 0.25, z = 0.2 }, Socket = 'l_weapon' },
        ['近战武器'] = { Icon = 'official://image/12024', Mesh = 'official://mesh/57363', Scale = { x = 0.1, y = 0.1, z = 0.1 }, Socket = 'r_weapon' },
        ['远程武器'] = { Icon = 'official://image/14066', Mesh = 'official://mesh/50450', Scale = { x = 0.15, y = 0.1, z = 0.15 }, Socket = 'r_weapon' },
        ['过关道具'] = { Icon = 'official://image/14105', Mesh = 'official://mesh/50450', Scale = { x = 0.15, y = 0.04, z = 0.15 } },
        ['属性道具'] = { Icon = 'official://image/11154', Mesh = 'official://mesh/7000253', Scale = { x = 0.2, y = 0.2, z = 0.2 } },
        ['特殊道具'] = { Icon = 'official://image/11164', Mesh = 'official://mesh/50227', Scale = { x = 0.07, y = 0.07, z = 0.07 } },
        ['自救道具'] = { Icon = 'official://image/13008', Mesh = 'official://mesh/7000253', Scale = { x = 0.15, y = 0.15, z = 0.15 } },
        ['爆炸物'] = { Icon = 'official://image/11154', Mesh = 'official://mesh/7000253', Scale = { x = 0.2, y = 0.2, z = 0.2 } },
    },
    ItemColors = {
        item152 = { 110, 220, 100, 255 }, item153 = { 190, 215, 240, 255 },
        item154 = { 255, 205, 65, 255 }, item155 = { 100, 110, 130, 255 },
        item156 = { 220, 220, 220, 255 }, item157 = { 190, 215, 240, 255 },
        item158 = { 255, 205, 65, 255 }, item159 = { 255, 120, 55, 255 },
        item160 = { 235, 80, 80, 255 }, item161 = { 150, 200, 255, 255 },
        item162 = { 230, 185, 110, 255 }, item163 = { 130, 220, 255, 255 },
        item164 = { 255, 240, 95, 255 }, item165 = { 255, 205, 65, 255 },
        item166 = { 255, 120, 55, 255 }, item167 = { 110, 220, 100, 255 },
        item168 = { 255, 160, 190, 255 }, item169 = { 150, 220, 255, 255 },
        item170 = { 100, 210, 130, 255 }, item171 = { 255, 100, 100, 255 },
    },
    Special = {
        wings = { Mesh = 'official://mesh/50227', Socket = 'origin', Offset = { x = 0, y = 1, z = -0.3 },
            Scale = { x = 0.07, y = 0.07, z = 0.07 } },
        godzilla = { Mesh = 'official://mesh/7000550', Socket = 'origin', Offset = { x = 0, y = 1, z = -0.3 },
            Scale = { x = 0.4, y = 0.4, z = 0.4 } },
    },
}

function Assets.Apply(cfg)
    for _, fish in pairs(cfg.Fish) do
        fish.VisualColor = fish.VisualColor or Assets.Grades[fish.Grade]
    end
    for id, item in pairs(cfg.Items.Definitions) do
        local category = Assets.Categories[item.Type]
        if category then
            local fish = cfg.Fish[id]
            item.Icon = item.Icon or (fish and 'official://image/11164' or category.Icon)
            item.Visual = item.Visual or category
            item.IconColor = item.IconColor or Assets.ItemColors[id]
                or (fish and fish.VisualColor) or { 255, 255, 255, 255 }
        end
    end
end

return Assets
