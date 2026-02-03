-- StarterPlayerScripts/SkateFacingLock
-- IsSkating中、キャラの向きを「ボードの進行方向 + 90°」に固定する（見た目用）

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local SIDE_SIGN = 1 -- 右向き=1 / 左向き=-1

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

RunService.RenderStepped:Connect(function()
	local isSkating = (player:GetAttribute("IsSkating") == true)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then return end

	if not isSkating then
		humanoid.AutoRotate = true
		return
	end

	local pp = getBoardPrimaryPart()
	if not pp then return end

	-- AutoRotateを止めて、向きを固定
	humanoid.AutoRotate = false

	local look = pp.CFrame.LookVector
	local boardYaw = math.atan2(look.X, look.Z)
	local targetYaw = boardYaw + SIDE_SIGN * math.rad(90)

	local pos = hrp.Position
	hrp.CFrame = CFrame.new(pos) * CFrame.Angles(0, targetYaw, 0)
end)

