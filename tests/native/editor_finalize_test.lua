-- 编辑器收尾的命令边界：用响应队列验证失败关闭，不启动真实编辑器。
local finalize = require("tools.editor_finalize")
local shell = require("tools.win_shell")

local function diff(local_count, differs, channel)
  return "channel=" .. (channel or "online") .. "\nchangelist: only-local="
    .. local_count .. " differs=" .. differs .. " only-on-map=2 unchanged=3"
end

describe("TestEditorFinalize", function()
  local saved, responses, commands, messages
  before_each(function()
    saved = { capture = shell.capture, exists = shell.exists, getenv = os.getenv, print = print }
    responses, commands, messages = {}, {}, {}
    shell.exists = function() return true end
    os.getenv = function(name)
      if name == "USERPROFILE" then return "C:/fixture" end
      return saved.getenv(name)
    end
    shell.capture = function(command)
      commands[#commands + 1] = command
      local response = table.remove(responses, 1)
      assert.is_not_nil(response, "出现未预期的编辑器命令")
      return response[1], response[2]
    end
    _G.print = function(message) messages[#messages + 1] = message end
  end)
  after_each(function()
    shell.capture, shell.exists, os.getenv, _G.print = saved.capture, saved.exists, saved.getenv, saved.print
  end)

  local function ready_for_push(last_code, last_output)
    responses = { { 0, "validate: OK" }, { 0, diff(1, 1) }, { 0, "push: OK" },
      { last_code, last_output } }
  end

  it("test_unchanged_does_not_push_and_keeps_map_only_files", function()
    responses = { { 0, "validate: OK" }, { 0, diff(0, 0) } }
    assert.is_true(finalize.run("C:/workspace"))
    assert.are.equal(2, #commands)
    assert.is_truthy(messages[#messages]:find("地图侧多出 2", 1, true))
  end)

  it("test_push_is_followed_by_online_verification", function()
    ready_for_push(0, diff(0, 0))
    assert.is_true(finalize.run("C:/workspace"))
    assert.are.equal(4, #commands)
    assert.is_truthy(commands[3]:find("code push", 1, true))
    assert.is_truthy(commands[4]:find("code diff", 1, true))
    for _, command in ipairs(commands) do
      assert.is_truthy(command:find("--workspace", 1, true))
    end
  end)

  it("test_push_failure_stops_verification", function()
    responses = { { 0, "validate: OK" }, { 0, diff(1, 0) }, { 1, "push rejected" } }
    local ok, err = finalize.run("C:/workspace")
    assert.is_nil(ok)
    assert.is_truthy(err:find("code push 失败", 1, true))
    assert.are.equal(3, #commands)
  end)

  for _, case in ipairs({
    { "offline", 0, diff(0, 0, "offline"), "离线" },
    { "failed", 1, diff(0, 0), "复核失败" },
    { "missing_changelist", 0, "editor disconnected", "读不到 changelist" },
    { "remaining_changes", 0, diff(1, 0), "仍有 1" },
  }) do
    it("test_verification_rejects_" .. case[1], function()
      ready_for_push(case[2], case[3])
      local ok, err = finalize.run("C:/workspace")
      assert.is_nil(ok)
      assert.is_truthy(err:find(case[4], 1, true))
      for _, message in ipairs(messages) do
        assert.is_nil(message:find("编辑器: 已同步", 1, true))
      end
    end)
  end

  it("test_initial_offline_diff_skips_push_without_claiming_sync", function()
    responses = { { 0, "validate: OK" }, { 0, diff(1, 0, "offline") } }
    assert.is_true(finalize.run("C:/workspace"))
    assert.are.equal(2, #commands)
    assert.is_truthy(messages[#messages]:find("未校验编辑器内代码", 1, true))
  end)
end)
