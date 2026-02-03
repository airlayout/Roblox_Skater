-- StarterPlayerScripts/BoostClient
-- ブーストボタン(B/左クリック)の入力検知と、ストック数のUI表示を行う。

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local boostEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("BoostRequestEvent")

-- ==== UI（下中央、最大5個） ====
local function createUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "BoostUI"
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")

    local holder = Instance.new("Frame")
    holder.Name = "Holder"
    holder.AnchorPoint = Vector2.new(0.5, 1)
    holder.Position = UDim2.new(0.5, 0, 1, -40)
    holder.Size = UDim2.new(0, 260, 0, 50)
    holder.BackgroundTransparency = 1
    holder.Parent = gui

    local icons = {}
    local gap = 10
    local size = 36
    local totalW = 5 * size + 4 * gap
    local startX = (holder.Size.X.Offset - totalW) / 2

    for i = 1, 5 do
        local f = Instance.new("Frame")
        f.Name = "Icon" .. i
        f.Size = UDim2.new(0, size, 0, size)
        f.Position = UDim2.new(0, startX + (i - 1) * (size + gap), 0, 7)
        f.BackgroundColor3 = Color3.fromRGB(255, 120, 40) -- 仮の炎色（四角）
        f.BorderSizePixel = 0
        f.Visible = false
        f.Parent = holder

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = f

        local s = Instance.new("UIStroke")
        s.Thickness = 2
        s.Color = Color3.fromRGB(40, 40, 40)
        s.Parent = f

        icons[i] = f
    end

    return gui, icons
end

local ui, icons = createUI()

local function refresh()
    local isSkating = (player:GetAttribute("IsSkating") == true)
    ui.Enabled = isSkating

    local stock = player:GetAttribute("BoostStock") or 0
    stock = math.clamp(stock, 0, 5)

    for i = 1, 5 do
        icons[i].Visible = (isSkating and i <= stock)
    end
end

player:GetAttributeChangedSignal("BoostStock"):Connect(refresh)
player:GetAttributeChangedSignal("IsSkating"):Connect(refresh)
refresh()

-- ==== 入力（B or 左クリック） ====
local lastLocalFire = 0
local LOCAL_CD = 0.12 -- クールダウンはServer確定だが、連打抑制として軽く入れる

local function tryBoost()
    if player:GetAttribute("IsSkating") ~= true then return end

    local now = os.clock()
    if now - lastLocalFire < LOCAL_CD then return end
    lastLocalFire = now

    boostEvent:FireServer()
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end

    if input.KeyCode == Enum.KeyCode.B then
        tryBoost()
    end

    -- 左クリック
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        tryBoost()
    end
end)
