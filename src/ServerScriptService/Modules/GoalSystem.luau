-- ServerScriptService/Modules/GoalSystem
local GoalSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local resultEvent = remoteEvents:WaitForChild("RaceResultEvent")
local endEvent = remoteEvents:WaitForChild("RaceEndEvent")

local participants = {} -- {[userId]: Player}
local finished = {}     -- {[userId]: boolean}
local finishOrder = {}  -- {userId}
local finishTime = {} -- Not strictly needed if we just calc elapsed

local ServerScriptService = game:GetService("ServerScriptService")
local RewardService = require(ServerScriptService.Economy.RewardService)

local spawnLocation = Workspace:FindFirstChild("SpawnLocation", true)

function GoalSystem.SetParticipants(playerList)
    participants = {}
    finished = {}
    finishOrder = {}
    finishTime = {}
    for _, p in ipairs(playerList) do
        participants[p.UserId] = p
    end
end

function GoalSystem.HandleGoal(player)
    if not player or not participants[player.UserId] then return end
    if finished[player.UserId] then return end
    
    local raceState = Workspace:GetAttribute("RaceState")
    if raceState ~= "Running" then return end

    local userId = player.UserId
    finished[userId] = true
    table.insert(finishOrder, userId)
    
    local place = #finishOrder
    local now = Workspace:GetServerTimeNow()
    finishTime[userId] = now
    
    local raceStartTime = Workspace:GetAttribute("RaceStartTime")
    local elapsed = now - (raceStartTime or now)
    
    local totalParticipants = 0
    for _ in pairs(participants) do totalParticipants += 1 end

    -- Grant Reward
    local currentRaceId = Workspace:GetAttribute("CurrentRaceId") or "UNKNOWN"
    local rewardAmount = RewardService.GrantRaceReward(player, currentRaceId, place)

    -- Reset Physics and Teleport to Lobby
    local char = player.Character
    if char then
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then humanoid.Sit = false end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            if spawnLocation then
                char:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
            end
        end
    end

    -- Notify Client (Added rewardAmount arg)
    resultEvent:FireClient(player, "Finish", place, player.Name, elapsed, totalParticipants, rewardAmount)
    print(string.format("[GoalSystem] %s finished at place %d! Time: %.2fs Reward: %d", player.Name, place, elapsed, rewardAmount))

    -- Check if all finished
    local finishedCount = 0
    for _ in pairs(finished) do finishedCount += 1 end
    
    if finishedCount >= totalParticipants then
        GoalSystem.EndRace("AllFinished")
    end
end

function GoalSystem.HandleDNF()
	local raceStartTime = Workspace:GetAttribute("RaceStartTime")
	local now = Workspace:GetServerTimeNow()
	local elapsed = raceStartTime and (now - raceStartTime) or 0
	
    local totalParticipants = 0
    for _ in pairs(participants) do totalParticipants += 1 end
    
    local dnfList = {}
    for userId, player in pairs(participants) do
        if not finished[userId] then
            table.insert(dnfList, player)
        end
    end
    
	for _, player in ipairs(dnfList) do
		local char = player.Character
        if char then
            local humanoid = char:FindFirstChild("Humanoid")
            if humanoid then humanoid.Sit = false end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                if spawnLocation then
                    char:SetPivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
                end
            end
		end
		-- DNF: place=0, reward=0
        resultEvent:FireClient(player, "DNF", 0, player.Name, 120, totalParticipants, 0)
    end
    
    GoalSystem.EndRace("TimeUp")
end

local onEndCallback = nil
function GoalSystem.OnRaceEnded(callback)
    onEndCallback = callback
end

function GoalSystem.EndRace(reason)
	local raceId = Workspace:GetAttribute("CurrentRaceId") -- RaceServiceがセットしている前提

    -- Notify all participants
    for _, player in pairs(participants) do
        if player.Parent then
			endEvent:FireClient(player,raceId,reason)
        end
    end
    
    if onEndCallback then
        onEndCallback(reason)
    end
end

-- Init Connection
local goalPart = Workspace:FindFirstChild("Race", true) and Workspace:FindFirstChild("Race", true):FindFirstChild("Goal")
if goalPart then
    goalPart.Touched:Connect(function(hit)
        local char = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if player and hit.Name == "HumanoidRootPart" then
            GoalSystem.HandleGoal(player)
        end
    end)
else
    warn("[GoalSystem] Goal part not found at Workspace/Race/Goal")
end

return GoalSystem
