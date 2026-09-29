-- #149 T28 全服纪录的纯逻辑（无 I/O，服务端与测试共用）：
--   整数化、合法性、决胜规则、读回校验与展示文案。
-- 存储口径：重量按两位小数放大成整数（GameCfg.Records.Scale），
-- 保持者身份与重量写在**同一条记录**里（{ w, u, n } 三元组），
-- 读出时要么两者都在、要么整条不算纪录——从结构上排除「重量更新了、名字还是旧的」。
local GameCfg = require('common.GameCfg')

local Records = {}

local function cfg() return GameCfg.Records end

-- 重量 → 放大整数。非法（非有限数/非正/超上限）返回 nil 与原因，绝不四舍五入成假值。
-- 上限用配置常量挡，而不是靠平台报错：OrderedDataStore 的整数范围在本轮未实测（[未查证]）。
function Records.Scale(weight)
    if type(weight) ~= 'number' or weight ~= weight or weight == math.huge or weight == -math.huge
        or weight <= 0 then return nil, 'invalid' end
    local scaled = math.floor(weight * cfg().Scale + 0.5 + 1e-9)
    if scaled < 1 then return nil, 'invalid' end
    if scaled > cfg().MaxScaled then return nil, 'overflow' end
    return scaled
end

function Records.Unscale(scaled)
    if type(scaled) ~= 'number' or scaled ~= math.floor(scaled) or scaled < 1 then return nil end
    return scaled / cfg().Scale
end

-- 保持者三元组。显示名缺失/为空/超长一律记 nil（读出时退成「玩家<ID>」），
-- 不把 UserID 写进名字字段冒充名字。
function Records.Entry(scaled, userId, name)
    if type(scaled) ~= 'number' or scaled ~= math.floor(scaled) or scaled < 1
        or scaled > cfg().MaxScaled then return nil, 'invalid' end
    if type(userId) ~= 'number' or userId ~= math.floor(userId) or userId < 1 then return nil, 'invalid' end
    local display = type(name) == 'string' and name ~= '' and #name <= cfg().MaxNameLength and name or nil
    return { w = scaled, u = userId, n = display }
end

-- 读回校验：坏数据（缺重量或缺身份、类型不对、超上限）返回 nil，当作「这条不算纪录」，不猜不补。
-- 注意 nil 有两种含义，调用方要分开：适配器读到 nil 且没有报错 = 本来就没有纪录；
-- 适配器报错 = 读不到，必须按「暂不可用」处理，不能当成「暂无纪录」。
function Records.Valid(entry)
    if type(entry) ~= 'table' then return nil end
    local scaled = entry.w
    if type(scaled) ~= 'number' or scaled ~= math.floor(scaled) or scaled < 1
        or scaled > cfg().MaxScaled then return nil end
    local userId = entry.u
    if type(userId) ~= 'number' or userId ~= math.floor(userId) or userId < 1 then return nil end
    local name = entry.n
    if name ~= nil and (type(name) ~= 'string' or #name > cfg().MaxNameLength) then name = nil end
    return { w = scaled, u = userId, n = name }
end

-- 决胜：重量大者胜；同重量按 UserID 升序（小者保持），同 UserID 不重复写。
-- 规则只依赖两个候选自身，与到达顺序无关——任意顺序应用两个同重量候选，结果都是 UserID 最小者。
-- 这既是「同值稳定决胜」的可测定义，也让跨服竞态与延迟重试下的结果确定（不是「先到者保持」）。
function Records.Wins(candidate, current)
    local next_ = Records.Valid(candidate)
    if not next_ then return false end
    local held = Records.Valid(current)
    if not held then return true end
    if next_.w ~= held.w then return next_.w > held.w end
    return next_.u < held.u
end

function Records.Holder(entry)
    local valid = Records.Valid(entry)
    if not valid then return nil end
    return valid.n or (cfg().HolderFallback:format(valid.u))
end

-- 记录 → 展示状态。'ok' 有值、'missing' 服务可用但没纪录、'unavailable' 读不到——
-- 三者互不等价，UI 不能把 unavailable 当作 missing 或拿旧值充当前值。
function Records.State(entry)
    local valid = Records.Valid(entry)
    if not valid then return { state = 'missing' } end
    return { state = 'ok', scaled = valid.w, weight = valid.w / cfg().Scale,
        userId = valid.u, name = valid.n, holder = Records.Holder(valid) }
end

function Records.Describe(state)
    local texts = cfg().Texts
    if type(state) ~= 'table' or state.state == 'unavailable' then return texts.Unavailable end
    if state.state ~= 'ok' then return texts.Missing end
    return texts.Format:format(state.weight, state.holder or cfg().HolderFallback:format(state.userId))
end

return Records
