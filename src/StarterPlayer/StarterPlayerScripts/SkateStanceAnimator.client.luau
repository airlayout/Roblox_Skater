-- StarterPlayerScripts/SkateStanceAnimator
-- IsSkating で SkateStance をループ再生
-- SkateTrickEvent("Play", trickType, userId, startAtServer, durationSec) を受けたら
-- TrickStance を最優先で割り込み再生し、終了後に SkateStance へ復帰

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local animationsFolder = ReplicatedStorage:WaitForChild("Animations")
local skateAnimAsset = animationsFolder:WaitForChild("SkateStance")
local trickAnimAsset = animationsFolder:WaitForChild("TrickStance")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local trickEvent = remoteEvents:WaitForChild("SkateTrickEvent")

local skateTrack = nil
local trickTrack = nil

local isSkatePlaying = false
local isTrickPlaying = false

local trickEndAtServerTime = 0

local function getAnimator()
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChild("Animator")
	return animator
end

local function stopSkate()
	if skateTrack then
		skateTrack:Stop()
	end
	isSkatePlaying = false
end

local function stopTrick()
	if trickTrack then
		trickTrack:Stop()
	end
	isTrickPlaying = false
	trickEndAtServerTime = 0
end

local function ensureTracks(animator)
	if not skateTrack then
		skateTrack = animator:LoadAnimation(skateAnimAsset)
		skateTrack.Priority = Enum.AnimationPriority.Action
		skateTrack.Looped = true
	end

	if not trickTrack then
		trickTrack = animator:LoadAnimation(trickAnimAsset)
		-- Trick中は最優先で上書きしたいので Skate より高い Priority にする
		trickTrack.Priority = Enum.AnimationPriority.Action4
		trickTrack.Looped = false
	end
end

local function playSkateIfNeeded()
	-- Trick中は絶対に Skate を流さない（最優先の要件）
	if isTrickPlaying then
		return
	end

	local isSkating = (player:GetAttribute("IsSkating") == true)
	if not isSkating then
		if isSkatePlaying then
			stopSkate()
		end
		return
	end

	local animator = getAnimator()
	if not animator then return end
	ensureTracks(animator)

	if not isSkatePlaying then
		skateTrack:Play()
		isSkatePlaying = true
	end
end

local function playTrickForDuration(startAtServer, durationSec)
	local animator = getAnimator()
	if not animator then return end
	ensureTracks(animator)

	-- 既に Skate が流れていたら止める（割り込み）
	if isSkatePlaying then
		stopSkate()
	end

	-- 既に Trick が流れていても、開始時刻を更新して延長/上書き（最新を優先）
	local nowServer = Workspace:GetServerTimeNow()
	local elapsed = nowServer - startAtServer
	local remaining = durationSec - elapsed
	if remaining <= 0 then
		-- 受信が遅すぎて既に終わっている
		return
	end

	trickEndAtServerTime = nowServer + remaining

	-- 再生
	if trickTrack.IsPlaying then
		trickTrack:Stop()
	end
	trickTrack:Play()
	isTrickPlaying = true

	-- 終了管理：サーバー時刻ベースで終わったら復帰
	task.spawn(function()
		while isTrickPlaying do
			local t = Workspace:GetServerTimeNow()
			if trickEndAtServerTime > 0 and t >= trickEndAtServerTime then
				break
			end
			task.wait(0.03)
		end

		if isTrickPlaying then
			stopTrick()
			-- まだ滑走中なら Skate に復帰
			playSkateIfNeeded()
		end
	end)
end

-- Trick Event
trickEvent.OnClientEvent:Connect(function(cmd, trickType, userId, startAtServer, durationSec)
	if cmd ~= "Play" then return end
	if userId ~= player.UserId then return end
	if type(startAtServer) ~= "number" then return end
	if type(durationSec) ~= "number" then return end

	-- Trick中は最優先で TrickStance を流す
	playTrickForDuration(startAtServer, durationSec)
end)

-- IsSkating change
player:GetAttributeChangedSignal("IsSkating"):Connect(function()
	-- Trick中は Skate を絶対に出さない
	if isTrickPlaying then
		-- IsSkating が false になった場合は Trick も止める方針にするならここで止める
		local isSkating = (player:GetAttribute("IsSkating") == true)
		if not isSkating then
			stopTrick()
			stopSkate()
		end
		return
	end

	playSkateIfNeeded()
end)

-- Reset on spawn
player.CharacterAdded:Connect(function()
	skateTrack = nil
	trickTrack = nil
	isSkatePlaying = false
	isTrickPlaying = false
	trickEndAtServerTime = 0

	-- 少し待ってから初期状態を反映
	task.wait(0.2)
	playSkateIfNeeded()
end)

-- Initial
task.wait(0.5)
playSkateIfNeeded()
