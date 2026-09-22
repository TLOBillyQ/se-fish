--技能系统 - server锚点预设壳：加速（speed_add）
-- 只声明编辑器可编辑的属性，不做挂接：
-- 运行时用 World:CreateAsset 实例化本预设时，壳脚本在 Parent 还是 World 的那一刻就跑了，
-- 此时 anchor_logic.Attach 会认错宿主（World），锚点永远不点火（见 issue #7 结论）。
-- 挂接改由根 AbilityAPI.AttachAnchor 在锚点 parent 到技能单位之后补做。
-- 编辑器侧的官方布局（把锚点预设放进技能预设里）不受此影响，但本图走的是运行时装配。

---@type number 开始时间
StartTime = 0.0
---开始时间

---@type number 持续时长
Duration = 0.0
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

---@type number 点火期间移速增量（可为负）
ABILITY_ANOSTATE_WALK_SPEED = 6.0
---移速增量
