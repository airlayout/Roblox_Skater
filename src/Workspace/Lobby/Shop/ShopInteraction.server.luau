local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LOBBY_PATH = "Lobby"
local SHOP_PATH = "Shop"

-- RemoteEvent: OpenShopUI
local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remoteEvents then
    remoteEvents = Instance.new("Folder")
    remoteEvents.Name = "RemoteEvents"
    remoteEvents.Parent = ReplicatedStorage
end

local openShopEvent = remoteEvents:FindFirstChild("OpenShopUI")
if not openShopEvent then
    openShopEvent = Instance.new("RemoteEvent")
    openShopEvent.Name = "OpenShopUI"
    openShopEvent.Parent = remoteEvents
end

local function SetupShopInteraction()
    local lobby = Workspace:FindFirstChild(LOBBY_PATH)
    if not lobby then
        warn("[ShopInteraction] Lobby not found")
        return
    end
    
    local shopFolder = lobby:FindFirstChild(SHOP_PATH)
    if not shopFolder then
        shopFolder = Instance.new("Folder")
        shopFolder.Name = SHOP_PATH
        shopFolder.Parent = lobby
    end
    
    local PART_NAME = "ShopPart"
    local existingPart = shopFolder:FindFirstChild(PART_NAME)
    
    local shopPart = existingPart or Instance.new("Part")
    if not existingPart then
        shopPart.Name = PART_NAME
        shopPart.Size = Vector3.new(4, 1, 4)
        
        local baseCFrame
        if lobby.PrimaryPart then
            baseCFrame = lobby.PrimaryPart.CFrame
        else
            baseCFrame = lobby:GetPivot()
            warn("[ShopInteraction] Lobby.PrimaryPart is nil; using lobby:GetPivot()")
        end
        
        shopPart.CFrame = baseCFrame * CFrame.new(10, 2, 0)
        shopPart.Anchored = true
        shopPart.CanCollide = true
        shopPart.BrickColor = BrickColor.new("Bright yellow")
        shopPart.Material = Enum.Material.Neon
        shopPart.Parent = shopFolder
    end
    
    local PROMPT_NAME = "ShopPrompt"
    local existingPrompt = shopPart:FindFirstChild(PROMPT_NAME)
    
    local prompt = existingPrompt or Instance.new("ProximityPrompt")
    if not existingPrompt then
        prompt.Name = PROMPT_NAME
        prompt.ObjectText = "Shop"
        prompt.ActionText = "Open Shop"
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.MaxActivationDistance = 10
        prompt.HoldDuration = 0.5
        prompt.Parent = shopPart
    end
    
    print("[ShopInteraction] Shop Part & Prompt set up at " .. shopPart:GetFullName() .. " pos=" .. tostring(shopPart.Position))
end

-- Connect Listener
local connected = false
local function ConnectPromptListener()
    if connected then return end
    connected = true
    
    ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if prompt and prompt.Name == "ShopPrompt" then
            print("[ShopInteraction] PromptTriggered: " .. prompt:GetFullName() .. " by " .. player.Name)
            openShopEvent:FireClient(player)
        end
    end)
end

SetupShopInteraction()
ConnectPromptListener()
