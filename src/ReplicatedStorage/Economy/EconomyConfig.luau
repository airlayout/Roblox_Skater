-- ReplicatedStorage/Economy/EconomyConfig
local EconomyConfig = {}

-- Constants
EconomyConfig.MAX_COIN = 99999999
EconomyConfig.MIN_COIN = 0

-- Race Rewards (1st, 2nd, 3rd, 4th+)
EconomyConfig.RACE_REWARD_BY_PLACE = {
    [1] = 100,
    [2] = 70,
    [3] = 50,
    DEFAULT = 20
}

-- Product Types
EconomyConfig.PRODUCT_TYPE = {
    CONSUMABLE = "CONSUMABLE",
    UNLOCK = "UNLOCK"
}

EconomyConfig.TRICK_REWARD_BY_TYPE = {
	Spin360 = 10,
}

-- Product Master Data
EconomyConfig.PRODUCTS = {
    -- Consumables
    ["boost_pack_1"] = {
        type = EconomyConfig.PRODUCT_TYPE.CONSUMABLE,
        price = 100,
        displayName = "Boost Pack x1",
        grantAmount = 1
    },
    ["boost_pack_5"] = {
        type = EconomyConfig.PRODUCT_TYPE.CONSUMABLE,
        price = 450,
        displayName = "Boost Pack x5",
        grantAmount = 5
    },
    
    -- Unlocks
    ["board_red"] = {
        type = EconomyConfig.PRODUCT_TYPE.UNLOCK,
        price = 1000,
        displayName = "Red Board"
    },
    ["board_blue"] = {
        type = EconomyConfig.PRODUCT_TYPE.UNLOCK,
        price = 1000,
        displayName = "Blue Board"
    }
}

return EconomyConfig
