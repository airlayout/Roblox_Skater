local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local raceStartEvent = remoteEvents:WaitForChild("RaceStartEvent")

-- ワールド上のBillboardGuiを参照
local raceFolder = Workspace:WaitForChild("Race")
local startGate = raceFolder:WaitForChild("StartGate")
local billboard = startGate:WaitForChild("CountdownBillboard")
local label = billboard:WaitForChild("TextLabel")

local startTime = nil
local running = false

local function formatCountdown(sec)
	if sec <= 0 then
		return "GO"
	else
		return tostring(sec)
	end
end

local function stop()
	running = false
	label.Text = ""
end

raceStartEvent.OnClientEvent:Connect(function(serverStartTime)
	startTime = serverStartTime
	running = true
end)

RunService.RenderStepped:Connect(function()
	if not running or not startTime then
		return
	end

	local remain = startTime - Workspace:GetServerTimeNow()
	local sec = math.ceil(remain)

	label.Text = formatCountdown(sec)

	local state = Workspace:GetAttribute("RaceState")
	if (state == "Running") and (remain <= -0.3) then
		stop()
	end
end)

