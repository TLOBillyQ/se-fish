-- #138 T17 抽奖界面（client/ScreenHandlers/ScreenLottery）失败方式先列：
--   1. 投注框看错格：不用当前选中格，或烤鱼/非极品也显示可投；
--   2. 投注价值显示不含个体倍率（与服务器结算口径不一致）；
--   3. 动画决定奖项：停轴图案来自客户端本地随机而不是服务端回包 axes；
--   4. 停轴顺序错：不是左→右→中，或未到 3 秒就停；
--   5. 动画中重复点抽奖重复发请求；重播回调（同 operation.id）重播动画/重置展示；
--   6. 关窗中断动画后结果丢失；断线恢复（recovered）又播一次动画或提示语不对；
--   7. 失败原因没有对应玩家可读提示。
-- seam：直接调 handler 的 RefreshBet / Draw / NoteResult / UpdateAnim / OpenScreen / CloseScreen，
--   替换 game/REUtil/EUI 边界（与 ferry_ui_test 同款）；动画用 UpdateAnim(dt) 推进，不用真实计时。
local lu = require('luaunit')

local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn)
            listeners[#listeners + 1] = fn
            return { Disconnect = function()
                for i, cb in ipairs(listeners) do
                    if cb == fn then table.remove(listeners, i) break end
                end
            end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
    }
end

TestScreenLottery = {}

function TestScreenLottery:setUp()
    local env = self
    self.previous = {}
    for _, key in ipairs({ 'game', 'Vector2', 'Vector3', 'Color', 'REUtil', 'LocalMsgNotice', 'MgrGameUI' }) do
        self.previous[key] = rawget(_G, key)
    end
    self.previousLoaded = {}
    for _, name in ipairs({ 'common.GameCfg', 'common.REUtil', 'common.LotteryEligibility',
        'client.GameUI' }) do
        self.previousLoaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    self.cfg = require('common.GameCfg')

    self.nodes = {}
    local world = {}
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal(), Visible = true }
        for key, value in pairs(attrs) do node[key] = value end
        if node.Name then env.nodes[node.Name] = node end
        return node
    end
    function world:FindFirstChild() return nil end
    local root = { Name = 'UIRoot', children = {} }
    function root:FindFirstChild(name)
        return self.children[name]
    end
    self.root = root
    local eui = { GetRootNode = function() return root end,
        GetDeviceResolution = function() return { x = 1920, y = 1080 } end }
    self.localPlayer = { PlayerGui = { EuiManager = eui }, UserId = 7,
        GetAttribute = function() return 0 end }

    self.commands, self.notices = {}, {}
    _G.LocalMsgNotice = function(msg) env.notices[#env.notices + 1] = msg end
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'Players' then return { LocalPlayer = env.localPlayer } end
        if name == 'RunService' then return { Heartbeat = signal(),
            IsClient = function() return true end, IsServer = function() return false end } end
        if name == 'Task' then return { Spawn = function(_, fn) fn() end, Wait = function() end,
            Delay = function() end } end
    end }
    local reStub = { GetRE = function(_, name)
        env.events = env.events or {}
        if not env.events[name] then
            env.events[name] = {
                OnClientEvent = signal(), OnServerEvent = signal(),
                FireServer = function(_, payload)
                    env.commands[#env.commands + 1] = { name = name, payload = payload }
                end,
            }
        end
        return env.events[name]
    end }
    package.loaded['common.REUtil'] = reStub
    _G.REUtil = reStub

    self.handler = assert(loadfile('client/ScreenHandlers/ScreenLottery.lua'))()
    self.handler:Start()
    -- 根节点挂上 UIRoot，MgrGameUI 按名字找得到
    root.children[self.handler.RootNode.Name] = self.handler.RootNode
end

function TestScreenLottery:tearDown()
    for name, module in pairs(self.previousLoaded) do package.loaded[name] = module end
    for key, value in pairs(self.previous) do _G[key] = value end
end

-- 构造道具栏快照：selectedSlot 指向 slots 里第 slot 格
function TestScreenLottery:snapshot(slot, entry)
    local state = { slots = {}, slotCount = 2, coin = 0, selectedSlot = slot }
    if entry then state.slots[slot] = entry end
    self.handler:NoteItemBar(state)
    return state
end

function TestScreenLottery:premiumEntry(mult, cooked)
    return { itemId = 'item7', count = 1, mult = mult, cooked = cooked,
        containerId = 'itemBar' }
end

function TestScreenLottery:test_bet_box_shows_selected_premium_with_actual_value()
    self:snapshot(1, self:premiumEntry(1.5))
    lu.assertStrContains(self.nodes.LabelLotteryBet.Text, '极品罗非鱼')
    lu.assertStrContains(self.nodes.LabelLotteryBet.Text, '4') -- floor(3 × 1.5)
    lu.assertTrue(self.handler:DrawEnabled())
end

function TestScreenLottery:test_bet_box_rejects_cooked_and_ordinary_and_empty()
    self:snapshot(1, { itemId = 'carp', count = 1, containerId = 'itemBar' })
    lu.assertFalse(self.handler:DrawEnabled())
    self:snapshot(1, self:premiumEntry(nil, 1.5)) -- 烤鱼
    lu.assertFalse(self.handler:DrawEnabled())
    self:snapshot(1, nil) -- 空槽
    lu.assertFalse(self.handler:DrawEnabled())
end

function TestScreenLottery:test_draw_sends_slot_and_seq_once_per_click()
    self:snapshot(1, self:premiumEntry())
    lu.assertTrue(self.handler:Draw())
    lu.assertFalse(self.handler:Draw()) -- 等待结果期间重复点击被忽略
    lu.assertEquals(#self.commands, 1)
    lu.assertEquals(self.commands[1].name, 'LotteryAction')
    lu.assertEquals(self.commands[1].payload, { action = 'Draw', slot = 1, seq = 1 })
end

local function result(env, axes, outcome, extra)
    local value = { ok = true, action = 'Draw', slot = 1, itemId = 'item7', itemName = '极品罗非鱼',
        betValue = 3, axes = axes, outcome = outcome,
        operation = { id = '7:1', sequence = 1, kind = 'lottery' } }
    for key, val in pairs(extra or {}) do value[key] = val end
    return value
end

function TestScreenLottery:test_reels_stop_left_right_middle_after_spin_seconds()
    self:snapshot(1, self:premiumEntry())
    self.handler:Draw()
    self.handler:NoteResult(result(self, { 1, 1, 2 }, 'pair', { coins = 6, multiplier = 2 }))
    local left, right, middle = self.nodes.LabelReelLeft, self.nodes.LabelReelRight, self.nodes.LabelReelMiddle
    self.handler:UpdateAnim(2.9)
    lu.assertFalse(self.handler:AxisStopped(1))
    self.handler:UpdateAnim(0.1) -- t = 3.0 停左轴
    lu.assertTrue(self.handler:AxisStopped(1))
    lu.assertEquals(left.Text, '鳄雀鳝')
    lu.assertFalse(self.handler:AxisStopped(2))
    self.handler:UpdateAnim(0.5) -- t = 3.5 停右轴
    lu.assertEquals(right.Text, '鳄雀鳝')
    lu.assertFalse(self.handler:AxisStopped(3))
    self.handler:UpdateAnim(0.5) -- t = 4.0 停中轴
    lu.assertEquals(middle.Text, '小白龙')
    lu.assertStrContains(self.nodes.LabelLotteryResult.Text, '6') -- 金币 +6
    lu.assertTrue(self.handler:DrawEnabled()) -- 结果落定后可继续抽下一件
end

function TestScreenLottery:test_triple_shows_jackpot_text_without_coins()
    self:snapshot(1, self:premiumEntry())
    self.handler:Draw()
    self.handler:NoteResult(result(self, { 4, 4, 4 }, 'triple',
        { prize = { kind = 'item', itemId = 'item167', name = '加速药水' }, patternName = '三头鲨' }))
    for _ = 1, 9 do self.handler:UpdateAnim(0.5) end
    lu.assertStrContains(self.nodes.LabelLotteryResult.Text, '恭喜获得')
    lu.assertStrContains(self.nodes.LabelLotteryResult.Text, '加速药水')
    lu.assertStrContains(self.nodes.LabelLotteryResult.Text, '三头鲨')
end

function TestScreenLottery:test_replay_callback_does_not_restart_animation_or_result()
    self:snapshot(1, self:premiumEntry())
    self.handler:Draw()
    local value = result(self, { 1, 1, 2 }, 'pair', { coins = 6, multiplier = 2 })
    self.handler:NoteResult(value)
    self.handler:UpdateAnim(3.0)
    local leftText = self.nodes.LabelReelLeft.Text
    self.handler:NoteResult(value) -- 同 operation.id 重播
    lu.assertEquals(self.handler.AnimationStarts, 1)
    lu.assertEquals(self.nodes.LabelReelLeft.Text, leftText)
    lu.assertTrue(self.handler:AxisStopped(1))
end

function TestScreenLottery:test_close_mid_animation_keeps_the_settled_result()
    self:snapshot(1, self:premiumEntry())
    self.handler:Draw()
    local value = result(self, { 4, 4, 4 }, 'triple',
        { prize = { kind = 'item', itemId = 'item167', name = '加速药水' }, patternName = '三头鲨' })
    self.handler:NoteResult(value)
    self.handler:UpdateAnim(1) -- 动画中途
    self.handler:CloseScreen()
    lu.assertFalse(self.handler:IsSpinning())
    self.handler:OpenScreen()
    lu.assertStrContains(self.nodes.LabelLotteryResult.Text, '加速药水') -- 重开展示同一结果
    lu.assertFalse(self.handler:IsSpinning()) -- 不重播动画
end

function TestScreenLottery:test_recovered_result_shows_without_animation()
    self:snapshot(1, self:premiumEntry())
    local value = result(self, { 4, 4, 4 }, 'triple',
        { prize = { kind = 'item', itemId = 'item167', name = '加速药水' }, patternName = '三头鲨' })
    value.recovered = true
    self.handler:NoteResult(value)
    lu.assertFalse(self.handler:IsSpinning())
    lu.assertStrContains(self.nodes.LabelLotteryResult.Text, '加速药水')
    lu.assertEquals(self.nodes.LabelReelLeft.Text, '三头鲨') -- 三轴直接落到结果图案
end

function TestScreenLottery:test_failure_reasons_have_readable_notice()
    local reasons = { ['not-premium'] = true, cooked = true, range = true, slot = true }
    self:snapshot(1, self:premiumEntry())
    for reason in pairs(reasons) do
        self.handler:NoteResult({ ok = false, reason = reason })
    end
    lu.assertEquals(#self.notices, 4)
    for _, msg in ipairs(self.notices) do lu.assertTrue(#msg > 0) end
end
