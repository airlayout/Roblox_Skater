-- ServerScriptService/Economy/EconomyBootstrap.server
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyService = require(ServerScriptService.Economy.MoneyService)
local ShopService = require(ServerScriptService.Economy.ShopService)
local EconomyRemotes = require(ReplicatedStorage.Economy.EconomyRemotes)

-- Lifecycle Hooks
local function onPlayerAdded(player)
    MoneyService.InitPlayer(player)
    local loaded = MoneyService.Load(player)
    if loaded then
        print("[EconomyBootstrap] Loaded data for " .. player.Name)
    else
        warn("[EconomyBootstrap] Failed to load data for " .. player.Name)
    end
end

local function onPlayerRemoving(player)
    MoneyService.Save(player) -- Attempt save on exit
    MoneyService.ClearSession(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle existing players (for Studio reload/edit)
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

-- Shop Remote Hook
local shopRequest = EconomyRemotes.GetShopPurchaseRequest()
shopRequest.OnServerInvoke = function(player, productId, quantity)
    return ShopService.Purchase(player, productId, quantity)
end

print("[EconomyBootstrap] Economy System Started")
