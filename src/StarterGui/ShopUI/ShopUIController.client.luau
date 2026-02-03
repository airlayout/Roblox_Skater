local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

print("[ShopUI] LocalScript started")

local UI_NAME = "ShopUI"
local REMOTE_FOLDER_NAME = "RemoteFunctions"

-- OpenShopUI RemoteEvent
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
if not remoteEvents then
    warn("[ShopUI] RemoteEvents folder missing")
    return
end
local openShopEvent = remoteEvents:WaitForChild("OpenShopUI", 10)
if not openShopEvent then
    warn("[ShopUI] OpenShopUI RemoteEvent missing")
    return
end

-- Remotes State
local Remotes = nil

-- --- LOGIC HELPERS ---

local function TryBindRemotes()
    local RemoteFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
    if not RemoteFolder then
        warn("[ShopUI] RemoteFunctions not found; UI will open without data/actions")
        Remotes = nil
        return
    end
    
    local getState = RemoteFolder:FindFirstChild("ShopGetState")
    local buy = RemoteFolder:FindFirstChild("ShopBuy")
    local equip = RemoteFolder:FindFirstChild("ShopEquip")
    local unequip = RemoteFolder:FindFirstChild("ShopUnequip")
    
    if getState and getState:IsA("RemoteFunction") then
        Remotes = { GetState = getState, Buy = buy, Equip = equip, Unequip = unequip }
        print("[ShopUI] Remotes bound")
    else
        warn("[ShopUI] ShopGetState missing or invalid")
        Remotes = nil
    end
end

-- --- UI GENERATION (Existing Logic) ---
local function CreateShopUI()
    local existing = PlayerGui:FindFirstChild(UI_NAME)
    if existing then return existing end
    
    local sg = Instance.new("ScreenGui")
    sg.Name = UI_NAME
    sg.ResetOnSpawn = false
    sg.Parent = PlayerGui
    
    -- Main Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.fromOffset(600, 400)
    mainFrame.Position = UDim2.fromScale(0.5, 0.5)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Visible = false
    mainFrame.Parent = sg
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame
    
    -- Title & Close Button... (Simplified for brevity but functionally same as before)
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Text = "  Item Shop"
    title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    title.TextColor3 = Color3.white
    title.Font = Enum.Font.GothamBold
    title.TextSize = 24
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = mainFrame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0,8)
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.fromOffset(30, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.Text = "X"
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeBtn.TextColor3 = Color3.white
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = mainFrame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,4)
    
    -- Content
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -20, 1, -60)
    content.Position = UDim2.fromOffset(10, 50)
    content.BackgroundTransparency = 1
    content.Parent = mainFrame
    
    -- Scroll List
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "ItemList"
    scroll.Size = UDim2.new(0.4, 0, 1, 0)
    scroll.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    scroll.Parent = content
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 5)
    layout.Parent = scroll
    
    -- Details
    local details = Instance.new("Frame")
    details.Name = "Details"
    details.Size = UDim2.new(0.58, 0, 1, 0)
    details.Position = UDim2.new(0.42, 0, 0, 0)
    details.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    details.Parent = content
    
    local itemName = Instance.new("TextLabel")
    itemName.Name = "ItemName"
    itemName.Text = "Select an item"
    itemName.Size = UDim2.new(1, -20, 0, 40)
    itemName.Position = UDim2.fromOffset(10, 10)
    itemName.TextColor3 = Color3.white
    itemName.BackgroundTransparency = 1
    itemName.Font = Enum.Font.GothamBold
    itemName.TextSize = 20
    itemName.Parent = details
    
    local itemPrice = Instance.new("TextLabel")
    itemPrice.Name = "ItemPrice"
    itemPrice.Text = ""
    itemPrice.Size = UDim2.new(1, -20, 0, 30)
    itemPrice.Position = UDim2.fromOffset(10, 50)
    itemPrice.TextColor3 = Color3.fromRGB(255, 200, 50)
    itemPrice.BackgroundTransparency = 1
    itemPrice.Font = Enum.Font.Gotham
    itemPrice.TextSize = 18
    itemPrice.Parent = details
    
    local actionBtn = Instance.new("TextButton")
    actionBtn.Name = "ActionButton"
    actionBtn.Text = "Buy"
    actionBtn.Size = UDim2.new(1, -40, 0, 50)
    actionBtn.Position = UDim2.new(0, 20, 1, -70)
    actionBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    actionBtn.TextColor3 = Color3.white
    actionBtn.Font = Enum.Font.GothamBold
    actionBtn.TextSize = 18
    actionBtn.Parent = details
    Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0,8)
    
    -- Connections
    closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)
    
    return sg
end

-- State
local currentCatalog = {}
local ownedItems = {}
local equippedSlots = {}
local selectedItemId = nil
local playerCoin = 0

local ShopGui = nil -- Lazy init

local function UpdateDetails()
    if not ShopGui then return end
    local Details = ShopGui.MainFrame.Content.Details
    
    if not selectedItemId then
        Details.ItemName.Text = "Select an Item"
        Details.ItemPrice.Text = ""
        Details.ActionButton.Visible = false
        return
    end
    
    local item = currentCatalog[selectedItemId]
    if not item then return end
    
    Details.ItemName.Text = item.displayName
    Details.ItemPrice.Text = "Price: " .. item.price .. " " .. item.currency
    Details.ActionButton.Visible = true
    
    if not ownedItems[selectedItemId] then
        Details.ActionButton.Text = "Buy (" .. item.price .. ")"
        Details.ActionButton.BackgroundColor3 = (playerCoin >= item.price) and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(100, 100, 100)
    else
        local slot = item.equipSlot
        local equippedItemInSlot = equippedSlots[slot]
        if equippedItemInSlot == selectedItemId then
            Details.ActionButton.Text = "Unequip"
            Details.ActionButton.BackgroundColor3 = Color3.fromRGB(200, 100, 50)
        else
            Details.ActionButton.Text = "Equip"
            Details.ActionButton.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
        end
    end
end

local function RefreshList()
    if not ShopGui then return end
    local Scroll = ShopGui.MainFrame.Content.ItemList
    
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    
    local sorted = {}
    for id, data in pairs(currentCatalog) do table.insert(sorted, data) end
    table.sort(sorted, function(a,b) return a.price < b.price end)
    
    for _, item in ipairs(sorted) do
        local btn = Instance.new("TextButton")
        btn.Name = item.id
        btn.Size = UDim2.new(1, -10, 0, 40)
        btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        btn.TextColor3 = Color3.white
        btn.Text = "  " .. item.displayName
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = Scroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)
        
        btn.MouseButton1Click:Connect(function()
            selectedItemId = item.id
            UpdateDetails()
        end)
    end
end

local function RefreshState()
    if not Remotes or not Remotes.GetState then
        warn("[ShopUI] RefreshState skipped: Remotes not ready")
        return
    end
    
    print("[ShopUI] RefreshState begin")
    local ok, result = pcall(function() return Remotes.GetState:InvokeServer() end)
    
    if not ok then
        warn("[ShopUI] GetState InvokeServer failed: " .. tostring(result))
        return
    end
    
    if result and result.ok then
        currentCatalog = result.data.catalog or {}
        ownedItems = result.data.ownedItems or {}
        equippedSlots = result.data.equippedSlots or {}
        playerCoin = result.data.coin or 0
        
        RefreshList()
        UpdateDetails()
        print("[ShopUI] RefreshState end ok")
    else
        warn("[ShopUI] Failed to get shop state: " .. tostring(result and result.errorCode))
    end
end

local function OnActionClicked()
    if not Remotes then
        warn("[ShopUI] Action ignored: Remotes not ready")
        return
    end
    if not selectedItemId then return end
    
    local Details = ShopGui.MainFrame.Content.Details
    Details.ActionButton.Text = "..."
    
    local item = currentCatalog[selectedItemId]
    
    if not ownedItems[selectedItemId] then
        -- Buy
        local hasBuy = Remotes.Buy and true or false
        if hasBuy then
             local res = Remotes.Buy:InvokeServer(selectedItemId)
             if res.ok or res.data then
                 if res.data.ownedDelta then
                     for k,v in pairs(res.data.ownedDelta) do ownedItems[k] = v end
                 end
                 if res.data.newCoin then playerCoin = res.data.newCoin end
             end
        end
    else
        -- Equip/Unequip
        local slot = item.equipSlot
        if equippedSlots[slot] == selectedItemId then
            if Remotes.Unequip then
                 local res = Remotes.Unequip:InvokeServer(slot)
                 if res.ok or res.data then
                      if res.data.equippedSlots then equippedSlots = res.data.equippedSlots end
                 end
            end
        else
            if Remotes.Equip then
                 local res = Remotes.Equip:InvokeServer(selectedItemId)
                 if res.ok or res.data then
                      if res.data.equippedSlots then equippedSlots = res.data.equippedSlots end
                 end
            end
        end
    end
    UpdateDetails()
end

-- --- EVENT LISTENER ---
openShopEvent.OnClientEvent:Connect(function()
    print("[ShopUI] OpenShopUI received")
    
    TryBindRemotes()
    
    if not ShopGui then
        ShopGui = CreateShopUI()
        -- Connect Action Button here to avoid dupes? Or just once
        local actionBtn = ShopGui.MainFrame.Content.Details.ActionButton
        actionBtn.MouseButton1Click:Connect(OnActionClicked)
    end
    
    local MainFrame = ShopGui.MainFrame
    
    if not Remotes then
        MainFrame.Content.Details.ActionButton.Visible = false
    end
    
    RefreshState()
    MainFrame.Visible = true
end)
