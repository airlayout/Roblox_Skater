-- StarterPlayerScripts/SkateJump
-- Space長押しによるジャンプチャージ、ゲージUIの表示、およびジャンプイベントの送信を行う。


local USE_CHARGE = false -- true に戻せばチャージ式に戻る


local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local jumpEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SkateJumpEvent")
local trickEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SkateTrickEvent")

local TRICK_WINDOW_SEC = 0.8
local trickLocalWindowUntil = 0
local trickLocalUsed = false
local suppressJumpRelease = false

print("[SkateJump] Script starting...")

-- ===== パラメータ =====
local CHARGE_TIME = 0.2 -- 秒で100%
local charging = false
local chargeStart = 0
local charge01 = 0

-- ===== UI生成（右側・縦ゲージ・黒背景・黄緑Fill） =====
local function createUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SkateJumpUI"
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")

    local holder = Instance.new("Frame")
    holder.Name = "GaugeHolder"
    holder.AnchorPoint = Vector2.new(1, 0.5)
    holder.Position = UDim2.new(0.5, 200, 0.5, 0) -- 画面右側
    holder.Size = UDim2.new(0, 18, 0, 160)
    holder.BackgroundColor3 = Color3.new(0, 0, 0) -- 黒
    holder.BorderSizePixel = 0
    holder.Parent = gui

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(40, 40, 40)
    stroke.Parent = holder

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.Size = UDim2.new(1, 0, 0, 0)
    fill.BackgroundColor3 = Color3.fromRGB(160, 255, 120) -- 黄緑
    fill.BorderSizePixel = 0
    fill.Parent = holder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = holder

    local corner2 = Instance.new("UICorner")
    corner2.CornerRadius = UDim.new(0, 6)
    corner2.Parent = fill

    print("[SkateJump] UI Created.")
    return gui, fill
end

local ui, fillFrame = createUI()

local function setGauge(v01)
    v01 = math.clamp(v01, 0, 1)
    fillFrame.Size = UDim2.new(1, 0, v01, 0) -- 縦に伸びる
end

local function setUIVisible(on)
    if ui.Enabled ~= on then
        ui.Enabled = on
    end
end

-- 初期状態
setUIVisible(false)

-- ===== 入力 =====
UserInputService.InputBegan:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.Space then
        local isSkating = player:GetAttribute("IsSkating") == true
        
        -- FIX: DisableDefaultJump が入力を Sink しているため、gpe は常に true になります。
        -- ジャンプ操作のために、ここでは gpe を無視して処理を続行します。
        if not isSkating then return end
		
		-- Trick Logic
		local now = os.clock()
		print("Space Press: Skat=", isSkating, "Win=", trickLocalWindowUntil-now, "Used=", trickLocalUsed)
		
		if now < trickLocalWindowUntil and not trickLocalUsed then
			trickEvent:FireServer("Spin360")
			trickLocalUsed = true
			suppressJumpRelease = true
			print("[SkateJump] Fired Trick: Spin360")
			return -- Skip charge
		end
		
		-- ★固定ジャンプは「押した瞬間」に跳ぶ
		if not USE_CHARGE then
			jumpEvent:FireServer(1)
			print("[SkateJump] Fixed Jump Fired on InputBegan")

			-- UIは出さない
			setGauge(0)
			setUIVisible(false)
			charging = false
			charge01 = 0

			-- トリック窓を開始（※仕様：ジャンプ発火後もトリックできる）
			trickLocalWindowUntil = os.clock() + TRICK_WINDOW_SEC
			trickLocalUsed = false

			return
		end

		charging = true

		if USE_CHARGE then
			chargeStart = os.clock()
			charge01 = 0
			setUIVisible(true)
			print("[SkateJump] Charge Started")
		else
			-- 固定ジャンプ：押した瞬間から「100%」扱い
			chargeStart = 0
			charge01 = 1
			setGauge(0)
			setUIVisible(false)
			print("[SkateJump] Fixed Jump Prepared")
		end
    end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.Space then
		if suppressJumpRelease then
			suppressJumpRelease = false
			return
		end
		
        if not charging then return end

        charging = false
		if USE_CHARGE then
			jumpEvent:FireServer(charge01)
			print("[SkateJump] Sent Jump Event with charge:", charge01)
		else
			-- 固定ジャンプは InputBegan で発火済み
			print("[SkateJump] Fixed Jump: already fired on InputBegan")
		end
        print("[SkateJump] Sent Jump Event with charge:", charge01)
		
		-- Start Trick Window
		trickLocalWindowUntil = os.clock() + TRICK_WINDOW_SEC
		trickLocalUsed = false

        charge01 = 0
        setGauge(0)
        setUIVisible(false)
    end
end)

-- ===== チャージ更新 =====
RunService.RenderStepped:Connect(function()
    local isSkating = (player:GetAttribute("IsSkating") == true)
    
    if charging and not isSkating then
        charging = false
        charge01 = 0
        setGauge(0)
        setUIVisible(false)
        return
    end

	if charging and USE_CHARGE then
        local t = (os.clock() - chargeStart) / CHARGE_TIME
        charge01 = math.clamp(t, 0, 1)
        setGauge(charge01)
    end
end)
