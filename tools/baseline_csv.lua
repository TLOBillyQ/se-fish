-- #65 P2/P3 现场基线 → CSV 转换器（离线）。
--
-- P2 的基线 CSV 当初是手工从 `log grep P2BASE65V2 --json` 的结果转出来的；这一轮施工后要再转一次，
-- 所以把口径固化成工具，避免每次靠临时脚本、也避免列序或四舍五入漂移。
--
-- 用法：
--   lua tools/baseline_csv.lua --log <grep.json> --out <rows.csv>
-- 输入是 editor-cli `log grep <MARK> --json` 的输出；只取 `N|...` 行（逐单位回读），忽略
-- `ZONE| / ROOTS| / ROOT| / ROOTNAME| / SUMMARY|` 这类汇总行。列序与 P2 的 zone-baseline-rows.csv 一致。
local M = {}

M.MARK = 'P2BASE65V2'
M.HEADER = 'zone,depth,path,name,type,spatial,pos,rot,scale,size,canCollide,canQuery,physicsActive,bodyType,assetId'
M.FIELDS = { 'zone', 'depth', 'path', 'name', 'type', 'spatial', 'pos', 'rot', 'scale', 'size',
    'canCollide', 'canQuery', 'physicsActive', 'bodyType', 'assetId' }

--- 从一行日志文本里剥出 MARK| 之后、结尾引号之前的载荷。
function M.payload(text, mark)
    mark = mark or M.MARK
    local at = text:find(mark .. '|', 1, true)
    if not at then return nil end
    local body = text:sub(at + #mark + 1)
    body = body:gsub('"$', '')
    return body
end

--- 一行 `N|` 载荷 → CSV 字段。
--- 载荷形状：`N|区|深度|路径|类型|key=value...`（**没有单独的 name 段**，名字取路径最后一段 ——
--- P2 那份 CSV 的 name 列就是这么来的）；键用探针的短名（cc/cq/pa/bt/asset），这里映到 CSV 列名。
function M.parseNodeRow(payload)
    local parts = {}
    for part in (payload .. '|'):gmatch('([^|]*)|') do parts[#parts + 1] = part end
    if parts[1] ~= 'N' then return nil end
    local path = parts[4] or ''
    local row = { zone = parts[2], depth = parts[3], path = path, type = parts[5],
        name = path:match('([^/]+)$') }
    local alias = { cc = 'canCollide', cq = 'canQuery', pa = 'physicsActive', bt = 'bodyType', asset = 'assetId' }
    for index = 6, #parts do
        local key, value = parts[index]:match('^([%w]+)=(.*)$')
        if key then row[alias[key] or key] = value end
    end
    return row
end

local function csvField(value)
    value = value or ''
    if value:find('[,"]') then
        return '"' .. value:gsub('"', '""') .. '"'
    end
    return value
end

--- 渲染 CSV 文本（行序 = 日志里的顺序，保证可 diff）。
function M.render(rows)
    local out = { M.HEADER }
    for _, row in ipairs(rows) do
        local fields = {}
        for _, key in ipairs(M.FIELDS) do fields[#fields + 1] = csvField(row[key]) end
        out[#out + 1] = table.concat(fields, ',')
    end
    return table.concat(out, '\n') .. '\n'
end

--- 从日志 JSON 文本里收集所有 `N|` 行（保持出现顺序）。
--- 不按 JSON 结构解析：日志里的 text 字段本身把引号转义了（`\"`），按 JSON 字符串切会切在半路；
--- 直接在原文里锚 MARK，取到下一个引号/反斜杠/换行为止 —— 基线载荷里不含这些字符。
function M.collect(logJson, mark)
    mark = mark or M.MARK
    local rows = {}
    for payload in tostring(logJson):gmatch(mark .. '|([^"\\\r\n]+)') do
        local row = M.parseNodeRow(payload)
        if row then rows[#rows + 1] = row end
    end
    return rows
end

local function readFile(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local text = file:read('*a')
    file:close()
    return text
end

local function main(argv)
    local logPath, outPath
    for index = 1, #(argv or {}) do
        if argv[index] == '--log' then logPath = argv[index + 1] end
        if argv[index] == '--out' then outPath = argv[index + 1] end
    end
    if not logPath or not outPath then
        print('用法: lua tools/baseline_csv.lua --log <grep.json> --out <rows.csv>')
        os.exit(2)
    end
    local text = readFile(logPath)
    if not text then
        print('读不到日志 JSON：' .. logPath)
        os.exit(1)
    end
    local rows = M.collect(text)
    if #rows == 0 then
        print('日志里没有 ' .. M.MARK .. ' 的 N| 行：' .. logPath)
        os.exit(1)
    end
    local file = assert(io.open(outPath, 'wb'))
    file:write(M.render(rows))
    file:close()
    print(('已写出 %d 行基线 → %s'):format(#rows, outPath))
end

if arg and arg[0] and arg[0]:find('baseline_csv', 1, true) then
    main(arg)
end

return M
