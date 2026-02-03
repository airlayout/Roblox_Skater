-- ServerScriptService/Economy/ShopService
local ShopService = {}

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyService = require(ServerScriptService.Economy.MoneyService)
local EconomyConfig = require(ReplicatedStorage.Economy.EconomyConfig)

function ShopService.Purchase(player, productId, quantity)
    -- Normalize quantity
    if not quantity or type(quantity) ~= "number" or quantity < 1 then
        quantity = 1
    end
    quantity = math.floor(quantity)

    -- Validate Product
    local product = EconomyConfig.PRODUCTS[productId]
    if not product then
        return {
            ok = false,
            reason = "INVALID_PRODUCT",
            newCoin = MoneyService.GetCoin(player),
            granted = nil
        }
    end

    -- ALREADY_OWNED Check for UNLOCKs
    if product.type == EconomyConfig.PRODUCT_TYPE.UNLOCK then
        local currentUnlocks = MoneyService.GetUnlocks(player)
        if currentUnlocks[productId] then
            return {
                ok = true,
                reason = "ALREADY_OWNED",
                newCoin = MoneyService.GetCoin(player),
                granted = {
                    type = "UNLOCK",
                    productId = productId,
                    quantity = 1,
                    changed = false
                }
            }
        end
    end

    -- Calculate Cost
    local cost = product.price * quantity
    
    -- Check Funds & Spend
    -- We assume SpendCoin writes to session and triggers Save
    local spent, reason = MoneyService.SpendCoin(player, cost, "PURCHASE")
    if not spent then
        return {
            ok = false,
            reason = "INSUFFICIENT_FUNDS",
            newCoin = MoneyService.GetCoin(player),
            granted = nil
        }
    end

    -- Update Inventory (In Memory)
    local grantDetails = {}
    if product.type == EconomyConfig.PRODUCT_TYPE.UNLOCK then
        MoneyService.UpdateInventory(player, { [productId] = true }, nil)
        grantDetails = {
            type = "UNLOCK",
            productId = productId,
            quantity = 1,
            changed = true
        }
    elseif product.type == EconomyConfig.PRODUCT_TYPE.CONSUMABLE then
        local amountToAdd = (product.grantAmount or 1) * quantity
        local currentConsumables = MoneyService.GetConsumables(player)
        local currentAmount = currentConsumables[productId] or 0
        MoneyService.UpdateInventory(player, nil, { [productId] = currentAmount + amountToAdd })
        grantDetails = {
            type = "CONSUMABLE",
            productId = productId,
            quantity = amountToAdd,
            changed = true
        }
    end

    -- Force Save explicitly after inventory update
    -- (SpendCoin triggered a Save, but inventory update happened after. We should save again or ensure atomic)
    -- Ideally SpendCoin and UpdateInventory should be one transaction or Save called at end.
    -- Calling Save again is safest.
    local saved = MoneyService.Save(player)
    
    if not saved then
        -- This is bad: Money spent but Save failed. Current spec says "Give up, Rollback acceptable".
        -- Since we updated session memory, the player has the item in this session.
        -- Next login might rollback. This is per spec ("Saved state is source of truth, but session is allowed to drift on failure").
        -- Spec: "DATASTORE_FAILED" if save fails 3 times.
        
        return {
            ok = true, -- Spec says "Game state is maintained". Returning OK to client lets them play.
                       -- But if we want to stick strictly to "Fail if invalid", the transaction "in memory" succeeded.
                       -- The spec said: "reason = DATASTORE_FAILED (Purchase applied but save failed)".
                       -- Let's return OK=true but reason=DATASTORE_FAILED to indicate partial success?
                       -- Or OK=false?
                       -- User spec: "Save failure: 3 retries -> give up -> no notification".
                       -- User spec also says: "reason = DATASTORE_FAILED".
                       -- So likely we should return ok=true (because they got the item in session) 
                       -- OR ok=false (to verify transaction).
                       -- Usually if memory is updated, it's "OK" for the session.
                       -- However, the spec includes DATASTORE_FAILED as a reason.
                       -- I will choose: ok=true (transaction successful in session), reason="DATASTORE_FAILED".
            reason = "DATASTORE_FAILED",
            newCoin = MoneyService.GetCoin(player),
            granted = grantDetails
        }
    end

    return {
        ok = true,
        reason = "OK",
        newCoin = MoneyService.GetCoin(player),
        granted = grantDetails
    }
end

return ShopService
