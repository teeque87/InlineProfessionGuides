local _, ns = ...

-- Trade-supply materials every profession vendor sells (unlimited stock). These are always bought at a vendor,
-- never on the Auction House. Items seen at any vendor in-game are added automatically (IPG_Settings.vendorPrices).
ns.VendorItems = {
    [2320] = true,  -- Coarse Thread
    [2321] = true,  -- Fine Thread
    [4291] = true,  -- Silken Thread
    [8343] = true,  -- Heavy Silken Thread
    [14341] = true, -- Rune Thread
    [2324] = true,  -- Bleach
    [2604] = true,  -- Red Dye
    [2605] = true,  -- Green Dye
    [2325] = true,  -- Black Dye
    [4340] = true,  -- Gray Dye
    [4342] = true,  -- Purple Dye
    [6260] = true,  -- Blue Dye
    [6261] = true,  -- Orange Dye
    [10290] = true, -- Pink Dye
    [4289] = true,  -- Salt
    [3371] = true,  -- Empty Vial
    [3372] = true,  -- Leaded Vial
    [8925] = true,  -- Crystal Vial
    [18256] = true, -- Imbued Vial
    [2880] = true,  -- Weak Flux
    [3466] = true,  -- Strong Flux
    [2678] = true,  -- Mild Spices
    [2692] = true,  -- Hot Spices
    [3713] = true,  -- Soothing Spices
    [159] = true,   -- Refreshing Spring Water
    [4470] = true,  -- Simple Wood
}
