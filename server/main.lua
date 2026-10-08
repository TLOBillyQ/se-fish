--local RunService = game:GetService("RunService")
--if RunService.EnableDeveloperMode() then
--    debug.start_debugger()
--end

local Task = game:GetService("Task")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
MgrUtil = require("server.MgrUtil")
MgrUtil:Start()

local MgrMap = {
    MgrPlayer = require("server.Mgr.MgrPlayer"),
    MgrPlayerData = require("server.Mgr.MgrPlayerData"),
    MgrCast = require("server.Mgr.MgrCast"),
    MgrAbility = require("server.Mgr.MgrAbility"),
    MgrReelIn = require("server.Mgr.MgrReelIn"),
    MgrFishCarrier = require("server.Mgr.MgrFishCarrier"),
    MgrFishUnit = require("server.Mgr.MgrFishUnit"),
    MgrLoot = require("server.Mgr.MgrLoot"),
    MgrInteract = require("server.Mgr.MgrInteract"),
    MgrGM = require("server.Mgr.MgrGM"),
    MgrShop = require("server.Mgr.MgrShop"),
    MgrLottery = require("server.Mgr.MgrLottery"),
    MgrQuest = require("server.Mgr.MgrQuest"),
    MgrVitals = require("server.Mgr.MgrVitals"),
    MgrStory = require("server.Mgr.MgrStory"),
    MgrFerry = require("server.Mgr.MgrFerry"),
    MgrSave = require("server.Mgr.MgrSave"),
    MgrSurvival = require("server.Mgr.MgrSurvival"),
    MgrWeapon = require("server.Mgr.MgrWeapon"),
    MgrSpecialItem = require("server.Mgr.MgrSpecialItem"),
    MgrCompendium = require("server.Mgr.MgrCompendium"),
    MgrRecords = require("server.Mgr.MgrRecords"),
    MgrGrill = require("server.Mgr.MgrGrill"),
    MgrPlatform = require("server.Mgr.MgrPlatform"),
    MgrBlindbox = require("server.Mgr.MgrBlindbox"),
    -- #153 官方包接入骨架：属性 / 效果 / 生物AI 的装配点，当前仅 Start 占位，玩法接线另开任务。
    MgrAttr = require("server.Mgr.MgrAttr"),
    MgrModifier = require("server.Mgr.MgrModifier"),
    MgrAi = require("server.Mgr.MgrAi"),
}

MgrMap.MgrCast.ReelIn = MgrMap.MgrReelIn
MgrMap.MgrReelIn.Cast = MgrMap.MgrCast
MgrMap.MgrCast.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrFishUnit.Cast = MgrMap.MgrCast
MgrMap.MgrFishUnit.Ability = MgrMap.MgrAbility
MgrMap.MgrLoot.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrLoot.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrPlayerData.Loot = MgrMap.MgrLoot
MgrMap.MgrInteract.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrGM.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrGM.Cast = MgrMap.MgrCast
MgrMap.MgrShop.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrShop.Interact = MgrMap.MgrInteract
MgrMap.MgrLoot.Quest = MgrMap.MgrQuest
MgrMap.MgrInteract.Quest = MgrMap.MgrQuest
MgrMap.MgrShop.Quest = MgrMap.MgrQuest
MgrMap.MgrPlayerData.Quest = MgrMap.MgrQuest
MgrMap.MgrCast.Quest = MgrMap.MgrQuest
MgrMap.MgrFishUnit.Quest = MgrMap.MgrQuest
MgrMap.MgrPlayerData.Vitals = MgrMap.MgrVitals
MgrMap.MgrGM.Vitals = MgrMap.MgrVitals
MgrMap.MgrGM.Save = MgrMap.MgrSave
MgrMap.MgrFerry.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrFerry.Interact = MgrMap.MgrInteract
MgrMap.MgrPlayerData.Save = MgrMap.MgrSave
MgrMap.MgrInteract.Save = MgrMap.MgrSave
MgrMap.MgrFerry.Save = MgrMap.MgrSave
MgrMap.MgrShop.Save = MgrMap.MgrSave
MgrMap.MgrFerry.Save = MgrMap.MgrSave
MgrMap.MgrSave.PlayerData = MgrMap.MgrPlayerData
--- #138 T17 抽奖机：结算走 #123 持久操作协议（扣物/发奖与结果同键落账），距离复验复用
--- MgrInteract 的锚点范围判定；断线重进由 OnPlayerAdded 补推最近一次抽奖结果（仅展示）。
MgrMap.MgrLottery.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrLottery.Save = MgrMap.MgrSave
MgrMap.MgrLottery.Interact = MgrMap.MgrInteract
--- #133 图鉴写入：上岸事实经 MgrCompendium 记进 extra.collection，写入走 #123 持久操作协议，
--- 所以条目与个人最大重量和操作日志同键落账、重进保留；只有上岸这一个写入口（击杀与掉落走 MgrLoot）。
MgrMap.MgrCompendium.Save = MgrMap.MgrSave
MgrMap.MgrCompendium.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrCast.Compendium = MgrMap.MgrCompendium

--- #149 T28 全服纪录：上岸经 MgrCompendium 的「刷新个人纪录」回调通知 MgrRecords，
--- 由它做合并窗口写入（DataStore 三元组 CAS）；图鉴查询（RecordsRequest RE）由 MgrRecords 受理并回
--- RecordsState，平台读不到时报「暂不可用」而不是伪纪录；查询顺带对账（个人纪录更高时补交）。
MgrMap.MgrCompendium.Records = MgrMap.MgrRecords
MgrMap.MgrRecords.PlayerData = MgrMap.MgrPlayerData

--- #147 T26 平台功能本地接缝：商品购买/广告的唯一服务端入口是 MgrPlatform（真实商品 ID
--- 未交付时入口明确不可用，Debug 开时 pending flow + 测试驱动器结算，生产构建拒绝驱动器）；
--- 盲盒结算（MgrBlindbox）先经平台购买 flow 收费，成功才在 #123 持久操作里逐抽发奖并写回
--- 保底计数（Extra.lottery.pity），满格溢出经 MgrLoot 按区落地。
MgrMap.MgrPlatform.Save = MgrMap.MgrSave
MgrMap.MgrPlatform.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrPlatform.Loot = MgrMap.MgrLoot
MgrMap.MgrBlindbox.Save = MgrMap.MgrSave
MgrMap.MgrBlindbox.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrBlindbox.Platform = MgrMap.MgrPlatform
MgrMap.MgrBlindbox.Loot = MgrMap.MgrLoot
--- 平台复活（广告 / 5 金豆满血复活）与濒死无药拉起肾上腺素购买入口都经 MgrPlatform。
MgrMap.MgrSurvival.Platform = MgrMap.MgrPlatform

-- #128 战斗接线：统一伤害入口的依赖单向注入在这里完成。
-- Vitals 需要鱼受击体解析（ApplyHit 的鱼分支）；Ability / FishUnit / Cast 需要玩家生命状态
-- （施法守卫、追咬结算、动作互斥）；鱼受击体的有效伤害经 DamageListener 回报仇恨。
-- 契约：DamageListener(carrier, actual, hit) 中 hit.sourcePlayer 是服务端登记的玩家来源身份，
-- 只有玩家武器伤害才累计仇恨；鱼攻击（fishAttack）来源不是玩家，自然不记。
MgrMap.MgrAbility.Vitals = MgrMap.MgrVitals
MgrMap.MgrFishUnit.Vitals = MgrMap.MgrVitals
-- #132 T11 三倍体型：吃药水成功后由 MgrPlayerData 就地重算体型（唯一消费口，幂等）。
MgrMap.MgrPlayerData.Ability = MgrMap.MgrAbility
-- #139 大奖成长：MgrAbility 读存档药水数、读虚弱标记，是移速/血量上限的唯一计算处；
-- 虚弱进出经 SpeedWriter 回到它整体重算；麻痹经 Vitals.ActGuard 统一封锁攻击/投掷/钓鱼/进食。
MgrMap.MgrAbility.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrAbility.Survival = MgrMap.MgrSurvival
-- 官方属性与五效果只有一个投影入口，组合倍率在 Modifier 内合成一次。
MgrMap.MgrAttr.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrAttr.Vitals = MgrMap.MgrVitals
MgrMap.MgrAttr.MoveMultiplierProvider = function(player) return MgrMap.MgrModifier:GetMoveMultiplier(player) end
MgrMap.MgrAbility.Attr = MgrMap.MgrAttr
MgrMap.MgrWeapon.Attr = MgrMap.MgrAttr
MgrMap.MgrVitals.Attr = MgrMap.MgrAttr
MgrMap.MgrAbility.Modifier = MgrMap.MgrModifier
MgrMap.MgrSurvival.Modifier = MgrMap.MgrModifier
MgrMap.MgrModifier.Ability = MgrMap.MgrAbility
MgrMap.MgrModifier.Vitals = MgrMap.MgrVitals
MgrMap.MgrFishUnit.Ai = MgrMap.MgrAi
MgrMap.MgrAi.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrSurvival.SpeedWriter = MgrMap.MgrAbility
MgrMap.MgrVitals.ActGuard = function(player) return not MgrMap.MgrAbility:IsParalyzed(player) end
MgrMap.MgrVitals.MaxHealthProvider = function(player) return MgrMap.MgrAttr:MaxHealth(player) end
MgrMap.MgrVitals.FishCarrier = MgrMap.MgrFishCarrier
MgrMap.MgrCast.Vitals = MgrMap.MgrVitals
-- #131 生存恢复：经 #128 预留的 LifeHooks 接管濒死/死亡，依赖单向注入在这里完成。
MgrMap.MgrSurvival.Vitals = MgrMap.MgrVitals
MgrMap.MgrSurvival.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrSurvival.ReelIn = MgrMap.MgrReelIn
MgrMap.MgrSurvival.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrSurvival.Save = MgrMap.MgrSave
MgrMap.MgrVitals:SetLifeHooks(MgrMap.MgrSurvival:Hooks())
MgrMap.MgrFishCarrier.DamageListener = function(carrier, actual, hit)
    local fish = carrier and MgrMap.MgrFishUnit:FindByCarrier(carrier)
    local attacker = hit and hit.sourcePlayer
    if fish and attacker and type(actual) == 'number' and actual > 0 then
        MgrMap.MgrFishUnit:NoteDamage(fish, attacker, actual)
    end
end

-- #129 武器系统接线：近战/枪械/投掷结算经统一伤害入口（Vitals）与鱼受击体解析（FishCarrier）；
-- 武器库存/装备读 PlayerData，投掷消耗走 Save 持久协议，爆炸保底鱼生成进 FishUnit。
-- Update（投掷飞行物推进）由 HandleTimeUpdate 心跳统一驱动，Start 注册 WeaponAction 通道与挥砍施法守卫。
MgrMap.MgrWeapon.Vitals = MgrMap.MgrVitals
MgrMap.MgrWeapon.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrWeapon.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrWeapon.FishCarrier = MgrMap.MgrFishCarrier
MgrMap.MgrWeapon.Save = MgrMap.MgrSave
MgrMap.MgrWeapon.Ability = MgrMap.MgrAbility -- #139 枪械大奖特效应用口

-- #137 烧烤接线：会话物品进出走 #123 持久协议（Save+PlayerData），烤糊伤害经统一伤害入口
-- （Vitals）；满格时物品不入地、会话转 ready 保留冻结倍率，腾出格位后重试原倍率发还。
-- 离开前结算挂在下面 HandlePlayerRemoving 里 MgrSurvival 终镜像之后、MgrPlayerData 序列化之前。
MgrMap.MgrGrill.Vitals = MgrMap.MgrVitals
MgrMap.MgrGrill.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrGrill.Save = MgrMap.MgrSave

-- #140 T19 特殊道具：选中调和每帧对齐「期望 × CanAct」，切换/丢弃/死亡/复活/摆渡/重进
-- 全走调和恢复；吐息结算经统一伤害入口（Vitals），摆渡前由 MgrFerry:Teleport 通知结束飞行。
MgrMap.MgrSpecialItem.Vitals = MgrMap.MgrVitals
MgrMap.MgrSpecialItem.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrSpecialItem.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrFerry.SpecialItem = MgrMap.MgrSpecialItem

-- 存档就绪前不创建 Vitals/Ability 等玩家状态；退出先撤销就绪标记，再清理管理器。
local ActivePlayers = {}
local Started = false
local ReadyQueue = {}
local function invoke(name, mgr, method, ...)
    if not mgr[method] then return end
    local ok, err = pcall(mgr[method], mgr, ...)
    if not ok then print('[server.main]', name, method, tostring(err)) end
end
MgrMap.MgrSave.OnReady = function(player, data)
    if MgrMap.MgrPlayerData:GetDataInst(player) ~= data or ActivePlayers[player.UserId] == player then return end
    if not Started then ReadyQueue[player.UserId] = { player, data } return end
    ActivePlayers[player.UserId] = player
    -- 这些管理器直接操作角色与生命状态，先于依赖它们的其他管理器初始化。
    -- MgrSurvival 紧随 MgrVitals：离线恢复要读 Vitals 状态并把控制器血量锁回 1。
    for _, name in ipairs({ 'MgrAttr', 'MgrPlayer', 'MgrVitals', 'MgrModifier', 'MgrSurvival', 'MgrAbility', 'MgrFishUnit' }) do
        invoke(name, MgrMap[name], 'OnPlayerAdded', player)
    end
    for name, mgr in pairs(MgrMap) do
        if name ~= 'MgrPlayerData' and name ~= 'MgrPlayer' and name ~= 'MgrVitals'
            and name ~= 'MgrSurvival' and name ~= 'MgrAbility' and name ~= 'MgrFishUnit'
            and name ~= 'MgrAttr' and name ~= 'MgrModifier' then
            invoke(name, mgr, 'OnPlayerAdded', player)
        end
    end
end
local function HandlePlayerAdded(player)
    invoke('MgrPlayerData', MgrMap.MgrPlayerData, 'OnPlayerAdded', player)
end

local function HandlePlayerRemoving(player)
    local queued = ReadyQueue[player.UserId]
    if queued and queued[1] == player then ReadyQueue[player.UserId] = nil end
    local active = ActivePlayers[player.UserId] == player
    if active then ActivePlayers[player.UserId] = nil end
    -- 终镜像必须先于 MgrPlayerData 的 SaveLeaving 序列化，离线标记才是最新的
    if active then invoke('MgrSurvival', MgrMap.MgrSurvival, 'BeforeLeave', player) end
    -- #137：烧烤会话同样要在序列化前结算一次（放回烤鱼或转待恢复标记），不复制不吞物
    if active then invoke('MgrGrill', MgrMap.MgrGrill, 'BeforeLeave', player) end
    if active then invoke('MgrSpecialItem', MgrMap.MgrSpecialItem, 'BeforeLeave', player) end
    invoke('MgrPlayerData', MgrMap.MgrPlayerData, 'OnPlayerRemoving', player)
    if active then
        for name, mgr in pairs(MgrMap) do
            if name ~= 'MgrPlayerData' then invoke(name, mgr, 'OnPlayerRemoving', player) end
        end
    end
end

local function HandleTimeUpdate(deltaTime)
    for k, mgr in pairs(MgrMap) do
        if mgr.Update then
            pcall(function() mgr:Update(deltaTime) end)
        end
    end
end 

local function GameStart()
    for name, mgr in pairs(MgrMap) do invoke(name, mgr, 'Start') end
    Started = true
    for userId, entry in pairs(ReadyQueue) do
        ReadyQueue[userId] = nil
        MgrMap.MgrSave.OnReady(entry[1], entry[2])
    end
end



Players.PlayerAdded:Connect(HandlePlayerAdded)
Players.PlayerRemoving:Connect(HandlePlayerRemoving)
--处理玩家在事件注册之前就加入的情况
local plst = Players:GetPlayers()
for _, player in pairs(plst)  do
    HandlePlayerAdded(player)
end

GameStart()
RunService.Heartbeat:Connect(HandleTimeUpdate)




