-- StarterPlayerScripts/RaceHudClient.client.lua
-- 目的: レース中のみ経過時間を表示 (00:12.34)、更新間隔0.1秒、Safe area対応
-- 前提: ReplicatedStorage.RemoteEvents.RaceStartEvent / RaceEndEvent が存在

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local remoteFolder = RS:WaitForChild("RemoteEvents")
local raceStartEvent = remoteFolder:WaitForChild("RaceStartEvent")
local raceEndEvent = remoteFolder:WaitForChild("RaceEndEvent")

-- UI参照（StarterGuiにRaceHUDがある前提。無い場合は警告して終了）
local function getHUD()
	local pg = player:WaitForChild("PlayerGui")

	local raceHUD = pg:FindFirstChild("RaceHUD")
	if not raceHUD then
		warn("[RaceHUD] RaceHUD not found in PlayerGui. Put StarterGui/RaceHUD (ScreenGui).")
		return nil
	end

	local topLeft = raceHUD:FindFirstChild("TopLeft")
	local timerFrame = topLeft and topLeft:FindFirstChild("TimerFrame")
	local timerText = timerFrame and timerFrame:FindFirstChild("TimerText")

	if not (topLeft and timerFrame and timerText) then
		warn("[RaceHUD] Missing UI nodes. Need: RaceHUD/TopLeft/TimerFrame/TimerText")
		return nil
	end

	return raceHUD, topLeft, timerFrame, timerText
end

local raceHUD, topLeft, timerFrame, timerText = getHUD()
if not raceHUD then
	return
end

-- 画面解像度差: 文字サイズ制約（任意だが推奨）
do
	local constraint = timerText:FindFirstChildOfClass("UITextSizeConstraint")
	if not constraint then
		constraint = Instance.new("UITextSizeConstraint")
		constraint.Parent = timerText
	end
	constraint.MinTextSize = 14
	constraint.MaxTextSize = 36
end

-- 状態
local running = false
local currentRaceId = nil
local startClock = 0
local acc = 0

-- 00:12.34 表示（切り捨て）
local function formatTime(elapsedSeconds)
	if elapsedSeconds < 0 then elapsedSeconds = 0 end

	local totalCentis = math.floor(elapsedSeconds * 100) -- 1/100秒
	local minutes = math.floor(totalCentis / (60 * 100))
	local centisLeft = totalCentis - minutes * 60 * 100
	local seconds = math.floor(centisLeft / 100)
	local centis = centisLeft - seconds * 100

	return string.format("%02d:%02d.%02d", minutes, seconds, centis)
end

local function showHUD(show)
	raceHUD.Enabled = show
end

-- 初期は非表示（待機/カウントダウン/ゴール後は表示しない）
showHUD(false)
timerText.Text = "00:00.00"

-- 0.1秒更新
RunService.Heartbeat:Connect(function(dt)
	if not running then return end

	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0

	local elapsed = os.clock() - startClock
	timerText.Text = formatTime(elapsed)
end)

-- RaceStart: raceId と raceStartServerTime を受け取る
raceStartEvent.OnClientEvent:Connect(function(raceId, raceStartServerTime)
	-- 多重イベント対策: 最新raceIdを採用
	currentRaceId = raceId
	running = true
	acc = 0
	startClock = os.clock() -- UIはクライアント計測でOK（仕様どおり）

	timerText.Text = "00:00.00"
	showHUD(true)

	-- 参考ログ（必要なら）
	-- print("[RaceHUD] RaceStart:", raceId, "serverTime:", raceStartServerTime)
end)

-- RaceEnd: ゴールしたプレイヤーだけ止める想定
-- サーバーは FireClient(player, raceId, finishTime?) で送るのがおすすめ
raceEndEvent.OnClientEvent:Connect(function(raceId, finishTime)
	-- raceIdが渡らない実装の可能性もあるのでケア
	if raceId ~= nil and currentRaceId ~= nil and raceId ~= currentRaceId then
		return
	end

	running = false
	currentRaceId = nil
	showHUD(false)

	-- ゴール後UIは出さない仕様。結果は別UI(例: RaceResultEvent)で出す想定
	-- print("[RaceHUD] RaceEnd:", raceId, "finishTime:", finishTime)
end)

