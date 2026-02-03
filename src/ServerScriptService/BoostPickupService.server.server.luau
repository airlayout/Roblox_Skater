-- ServerScriptService/BoostPickupService.server.lua
-- コース上のブースト取得アイテム（Touched + 10秒復活）を管理する

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BoostSystem = require(script.Parent:WaitForChild("Modules"):WaitForChild("BoostSystem"))

-- ===== 設定 =====
local RESPAWN_SEC = 10
local PICKUP_AMOUNT = 1

-- ここはあなたのコース構造に合わせる
local function getPickupsFolder()
	local race = Workspace:FindFirstChild("Race")
	local course1 = race and race:FindFirstChild("Course1")
	return course1 and course1:FindFirstChild("BoostPickups")
end

local function getPlayerFromHit(hit: BasePart): Player?
	if not hit then return nil end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then return nil end
	return Players:GetPlayerFromCharacter(character)
end

local function setPickupEnabled(p: BasePart, enabled: boolean)
	-- 見た目/当たり判定をまとめて制御
	p.CanTouch = enabled
	p.CanCollide = false -- アイテムは衝突させない
	p.Transparency = enabled and 0 or 1

	-- 光り方（仮）
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 140, 60)

	-- 触れない時にパーティクル等も止めたいならここで制御
end

local debounces = {} -- [BasePart] = true/false

local function hookPickup(p: BasePart)
	if not p:IsA("BasePart") then return end

	-- 初期化
	setPickupEnabled(p, true)
	debounces[p] = false

	p.Touched:Connect(function(hit)
		if debounces[p] then return end

		local plr = getPlayerFromHit(hit)
		if not plr then return end

		-- 満タンなら取得不可（アイテムは残る）
		if not BoostSystem.CanAdd(plr, PICKUP_AMOUNT) then
			return
		end

		-- 取得処理（在庫+1）
		debounces[p] = true
		local ok = BoostSystem.Add(plr, PICKUP_AMOUNT)
		if not ok then
			debounces[p] = false
			return
		end

		-- 消失 → 10秒後復活（ワールド共有）
		setPickupEnabled(p, false)
		task.delay(RESPAWN_SEC, function()
			if p and p.Parent then
				setPickupEnabled(p, true)
				debounces[p] = false
			end
		end)
	end)
end

-- 起動時に既存Pickupへフック
local folder = getPickupsFolder()
if not folder then
	warn("[BoostPickupService] BoostPickups folder not found: Workspace/Race/Course1/BoostPickups")
	return
end

for _, obj in ipairs(folder:GetChildren()) do
	if obj:IsA("BasePart") then
		hookPickup(obj)
	end
end

-- 途中で追加されたPartにも対応したい場合
folder.ChildAdded:Connect(function(obj)
	if obj:IsA("BasePart") then
		-- 追加直後だとプロパティ設定が上書きされることがあるので少し待つ
		task.wait()
		hookPickup(obj)
	end
end)

print("[BoostPickupService] Ready. Pickups:", #folder:GetChildren())

