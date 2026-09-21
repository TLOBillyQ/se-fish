-- 纯模块单测：部署计划（哪些子树归本仓库、仓库路径与宿主目录路径怎么配对）与宿主目录
-- 定位。两条都不碰文件系统、不起子进程。真实文件系统的镜像行为由
-- tests/deploy_transport_test.lua 从 CLI 那一侧覆盖。
local lu = require("luaunit")
local plan = require("tools.deploy_plan")
local workspace = require("tools.eggy_workspace")

TestDeployPlan = {}

local function listing(byrealm)
  return function(realm) return byrealm[realm] or {} end
end

function TestDeployPlan:test_realms_are_the_official_workspace_roots()
  lu.assertEquals(plan.REALMS, { "client", "common", "server" })
end

function TestDeployPlan:test_targets_pair_repo_path_with_same_workspace_path()
  local targets = plan.targets("/ws", listing({
    server = { { name = "Mgr", dir = true }, { name = "main.lua", dir = false } },
  }), { "server" })
  lu.assertEquals(#targets, 2)
  lu.assertEquals(targets[1], { rel = "server/Mgr", dir = true,
    src = "server/Mgr", dst = "/ws/server/Mgr" })
  lu.assertEquals(targets[2], { rel = "server/main.lua", dir = false,
    src = "server/main.lua", dst = "/ws/server/main.lua" })
end

function TestDeployPlan:test_targets_follow_realm_order_then_listing_order()
  local targets = plan.targets("/ws", listing({
    client = { { name = "main.lua", dir = false } },
    common = { { name = "Util.lua", dir = false } },
    server = { { name = "_trigger", dir = true } },
  }))
  local rels = {}
  for _, t in ipairs(targets) do rels[#rels + 1] = t.rel end
  lu.assertEquals(rels, { "client/main.lua", "common/Util.lua", "server/_trigger" })
end

function TestDeployPlan:test_targets_of_empty_realm_contribute_nothing()
  lu.assertEquals(plan.targets("/ws", listing({}), { "server" }), {})
end

-- 白名单就是全部：仓库根的 docs/、tools/、tests/ 连问都不问。
function TestDeployPlan:test_only_whitelisted_realms_are_listed()
  local asked = {}
  plan.targets("/ws", function(realm) asked[#asked + 1] = realm return {} end)
  lu.assertEquals(asked, { "client", "common", "server" })
end

TestWorkspace = {}

-- 默认宿主目录写死钓鱼图，改错就等于镜像到别人的地图里。
function TestWorkspace:test_default_is_the_fishing_map_host_directory()
  lu.assertStrContains(workspace.DEFAULT, "LuaSource_钓鱼怎么这么危险啊喂！")
end
