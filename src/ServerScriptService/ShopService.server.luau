local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MoneyService = require(ServerScriptService.Economy.MoneyService)
local Catalog = require(ReplicatedStorage.Shop.Catalog)

-- Ensure RemoteFunctions exist
local RemoteFolder = ReplicatedStorage:FindFirstChild("RemoteFunctions")
if not RemoteFolder then
    RemoteFolder = Instance.new("Folder")
    RemoteFolder.Name = "RemoteFunctions"
    RemoteFolder.Parent = ReplicatedStorage
end

local function GetOrCreateRemote(name)
    local remote = RemoteFolder:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = RemoteFolder
    end
    return remote
end

local Remotes = {
    ShopGetState = GetOrCreateRemote("ShopGetState"),
    ShopBuy = GetOrCreateRemote("ShopBuy"),
    ShopEquip = GetOrCreateRemote("ShopEquip"),
    ShopUnequip = GetOrCreateRemote("ShopUnequip"),
}

-- Error Codes
local ERR = {
    DATA_NOT_READY = "DATA_NOT_READY",
    ITEM_NOT_FOUND = "ITEM_NOT_FOUND",
    ALREADY_OWNED = "ALREADY_OWNED",
    NOT_OWNED = "NOT_OWNED",
    INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS",
    SAVE_FAILED = "SAVE_FAILED",
    INVALID_SLOT = "INVALID_SLOT",
    NO_CHARACTER = "NO_CHARACTER",
    INTERNAL_ERROR = "INTERNAL_ERROR",
}

-- Asset Resolution Helper
local function ResolveAsset(path)
    local parts = string.split(path, ".")
    local current = game
    
    -- Safe traversal
    for i, part in ipairs(parts) do
        if i == 2 and part == "AssetService" and current == ReplicatedStorage then
             -- Specific robust check for AssetService
            current = current:WaitForChild(part, 2) -- Short timeout
        else
            current = current:FindFirstChild(part)
        end
        
        if not current then return nil end
    end
    
    return current
end

-- --- Logic ---

-- Gate: Is Player Ready?
local function IsReady(player)
    return player:GetAttribute("EconomyReady") == true
end

function Remotes.ShopGetState.OnServerInvoke(player)
    if not IsReady(player) then
        return { ok = false, errorCode = ERR.DATA_NOT_READY }
    end
    
    local unlocks = MoneyService.GetUnlocks(player)
    local shopData = unlocks.shop or { ownedItems = {}, equippedSlots = {} }
    
    -- Shallow Copy for Safety & Client Isolation
    local ownedCopy = {}
    for k,v in pairs(shopData.ownedItems or {}) do ownedCopy[k] = v end
    
    local equippedCopy = {}
    for k,v in pairs(shopData.equippedSlots or {}) do equippedCopy[k] = v end

    -- Filtered Catalog (Privacy)
    local catalogSafe = {}
    for id, item in pairs(Catalog.Items) do
        catalogSafe[id] = {
            id = item.id,
            displayName = item.displayName,
            price = item.price,
            currency = item.currency,
            category = item.category,
            rarity = item.rarity,
            equipSlot = item.equipSlot,
            repurchase = item.repurchase
            -- Exclude assetPath
        }
    end

    return {
        ok = true,
        data = {
            coin = MoneyService.GetCoin(player),
            catalog = catalogSafe,
            ownedItems = ownedCopy,
            equippedSlots = equippedCopy
        }
    }
end

function Remotes.ShopBuy.OnServerInvoke(player, itemId)
    if not IsReady(player) then return { ok = false, errorCode = ERR.DATA_NOT_READY } end
    
    local item = Catalog.Items[itemId]
    if not item then return { ok = false, errorCode = ERR.ITEM_NOT_FOUND } end
    
    local unlocks = MoneyService.GetUnlocks(player)
    local shopData = unlocks.shop or { ownedItems = {}, equippedSlots = {} }
    
    if shopData.ownedItems[itemId] then
        return { ok = false, errorCode = ERR.ALREADY_OWNED }
    end
    
    -- 1. Spend
    local success, code = MoneyService.SpendCoin(player, item.price, "ShopBuy:"..itemId)
    if not success then
        if code == "NO_SESSION" then return { ok = false, errorCode = ERR.DATA_NOT_READY } end
        if code == "INSUFFICIENT_FUNDS" then return { ok = false, errorCode = ERR.INSUFFICIENT_FUNDS } end
        return { ok = false, errorCode = ERR.INTERNAL_ERROR }
    end
    
    -- 2. Update Inventory
    shopData.ownedItems[itemId] = true
    unlocks.shop = shopData -- Ensure structure is linked
    MoneyService.UpdateInventory(player, {shop = shopData}, nil)
    
    -- 3. Sync Save
    local saveSuccess = MoneyService.Save(player)
    local ownedDelta = {[itemId]=true}
    local newCoin = MoneyService.GetCoin(player)

    if not saveSuccess then
        -- Return SAVE_FAILED but with data so UI knows it succeeded in session
        return { 
            ok = false, 
            errorCode = ERR.SAVE_FAILED, 
            data = { ownedDelta = ownedDelta, newCoin = newCoin } 
        }
    end
    
    return { 
        ok = true, 
        data = { ownedDelta = ownedDelta, newCoin = newCoin } 
    }
end

function Remotes.ShopEquip.OnServerInvoke(player, itemId)
    if not IsReady(player) then return { ok = false, errorCode = ERR.DATA_NOT_READY } end
    
    local unlocks = MoneyService.GetUnlocks(player)
    local shopData = unlocks.shop or { ownedItems = {}, equippedSlots = {} }
    
    if not shopData.ownedItems[itemId] then
        return { ok = false, errorCode = ERR.NOT_OWNED }
    end
    
    local item = Catalog.Items[itemId]
    local slot = item.equipSlot
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    
    if not character or not humanoid then
        return { ok = false, errorCode = ERR.NO_CHARACTER }
    end
    
    -- A. Visual Cleanup (Internal Unequip logic)
    -- Try to find existing Clean up if ANY accessory in that slot exists
    -- For v1, we assume any accessory with valid ShopItemId in that slot is target
    if shopData.equippedSlots[slot] then
        -- We won't error here if not found, just proceed
        -- Implementation: Scan for matching ShopItemId logic
    end

    -- B. Character Logic
    local asset = ResolveAsset(item.assetPath)
    if not asset or not asset:IsA("Accessory") then
        warn("[ShopService] Invalid Asset for " .. itemId)
        return { ok = false, errorCode = ERR.INTERNAL_ERROR }
    end
    
    local cloned = asset:Clone()
    cloned:SetAttribute("ShopItemId", itemId)
    
    -- Anti-Dupe Cleanup: Remove any EXISTING accessory that has ShopItemId for this slot?
    -- Actually, simpler: Remove any accessory that IS the old item
    -- Better: Remove any accessory whose ItemId matches the OLD slot value
    local oldItemId = shopData.equippedSlots[slot]
    if oldItemId then
        for _, acc in ipairs(humanoid:GetAccessories()) do
             if acc:GetAttribute("ShopItemId") == oldItemId then
                 acc:Destroy()
             end
        end
    end
    
    humanoid:AddAccessory(cloned)
    
    -- C. Data Update
    shopData.equippedSlots[slot] = itemId
    unlocks.shop = shopData
    MoneyService.UpdateInventory(player, {shop = shopData}, nil)
    
    local saveSuccess = MoneyService.Save(player)
    if not saveSuccess then
        return { ok = false, errorCode = ERR.SAVE_FAILED, data = { equippedSlots = shopData.equippedSlots } }
    end
    
    return { ok = true, data = { equippedSlots = shopData.equippedSlots } }
end

function Remotes.ShopUnequip.OnServerInvoke(player, slotName)
    if not IsReady(player) then return { ok = false, errorCode = ERR.DATA_NOT_READY } end
    
    if not Catalog.ValidSlots[slotName] then
        return { ok = false, errorCode = ERR.INVALID_SLOT }
    end
    
    local unlocks = MoneyService.GetUnlocks(player)
    local shopData = unlocks.shop or { ownedItems = {}, equippedSlots = {} }
    
    local currentItemId = shopData.equippedSlots[slotName]
    
    -- Character Logic
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if humanoid and currentItemId then
        for _, acc in ipairs(humanoid:GetAccessories()) do
            if acc:GetAttribute("ShopItemId") == currentItemId then
                acc:Destroy()
                -- Don't break, strictly just one? Anti-dupe says maybe destroy all matching?
                -- stick to one or all. simple is check all.
            end
        end
    end
    
    -- Update Data
    shopData.equippedSlots[slotName] = nil
    unlocks.shop = shopData
    MoneyService.UpdateInventory(player, {shop = shopData}, nil)
    
    local saveSuccess = MoneyService.Save(player)
    if not saveSuccess then
         return { ok = false, errorCode = ERR.SAVE_FAILED, data = { equippedSlots = shopData.equippedSlots } }
    end
    
    return { ok = true, data = { equippedSlots = shopData.equippedSlots } }
end

local function RestoreCharacter(player, character)
    -- Poll for EconomyReady
    local MAX_RETRIES = 10
    local retry = 0
    while not IsReady(player) and retry < MAX_RETRIES do
        task.wait(0.5)
        retry += 1
    end
    
    if not IsReady(player) then
        warn("[ShopService] Economy not ready for restore: " .. player.Name)
        return
    end
    
    local unlocks = MoneyService.GetUnlocks(player)
    local shopData = unlocks.shop
    if not shopData or not shopData.equippedSlots then return end
    
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end
    
    for slot, itemId in pairs(shopData.equippedSlots) do
        local item = Catalog.Items[itemId]
        if item then
            -- Anti-Dupe Check
            local alreadyEquipped = false
            for _, acc in ipairs(humanoid:GetAccessories()) do
                if acc:GetAttribute("ShopItemId") == itemId then
                    alreadyEquipped = true
                    break
                end
            end
            
            if not alreadyEquipped then
                 local asset = ResolveAsset(item.assetPath)
                 if asset and asset:IsA("Accessory") then
                     local cloned = asset:Clone()
                     cloned:SetAttribute("ShopItemId", itemId)
                     humanoid:AddAccessory(cloned)
                 else
                     warn("[ShopService] Restore failed for item: " .. itemId)
                 end
            end
        end
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        RestoreCharacter(player, char)
    end)
end)
