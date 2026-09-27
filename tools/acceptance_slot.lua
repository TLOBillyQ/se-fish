-- #93 验收槽配置：离线修改 GameCfg.Save.AcceptanceSlot，部署后新局生效。
-- 只改源码配置，不接入游戏内 GM 通道；正在试玩时不要修改或部署。
local M = {}
local CONFIG = 'common/GameCfg.lua'
local TEMP = 'common/GameCfg.lua.acceptance-slot.tmp'

function M.usage()
  return table.concat({
    '用法: lua tools/cli.lua acceptance-slot <status|new|set|off> [槽名]',
    '  status       查看当前槽；空槽表示正式存档',
    '  new          生成一个新的验收槽名并写入配置',
    '  set <槽名>   指定验收槽；复用槽名会恢复该槽上次进度',
    '  off          恢复正式存档配置（不删除任何存档）',
    '槽名只能包含 1—40 位字母、数字、下划线或连字符。',
    '请在试玩前运行，再执行 lua tools/cli.lua deploy；同槽重进不要运行 new。',
  }, '\n') .. '\n'
end

function M.valid_slot(slot)
  return type(slot) == 'string' and #slot > 0 and #slot <= 40
    and slot:match('^[%w_-]+$') ~= nil
end

-- 仅识别 GameCfg.Save 表内的非注释赋值行；格式不符时拒绝写入。
local function locate(text)
  local start = text:find('\nGameCfg.Save%s*=%s*{')
  if not start and text:match('^GameCfg.Save%s*=%s*{') then start = 0 end
  if not start then return nil, '找不到 GameCfg.Save 配置' end
  local finish = text:find('\n}', start + 1, true)
  if not finish then return nil, 'GameCfg.Save 配置不完整' end
  local section = text:sub(start + 1, finish - 1)
  local count, current, valid, updated = 0, nil, false, {}
  for line in (section .. '\n'):gmatch('([^\n]*)\n') do
    if line:match('^%s*AcceptanceSlot%s*=') then
      count = count + 1
      local prefix, value, suffix = line:match("^(%s*AcceptanceSlot%s*=%s*)'([^'\r\n]*)'(.*)$")
      if prefix and (suffix:match('^%s*,?%s*$') or suffix:match('^%s*,?%s*%-%-')) then
        current, valid = value, true
        updated[#updated + 1] = { prefix = prefix, suffix = suffix }
      end
    end
  end
  if count ~= 1 or not valid then return nil, 'AcceptanceSlot 必须是唯一的单引号字符串配置' end
  return { start = start, finish = finish, current = current, line = updated[1] }
end

function M.replace_slot(text, slot)
  local info, err = locate(text)
  if not info then return nil, err end
  local section = text:sub(info.start + 1, info.finish - 1)
  local rewritten = section:gsub('([^\n]*)(\n?)', function(line, newline)
    if line:match('^%s*AcceptanceSlot%s*=') then
      return info.line.prefix .. "'" .. slot .. "'" .. info.line.suffix .. newline
    end
    return line .. newline
  end)
  return text:sub(1, info.start) .. rewritten .. text:sub(info.finish)
end

function M.current_slot(text)
  local info, err = locate(text)
  if not info then return nil, err end
  if info.current ~= '' and not M.valid_slot(info.current) then return nil, '当前验收槽名无效' end
  return info.current
end

local function read_config()
  local file, err = io.open(CONFIG, 'rb')
  if not file then return nil, err end
  local text = file:read('*a')
  file:close()
  return text
end

local function write_config(text)
  local existing = io.open(TEMP, 'rb')
  if existing then existing:close(); return nil, '临时文件已存在，请先检查 ' .. TEMP end
  local file, err = io.open(TEMP, 'wb')
  if not file then return nil, err end
  local ok, write_err = file:write(text)
  local closed, close_err = file:close()
  if not ok or not closed then
    os.remove(TEMP)
    return nil, write_err or close_err
  end
  -- 同目录写完再原子替换：失败时原 GameCfg 保持完整。命令及路径均为静态常量。
  local success = os.execute('pwsh -NoProfile -NonInteractive -Command "[System.IO.File]::Move(\'common/GameCfg.lua.acceptance-slot.tmp\',\'common/GameCfg.lua\',$true)"')
  if not success then
    os.remove(TEMP)
    return nil, '配置替换失败，原配置保持不变'
  end
  return true
end

function M.main(args)
  args = args or {}
  local action = args[1]
  if action == '--help' or action == '-h' then io.write(M.usage()); return 0 end
  if (action ~= 'status' and action ~= 'new' and action ~= 'set' and action ~= 'off')
    or (action == 'set' and (#args ~= 2 or not M.valid_slot(args[2])))
    or (action ~= 'set' and #args ~= 1) then
    io.stderr:write(M.usage())
    return 2
  end
  local text, err = read_config()
  if not text then io.stderr:write('acceptance-slot: ' .. tostring(err) .. '\n'); return 1 end
  local current
  current, err = M.current_slot(text)
  if current == nil and (action == 'status' or action == 'new') then
    io.stderr:write('acceptance-slot: ' .. err .. '\n')
    return 1
  end
  if action == 'status' then
    print(current == '' and '当前使用正式存档' or '当前验收槽：' .. current)
    return 0
  end
  local slot = ''
  if action == 'set' then slot = args[2] end
  if action == 'new' then
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))
    slot = os.date('!qa93-%Y%m%d-%H%M%S-') .. string.format('%06d', math.random(0, 999999))
    if slot == current then io.stderr:write('acceptance-slot: 新槽与当前槽重名，请重试\n'); return 1 end
  end
  local updated
  updated, err = M.replace_slot(text, slot)
  if not updated then io.stderr:write('acceptance-slot: ' .. err .. '\n'); return 1 end
  if updated ~= text then
    local ok
    ok, err = write_config(updated)
    if not ok then io.stderr:write('acceptance-slot: ' .. tostring(err) .. '\n'); return 1 end
  end
  print(slot == '' and '已切回正式存档配置' or '已设置验收槽：' .. slot)
  print('试玩前执行 lua tools/cli.lua deploy；同槽重进时不要更换槽名。')
  return 0
end

return M
