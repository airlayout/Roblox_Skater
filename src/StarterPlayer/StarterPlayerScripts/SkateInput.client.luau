-- StarterPlayerScripts/SkateInput
-- 入力をサーバーへ送るだけ（サーバー主導物理）

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local inputEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SkateInputEvent")

local lastSentThrottle = 0
local lastSentSteer = 0
local lastSendTime = 0

local SEND_INTERVAL = 0.1 -- 押しっぱなしでも定期送信

local function readKeys()
	local t = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then t = t + 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then t = t - 1 end

	local s = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then s = s - 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then s = s + 1 end

	return t, s
end

local function sendIfNeeded(force)
	local isSkating = (player:GetAttribute("IsSkating") == true)
	local now = os.clock()

	if not isSkating then
		-- 降車/未参加時は 0,0 を1回だけ送る
		if lastSentThrottle ~= 0 or lastSentSteer ~= 0 then
			inputEvent:FireServer(0, 0)
			lastSentThrottle = 0
			lastSentSteer = 0
			lastSendTime = now
		end
		return
	end

	local t, s = readKeys()

	local needSend =
		force
		or (t ~= lastSentThrottle)
		or (s ~= lastSentSteer)
		or ((now - lastSendTime) >= SEND_INTERVAL)

	if needSend then
		inputEvent:FireServer(t, s)
		lastSentThrottle = t
		lastSentSteer = s
		lastSendTime = now
	end
end

-- 押した/離した瞬間は即送信
UserInputService.InputBegan:Connect(function()
	sendIfNeeded(true)
end)

UserInputService.InputEnded:Connect(function()
	sendIfNeeded(true)
end)

-- 取りこぼし防止＆押しっぱなし維持
RunService.Heartbeat:Connect(function()
	sendIfNeeded(false)
end)
