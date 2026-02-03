-- StarterPlayerScripts/DisableDefaultJump
-- スケボー乗車中の標準ジャンプを無効化し、VehicleSeatからの予期せぬ降車を防ぐスクリプト。

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local ACTION_NAME = "DisableDefaultJumpWhileSkating"

local function sinkJump(actionName, inputState, inputObject)
    -- 何もしないで入力を食う
    return Enum.ContextActionResult.Sink
end

local function updateBinding()
    local isSkating = (player:GetAttribute("IsSkating") == true)
    if isSkating then
        -- Space と “ジャンプアクション” を無効化
        ContextActionService:BindAction(
            ACTION_NAME,
            sinkJump,
            false,
            Enum.PlayerActions.CharacterJump,
            Enum.KeyCode.Space
        )
        print("[DisableJump] Default jump DISABLED.")
    else
        ContextActionService:UnbindAction(ACTION_NAME)
        print("[DisableJump] Default jump ENABLED.")
    end
end

local function clearJumpFlag()
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if player:GetAttribute("IsSkating") == true then
        humanoid.Jump = false
    end
end

-- 初期設定
player:GetAttributeChangedSignal("IsSkating"):Connect(updateBinding)
player:GetAttributeChangedSignal("IsSkating"):Connect(function()
    task.defer(clearJumpFlag)
end)

player.CharacterAdded:Connect(function()
    task.wait(0.2)
    clearJumpFlag()
end)

updateBinding()
