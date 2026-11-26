local _, ns = ...

--[[ Shopping list for the rest of the current bracket, with craft-or-buy advice for intermediates.

  For every material the planned crafts use:
    missing = used - made by later guide steps (e.g. the bolt step) - have (bags + cached bank)
  For an intermediate you can craft (Bolt of Silk Cloth):
    1. craft from spare raw materials you own (owned mats count as free)
    2. the rest: buy the item, or buy the raw materials and craft it - whichever is cheaper per unit
       (if there's no price data, crafting is assumed when you know the recipe)
  Raw materials then need: used directly + used for the extra crafts - have. ]]

local Shopping = {}
ns.Shopping = Shopping

local Inventory, Prices, Guide = ns.Inventory, ns.Prices, ns.Guide

local function unitCraftCost(craft)
    local total = 0
    for item, per in pairs(craft.reagents) do
        local price = Prices.Get(item)
        if not price then return end
        total = total + price * per
    end
    return total
end

--[[ Returns rows sorted intermediates first:
  { item, used, made, have, missing, fromOwned, craftBought, buy, price, priceSource, priceAge,
    unitCraft, recipeKnown, intermediate }
  plus rank and untilSkill. ]]
function Shopping.Build(skillLine)
    local consumed, produced, rank, untilSkill = Guide.GetBracketPlan(skillLine)
    local rows, byItem, rawExtra = {}, {}, {}

    local function row(item)
        if not byItem[item] then
            local price, source, age = Prices.Get(item)
            byItem[item] = { item = item, used = 0, made = produced[item] or 0, have = Inventory.Have(item),
                fromOwned = 0, craftBought = 0, buy = 0, price = price, priceSource = source, priceAge = age }
            tinsert(rows, byItem[item])
        end
        return byItem[item]
    end

    for item, amount in pairs(consumed) do row(item).used = amount end

    -- intermediates first, so their extra raw needs are known before the raw rows are settled
    for _, r in ipairs(rows) do
        local craft = r.made == 0 and Guide.GetRecipeForItem(r.item) or nil
        if craft and craft.reagents then
            r.intermediate = true
            r.recipeKnown = Guide.IsKnown(craft.spell)
            local missing = math.max(0, r.used - r.have)
            if r.recipeKnown and missing > 0 then
                -- spare raw = owned minus what the plan already uses directly
                local possible = missing
                for raw, per in pairs(craft.reagents) do
                    local spare = Inventory.Have(raw) - (consumed[raw] or 0)
                    possible = math.min(possible, math.max(0, math.floor(spare / per)))
                end
                r.fromOwned = possible
                missing = missing - possible
                r.unitCraft = unitCraftCost(craft)
                local craftIsCheaper = r.unitCraft and (not r.price or r.unitCraft < r.price)
                    or (not r.unitCraft and not r.price)
                if craftIsCheaper then
                    r.craftBought = missing
                    missing = 0
                end
                for raw, per in pairs(craft.reagents) do
                    local extra = per * (r.fromOwned + r.craftBought)
                    if extra > 0 then
                        rawExtra[raw] = (rawExtra[raw] or 0) + extra
                        row(raw)
                    end
                end
            end
            r.buy = missing
        end
    end

    for _, r in ipairs(rows) do
        if not r.intermediate then
            r.used = r.used + (rawExtra[r.item] or 0)
            r.buy = math.max(0, r.used - r.made - r.have)
        end
    end

    table.sort(rows, function(a, b)
        if (a.intermediate or false) ~= (b.intermediate or false) then return a.intermediate == true end
        return a.item < b.item
    end)
    return rows, rank, untilSkill
end

function Shopping.TotalCost(rows)
    local total, unknown = 0, 0
    for _, r in ipairs(rows) do
        if r.buy > 0 then
            if r.price then total = total + r.buy * r.price else unknown = unknown + 1 end
        end
    end
    return total, unknown
end

-- itemID -> amount to buy, over every guided profession (vendor "need N" marks)
function Shopping.GetAllBuys()
    local all = {}
    for skillLine in pairs(ns.Guides) do
        for _, r in ipairs((Shopping.Build(skillLine))) do
            if r.buy > 0 then all[r.item] = (all[r.item] or 0) + r.buy end
        end
    end
    return all
end

-- the Auctionator list: everything to buy that isn't cheaper at a vendor
function Shopping.AuctionBuys(rows)
    local buys = {}
    for _, r in ipairs(rows) do
        if r.buy > 0 and r.priceSource ~= "vendor" then tinsert(buys, { item = r.item, quantity = r.buy }) end
    end
    return buys
end
