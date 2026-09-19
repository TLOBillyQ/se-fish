--技能系统 - server锚点预设壳
-- 锚点实例服务端脚本（ScriptUnit，挂在技能实例 ScriptUnit 之下）
-- 数据化预设壳：仅保留编辑器可编辑的 @type 配置属性声明
--（与作者图 editor.lua 的 @attr、编辑器侧 ChildNodeAnchorSource 静态 schema 三方同键同型），
-- 运行时行为统一委派给 anchor_logic.lua 的 Attach(script)（自注册：向宿主能力订阅施法生命周期）。
-- 运行时状态（_isRunning 等）不在此声明，由 common/.../Anchor.lua 调度器内部维护。

---@type number 开始时间
StartTime = 0.0
---开始时间

---@type number 持续时长
Duration = 0.0
---持续时长

---@type Int
---@style enum
---@enum [[1, "Accumulate", "蓄力"],[2, "Cast", "施法"]]
---@title 施法阶段
Phase = 2
---所属阶段

---@type integer 轨道序号
TrackIndex = 0
---轨道序号

-- 业务逻辑（委派共享模块）
-- 自注册模型：Attach 内部读取自身属性（Phase/StartTime/Duration），找宿主能力（script.Parent），
-- 按 Phase 订阅宿主对应窗口事件（Phase=1 蓄力: AccumulateStart/AccumulateBreak/AccumulateEnd；
-- Phase=2 施法: CastStart/CastEnd/CastBreak），按 StartTime/Duration 排程并点火
-- AnchorStart/AnchorBreak/AnchorEnd/AnchorStop（载荷 abilityScript, groupId）。
-- 同时在本锚点子单位下创建锚点级四事件单位（AnchorStart/Break/End/Stop）：
-- 主体即锚点自身，监听方无需 groupId 过滤，载荷 = (abilityScript)。
-- Attach 内部自带 IsServer() 判断与重复挂载保护。

local RunService = game:GetService("RunService")
if RunService:IsServer() then
	require("server.packages.ability_system.anchor_logic").Attach(script)
end
