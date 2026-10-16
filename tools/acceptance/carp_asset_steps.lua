-- 鲤鱼资产交付契约（features/art/carp_asset.feature）的步骤处理器。
--
-- 只读美术工作区里步骤 04 产出的重导入校验报告；报告定位与读取见 tools/art_report.lua。
-- 资产本体不进本仓，所以验收必须对着美术工作区的真实产物跑：
--   <宿主目录同级>/美术资产/鲤鱼/validation/validation.json
--
-- 本文件只覆盖接缝 B（导出链路自洽）；接缝 A（游戏内尺寸、外观、动画表现与碰撞体）是
-- 人工验收，条件写在 feature 文件头，执行步骤与结论见美术工作区的 NOTES.md。
local report = require('tools.art_report')

local CARP = '鲤鱼'
local MODEL = 'Model/Carp.fbx'
local ANIMATIONS = { 'Idle', 'Swim', 'SwimFast', 'TurnLeft', 'TurnRight', 'Jump', 'Land_Idle', 'Hit',
  'Death' }
local BASE_COLOR = 'Textures/Carp_BaseColor_1K.png'
local NORMAL = 'Textures/Carp_Normal_1K.png'
local ORM = 'Textures/Carp_ORM_1K.png'
local TEXTURES = { BASE_COLOR, NORMAL, ORM }

-- 尺度口径见 ADR-0004：导入资源全长约 0.015，游戏端缩放 100 → 1.5 个游戏单位
local GAME_SCALE = 100
local LENGTH_TOLERANCE = 0.0005
-- 8 位 PNG 会把常数通道量化到相邻两个字节值，标准差不会严格为 0
local CONSTANT_CHANNEL_STD = 0.01
-- ORM 的 B 是 metallic，只能是 0；量化后允许一个字节以内的残差
local METALLIC_EPSILON = 0.001

local function entry(world, relative)
  return report.entry(world, CARP, relative)
end

local function model(world)
  return entry(world, MODEL)
end

local function reference(world)
  local value = report.load(world, CARP).reference_tilapia
  assert(type(value) == 'table' and #(value.bones or {}) > 0,
    '校验报告没带罗非鱼基准（骨骼名由步骤 04 同场实导入量出）')
  return value
end

local function clip_entries(world)
  local found = {}
  for index, clip in ipairs(ANIMATIONS) do
    found[index] = { clip = clip, entry = entry(world, 'Animations/' .. clip .. '.fbx') }
  end
  return found
end

local function is_close(value, target, tolerance)
  return math.abs(value - target) <= tolerance
end

local function all_close(values, target, tolerance)
  for _, value in ipairs(values) do
    if not is_close(value, target, tolerance) then return false end
  end
  return true
end

return { patterns = {
  { '^鲤鱼的重导入校验报告已产出且没有失败项$', function(world)
      local failures = report.load(world, CARP).failures
      assert(type(failures) == 'table' and #failures == 0,
        '校验报告自带失败项：' .. table.concat(failures, '；'))
  end },

  -- 模型件：分件约定与预算
  { '^查看模型件 Model/Carp.fbx$', function(world)
      model(world)
  end },
  { '^网格数为 (%d+) 且骨架数为 (%d+)$', function(world, meshes, rigs)
      assert(model(world).mesh_count == tonumber(meshes),
        '网格数应为 ' .. meshes .. '，实际 ' .. tostring(model(world).mesh_count))
      assert(model(world).armature_count == tonumber(rigs),
        '骨架数应为 ' .. rigs .. '，实际 ' .. tostring(model(world).armature_count))
  end },
  { '^材质数为 (%d+)$', function(world, count)
      assert(#model(world).materials == tonumber(count),
        '材质数应为 ' .. count .. '，实际 ' .. tostring(#model(world).materials))
  end },
  { '^三角面数不超过 (%d+)$', function(world, budget)
      assert(model(world).triangles <= tonumber(budget),
        '三角面数 ' .. tostring(model(world).triangles) .. ' 超过预算 ' .. budget)
  end },
  { '^模型件不含动画片段$', function(world)
      assert(model(world).animation_clips == 0,
        '模型件内嵌了 ' .. tostring(model(world).animation_clips)
          .. ' 个动画片段，分件约定要求动画全在 Animations/ 下')
  end },

  -- 模型件：尺度口径（ADR-0004）
  { '^静止姿态全长约为 ([%d%.]+)$', function(world, target)
      local length = model(world).rest_dimensions[2]
      assert(is_close(length, tonumber(target), LENGTH_TOLERANCE),
        '静止姿态全长 ' .. tostring(length) .. ' 偏离 ' .. target)
  end },
  { '^游戏端缩放 (%d+) 后全长为 ([%d%.]+) 个游戏单位$', function(world, scale, target)
      assert(tonumber(scale) == GAME_SCALE, '游戏端缩放应为 ' .. GAME_SCALE)
      local game_length = model(world).rest_dimensions[2] * tonumber(scale)
      assert(is_close(game_length, tonumber(target), 0.05),
        '缩放 ' .. scale .. ' 后全长 ' .. tostring(game_length) .. ' 不是 ' .. target .. ' 个游戏单位')
  end },

  -- 模型件：骨架与网格节点与罗非鱼交付件同构
  { '^比对鲤鱼模型件与罗非鱼交付件的骨架$', function(world)
      model(world)
      reference(world)
  end },
  { '^骨骼名逐名一致$', function(world)
      assert.same(reference(world).bones, model(world).bones)
  end },
  { '^网格与骨架的节点缩放与罗非鱼交付件逐项一致$', function(world)
      local node_scale = model(world).node_scale
      local expected = reference(world).node_scale
      assert(type(expected) == 'table', '校验报告没带罗非鱼基准的节点缩放')
      assert(all_close(node_scale.mesh_local, 1.0, 1e-4),
        '网格节点带自身缩放 ' .. table.concat(node_scale.mesh_local, ', ')
          .. '，这一层不许另加补偿')
      assert(all_close(node_scale.mesh_world, node_scale.rig_world[1], 1e-4),
        '网格节点世界缩放 ' .. table.concat(node_scale.mesh_world, ', ')
          .. ' 与骨架 ' .. table.concat(node_scale.rig_world, ', ') .. ' 不一致')
      assert.same(expected, node_scale)
  end },

  -- 动画件：仅含骨架、骨骼同名、有实际动作、帧区间对齐
  { '^逐段查看 Animations 下的 (%d+) 个动画文件$', function(world, count)
      assert(tonumber(count) == #ANIMATIONS, '本试点交付 ' .. #ANIMATIONS .. ' 段动画')
      clip_entries(world)
  end },
  { '^每段都没有网格且只有一个骨架$', function(world)
      for _, clip in ipairs(clip_entries(world)) do
        assert(clip.entry.mesh_count == 0,
          clip.clip .. ' 带了 ' .. tostring(clip.entry.mesh_count) .. ' 个网格')
        assert(clip.entry.armature_count == 1,
          clip.clip .. ' 骨架数不是 1，实际 ' .. tostring(clip.entry.armature_count))
      end
  end },
  { '^每段恰好内嵌 (%d+) 个动画片段$', function(world, count)
      for _, clip in ipairs(clip_entries(world)) do
        assert(clip.entry.animation_clips == tonumber(count),
          clip.clip .. ' 内嵌 ' .. tostring(clip.entry.animation_clips) .. ' 个片段，应为 ' .. count)
      end
  end },
  { '^每段的骨骼名与罗非鱼一致$', function(world)
      for _, clip in ipairs(clip_entries(world)) do
        assert.same(reference(world).bones, clip.entry.bones)
      end
  end },
  { '^查看每段动画的尾鳍位移$', function(world)
      clip_entries(world)
  end },
  { '^每段位移都大于 (%d+)$', function(world, threshold)
      for _, clip in ipairs(clip_entries(world)) do
        assert(clip.entry.probe_tailfin_travel > tonumber(threshold),
          clip.clip .. ' 的尾鳍位移只有 ' .. tostring(clip.entry.probe_tailfin_travel) .. '，是空动画')
      end
  end },
  { '^逐段比对鲤鱼与罗非鱼的动画帧区间$', function(world)
      reference(world)
      clip_entries(world)
  end },
  { '^(%d+) 段的帧区间逐段相同$', function(world, count)
      assert(tonumber(count) == #ANIMATIONS, '本试点交付 ' .. #ANIMATIONS .. ' 段动画')
      local frames = reference(world).animation_frames
      for _, clip in ipairs(clip_entries(world)) do
        assert.same({ frames[clip.clip] }, clip.entry.animation_frames,
          clip.clip .. ' 的帧区间与罗非鱼不一致')
      end
  end },

  -- 蒙皮：模型网格 + 动画骨架，形变后不能跑出鱼的量级
  { '^把模型件网格挂到 Swim 与 Jump 的动画骨架上逐帧求包围盒$', function(world)
      local skinning = report.load(world, CARP).skinning
      assert(type(skinning) == 'table' and next(skinning) ~= nil, '校验报告没带蒙皮自检结果')
  end },
  { '^全长始终在 ([%d%.]+) 到 ([%d%.]+) 之间$', function(world, low, high)
      local low_bound, high_bound = tonumber(low), tonumber(high)
      for clip, value in pairs(report.load(world, CARP).skinning) do
        assert(value.length_min >= low_bound and value.length_max <= high_bound,
          clip .. ' 形变后全长跑到 ' .. tostring(value.length_min) .. '~'
            .. tostring(value.length_max) .. '，骨架与网格不匹配')
      end
  end },

  -- 交付贴图：1K、色彩空间语义与 ORM 通道语义
  { '^查看 Textures 下的三张交付贴图$', function(world)
      for _, relative in ipairs(TEXTURES) do
        entry(world, relative)
      end
  end },
  { '^三张都是 (%d+) 见方$', function(world, size)
      for _, relative in ipairs(TEXTURES) do
        assert.same({ tonumber(size), tonumber(size) }, entry(world, relative).size,
          relative .. ' 不是 ' .. size .. ' 见方')
      end
  end },
  { '^模型件内嵌的 BaseColor 是 sRGB、Normal 是 Non%-Color$', function(world)
      for _, texture in ipairs(model(world).textures) do
        local expected = texture.name == 'Carp_Normal_1K.png' and 'Non-Color' or 'sRGB'
        assert(texture.colorspace == expected,
          texture.name .. ' 的色彩空间是 ' .. tostring(texture.colorspace) .. '，应为 ' .. expected)
      end
  end },
  { '^ORM 的 G 通道是常数粗糙度、B 通道为 0$', function(world)
      local orm = entry(world, ORM)
      assert(orm.channel_std[2] <= CONSTANT_CHANNEL_STD,
        'ORM 的 G（roughness）标准差 ' .. tostring(orm.channel_std[2]) .. '，不是常数')
      assert(orm.channel_mean[3] <= METALLIC_EPSILON,
        'ORM 的 B（metallic）均值 ' .. tostring(orm.channel_mean[3]) .. '，不是 0')
      -- 兜底：整张常数说明烘出来的不是 AO 图，R=AO 这条约定实际没落地
      assert(orm.channel_std[1] > CONSTANT_CHANNEL_STD,
        'ORM 的 R（AO）标准差 ' .. tostring(orm.channel_std[1]) .. '，不像 AO 图')
  end },
} }
