-- ServerScriptService/Modules/BoostSystem.lua
-- Boostの在庫管理 / 消費 / クールダウン / 有効時間をサーバー確定で扱う

local BoostSystem = {}

BoostSystem.BOOST_MAX = 5
BoostSystem.BOOST_DURATION = 0.5
BoostSystem.BOOST_COOLDOWN = 0.2

-- userId -> number
local stockByUserId = {}
-- userId -> { activeUntil:number, cooldownUntil:number }
local stateByUserId = {}

local function ensure(userId: number)
	stockByUserId[userId] = stockByUserId[userId] or 0
	stateByUserId[userId] = stateByUserId[userId] or { activeUntil = 0, cooldownUntil = 0 }
	return stockByUserId[userId], stateByUserId[userId]
end

function BoostSystem.GetStock(player: Player): number
	local v = stockByUserId[player.UserId]
	if v == nil then v = 0 end
	return v
end

function BoostSystem.SetStock(player: Player, value: number)
	value = math.clamp(tonumber(value) or 0, 0, BoostSystem.BOOST_MAX)
	stockByUserId[player.UserId] = value
	player:SetAttribute("BoostStock", value)
end

function BoostSystem.CanAdd(player: Player, amount: number): boolean
	amount = tonumber(amount) or 0
	if amount <= 0 then return false end
	local cur = BoostSystem.GetStock(player)
	return cur < BoostSystem.BOOST_MAX
end

function BoostSystem.Add(player: Player, amount: number): boolean
	if not player or not player.Parent then return false end
	amount = tonumber(amount) or 0
	if amount <= 0 then return false end

	local cur = BoostSystem.GetStock(player)
	local nextV = math.clamp(cur + amount, 0, BoostSystem.BOOST_MAX)

	if nextV == cur then
		-- 既に満タン
		return false
	end

	BoostSystem.SetStock(player, nextV)
	return true
end

function BoostSystem.Consume(player: Player, amount: number): boolean
	if not player or not player.Parent then return false end
	amount = tonumber(amount) or 0
	if amount <= 0 then return false end

	local cur = BoostSystem.GetStock(player)
	if cur < amount then return false end
	BoostSystem.SetStock(player, cur - amount)
	return true
end

-- ブースト要求（B / 左クリック）を処理
-- jumpStateByUserId[userId] などから airborne 判定したいので、外から渡してもらう
function BoostSystem.HandleRequest(player: Player, isSkating: boolean, isAirborne: boolean): boolean
	if not player or not player.Parent then return false end
	if isSkating ~= true then return false end
	if isAirborne == true then return false end

	local userId = player.UserId
	local _, st = ensure(userId)

	local now = os.clock()
	if now < (st.cooldownUntil or 0) then
		return false
	end

	if not BoostSystem.Consume(player, 1) then
		return false
	end

	st.activeUntil = now + BoostSystem.BOOST_DURATION
	st.cooldownUntil = now + BoostSystem.BOOST_COOLDOWN

	player:SetAttribute("BoostActive", true)
	task.delay(BoostSystem.BOOST_DURATION, function()
		if player and player.Parent then
			player:SetAttribute("BoostActive", false)
		end
	end)

	return true
end

-- Physics側で参照する：今ブースト中か？
function BoostSystem.IsActive(userId: number): boolean
	local st = stateByUserId[userId]
	if not st then return false end
	return os.clock() <= (st.activeUntil or 0)
end

-- セッション終了/掃除（任意）
function BoostSystem.ClearForUser(userId: number)
	stockByUserId[userId] = nil
	stateByUserId[userId] = nil
end

return BoostSystem

