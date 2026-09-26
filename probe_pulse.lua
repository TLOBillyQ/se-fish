local w = game:GetService('World')
local m = w:FindFirstChild('FishermanModel')
if not m then
  print('PULSEPROBE no model')
  return
end
local n = 0
local conn
conn = game:GetService('RunService').Heartbeat:Connect(function()
  n = n + 1
  local ok, s = pcall(function() return m.Scale end)
  print(string.format('PULSEPROBE %d %s', n, tostring(ok and s or 'ERR')))
  if n >= 40 then conn:Disconnect() end
end)
