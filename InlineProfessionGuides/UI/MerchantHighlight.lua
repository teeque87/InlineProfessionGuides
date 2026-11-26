local _, ns = ...
local Mark = ns.Mark

-- At a vendor: a colored border around the icon of patterns for guide recipes you haven't learned, and of
-- guide materials you still need. The details ("needed at 175", "buy 39 more") are in the item tooltip.

local function merchantItemID(index)
    if GetMerchantItemID then return GetMerchantItemID(index) end
    local link = GetMerchantItemLink(index)
    return link and tonumber(link:match("item:(%d+)"))
end

local function update()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page or 1
    local buyback = MerchantFrame.selectedTab == 2 or not ns.IsEnabled("vendorBorder")
    local patterns = not buyback and ns.NeededPatterns() or {}
    local materials = not buyback and ns.NeededMaterials() or {}

    for i = 1, perPage do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then
            local item = not buyback and merchantItemID((page - 1) * perPage + i)
            local pattern = item and patterns[item]
            if pattern then
                Mark.Show(button, (Mark.ForRecipe(pattern)), nil, nil, 1)
            elseif item and materials[item] then
                Mark.Show(button, "now", nil, nil, 1)
            else
                Mark.Hide(button)
            end
        end
    end
end

for _, name in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
    if _G[name] then hooksecurefunc(name, update) end
end
if not _G.MerchantFrame_UpdateMerchantInfo then ns.Print("merchant frame not found, vendor highlight disabled") end

-- buying something changes what's still needed (bag updates trigger a refresh)
ns.OnRefresh(update)
