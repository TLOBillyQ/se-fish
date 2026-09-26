local REUtil = require('common.REUtil')
REUtil:GetRE('InteractAction'):FireServer({ target = 'fisherman', action = 'Feed', seq = 1 })
print('FEEDPROBE feed fired')
