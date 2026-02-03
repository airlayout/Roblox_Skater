-- StarterPlayer/StarterPlayerScripts/Economy/MoneyClient
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local EconomyRemotes = require(ReplicatedStorage.Economy.EconomyRemotes)
local MoneyChangedEvent = EconomyRemotes.GetMoneyChangedEvent()

-- 1. Create HUD (Programmatic)
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CoinHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Container"
frame.Size = UDim2.new(0, 200, 0, 40)
frame.Position = UDim2.new(0, 20, 1, -60) -- Bottom Left
frame.BackgroundTransparency = 1
frame.Parent = screenGui

local icon = Instance.new("TextLabel")
icon.Text = "💰"
icon.Size = UDim2.new(0, 40, 1, 0)
icon.BackgroundTransparency = 1
icon.TextSize = 24
icon.Parent = frame

local amountLabel = Instance.new("TextLabel")
amountLabel.Name = "AmountLabel"
amountLabel.Size = UDim2.new(1, -40, 1, 0)
amountLabel.Position = UDim2.new(0, 40, 0, 0)
amountLabel.BackgroundTransparency = 1
amountLabel.TextXAlignment = Enum.TextXAlignment.Left
amountLabel.TextColor3 = Color3.new(1, 1, 0)
amountLabel.TextStrokeTransparency = 0
amountLabel.Font = Enum.Font.GothamBold
amountLabel.TextSize = 24
amountLabel.Text = "0"
amountLabel.Parent = frame

-- Helper: Format Number
local function formatNumber(n)
    return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- 2. Attribute Watcher
local function updateDisplay()
    local coin = player:GetAttribute("Coin") or 0
    amountLabel.Text = formatNumber(coin)
end

player:GetAttributeChangedSignal("Coin"):Connect(updateDisplay)
updateDisplay() -- Init

-- 3. Event Listener (Log)
MoneyChangedEvent.OnClientEvent:Connect(function(newCoin, delta, source)
    print(string.format("[Economy] Coin Changed: %+d (Total: %d) Source: %s", delta, newCoin, source))
    -- Future: Floating Text Effect
end)
