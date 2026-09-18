local Task = game:GetService("Task")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local World = game:GetService("World")
local Mgr = {}

local ONCE_FISH_TIME = 10
local SAVE_CLOSE_TIME = 5
local playerFishMap = {}
local GameCfg = require("common.GameCfg")

local function StartFish(player)
	local fishInfo = playerFishMap[player.UserId]
	if fishInfo then
		print("[MgrFish] 已经在钓了!", player)
		return
	end

	local pData = _G.MgrPlayerData:GetDataInst(player)
	if not pData then
		print("[MgrFish] 玩家存档无了!", player)
		return
	end

	local fishLv = pData.Data.FishLevel
	local rodLv = pData.Data.RodLevel

	local rodLvCfg = GameCfg.RodLevelMap[rodLv]
	local fishLvCfg = GameCfg.FishLevelMap[fishLv]
	if not fishLvCfg or not rodLvCfg then
		print("[MgrFish] 钓鱼等级无配置!", fishLv, rodLv)
		return
	end

	fishInfo = {
		UserId = player.UserId,
		TotalTime = rodLvCfg.FishTime,
		EndTime = World:GetServerTime() + rodLvCfg.FishTime + SAVE_CLOSE_TIME,
		FishId = GameCfg:GetLootRst(fishLvCfg.Loot),
	}
	playerFishMap[player.UserId] = fishInfo
	_G.REUtil:GetRE("OpenScreenRE"):FireClient(player, "ScreenFishing", fishInfo)
end

local function DoneFish(player)
	local fishInfo = playerFishMap[player.UserId]
	if not fishInfo then return end
	local fishCfg = GameCfg.FishMap[fishInfo.FishId]

	local pData = _G.MgrPlayerData:GetDataInst(player)
	if not pData then
		print("[MgrFish] 玩家存档无了!", player)
		return
	end

	pData:UpdateData(function(data)
		data.FishCoin = data.FishCoin + fishCfg.Coin
	end, true)

	fishInfo.DoReward = true
	playerFishMap[player.UserId] = nil
	_G.REUtil:GetRE("OpenScreenRE"):FireClient(player, "ScreenFishing", fishInfo)
end

local function CancelFish(player)
	local fishInfo = playerFishMap[player.UserId]
	if not fishInfo then return end

	playerFishMap[player.UserId] = nil
	_G.REUtil:GetRE("CloseScreenRE"):FireClient(player, "ScreenFishing")
	
end	

local function FishTimeEnd(player)
	local fishInfo = playerFishMap[player.UserId]
	if not fishInfo then return end

	playerFishMap[player.UserId] = nil
	_G.REUtil:GetRE("OpenScreenRE"):FireClient(player, "ScreenFishing", {TimeOver = true})
end

local function RodLevelUp(player)
	local pData = _G.MgrPlayerData:GetDataInst(player)
	if not pData then
		print("[MgrFish] 玩家存档无了!", player)
		return
	end

	
	local rodLv = pData.Data.RodLevel
	if rodLv >= GameCfg.MaxRodLv then
		_G.Util:MsgNotice(player, "等级已经到达上限!")
		return 
	end

	local coin = pData.Data.FishCoin
	local rodLvCfg = GameCfg.RodLevelMap[rodLv]
	if rodLvCfg.Cost > coin then
		_G.Util:MsgNotice(player, "金币不足，快去钓鱼赚金币吧!")
		return 
	end

	--确认升级
	pData:UpdateData(function(data)
		data.RodLevel = data.RodLevel + 1
		data.FishCoin = data.FishCoin - rodLvCfg.Cost
	end, true)

	_G.REUtil:GetRE("RodLevelUp"):FireClient(player, pData.Data.RodLevel, pData.Data.FishCoin)
end

local function FishLevelUp(player)
	local pData = _G.MgrPlayerData:GetDataInst(player)
	if not pData then
		print("[MgrFish] 玩家存档无了!", player)
		return
	end

	local fishLv = pData.Data.FishLevel
	if fishLv >= GameCfg.MaxFishLv then
		_G.Util:MsgNotice(player, "等级已经到达上限!")
		return 
	end

	local coin = pData.Data.FishCoin
	local fishLvCfg = GameCfg.FishLevelMap[fishLv]
	if fishLvCfg.Cost > coin then
		_G.Util:MsgNotice(player, "金币不足，快去钓鱼赚金币吧!")
		return 
	end

	--确认升级
	pData:UpdateData(function(data)
		data.FishLevel = data.FishLevel + 1
		data.FishCoin = data.FishCoin - fishLvCfg.Cost
	end, true)

	_G.REUtil:GetRE("FishLevelUp"):FireClient(player, pData.Data.FishLevel, pData.Data.FishCoin)
end

function Mgr:Start()
	_G.REUtil:GetRE("ReqFish").OnServerEvent:Connect(StartFish)
	_G.REUtil:GetRE("CancelFish").OnServerEvent:Connect(CancelFish)

	_G.REUtil:GetRE("DoneFish").OnServerEvent:Connect(function(player, done) 
		if done then
			DoneFish(player)
		else
			FishTimeEnd(player)
		end
	end)

	_G.REUtil:GetRE("RodLevelUp").OnServerEvent:Connect(RodLevelUp)
	_G.REUtil:GetRE("FishLevelUp").OnServerEvent:Connect(FishLevelUp)
end

function Mgr:OnPlayerAdded(player)
end

function Mgr:OnPlayerRemoving(player)
	CancelFish(player)
end

function Mgr:Update(deltaTime)
	local nowTime = World:GetServerTime()
	local removeMap = {}
    for uid, fishInfo in pairs(playerFishMap) do
		if fishInfo.EndTime < nowTime then
			removeMap[uid] = true
		end
	end

	for uid, v in pairs(removeMap) do
		local player = Players:GetPlayerByUserId(uid)
		if player then
			FishTimeEnd(player)
		else
			print("[MgrFish] Remove fishInfo but not player", uid)
			playerFishMap[uid] = nil
		end
	end
end

return Mgr