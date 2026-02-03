-- StarterPlayerScripts/SkateCamera
-- IsSkating中はボード後方カメラ（Scriptable）に切替。降りたら標準に戻す。
-- 追加仕様：JumpFlag==1（空中）の間はカメラYawを固定して、トリック回転でカメラが回らないようにする。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local lastIsSkating = false

-- カメラオフセット（好みで調整）
local HEIGHT = 6
local BACK = 14
local LOOK_AHEAD = 8
local SMOOTH = 12 -- 大きいほど追従が早い（6〜20目安）

-- 空中Yawロック用
local wasAirborne = false
local lockedYaw = nil

local function yawFromForward(forward)
	return math.atan2(forward.X, forward.Z)
end

local function forwardFromYaw(yaw)
	-- yaw=atan2(x,z) と逆変換
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function getBoardPrimaryPart()
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local seatPart = humanoid.SeatPart
	if not seatPart or not seatPart:IsA("VehicleSeat") then return nil end

	local board = seatPart:FindFirstAncestorOfClass("Model")
	if not board or not board.PrimaryPart then return nil end

	return board.PrimaryPart
end

RunService.RenderStepped:Connect(function(dt)
	local isSkating = (player:GetAttribute("IsSkating") == true)

	if isSkating then
		local pp = getBoardPrimaryPart()
		if not pp then return end

		if not lastIsSkating then
			camera.CameraType = Enum.CameraType.Scriptable
			lastIsSkating = true
			wasAirborne = false
			lockedYaw = nil
		end

		local jumpFlag = tonumber(player:GetAttribute("JumpFlag")) or 0
		local airborne = (jumpFlag == 1)

		local pos = pp.Position
		local forward

		if airborne then
			-- 空中に入った瞬間にYawを保存（このYawで固定）
			if not wasAirborne then
				local f0 = pp.CFrame.LookVector
				f0 = Vector3.new(f0.X, 0, f0.Z)
				if f0.Magnitude < 1e-6 then
					f0 = Vector3.new(0, 0, -1)
				else
					f0 = f0.Unit
				end
				lockedYaw = yawFromForward(f0)
				wasAirborne = true
			end

			-- 空中中はボード回転を参照しない（トリック回転でカメラが回らない）
			forward = forwardFromYaw(lockedYaw or 0)
			if forward.Magnitude < 1e-6 then
				forward = Vector3.new(0, 0, -1)
			else
				forward = forward.Unit
			end
		else
			-- 地上：通常追従（ボード向き）
			wasAirborne = false
			lockedYaw = nil

			local f = pp.CFrame.LookVector
			forward = Vector3.new(f.X, 0, f.Z)
			if forward.Magnitude < 1e-6 then
				forward = Vector3.new(0, 0, -1)
			else
				forward = forward.Unit
			end
		end

		local desiredPos = pos - forward * BACK + Vector3.new(0, HEIGHT, 0)
		local lookAt = pos + forward * LOOK_AHEAD
		local desiredCF = CFrame.new(desiredPos, lookAt)

		-- スムージング
		local a = 1 - math.exp(-SMOOTH * dt)
		camera.CFrame = camera.CFrame:Lerp(desiredCF, a)

	else
		if lastIsSkating then
			camera.CameraType = Enum.CameraType.Custom
			lastIsSkating = false
			wasAirborne = false
			lockedYaw = nil
		end
	end
end)
