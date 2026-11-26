local addonName, ns = ...
local L = ns.L

-- Prices (vendor + Auctionator) and Auctionator shopping lists (optional dependency).

local Prices = {}
ns.Prices = Prices

local function api()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

function Prices.Available() return api() ~= nil end

local function vendorPrice(item)
    local own = IPG_Settings and IPG_Settings.vendorPrices and IPG_Settings.vendorPrices[item]
    if own then return own end
    local v1 = api()
    return v1 and v1.GetVendorPriceByItemID(addonName, item)
end

-- sold by vendors with unlimited stock: always bought there, never on the AH
function Prices.IsVendorItem(item)
    return ns.VendorItems[item] or vendorPrice(item) ~= nil
end

--[[ Price per item in copper. Vendor items always use the vendor price (nil until a vendor selling it was
     opened); everything else the last Auctionator AH scan.
     Returns price, "vendor"|"ah"|nil, age in days of the AH data. ]]
function Prices.Get(item)
    if Prices.IsVendorItem(item) then return vendorPrice(item), "vendor" end
    local v1 = api()
    local auction = v1 and v1.GetAuctionPriceByItemID(addonName, item)
    if auction then return auction, "ah", v1.GetAuctionAgeByItemID(addonName, item) end
end

-- time() of Auctionator's most recent AH scan (full, GetAll or browse), or nil.
-- Read from Auctionator's saved state (not part of its public API), so every field is optional.
function Prices.LastScan()
    local state = Auctionator and Auctionator.SavedState
    if type(state) ~= "table" then return end
    local latest
    for _, key in ipairs({ "TimeOfLastReplicateScan", "TimeOfLastGetAllScan", "TimeOfLastBrowseScan" }) do
        local t = state[key]
        if type(t) == "number" and (not latest or t > latest) then latest = t end
    end
    return latest
end

-- remember unlimited-stock vendor items and their unit price, so they're never sent to the AH list
local function merchantItem(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then return info.price, info.stackCount, info.numAvailable end
        return
    end
    local _, _, price, stack, numAvailable = GetMerchantItemInfo(index)
    return price, stack, numAvailable
end

local function recordVendor()
    IPG_Settings.vendorPrices = IPG_Settings.vendorPrices or {}
    for index = 1, GetMerchantNumItems() do
        local item = GetMerchantItemID and GetMerchantItemID(index)
        local price, stack, numAvailable = merchantItem(index)
        if item and price and price > 0 and numAvailable == -1 then
            IPG_Settings.vendorPrices[item] = math.floor(price / math.max(1, stack or 1) + 0.5)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:SetScript("OnEvent", function()
    recordVendor()
    ns.Refresh()
end)

-- buys: list of { item = itemID, quantity = n }. Replaces an existing list with the same name.
function Prices.CreateShoppingList(name, buys)
    local v1 = api()
    if not v1 or #buys == 0 then return end
    local pending, searchStrings = #buys, {}
    for i, buy in ipairs(buys) do
        Item:CreateFromItemID(buy.item):ContinueOnItemLoad(function()
            searchStrings[i] = v1.ConvertToSearchString(addonName, {
                searchString = C_Item.GetItemNameByID(buy.item),
                isExact = true,
                quantity = buy.quantity,
            })
            pending = pending - 1
            if pending == 0 then
                v1.CreateShoppingList(addonName, name, searchStrings)
                ns.Print(L.LIST_CREATED:format(name, #searchStrings))
            end
        end)
    end
end
