-- ServerScriptService/RaceService
-- レースの招待サイクル、参加者管理、スケボーの配布およびテレポートを管理するサーバースクリプト。
--
-- 方針（着地補正を抜いた版 / トリックは見た目だけ・回転再生はクライアント）：
-- - LandingCorrectionAO / landingAssist / jumpYaw復帰 は全削除
-- - 転倒復帰・Yaw制限は維持
-- - トリックの判定（空中/ウィンドウ/クールダウン）はサーバー
-- - トリック再生（見た目回転）は trickEvent:FireAllClients("Play", ...) で通知してクライアントで再生


local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteEvents = RS:WaitForChild("RemoteEvents")
local inviteEvent = RemoteEvents:WaitForChild("RaceInviteEvent")
local joinEvent = RemoteEvents:WaitForChild("RaceJoinEvent")
local inputEvent = RemoteEvents:WaitForChild("SkateInputEvent")
local jumpEvent = RemoteEvents:WaitForChild("SkateJumpEvent")
local boostEvent = RemoteEvents:WaitForChild("BoostRequestEvent")

local ServerScriptService = game:GetService("ServerScriptService")

local RewardService = nil
do
	local ok, result = pcall(function()
		local econ = ServerScriptService:FindFirstChild("Economy")
		if not econ then
			warn("[RaceService] Economy folder not found. Trick rewards disabled.")
			return nil
		end
		local mod = econ:FindFirstChild("RewardService")
		if not mod then
			warn("[RaceService] RewardService not found. Trick rewards disabled.")
			return nil
		end
		return require(mod)
	end)

	if ok then
		RewardService = result
	else
		warn("[RaceService] Failed to require RewardService. Trick rewards disabled:", result)
		RewardService = nil
	end
end


-- Ensure SkateTrickEvent exists
local function ensureRemoteEvent(name)
	local re = RemoteEvents:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = RemoteEvents
	end
	return re
end

local trickEvent = ensureRemoteEvent("SkateTrickEvent")

local BoostSystem = require(script.Parent:WaitForChild("Modules"):WaitForChild("BoostSystem"))
local skateboardTemplate = RS:WaitForChild("Skateboard")

local currentInviteId = 0
local isInviting = false
local participants = {}
local inviteEndTimeServer = 0

local activeBoardByUserId = {}
local inputStateByUserId = {}
local jumpStateByUserId = {}

-- Trick State (server authority)
local trickWindowUntilByUserId = {}
local trickUsedByUserId = {}
local trickCooldownUntilByUserId = {}
local trickEndAtByUserId = {}

-- Trick Constants
local TRICK_WINDOW_SEC = 0.8
local TRICK_DURATION_SEC = 0.3
local TRICK_SPIN_DEG = 360
local TRICK_COOLDOWN_SEC = 0.2

print("[RaceService] boot:", script:GetFullName())
print("[RaceService] inviteEvent path:", inviteEvent:GetFullName())

local function getOrCreateRaceBoardsFolder()
	local folder = Workspace:FindFirstChild("RaceBoards")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RaceBoards"
		folder.Parent = Workspace
	end
	return folder
end

local function cleanUpBoards()
	local folder = getOrCreateRaceBoardsFolder()
	folder:ClearAllChildren()

	activeBoardByUserId = {}
	inputStateByUserId = {}
	jumpStateByUserId = {}

	trickWindowUntilByUserId = {}
	trickUsedByUserId = {}
	trickCooldownUntilByUserId = {}
	trickEndAtByUserId = {}
end

local function setJumpFlag(player, v)
	player:SetAttribute("JumpFlag", v)
end

local function applySideStance(player, board)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not board or not board.PrimaryPart then
		return
	end

	humanoid.AutoRotate = false
	player:SetAttribute("IsSkating", true)

	local boardCF = board.PrimaryPart.CFrame
	local boardLook = boardCF.LookVector
	local boardYaw = math.atan2(boardLook.X, boardLook.Z)

	local SIDE_SIGN = 1
	local targetYaw = boardYaw + SIDE_SIGN * math.rad(90)

	local currentPos = hrp.Position
	hrp.CFrame = CFrame.new(currentPos) * CFrame.Angles(0, targetYaw, 0)
end

local function removeSideStance(player)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	player:SetAttribute("IsSkating", nil)
	player:SetAttribute("JumpFlag", 0)
	player:SetAttribute("BoostActive", false)
end

local function onSeated(active, seatPart, player)
	if active then
		local board = activeBoardByUserId[player.UserId]
		if board and seatPart and seatPart:IsDescendantOf(board) then
			task.wait(0.1)
			applySideStance(player, board)
		end
	else
		removeSideStance(player)
	end
end

local function setupPlayerSeated(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Seated:Connect(function(active, seatPart)
				onSeated(active, seatPart, player)
			end)
		end
	end)

	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Seated:Connect(function(active, seatPart)
				onSeated(active, seatPart, player)
			end)
		end
	end
end

Players.PlayerAdded:Connect(setupPlayerSeated)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerSeated(player)
end

-- Input
local INPUT_TIMEOUT = 1.0

inputEvent.OnServerEvent:Connect(function(player, t, s)
	if type(t) ~= "number" then
		t = 0
	end
	if type(s) ~= "number" then
		s = 0
	end

	t = math.clamp(t, -1, 1)
	s = math.clamp(s, -1, 1)

	inputStateByUserId[player.UserId] = {
		throttle = t,
		steer = s,
		lastUpdate = os.clock(),
	}
end)

-- Jump
local MAX_JUMP_HEIGHT = 15.0

jumpEvent.OnServerEvent:Connect(function(player, charge01)
	if type(charge01) ~= "number" then
		return
	end
	charge01 = math.clamp(charge01, 0, 1)

	if player:GetAttribute("IsSkating") ~= true then
		return
	end

	-- Block double jump / air jump
	if jumpStateByUserId[player.UserId] and jumpStateByUserId[player.UserId].airborne then
		return
	end

	local board = activeBoardByUserId[player.UserId]
	if not board or not board.Parent or not board.PrimaryPart then
		return
	end
	local pp = board.PrimaryPart

	local g = workspace.Gravity
	local vMax = math.sqrt(2 * g * MAX_JUMP_HEIGHT)
	local v = vMax * charge01
	if v <= 0 then
		return
	end

	local impulse = Vector3.new(0, 1, 0) * (pp.AssemblyMass * v)
	pp:ApplyImpulse(impulse)

	setJumpFlag(player, 1)
	jumpStateByUserId[player.UserId] = jumpStateByUserId[player.UserId] or {}
	jumpStateByUserId[player.UserId].airborne = true

	-- Trick window start
	trickWindowUntilByUserId[player.UserId] = os.clock() + TRICK_WINDOW_SEC
	trickUsedByUserId[player.UserId] = false
end)

-- Trick: server validates, then broadcasts to clients to play visual-only trick
local function broadcastTrick(trickType, userId, durationSec)
	local startAtServer = workspace:GetServerTimeNow()
	trickEvent:FireAllClients("Play", trickType, userId, startAtServer, durationSec)
end

trickEvent.OnServerEvent:Connect(function(player, trickType)
	-- サーバーは「要求」だけ処理（クライアント再生通知とはモードで分離）
	if trickType ~= "Spin360" then
		return
	end

	local userId = player.UserId
	local now = os.clock()

	-- window
	if now > (trickWindowUntilByUserId[userId] or 0) then
		warn("[Trick] Rejected: Window expired. UserId=", userId)
		return
	end

	-- once per jump
	if trickUsedByUserId[userId] then
		warn("[Trick] Rejected: Already used. UserId=", userId)
		return
	end

	-- cooldown
	if now < (trickCooldownUntilByUserId[userId] or 0) then
		warn("[Trick] Rejected: Cooldown. UserId=", userId)
		return
	end

	local board = activeBoardByUserId[userId]
	if not board or not board.Parent or not board.PrimaryPart then
		warn("[Trick] Rejected: No board. UserId=", userId)
		return
	end

	-- Strict Airborne Check (Raycast)
	local pp = board.PrimaryPart
	local origin = pp.Position
	local dir = Vector3.new(0, -3.0, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { board, player.Character }

	local hit = Workspace:Raycast(origin, dir, params)
	if hit then
		warn("[Trick] Rejected: Grounded (Raycast). UserId=", userId)
		return
	end

	-- accept
	print("[Trick] Accepted: Spin360 (broadcast to clients). UserId=", userId)
	trickUsedByUserId[userId] = true
	trickCooldownUntilByUserId[userId] = now + TRICK_COOLDOWN_SEC
	trickEndAtByUserId[userId] = now + TRICK_DURATION_SEC
	
	
	
	broadcastTrick("Spin360", userId, TRICK_DURATION_SEC)
	
	-- 報酬は失敗してもゲームを止めない
	if RewardService and RewardService.GrantTrickReward then
		print("[TrickReward] before grant", player.Name, trickType, "race")
		local ok, amountOrErr = pcall(function()
			return RewardService.GrantTrickReward(player, "race", trickType)
		end)
		if ok then
			print("[TrickReward] granted amount=", amountOrErr, "coinNow=", player:GetAttribute("Coin"))
		else
			warn("[TrickReward] GrantTrickReward failed:", amountOrErr)
		end
	else
		warn("[TrickReward] GrantTrickReward not defined. Check RewardService.lua")
	end
	
	
end)



-- Boost request
boostEvent.OnServerEvent:Connect(function(player)
	if not player or not player.Parent then
		return
	end

	local isSkating = (player:GetAttribute("IsSkating") == true)
	if not isSkating then
		return
	end

	local js = jumpStateByUserId[player.UserId]
	local isAirborne = (js and js.airborne) == true

	BoostSystem.HandleRequest(player, isSkating, isAirborne)
end)

-- Begin race: spawn boards + teleport
local function beginRaceNow()
	cleanUpBoards()

	local boardsFolder = getOrCreateRaceBoardsFolder()
	local raceFolder = Workspace:FindFirstChild("Race")
	local courseFolder = raceFolder and raceFolder:FindFirstChild("Course1")
	local startSpawn = courseFolder and courseFolder:FindFirstChild("StartSpawn1")

	if not startSpawn then
		warn("[RaceService] StartSpawn1 not found")
		return
	end

	local spawnCFrame = startSpawn.CFrame * CFrame.new(0, 5, 0)
	local cols = 4
	local spacing = 6

	for i, player in ipairs(participants) do
		if not player.Parent then
			continue
		end

		local character = player.Character or player.CharacterAdded:Wait()
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not hrp or not humanoid then
			continue
		end

		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		local offset = CFrame.new(row * spacing, 0, col * spacing - (cols * spacing) / 2)

		local targetCF = spawnCFrame * offset
		hrp.CFrame = targetCF + Vector3.new(0, 2, 0)

		local board = skateboardTemplate:Clone()
		board.Name = "Board_" .. player.Name
		board:SetAttribute("OwnerUserId", player.UserId)
		board:PivotTo(targetCF + Vector3.new(0, 1.5, 0))
		board.Parent = boardsFolder

		activeBoardByUserId[player.UserId] = board

		BoostSystem.Add(player, 1)

		local seat = board:FindFirstChild("Seat")
		if seat and seat:IsA("VehicleSeat") then
			task.delay(0.1, function()
				if humanoid and humanoid.Health > 0 and seat.Parent then
					seat:Sit(humanoid)
				end
			end)
		end
	end

	local GoalSystem = require(script.Parent.Modules:WaitForChild("GoalSystem"))
	GoalSystem.SetParticipants(participants)

	Workspace:SetAttribute("RaceTeleportDoneAt", Workspace:GetServerTimeNow())
end

-- Invite
local function sendInviteToPlayer(player)
	if isInviting then
		inviteEvent:FireClient(player, currentInviteId, inviteEndTimeServer)
	end
end

local function startInvite()
	currentInviteId += 1
	local inviteId = currentInviteId
	local joinDuration = 5

	isInviting = true
	participants = {}

	inviteEndTimeServer = workspace:GetServerTimeNow() + joinDuration

	print(
		"[RaceService] FireAllClients",
		"script=", script:GetFullName(),
		"inviteId=", inviteId,
		"inviteEndTimeServer=", inviteEndTimeServer
	)

	inviteEvent:FireAllClients(inviteId, inviteEndTimeServer)

	task.wait(joinDuration)
	isInviting = false

	if #participants > 0 then
		beginRaceNow()
	end
end

joinEvent.OnServerEvent:Connect(function(player, inviteId)
	if isInviting
		and inviteId == currentInviteId
		and workspace:GetServerTimeNow() < inviteEndTimeServer
	then
		local found = false
		for _, p in ipairs(participants) do
			if p == player then
				found = true
				break
			end
		end
		if not found then
			table.insert(participants, player)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	-- 即時（招待中なら）
	sendInviteToPlayer(player)

	-- UI準備猶予でもう一度
	task.delay(1, function()
		if player.Parent then
			sendInviteToPlayer(player)
		end
	end)
end)

-- Physics constants
local MAX_SPEED = 100
local ACCEL = 220
local TURN_RATE = 2.0
local DRAG = 0.97

-- Auto recover settings
local FALL_UPY_THRESHOLD = 0.25
local FALL_HOLD_SECONDS = 0.5
local RECOVER_DELAY = 0.5
local RECOVER_LIFT = 2.0
local RECOVER_DAMP = 0.2

-- Yaw clamp / smoothing settings
local MAX_YAW_RATE_DEG = 180
local MAX_YAW_RATE_AIR_DEG = 360
local YAW_SLEW_DEG = 720
local MAX_ROLL_RATE_DEG = 20

RunService.Heartbeat:Connect(function(dt)
	for userId, board in pairs(activeBoardByUserId) do
		if not board or not board.Parent or not board.PrimaryPart then
			continue
		end

		local pp = board.PrimaryPart
		local now = os.clock()

		-- Trick state
		local trickEnd = trickEndAtByUserId[userId] or 0
		local isTricking = (now < trickEnd)

		-- Jump state init
		local stJump = jumpStateByUserId[userId]
		if not stJump then
			stJump = { airborne = false }
			jumpStateByUserId[userId] = stJump
		end

		-- Input
		local st = inputStateByUserId[userId]
		local throttle = 0
		local steer = 0
		if st and (now - (st.lastUpdate or 0)) <= INPUT_TIMEOUT then
			throttle = tonumber(st.throttle) or 0
			steer = tonumber(st.steer) or 0
		end

		-- Server-owned physics
		if pp:GetNetworkOwner() ~= nil then
			pp:SetNetworkOwner(nil)
		end

		-- Ground check
		local origin = pp.Position
		local dir = Vector3.new(0, -4.0, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { board }

		local hit = Workspace:Raycast(origin, dir, params)

		local grounded = false
		if hit then
			local dist = (origin - hit.Position).Magnitude
			if dist <= 1.2 and math.abs(pp.AssemblyLinearVelocity.Y) < 5 then
				grounded = true
			end
		end

		-- Landing detect
		if stJump.airborne and grounded then
			stJump.airborne = false
			local plr = Players:GetPlayerByUserId(userId)
			if plr then
				setJumpFlag(plr, 0)
			end
		end

		-- Linear velocity
		local boostMul = 1.0
		local accelMul = 1.0
		if BoostSystem.IsActive(userId) then
			boostMul = 2.0
			accelMul = 2.0
		end

		local airMul = 1.0
		if stJump.airborne then
			airMul = 1.5
		end

		local maxSpeedNow = MAX_SPEED * airMul * boostMul
		local accelNow = ACCEL * accelMul

		local lv = pp.CFrame.LookVector
		local forward = Vector3.new(lv.X, 0, lv.Z)
		if forward.Magnitude > 1e-6 then
			forward = forward.Unit
		else
			forward = Vector3.new(0, 0, -1)
		end

		local curVel = pp.AssemblyLinearVelocity
		local horizVel = Vector3.new(curVel.X, 0, curVel.Z) * DRAG
		local added = forward * (throttle * accelNow * dt)
		local newHoriz = horizVel + added

		if newHoriz.Magnitude > maxSpeedNow then
			newHoriz = newHoriz.Unit * maxSpeedNow
		end

		pp.AssemblyLinearVelocity = Vector3.new(newHoriz.X, curVel.Y, newHoriz.Z)

		-- Angular control
		local curAV = pp.AssemblyAngularVelocity
		local airborne = (stJump.airborne == true)

		if isTricking then
			-- Trick中：物理回転は抑える（見た目回転はクライアントで再生）
			local dampXZ = 0.15
			pp.AssemblyAngularVelocity = Vector3.new(curAV.X * dampXZ, curAV.Y, curAV.Z * dampXZ)

			local js = jumpStateByUserId[userId]
			js.fallStartAt = 0
			js.recoverAt = 0
		else
			-- Fall detect & recover
			local js = jumpStateByUserId[userId]
			js.fallStartAt = js.fallStartAt or 0
			js.recoverAt = js.recoverAt or 0

			local upY = pp.CFrame.UpVector.Y
			local isFalling = (upY < FALL_UPY_THRESHOLD)

			if not airborne then
				if isFalling then
					if js.fallStartAt == 0 then
						js.fallStartAt = now
					end
					if (now - js.fallStartAt) >= FALL_HOLD_SECONDS then
						if js.recoverAt == 0 then
							js.recoverAt = now + RECOVER_DELAY
						end
					end
				else
					js.fallStartAt = 0
					js.recoverAt = 0
				end
			else
				js.fallStartAt = 0
				js.recoverAt = 0
			end

			if js.recoverAt ~= 0 and now >= js.recoverAt then
				local pos = pp.Position + Vector3.new(0, RECOVER_LIFT, 0)
				local look = pp.CFrame.LookVector
				local yaw = math.atan2(look.X, look.Z)
				local fixedCF = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

				board:PivotTo(fixedCF)

				local v = pp.AssemblyLinearVelocity
				pp.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z) * RECOVER_DAMP
				pp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

				js.fallStartAt = 0
				js.recoverAt = 0
				continue
			end

			-- 通常時：Yaw clamp + smoothing（steerで回す）
			local desiredYaw = -steer * TURN_RATE
			local maxYawRad = math.rad(airborne and MAX_YAW_RATE_AIR_DEG or MAX_YAW_RATE_DEG)
			desiredYaw = math.clamp(desiredYaw, -maxYawRad, maxYawRad)

			local maxDelta = math.rad(YAW_SLEW_DEG) * dt
			local yawNow = curAV.Y
			local yawNext = yawNow + math.clamp(desiredYaw - yawNow, -maxDelta, maxDelta)

			local maxRollRad = math.rad(MAX_ROLL_RATE_DEG)
			local rollNow = curAV.Z
			local rollNext = math.clamp(rollNow, -maxRollRad, maxRollRad)

			local outX, outY, outZ
			if grounded and (not airborne) then
				outX = 0
				outY = yawNext
				outZ = rollNext * 0.5
			else
				outX = curAV.X * 0.8
				outY = yawNext
				outZ = rollNext * 0.8
			end

			pp.AssemblyAngularVelocity = Vector3.new(outX, outY, outZ)

			local v = pp.AssemblyLinearVelocity
			pp.AssemblyLinearVelocity = Vector3.new(v.X * 0.995, v.Y, v.Z * 0.995)
		end
	end
end)

-- Invite loop
task.spawn(function()
	while true do
		task.wait(10)

		local ok, err = pcall(function()
			print("[RaceService] startInvite tick. players=", #Players:GetPlayers())
			startInvite()
			print("[RaceService] startInvite done.")
		end)

		if not ok then
			warn("[RaceService] startInvite crashed:", err)
		end

		task.wait(120)
	end
end)
