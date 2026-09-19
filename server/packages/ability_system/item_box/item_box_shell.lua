--技能系统 - server道具箱表现数据壳
-- 道具箱表现 · 技能预设数据壳模板
-- 用法：把本文件内容贴入「需要道具箱表现」的技能预设 Script 子节点 SourceCode，
--       在编辑器属性面板按各技能需求填写下方字段（不填则用默认值兜底）。
-- 业务逻辑委派：ability_logic（通用状态机，必选）+ item_box_logic（道具箱表现，可选）。
-- 注意：@type 注解的显示名 key 必须与逻辑模块 DEF 表的字段名（HeadPrefab 等）一致。

-- 公开字段（编辑器可配置）
-- 字段名与逻辑模块 DEF 表一一对应。

---@type WorldUnitPrefab 道具箱模型路径
local HeadPrefab = nil
---道具箱模型路径

---@type Vector3 道具箱模型偏移
local HeadOffset = { 0.0, 2.0, 0.0 }
---道具箱模型偏移

---@type Vector3 道具箱模型旋转
local HeadRotation = { 0.0, 0.0, 0.0 }
---道具箱模型旋转

---@type Vector3 道具箱模型缩放系数
local HeadScale = { 1.0, 1.0, 1.0 }
---道具箱模型缩放系数

---@type EggyAnimationKey 释放动作
local PlaceAnimId = "official://animation/25205"
---释放动作

-- 业务逻辑（委派共享模块）
-- 状态机（必选）+ 道具箱表现增强（可选）。
-- 两个 Attach 内部均自带 IsServer() 判断与重复挂载保护。

local RunService = game:GetService("RunService")
if RunService:IsServer() then
	-- 状态机挂技能本体（script.Parent）；道具箱逻辑挂本子节点。
	-- ability_logic 有重复挂载保护，技能壳已挂过也不会重复。
	local ability = script.Parent
	if ability then
		require("server.packages.ability_system.ability_logic").Attach(ability)
	end
	require("server.packages.ability_system.item_box.item_box_logic").Attach(script)
end
