-- StarterPlayerScripts/RaceClient
-- レース招待の受信、参加・辞退ボタンのUI制御、カウントダウン表示を管理するクライアントスクリプト。
-- 方針: サーバから「残り秒(remainingSeconds)」を受け取り、クライアント側は受信時刻を基準にカウントダウンする。
-- 注意: サーバ側(RaceService)も RaceInviteEvent の引数を (inviteId, remainingSeconds) に変更している前提。

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- RemoteEvents
local RemoteEvents = RS:WaitForChild("RemoteEvents", 30)
if not RemoteEvents then
	warn("[RaceClient] RemoteEvents not found in ReplicatedStorage")
	return
end

local inviteEvent = RemoteEvents:WaitForChild("RaceInviteEvent", 30)
local joinEvent = RemoteEvents:WaitForChild("RaceJoinEvent", 30)

if not inviteEvent then
	warn("[RaceClient] RaceInviteEvent not found")
	return
end
if not joinEvent then
	warn("[RaceClient] RaceJoinEvent not found")
	return
end

-- State
local currentInviteId = 0
local countdownConnection = nil
local buttonWired = false

-- UI helpers
local function getGuiComponents()
	-- 期待構造:
	-- PlayerGui
	--  └ RaceInviteUI (ScreenGui)
	--     └ InviteFrame (Frame)
	--        ├ CountdownLabel (TextLabel)
	--        ├ StatusLabel (TextLabel)
	--        ├ YesButton (TextButton)
	--        └ NoButton (TextButton)
	local gui = PlayerGui:WaitForChild("RaceInviteUI", 30)
	if not gui then error("RaceInviteUI not found") end

	local frame = gui:WaitForChild("InviteFrame", 30)
	if not frame then error("InviteFrame not found") end

	local countLbl = frame:WaitForChild("CountdownLabel", 30)
	local statusLbl = frame:WaitForChild("StatusLabel", 30)
	local yesBtn = frame:WaitForChild("YesButton", 30)
	local noBtn = frame:WaitForChild("NoButton", 30)

	return frame, countLbl, statusLbl, yesBtn, noBtn
end

local function resetUI(statusLbl, yesBtn, noBtn)
	statusLbl.Text = "未選択"
	statusLbl.TextColor3 = Color3.fromRGB(200, 200, 200)

	yesBtn.Active = true
	yesBtn.AutoButtonColor = true
	yesBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 0)
	yesBtn.Text = "参加"

	noBtn.Active = true
	noBtn.AutoButtonColor = true
	noBtn.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
	noBtn.Text = "不参加"
end

local function disableButtons(yesBtn, noBtn)
	yesBtn.Active = false
	yesBtn.AutoButtonColor = false
	yesBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

	noBtn.Active = false
	noBtn.AutoButtonColor = false
	noBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
end

local function ensureButtonsWired()
	if buttonWired then return end
	local ok, err = pcall(function()
		local frame, _, statusLbl, yesBtn, noBtn = getGuiComponents()

		yesBtn.MouseButton1Click:Connect(function()
			if not yesBtn.Active then return end

			-- 参加意思を送信
			joinEvent:FireServer(currentInviteId)

			statusLbl.Text = "参加します（確定）"
			statusLbl.TextColor3 = Color3.fromRGB(0, 255, 0)

			disableButtons(yesBtn, noBtn)
		end)

		noBtn.MouseButton1Click:Connect(function()
			if not noBtn.Active then return end

			statusLbl.Text = "参加しません"
			statusLbl.TextColor3 = Color3.fromRGB(255, 0, 0)

			disableButtons(yesBtn, noBtn)
		end)

		-- 初期状態は非表示にしておく（好みで）
		frame.Visible = false
	end)

	if not ok then
		warn("[RaceClient] ensureButtonsWired failed:", err)
		return
	end

	buttonWired = true
end

local function stopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

local function startCountdown(frame, countLbl, durationSeconds)
	stopCountdown()

	local t0 = os.clock()
	local dur = math.max(0, tonumber(durationSeconds) or 0)

	countdownConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		local remaining = math.max(0, math.ceil(dur - elapsed))

		countLbl.Text = "開始まで " .. tostring(remaining) .. " 秒"

		if remaining <= 0 then
			frame.Visible = false
			stopCountdown()
		end
	end)
end


--[[
local function startCountdownToEndTime(frame, countLbl, endTimeServer)
	stopCountdown()
	local endT = tonumber(endTimeServer) or 0

	countdownConnection = RunService.RenderStepped:Connect(function()
		local nowServer = workspace:GetServerTimeNow()
		local remaining = math.max(0, math.ceil(endT - nowServer))
		countLbl.Text = "開始まで " .. tostring(remaining) .. " 秒"
		if remaining <= 0 then
			frame.Visible = false
			stopCountdown()
		end
	end)
end


-- ボタン接続はUIが来たら確実に行う（レプリケーション順の揺れに強くする）
task.spawn(function()
	while not buttonWired do
		ensureButtonsWired()
		if not buttonWired then
			task.wait(0.5)
		end
	end
end)
]]
-- 招待受信: (inviteId, remainingSeconds)
inviteEvent.OnClientEvent:Connect(function(inviteId, remainingSeconds)
	ensureButtonsWired()

	print("[RaceClient] invite:", inviteId, "remainingSeconds=", remainingSeconds, "type=", typeof(remainingSeconds))

	currentInviteId = tonumber(inviteId) or 0

	local raw = tonumber(remainingSeconds) or 0

	-- 防御：サーバーが「時刻」を送ってきた可能性に対応
	-- 例: Unix秒(1,700,000,000) や ServerTimeNow のような大きい値
	-- 「残り秒」は普通 0〜30(〜60)くらいの想定
	local remaining = raw

	-- 1) 明らかに大きすぎる -> 時刻とみなして変換を試みる
	if remaining > 360000 then
		-- ServerTimeNow 系かもしれないので、現在の server time を使って差分を取る
		-- ※クライアントでも GetServerTimeNow は呼べます（同期されたサーバー時刻）
		local nowServer = workspace:GetServerTimeNow()
		local diff = math.ceil(raw - nowServer)

		-- 差分が妥当ならそれを採用
		if diff >= 0 and diff <= 120 then
			remaining = diff
		else
			-- それでも変なら安全側に倒す（0にする or 最大値に丸める）
			warn("[RaceClient] remainingSeconds looks invalid. raw=", raw, "nowServer=", nowServer, "diff=", diff)
			remaining = 0
		end
	end

	-- 2) さらに念のため範囲クランプ（設計値に合わせて変更）
	remaining = math.clamp(remaining, 0, 60)

	local frame, countLbl, statusLbl, yesBtn, noBtn = getGuiComponents()

	resetUI(statusLbl, yesBtn, noBtn)
	frame.Visible = true

	startCountdown(frame, countLbl, remaining)
end)


print("[RaceClient] inviteEvent path:", inviteEvent:GetFullName())
print("[RaceClient] ready")
