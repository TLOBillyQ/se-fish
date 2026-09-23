package.path = "./?.lua;" .. package.path
local ok, err = require("tools.acceptance.bootstrap").ensure(arg[1])
if not ok then io.stderr:write(err .. "\n") os.exit(1) end
