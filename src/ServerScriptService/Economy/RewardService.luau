-- ServerScriptService/Economy/RewardService
local RewardService = {}

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyService = require(ServerScriptService.Economy.MoneyService)
local EconomyConfig = require(ReplicatedStorage.Economy.EconomyConfig)

-- Cache for Idempotency: paidByRaceId[raceId][userId] = true
local paidByRaceId = {}

-- Trick debounce: lastTrick[userId] = { t=os.clock(), trickType="Spin360" }
local lastTrick = {}
local TRICK_DEBOUNCE_SEC = 0.10


function RewardService.GrantRaceReward(player, raceId, place)
    if not player or not raceId or not place then return 0 end
    
    -- Initialize cache for this raceId
    if not paidByRaceId[raceId] then
        paidByRaceId[raceId] = {}
        
        -- Cleanup old raceIds to prevent memory leak (Optional: simple size check or timestamp)
        -- For simplicity, we won't implement complex cleanup here, assuming server restart clears it 
        -- or RaceService manages raceId lifecycle.
    end
    
    -- Check Idempotency
    if paidByRaceId[raceId][player.UserId] then
        warn(string.format("[RewardService] Double Payment Blocked: Player %s, Race %s", player.Name, tostring(raceId)))
        return 0
    end
    
    -- Determine Reward
    local amount = EconomyConfig.RACE_REWARD_BY_PLACE[place] or EconomyConfig.RACE_REWARD_BY_PLACE.DEFAULT
    if amount > 0 then
        MoneyService.AddCoin(player, amount, "RACE_REWARD")
        
        -- Mark as paid
        paidByRaceId[raceId][player.UserId] = true
        
        -- Optional: Set Debug Attribute
        player:SetAttribute("LastRaceRewardAt", os.time())
    end
    
    return amount
end

-- ★追加：トリック報酬
-- 前提：呼び出し側（RaceService等）が「レース中のみ」を保証して呼ぶのが一番安全
-- もしここで保証したいなら、isInRace を引数で渡してチェックする設計にする
function RewardService.GrantTrickReward(player, raceId, trickType)
	if not player or not raceId or not trickType then return 0 end

	-- 事故的な二重発火だけ防ぐ（「連打で稼ぐ」仕様は止めない）
	local now = os.clock()
	local lt = lastTrick[player.UserId]
	if lt and lt.trickType == trickType and (now - lt.t) < TRICK_DEBOUNCE_SEC then
		return 0
	end
	lastTrick[player.UserId] = { t = now, trickType = trickType }

	-- 報酬表（EconomyConfig側に置くのがベスト）
	local tableByType = EconomyConfig.TRICK_REWARD_BY_TYPE
	local amount = 0
	if typeof(tableByType) == "table" then
		amount = tableByType[trickType] or 0
	end
	
	print("[RewardService] trickType=", trickType, "table=", EconomyConfig.TRICK_REWARD_BY_TYPE)
	

	if amount > 0 then
		-- source はポップアップ表示やログの分岐に使える
		MoneyService.AddCoin(player, amount, "TRICK_" .. tostring(trickType))
	end

	return amount
end

return RewardService

