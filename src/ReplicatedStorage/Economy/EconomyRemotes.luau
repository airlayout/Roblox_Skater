-- ReplicatedStorage/Economy/EconomyRemotes
local EconomyRemotes = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_FOLDER_NAME = "RemoteEvents"

-- Ensure RemoteEvents folder exists (Client can only wait, Server creates)
local function getRemoteFolder()
    local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
    if not folder then
        if RunService:IsServer() then
            folder = Instance.new("Folder")
            folder.Name = REMOTE_FOLDER_NAME
            folder.Parent = ReplicatedStorage
        else
            folder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
        end
    end
    return folder
end

local function getOrCreateRemoteFunction(name)
    local folder = getRemoteFolder()
    local rf = folder:FindFirstChild(name)
    if not rf then
        if RunService:IsServer() then
            rf = Instance.new("RemoteFunction")
            rf.Name = name
            rf.Parent = folder
        else
            rf = folder:WaitForChild(name)
        end
    end
    return rf
end

local function getOrCreateRemoteEvent(name)
    local folder = getRemoteFolder()
    local re = folder:FindFirstChild(name)
    if not re then
        if RunService:IsServer() then
            re = Instance.new("RemoteEvent")
            re.Name = name
            re.Parent = folder
        else
            re = folder:WaitForChild(name)
        end
    end
    return re
end

-- Public Accessors
function EconomyRemotes.GetShopPurchaseRequest()
    return getOrCreateRemoteFunction("ShopPurchaseRequest")
end

function EconomyRemotes.GetMoneyChangedEvent()
    return getOrCreateRemoteEvent("MoneyChangedEvent")
end

-- Ensuring other related remotes exist (Optional helper)
function EconomyRemotes.EnsureRaceResultEvent()
    return getOrCreateRemoteEvent("RaceResultEvent")
end

return EconomyRemotes
