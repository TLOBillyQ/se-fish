-- 部署计划护栏：三端 packages 与业务子树同属清单，镜像和 --clean 消费相同目标。
-- 所有目录枚举与传输均用夹具替代，不碰真实宿主目录、不启动编辑器。
local plan = require("tools.deploy_plan")

local WORKSPACE = "fixture-host"
local ENTRIES = {
  client = { { name = "UI", dir = true }, { name = "packages", dir = true } },
  common = { { name = "GameCfg.lua", dir = false }, { name = "packages", dir = true } },
  server = { { name = "Mgr", dir = true }, { name = "packages", dir = true } },
}
local EXPECTED = {
  { rel = "client/UI", dir = true, src = "client/UI", dst = WORKSPACE .. "/client/UI" },
  { rel = "client/packages", dir = true, src = "client/packages", dst = WORKSPACE .. "/client/packages" },
  { rel = "common/GameCfg.lua", dir = false, src = "common/GameCfg.lua", dst = WORKSPACE .. "/common/GameCfg.lua" },
  { rel = "common/packages", dir = true, src = "common/packages", dst = WORKSPACE .. "/common/packages" },
  { rel = "server/Mgr", dir = true, src = "server/Mgr", dst = WORKSPACE .. "/server/Mgr" },
  { rel = "server/packages", dir = true, src = "server/packages", dst = WORKSPACE .. "/server/packages" },
}

local function list_entries(realm)
  return assert(ENTRIES[realm], "不应枚举部署白名单之外的目录: " .. realm)
end

describe("TestDeployPlan", function()
  it("test_targets_include_packages_and_business_entries_in_all_realms", function()
    assert.same(EXPECTED, plan.targets(WORKSPACE, list_entries))
  end)

  it("test_custom_realms_limit_the_target_list", function()
    assert.same({ EXPECTED[5], EXPECTED[6] }, plan.targets(WORKSPACE, list_entries, { "server" }))
  end)
end)

describe("TestDeployOwnedTargets", function()
  local saved, deployed, removed, finalized, deploy
  local MODULES = { "tools.deploy", "tools.eggy_workspace", "tools.win_shell", "tools.editor_finalize" }

  before_each(function()
    saved = { path = package.path, modules = {} }
    for _, name in ipairs(MODULES) do saved.modules[name] = package.loaded[name] end
    deployed, removed, finalized = {}, {}, 0
    package.loaded["tools.deploy"] = nil
    package.loaded["tools.eggy_workspace"] = { resolve = function() return WORKSPACE end }
    package.loaded["tools.win_shell"] = {
      is_dir = function() return true end,
      exists = function() return true end,
      list_entries = list_entries,
      list_files = function() return {} end,
      mirror = function(target)
        deployed[#deployed + 1] = target
        return true, 0
      end,
      remove = function(target) removed[#removed + 1] = target end,
    }
    package.loaded["tools.editor_finalize"] = {
      run = function(ws)
        assert.are.equal(WORKSPACE, ws)
        finalized = finalized + 1
        return true
      end,
    }
    deploy = require("tools.deploy")
  end)

  after_each(function()
    for _, name in ipairs(MODULES) do package.loaded[name] = saved.modules[name] end
    package.path = saved.path
    saved, deploy = nil, nil
  end)

  it("test_mirror_and_clean_consume_the_same_owned_targets", function()
    assert.are.equal(0, deploy.main({}))
    assert.same(EXPECTED, deployed)
    assert.same({}, removed)
    assert.are.equal(1, finalized)

    assert.are.equal(0, deploy.main({ "--clean" }))
    assert.same(EXPECTED, removed)
    assert.same(deployed, removed)
    assert.are.equal(1, finalized, "--clean 不应进入编辑器收尾")
  end)
end)
