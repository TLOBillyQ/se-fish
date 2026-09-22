--技能系统 - server锚点预设壳：近战挥砍（melee_hit）
-- 只声明编辑器可编辑的属性，不做挂接（壳会在 Parent=World 时抢跑，理由同 speed_add 壳，见 issue #7）；
-- 挂接由根 AbilityAPI.AttachAnchor 在锚点 parent 到技能单位之后补做。
-- 已声明属性（StartTime/Duration/Phase/TrackIndex）改默认值不会下发到实例（issue #7 坑 2），
-- 关键值由 MgrAbility 按 GameCfg.Ability 配置在挂接前 SetAttribute 覆盖。

---@type number 开始时间
StartTime = 0.0
---开始时间

---@type number 持续时长（命中盒存活窗口；melee_hit 要求 > 0，实例值由配置覆盖）
Duration = 0.3
---持续时长

---@type Int
---@style enum
---@enum [[1, "Accumulate", "蓄力"],[2, "Cast", "施法"]]
---@title 生效阶段
Phase = 2
---所属阶段

---@type integer 轨道序号
TrackIndex = 0
---轨道序号

---@type Vector3 命中盒本地偏移（+Z=朝向, +X=右侧, +Y=上）
ABILITY_ANOSTATE_HITBOX_OFFSET = Vector3.New(0, 1, 2)
---命中盒偏移

---@type Vector3 命中盒缩放
ABILITY_ANOSTATE_HITBOX_SCALE = Vector3.New(3, 2, 3)
---命中盒缩放

---@type number 命中伤害
ABILITY_ANOSTATE_BULLET_DAMAGE = 25.0
---命中伤害

---@type number 击退力度（0=不击退）
ABILITY_ANOSTATE_HITPOWER = 0.0
---击退力度

---@type String 武器模型预设（空=不挂武器）
ABILITY_ANOSTATE_USE_PERFAB = ""
---武器模型预设

---@type String 挥击动画（空=不播动画）
ABILITY_ANOSTATE_ANIMKEY = ""
---挥击动画

---@type String 命中特效预设（空=不播）
ABILITY_ANOSTATE_HIT_SFX = ""
---命中特效预设

---@type boolean 命中盒朝向跟随施法者
ABILITY_ANOSTATE_FACE_SYNC = true
---朝向跟随
