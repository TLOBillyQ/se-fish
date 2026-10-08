--生物AI包 - 配置常量
--行为默认参数、反应行为编号与阵营关系取值；包内外只读，不做修改。

local Configs = {}

-- 反应行为编号：与蛋码 AIBasicCommand 枚举取值一致（2=跳跃 3=滚动 4=飞扑 5=抓举 6=施放技能）
Configs.CMD_JUMP = 2
Configs.CMD_FLING = 3
Configs.CMD_RUSH = 4
Configs.CMD_LIFT = 5
Configs.CMD_ABILITY = 6

-- 阵营关系：World:GetUnitRelationShip 的返回值（0=未知 1=敌人 2=友军）
Configs.CAMP_UNKNOWN = 0
Configs.CAMP_ENEMY = 1
Configs.CAMP_FRIEND = 2

-- 固定技能槽位：战技与道具共用技能包的槽位号
Configs.CAREER_SKILL_SLOT = 4
Configs.ITEM_SKILL_SLOT = 5

-- 行为默认参数
Configs.DEFAULT_SEARCH_RADIUS = 10
Configs.DEFAULT_REACTION_DISTANCE = 5
Configs.DEFAULT_MOVE_TOLERANCE = 1.5
Configs.DEFAULT_STOP_DISTANCE = 1.0
Configs.DEFAULT_ALERT_DELAY = 1.0
Configs.DEFAULT_ALERT_TOLERANCE = 2.0
Configs.DEFAULT_ALERT_ROTATE_DISTANCE = 0.5
Configs.DEFAULT_NAV_THRESHOLD = 2.0
Configs.DEFAULT_ACTION_COUNT = 10

-- 行为循环节拍（秒）
Configs.MOVE_TICK = 0.1
Configs.REACT_TICK = 0.5
Configs.REACT_COOLDOWN = 0.5
Configs.COLLISION_JUMP_COOLDOWN = 0.5
Configs.IMITATE_ACTION_DELAY = 0.5
Configs.IMITATE_SAMPLE_TICK = 0.5
Configs.IMITATE_MOVE_TICK = 0.05
Configs.IMITATE_MOVE_SPEED = 7.0
Configs.IMITATE_IDLE_TICK = 1.0

return Configs
