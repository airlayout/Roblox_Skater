-- ServerScriptService/StartGateService.server.lua
-- 役割:
--  - RaceServiceが「テレポ完了」を Workspace Attribute で通知する
--  - それをトリガーにサーバー主導で StartTime を確定
--  - 全クライアントへStartTimeを通知（ワールドUI表示用）
--  - StartTime到来で GatePart を Destroy()
--
-- 前提:
--  - RaceService が beginRaceNow() の最後で
--      Workspace:SetAttribute("RaceTeleportDoneAt", Workspace:GetServerTimeNow())
--    を実行する
--  - ゲートパス: Workspace/Race/StartGate/GatePart
--  - RemoteEvent: ReplicatedStorage/RemoteEvents/RaceStartEvent を使用（無ければ作る）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ===== 設定 =====
local COUNTDOWN_SECONDS = 5
local GATE_PART_PATH = {"Race", "StartGate", "GatePart"}

-- ===== RemoteEvents 構成に合わせる =====
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local raceStartEvent = remoteEvents:FindFirstChild("RaceStartEvent")
if not raceStartEvent then
	raceStartEvent = Instance.new("RemoteEvent")
	raceStartEvent.Name = "RaceStartEvent"
	raceStartEvent.Parent = remoteEvents
end

-- ===== パス探索 =====
local function findByPath(root, pathArray)
	local cur = root
	for _, name in ipairs(pathArray) do
		if not cur then return nil end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

local function getGatePart()
	return findByPath(Workspace, GATE_PART_PATH)
end

-- ===== 内部状態 =====
local startedCountdown = false

-- 初期化（必要なら）
if Workspace:GetAttribute("RaceState") == nil then
	Workspace:SetAttribute("RaceState", "Waiting")
end
Workspace:SetAttribute("RaceStartTime", nil)

local function startCountdown()
	if startedCountdown then return end
	startedCountdown = true

	local gatePart = getGatePart()
	if not gatePart then
		warn("[StartGateService] GatePart not found at Workspace/" .. table.concat(GATE_PART_PATH, "/"))
	end

	Workspace:SetAttribute("RaceState", "Countdown")

	local startTime = Workspace:GetServerTimeNow() + COUNTDOWN_SECONDS
	Workspace:SetAttribute("RaceStartTime", startTime)

	-- 全員へ通知（UIはこれを受けて表示）
	raceStartEvent:FireAllClients(startTime)

	task.spawn(function()
		while Workspace:GetServerTimeNow() < startTime do
			task.wait(0.05)
		end

		Workspace:SetAttribute("RaceState", "Running")

		local gp = getGatePart()
		if gp and gp.Parent then
			gp:Destroy()
		else
			warn("[StartGateService] GatePart missing when trying to destroy (already destroyed or path mismatch).")
		end
	end)
end

-- ===== トリガー：RaceTeleportDoneAt が更新されたら開始 =====
-- RaceServiceがテレポ完了時刻を書き込む想定
Workspace:GetAttributeChangedSignal("RaceTeleportDoneAt"):Connect(function()
	-- 値が数値になった時だけ反応
	local t = Workspace:GetAttribute("RaceTeleportDoneAt")
	if typeof(t) ~= "number" then
		return
	end

	-- すでにCountdown/Runningなら無視（多重防止）
	local state = Workspace:GetAttribute("RaceState")
	if state == "Countdown" or state == "Running" then
		return
	end

	startCountdown()
end)

