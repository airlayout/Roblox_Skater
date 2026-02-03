-- StarterPlayerScripts/SkateTrickClient
-- サーバーが許可したトリックだけ「見た目回転」を再生する（Motor6D.Transform）
-- 方針：板だけ回す（キャラ/HRPには触れない）

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteEvents = RS:WaitForChild("RemoteEvents")
local trickEvent = RemoteEvents:WaitForChild("SkateTrickEvent")

local function findBoardByUserId(userId)
	local folder = Workspace:FindFirstChild("RaceBoards")
	if not folder then return nil end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local owner = m:GetAttribute("OwnerUserId")
			if owner == userId then
				return m
			end
		end
	end
	return nil
end

local function getVisualRoot(board)
	local visual = board and board:FindFirstChild("Visual")
	local vr = visual and visual:FindFirstChild("VisualRoot")
	if vr and vr:IsA("BasePart") then return vr end
	return nil
end

local function getVisualJoint(board)
	local frame = board and board:FindFirstChild("Frame", true)
	local vr = getVisualRoot(board)
	if not frame or not vr then return nil end

	local joint = frame:FindFirstChild("VisualJoint")
	if joint and joint:IsA("Motor6D") then
		return joint
	end

	-- 保険：Part0/Part1一致で拾う
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 == frame and d.Part1 == vr then
			return d
		end
	end
	return nil
end

-- =========================
-- Trick FX
-- =========================

-- trickType -> ParticleEmitter名
local FX_BY_TRICK = {
	Spin360 = "TrickFX_Spin",
}

local function getTrickEmitter(board, emitterName)
	if not board then return nil end

	-- Visual配下を優先探索（trueで子孫も探索）
	local visual = board:FindFirstChild("Visual")
	if visual then
		local em = visual:FindFirstChild(emitterName, true)
		if em and em:IsA("ParticleEmitter") then
			return em
		end
	end

	-- 保険：ボード全体を探索
	local em = board:FindFirstChild(emitterName, true)
	if em and em:IsA("ParticleEmitter") then
		return em
	end

	return nil
end

local function playTrickFx(board, trickType)
	local emitterName = FX_BY_TRICK[trickType]
	if not emitterName then return end

	local emitter = getTrickEmitter(board, emitterName)
	if not emitter then
		warn("[TrickClient] FX emitter not found:", emitterName, "board=", board and board:GetFullName())
		return
	end

	-- Emit数は Attribute: BurstCount を優先（無ければ40）
	local burst = emitter:GetAttribute("BurstCount")
	if typeof(burst) ~= "number" then
		burst = 40
	end

	-- 念のため：継続発生を止める（Rate>0だと最初から出る）
	if emitter.Rate ~= 0 then
		emitter.Rate = 0
	end
	if emitter.Enabled == false then
		emitter.Enabled = true
	end

	emitter:Emit(burst)
end

-- userId -> { token=table, conn=RBXScriptConnection }
local activeByUserId = {}

local function stopSpin(userId)
	local st = activeByUserId[userId]
	if not st then return end
	if st.conn then
		st.conn:Disconnect()
	end
	activeByUserId[userId] = nil
end

local function playSpin360(userId, startAtServer, durationSec)
	
	local board = findBoardByUserId(userId)
	if not board then return end
	
	-- 追加：トリック開始の瞬間FX
	playTrickFx(board, "Spin360")
	
	local joint = getVisualJoint(board)
	if not joint then
		warn("[TrickClient] VisualJoint not found for userId=", userId)
		return
	end

	-- 既存再生を停止
	stopSpin(userId)

	local token = {}
	local base = joint.Transform

	local total = math.rad(360)
	local dur = tonumber(durationSec) or 0.3
	if dur <= 0 then dur = 0.3 end

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local st = activeByUserId[userId]
		if not st or st.token ~= token then
			if conn then conn:Disconnect() end
			return
		end

		local nowServer = workspace:GetServerTimeNow()
		local t = (nowServer - startAtServer) / dur

		if t >= 1 then
			joint.Transform = base
			stopSpin(userId)
			return
		end

		t = math.clamp(t, 0, 1)
		local yaw = total * t
		joint.Transform = base * CFrame.Angles(0, yaw, 0)
	end)

	activeByUserId[userId] = {
		token = token,
		conn = conn,
	}
end

trickEvent.OnClientEvent:Connect(function(mode, trickType, userId, startAtServer, durationSec)
	if mode ~= "Play" then return end
	if trickType ~= "Spin360" then return end
	if typeof(userId) ~= "number" then return end

	playSpin360(
		userId,
		tonumber(startAtServer) or workspace:GetServerTimeNow(),
		durationSec
	)
end)
