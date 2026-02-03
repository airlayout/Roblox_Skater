-- StarterGui/RaceUI/ResultPopup/ResultPopupHandler
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = script.Parent
local frame = gui:WaitForChild("MainFrame")
local title = frame:WaitForChild("TitleLabel")
local nameLabel = frame:WaitForChild("NameLabel")
local timeLabel = frame:WaitForChild("TimeLabel")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local resultEvent = remoteEvents:WaitForChild("RaceResultEvent")

resultEvent.OnClientEvent:Connect(function(resultType, place, playerName, elapsed, totalParticipants, rewardAmount)
    local rewardText = ""
    if rewardAmount and rewardAmount > 0 then
        rewardText = " + " .. tostring(rewardAmount) .. " Coin"
    end

    if resultType == "Finish" then
        title.Text = tostring(place) .. "位！" .. rewardText
        title.TextColor3 = Color3.new(1, 1, 0)
    else
        title.Text = "Time Up（DNF）"
        title.TextColor3 = Color3.new(1, 0, 0)
    end
    
    nameLabel.Text = playerName
    timeLabel.Text = string.format("Time: %.2fs", elapsed)
    
    gui.Enabled = true
    
    task.delay(5, function()
        gui.Enabled = false
    end)
end)

player.CharacterAdded:Connect(function()
    gui.Enabled = false
end)
