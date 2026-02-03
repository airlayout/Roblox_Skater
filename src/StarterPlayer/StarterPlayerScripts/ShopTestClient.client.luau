local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Wait for Remotes (ShopService creates them, but loop safe)
local RemotesFolder = ReplicatedStorage:WaitForChild("RemoteFunctions", 10)
if not RemotesFolder then
    warn("[ShopTestClient] RemoteFunctions folder not found!")
    return
end

local Remotes = {
    GetState = RemotesFolder:WaitForChild("ShopGetState"),
    Buy = RemotesFolder:WaitForChild("ShopBuy"),
    Equip = RemotesFolder:WaitForChild("ShopEquip"),
    Unequip = RemotesFolder:WaitForChild("ShopUnequip"),
}

-- --- TEST HELPER ---
local function Test(name, func)
    print("--------------------------------------------------")
    print("TEST: " .. name)
    local success, err = pcall(func)
    if success then
        print("PASS: " .. name)
    else
        warn("FAIL: " .. name .. " | Error: " .. tostring(err))
    end
    print("--------------------------------------------------")
    task.wait(1)
end

local function Expect(val, expected, msg)
    if val ~= expected then
        error(msg .. " | Got: " .. tostring(val) .. " Expected: " .. tostring(expected))
    end
    print("   CHECK OK: " .. msg)
end

-- --- RUN TESTS ---
task.spawn(function()
    print("[ShopTestClient] Waiting for Game Load...")
    task.wait(3) -- Wait for server init/session load
    
    Test("1. Get Initial State", function()
        local result = Remotes.GetState:InvokeServer()
        Expect(result.ok, true, "State OK")
        print("   Coin: " .. tostring(result.data.coin))
        
        -- Verify Catalog Privacy (No assetPath)
        local item = result.data.catalog["bloxxer_helmet_01"]
        if item then
             if item.assetPath then
                 error("PRIVACY FAIL: assetPath exposed to client")
             else
                 print("   CHECK OK: assetPath hidden")
             end
        else
            warn("   Catalog item missing (maybe acceptable if empty)")
        end
    end)
    
    local TEST_ITEM = "bloxxer_helmet_01"
    
    Test("2. Buy Item", function()
        local result = Remotes.Buy:InvokeServer(TEST_ITEM)
        if result.ok then
             print("   Buy Success! New Coin: " .. tostring(result.data.newCoin))
        else
             -- Might own it from previous run, which is fine for repeated tests
             if result.errorCode == "ALREADY_OWNED" then
                 print("   Item already owned. Skipping buy.")
             elseif result.errorCode == "INSUFFICIENT_FUNDS" then
                 warn("   Not enough coins to test buy!")
             else
                 error("Buy Failed: " .. tostring(result.errorCode))
             end
        end
    end)
    
    Test("3. Equip Item", function()
        local result = Remotes.Equip:InvokeServer(TEST_ITEM)
        if not result.ok then
             error("Equip Failed: " .. tostring(result.errorCode))
        end
        print("   Equip Success!")
        
        -- Verify Attribute locally?
        task.wait(1) -- Replication delay
        local char = player.Character
        local humanoid = char and char:FindFirstChild("Humanoid")
        local found = false
        if humanoid then
             for _, acc in ipairs(humanoid:GetAccessories()) do
                 if acc:GetAttribute("ShopItemId") == TEST_ITEM then
                     found = true
                     break
                 end
             end
        end
        Expect(found, true, "Visual Accessory Found on Character")
    end)
    
    Test("4. Idempotency (Double Equip)", function()
        local result = Remotes.Equip:InvokeServer(TEST_ITEM)
        Expect(result.ok, true, "Double Equip Should succeed (No-Op or Re-Equip)")
        
        -- Check count
        local count = 0
        local char = player.Character
        local humanoid = char and char:FindFirstChild("Humanoid")
        if humanoid then
             for _, acc in ipairs(humanoid:GetAccessories()) do
                 if acc:GetAttribute("ShopItemId") == TEST_ITEM then
                     count += 1
                 end
             end
        end
        Expect(count, 1, "Only 1 Accessory of this type should exist")
    end)
    
    Test("5. Unequip Item", function()
        local result = Remotes.Unequip:InvokeServer("Head")
        Expect(result.ok, true, "Unequip Success")
        
         task.wait(1)
        local char = player.Character
        local humanoid = char and char:FindFirstChild("Humanoid")
        local found = false
        if humanoid then
             for _, acc in ipairs(humanoid:GetAccessories()) do
                 if acc:GetAttribute("ShopItemId") == TEST_ITEM then
                     found = true
                     break
                 end
             end
        end
        Expect(found, false, "Visual Accessory Removed from Character")
    end)
    
     Test("6. Invalid Slot Unequip", function()
        local result = Remotes.Unequip:InvokeServer("Legs") -- Invalid
        Expect(result.ok, false, "Should fail invalid slot")
        Expect(result.errorCode, "INVALID_SLOT", "Error Code Match")
    end)

    print("[ShopTestClient] ALL TESTS COMPLETED")
end)
