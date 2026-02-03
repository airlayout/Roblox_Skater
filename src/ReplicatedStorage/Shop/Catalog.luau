local Catalog = {}

Catalog.Items = {
    bloxxer_helmet_01 = {
        id = "bloxxer_helmet_01",
        displayName = "Bloxxer Helmet",
        price = 300,
        currency = "Coin",
        category = "Head",
        rarity = "Uncommon",
        equipSlot = "Head",
        repurchase = false,
        assetPath = "ReplicatedStorage.AssetService.BloxxerHelmet"
    }
}

Catalog.ValidSlots = {
    Head = true
}

return Catalog
