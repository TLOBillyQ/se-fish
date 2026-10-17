-- 网格封闭性验收（#112）的通用步骤处理器，对应 features/art/mesh_topology.feature。
--
-- 只读美术工作区里步骤 04 产出的 validation.json 的 mesh 段，并重新读盘算一次生效预算：
-- 报告的 metrics 是 04-validate 的审计结果；阈值只来自默认 mesh-budget.json 加单鱼豁免，
-- 这里不写任何数字，也不拿报告自带的 budget 自证（改预算没重跑会暴露成报告过期）。
-- 与美术工作区 scripts/04-validate.py 的 mesh_failures() 判定同一套规则。
local report = require('tools.art_report')
local budget = require('tools.art_budget')

local HARD_ZERO = {
  { key = 'non_manifold_edges', label = '非流形边（>2 面）' },
  { key = 'inconsistent_winding_edges', label = '绕向不一致的边' },
  { key = 'loose_vertices', label = '游离顶点' },
}

return { patterns = {
  { '^读取 (.+) 的网格审计段并取美术资产根目录的网格预算$', function(world, fish)
      local document = report.load(world, fish)
      assert(type(document.failures) == 'table', fish .. ' 的校验报告缺少 failures 列表')
      local mesh = document.mesh
      assert(type(mesh) == 'table',
        fish .. ' 的校验报告没有 mesh 段（旧报告或步骤 04 未跑网格审计），按不合格处理')
      assert(type(mesh.metrics) == 'table', fish .. ' 的 mesh 段缺少 metrics')
      assert(type(mesh.budget) == 'table', fish .. ' 的 mesh 段缺少生效预算 budget')
      world.art_mesh = { fish = fish, mesh = mesh }
  end },

  { '^报告中的生效预算与磁盘上的默认预算和单鱼豁免一致$', function(world)
      local state = assert(world.art_mesh, '先读取网格审计段')
      local effective = budget.effective(state.fish)
      local problems = {}
      for _, problem in ipairs(effective.problems) do problems[#problems + 1] = problem end
      local recorded = budget.limits_only(state.mesh.budget)
      for _, key in ipairs({ 'max_components', 'max_open_edge_ratio', 'max_boundary_loop_edges' }) do
        if recorded[key] ~= effective.limits[key] then
          problems[#problems + 1] = '报告里的 ' .. key .. ' 是 ' .. tostring(recorded[key])
            .. '，磁盘预算是 ' .. tostring(effective.limits[key]) .. '（报告已过期，重跑步骤 04）'
        end
      end
      assert(#problems == 0, table.concat(problems, '；'))
  end },

  { '^硬性为 0 的封闭性指标全部为 0$', function(world)
      local state = assert(world.art_mesh, '先读取网格审计段')
      local metrics = state.mesh.metrics
      local violations = {}
      for _, item in ipairs(HARD_ZERO) do
        local value = metrics[item.key]
        if type(value) ~= 'number' then
          violations[#violations + 1] = item.label .. ' 没有记录'
        elseif value ~= 0 then
          violations[#violations + 1] = item.label .. ' ' .. tostring(value) .. ' 条'
        end
      end
      assert(#violations == 0, state.fish .. ' 不封闭：' .. table.concat(violations, '、'))
  end },

  { '^连通块数、开放边占比与最大边界环都不超过生效预算$', function(world)
      local state = assert(world.art_mesh, '先读取网格审计段')
      local mesh = state.mesh
      local metrics = mesh.metrics
      local limits = mesh.budget
      local violations = {}
      local function compare(label, actual, limit, render)
        if limit == nil then return end
        render = render or tostring
        if type(actual) ~= 'number' then
          violations[#violations + 1] = label .. ' 没有记录'
        elseif actual > limit then
          violations[#violations + 1] = label .. ' ' .. render(actual) .. ' 超过上限 ' .. render(limit)
        end
      end

      -- 占比不信任报告里四舍五入过的值，用边数重算
      local open_ratio
      if type(metrics.open_edges) == 'number' and type(metrics.edges) == 'number' and metrics.edges > 0 then
        open_ratio = metrics.open_edges / metrics.edges
      end
      compare('连通块数', metrics.components, limits.max_components)
      compare('开放边占比', open_ratio, limits.max_open_edge_ratio,
        function(value) return string.format('%.2f%%', value * 100) end)
      compare('最大边界环（边）', metrics.max_boundary_loop_edges, limits.max_boundary_loop_edges)
      assert(#violations == 0, state.fish .. ' 网格预算不合格：' .. table.concat(violations, '、'))
  end },

  { '^报告如实记录生效预算并给出豁免理由$', function(world)
      local state = assert(world.art_mesh, '先读取网格审计段')
      local effective = budget.effective(state.fish)
      local override = state.mesh.override
      if effective.override then
        assert(type(override) == 'table',
          state.fish .. ' 有单鱼豁免文件，但报告没记下豁免（报告已过期，重跑步骤 04）')
        assert(type(override.reason) == 'string' and not override.reason:match('^%s*$'),
          state.fish .. ' 的单鱼豁免没有理由')
        for key, value in pairs(effective.override.limits) do
          assert(override.limits and override.limits[key] == value,
            state.fish .. ' 报告里的豁免项 ' .. key .. ' 与磁盘不一致')
        end
      else
        assert(override == nil, state.fish .. ' 报告记了豁免，但磁盘上已没有豁免文件')
      end
  end },
} }
