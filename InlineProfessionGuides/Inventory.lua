local _, ns = ...

-- Item counts: bags live, bank from a per-character cache that's refreshed whenever the bank is open.

local Inventory = {}
ns.Inventory = Inventory

local bankOpen = false

local function count(item, includeBank)
    if C_Item and C_Item.GetItemCount then
        -- itemID, includeBank, includeUses, includeReagentBank
        return C_Item.GetItemCount(item, includeBank, false, includeBank) or 0
    end
    return GetItemCount(item, includeBank) or 0
end

-- every item the guides use or make
local function trackedItems()
    local items = {}
    for _, guide in pairs(ns.Guides) do
        for _, step in ipairs(guide.steps) do
            local options = { step.main, unpack(step.alts or {}) }
            for _, option in pairs(options) do
                for _, craft in ipairs(option) do
                    for item in pairs(craft.reagents or {}) do items[item] = true end
                    local source = ns.Sources[craft.spell]
                    if source and source.creates then items[source.creates] = true end
                end
            end
        end
    end
    return items
end

local function snapshotBank()
    if not bankOpen then return end
    local bank = {}
    for item in pairs(trackedItems()) do
        local inBank = count(item, true) - count(item, false)
        if inBank > 0 then bank[item] = inBank end
    end
    IPG_CharData.bank = { items = bank, time = time() }
end

function Inventory.Bags(item) return count(item, false) end

function Inventory.Bank(item)
    if bankOpen then return count(item, true) - count(item, false) end
    local bank = IPG_CharData and IPG_CharData.bank
    return bank and bank.items[item] or 0
end

function Inventory.Have(item) return Inventory.Bags(item) + Inventory.Bank(item) end

-- seconds since the bank was cached, or nil if it never was
function Inventory.BankAge()
    if bankOpen then return 0 end
    local bank = IPG_CharData and IPG_CharData.bank
    return bank and (time() - bank.time)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false -- keep the snapshot taken while it was open
        return
    end
    snapshotBank()
end)
