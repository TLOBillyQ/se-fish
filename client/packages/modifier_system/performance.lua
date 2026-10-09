--效果系统包 - 客户端表现播放
--播放获得/失去表现中的特效与音效；皮肤材质替换由客户端管理器负责。

local World = game:GetService("World")

local config = require("common.packages.modifier_system.config")

local performance = {}

---播放单个特效（创建即绑定 owner 挂点）
---仅"跟随效果销毁"的特效返回单位；循环特效必须纳入跟随列表，避免失去引用后持续播放
---@param performanceConfig table 表现配置
---@param owner Unit 拥有者单位
---@return Unit? 跟随销毁的特效单位
local function playEffect(performanceConfig, owner)
	local effectId = performanceConfig.EffectID
	if not effectId or effectId == "" or effectId == "-1" then
		return nil
	end
	-- 绑定数据随初始 values 直达：特效首帧即位于挂点，避免先建后绑的瞬移（连线类特效会拉伸）
	local effectUnit = World:CreateUnit("EffectUnit", {
		EffectId = effectId,
		EffectBindData = {
			BindUnitId = owner.UnitId,
			BindSocket = performanceConfig.EffectAttachPoint or "socket_origin",
			BindOffset = Vector3.New(0, 0, 0),
			BindType = tonumber(performanceConfig.EffectInherit) or 7,
		},
	})
	if not effectUnit then
		return nil
	end
	local scale = tonumber(performanceConfig.EffectScale) or 1.0
	if scale ~= 1.0 then
		effectUnit:SetScale(Vector3.New(scale, scale, scale))
	end
	local frameRate = tonumber(performanceConfig.EffectFrameRate) or 1.0
	if frameRate ~= 1.0 then
		effectUnit:SetRate(frameRate)
	end
	-- DestroyWithModifier 缺省 true（属性面板只物化作者改动的字段，nil 须按 true 处理），避免失去引用永续播放
	local destroyWithModifier = performanceConfig.DestroyWithModifier ~= false
	-- IsLoop=true → ForceLoop=true 持续循环直至跟随销毁；false → 按资源自带方式播放（循环资源仍会循环）
	if performanceConfig.IsLoop == true then
		effectUnit.ForceLoop = true
		return effectUnit
	end
	effectUnit.ForceLoop = false
	if destroyWithModifier then
		return effectUnit
	end
	return nil
end

---播放单个音效；仅"跟随效果销毁"的音效返回单位
---SoundID 支持资源路径或数字 ID，空值/-1 视为未配置
---@param performanceConfig table 表现配置
---@param owner Unit 拥有者单位
---@return Unit? 跟随销毁的音效单位
local function playSound(performanceConfig, owner)
	local soundId = performanceConfig.SoundID
	if not soundId or soundId == "" or soundId == "-1" or soundId == -1 then
		return nil
	end
	local soundType = "3D"
	if (tonumber(performanceConfig.SoundType) or 1) == 0 then
		soundType = "2D"
	end
	local duration = tonumber(performanceConfig.SoundDuration) or -1
	local values = {
		SoundId = soundId,
		SoundType = soundType,
		Duration = duration,
		needInit = true,
	}
	if duration > 0 then
		-- 指定时长：循环播放至时长上限；未指定：播完资源即停
		values.Looped = true
	end
	if soundType == "3D" then
		values.Position = owner.Position or Vector3.New(0, 0, 0)
		values.FadeDistance = tonumber(performanceConfig.SoundDistance) or 10
	end
	local soundUnit = World:CreateUnit("SoundUnit", values)
	if not soundUnit then
		return nil
	end
	-- DestroyWithModifier 缺省 true
	if performanceConfig.DestroyWithModifier ~= false then
		return soundUnit
	end
	return nil
end

---播放表现列表
---@param performanceList table 表现配置列表（预设的获得/失去表现字段）
---@param owner Unit 拥有者单位，作为特效挂点/音效位置
---@return table { effects = Unit[], sounds = Unit[] }，仅含需跟随效果销毁的单位
function performance.play(performanceList, owner)
	local result = { effects = {}, sounds = {} }
	if not performanceList or not owner then
		return result
	end
	for _, performanceConfig in ipairs(performanceList) do
		local performanceType = tonumber(performanceConfig.PerformanceType) or -1
		if performanceType == config.PerformanceType.Effect then
			local effectUnit = playEffect(performanceConfig, owner)
			if effectUnit then
				table.insert(result.effects, effectUnit)
			end
		elseif performanceType == config.PerformanceType.Sound then
			local soundUnit = playSound(performanceConfig, owner)
			if soundUnit then
				table.insert(result.sounds, soundUnit)
			end
		end
	end
	return result
end

return performance
