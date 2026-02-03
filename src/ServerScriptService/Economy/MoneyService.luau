-- ServerScriptService/Economy/MoneyService
local MoneyService = {}

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local EconomyConfig = require(ReplicatedStorage.Economy.EconomyConfig)
local EconomyRemotes = require(ReplicatedStorage.Economy.EconomyRemotes)

local DATASTORE_NAME = "EconomyStore_v1"
local economyStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local sessionData = {} -- [Player] = { coin=0, unlocks={}, consumables={} }

-- Helper: Get MoneyChangedEvent
local moneyChangedEvent = EconomyRemotes.GetMoneyChangedEvent()

function MoneyService.HasSession(player)
    return sessionData[player] ~= nil
end

function MoneyService.InitPlayer(player)
    sessionData[player] = {
        coin = 0,
        unlocks = {},
        consumables = {}
    }
    player:SetAttribute("Coin", 0)
    -- Optional: LastRaceRewardAt
end

function MoneyService.GetCoin(player)
    local data = sessionData[player]
    return data and data.coin or 0
end

function MoneyService.GetUnlocks(player)
    local data = sessionData[player]
    return data and data.unlocks or {}
end

function MoneyService.GetConsumables(player)
    local data = sessionData[player]
    return data and data.consumables or {}
end

function MoneyService.AddCoin(player, amount, source)
    if amount <= 0 then return end
    local data = sessionData[player]
    if not data then return end

    local oldCoin = data.coin
    local newCoin = math.min(oldCoin + amount, EconomyConfig.MAX_COIN)
    
    if newCoin ~= oldCoin then
        data.coin = newCoin
        player:SetAttribute("Coin", newCoin)
        
        -- Fire Event (Logging/FX)
        moneyChangedEvent:FireClient(player, newCoin, amount, source or "UNKNOWN")
        
        -- Auto Save
        task.spawn(function()
            MoneyService.Save(player)
        end)
    end
end

function MoneyService.SpendCoin(player, amount, source)
    if amount <= 0 then return false, "INVALID_AMOUNT" end
    local data = sessionData[player]
    if not data then return false, "NO_SESSION" end

    local oldCoin = data.coin
    if oldCoin < amount then
        return false, "INSUFFICIENT_FUNDS"
    end

    local newCoin = oldCoin - amount
    data.coin = newCoin
    player:SetAttribute("Coin", newCoin)
    
    -- Fire Event
    moneyChangedEvent:FireClient(player, newCoin, -amount, source or "PURCHASE")
    
    -- Auto Save
    task.spawn(function()
        MoneyService.Save(player)
    end)
    
    return true, "OK"
end

-- Update Unlocks/Consumables state directly (Internal Use)
function MoneyService.UpdateInventory(player, unlocks, consumables)
    local data = sessionData[player]
    if not data then return end
    
    if unlocks then
        for k, v in pairs(unlocks) do
            data.unlocks[k] = v
        end
    end
    if consumables then
        for k, v in pairs(consumables) do
            data.consumables[k] = v
        end
    end
    -- Save is usually called by the caller (ShopService) or auto-saved after spending coin
end

function MoneyService.Load(player)
    local success, result = pcall(function()
        return economyStore:GetAsync("u_" .. player.UserId)
    end)

    if success then
        local data = sessionData[player] or {}
        if result then
            data.coin = result.coin or 0
            data.unlocks = result.unlocks or {}
            data.consumables = result.consumables or {}
        else
            -- New player
            data.coin = 0
            data.unlocks = {}
            data.consumables = {}
        end
        sessionData[player] = data
        
        -- Sync Attribute
        player:SetAttribute("Coin", data.coin)
        player:SetAttribute("EconomyReady", true)
        return true
    else
        warn("[MoneyService] Failed to load data for " .. player.Name .. ": " .. tostring(result))
        -- Initialize empty session to prevent errors, but maybe don't save?
        -- For now, initialize empty so game works.
        MoneyService.InitPlayer(player)
        -- Warn but allow ready (Shop will attempt sync save later)
        player:SetAttribute("EconomyReady", true)
        return false
    end
end

function MoneyService.Save(player)
    local data = sessionData[player]
    if not data then return false end
    
    local key = "u_" .. player.UserId
    local saveData = {
        coin = data.coin,
        unlocks = data.unlocks,
        consumables = data.consumables
    }

    local RETRY_MAX = 3
    for i = 1, RETRY_MAX do
        local success, err = pcall(function()
            economyStore:SetAsync(key, saveData)
        end)
        
        if success then
            return true
        else
            warn(string.format("[MoneyService] Save failed for %s (Attempt %d/%d): %s", player.Name, i, RETRY_MAX, tostring(err)))
            if i < RETRY_MAX then
                task.wait(1)
            end
        end
    end
    
    warn("[MoneyService] Gave up saving for " .. player.Name)
    return false
end

function MoneyService.ClearSession(player)
    sessionData[player] = nil
end

return MoneyService
