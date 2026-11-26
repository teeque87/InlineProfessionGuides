local addonName, ns = ...
local L = ns.L

ns.Guides = ns.Guides or {}
ns.Sources = ns.Sources or {}

function ns.Print(...)
    print("|cff33ff99IPG|r:", ...)
end

-- "v0.1.0" in release zips; the repo TOC holds a placeholder the release workflow fills in.
function ns.Version()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    if not version or version:find("@", 1, true) then return "dev" end
    return "v" .. version
end

-- Refresh hub: UI modules register here and are refreshed on profession/skill/recipe changes.
local refreshers = {}
function ns.OnRefresh(fn) tinsert(refreshers, fn) end
-- Results of the guide calculations, shared by tooltips and highlights; dropped on every refresh trigger.
local cache = {}
function ns.Cached(key, compute)
    if cache[key] == nil then cache[key] = compute() end
    return cache[key]
end

local pending = false
-- coalesces bursts of events (bag updates, item info) into one refresh
function ns.Refresh()
    cache = {}
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        for _, fn in ipairs(refreshers) do fn() end
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
    "LEARNED_SPELL_IN_SKILL_LINE", "TRADE_SKILL_SHOW", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName then
            IPG_Settings = IPG_Settings or {}
            IPG_CharData = IPG_CharData or {}
            ns.Print(L.ADDON_NAME, L.LOADED)
        end
        return
    end
    ns.Refresh()
end)

SLASH_INLINEPROFESSIONGUIDES1 = "/ipg"
SlashCmdList.INLINEPROFESSIONGUIDES = function(msg)
    local command, arg = strsplit(" ", strtrim(msg or ""), 2)
    command = command and command:lower()
    if command == "help" or command == "?" then
        for _, line in ipairs(L.HELP) do ns.Print(line) end
        return
    elseif command == "options" or command == "config" then
        ns.OpenOptions()
        return
    elseif command == "reset" then
        ns.ResetChoices()
        ns.Print(L.CHOICES_RESET)
        return
    end
    if command == "dump" then
        -- written to WTF\Account\<account>\SavedVariables\InlineProfessionGuides.lua on /reload or logout
        local out = { "dumped " .. date("%Y-%m-%d %H:%M:%S") }
        for spell, info in pairs(ns.Guide.GetNeededRecipes()) do
            tinsert(out, ("needed: %s (%d) at %d%s%s"):format(ns.Guide.SpellName(spell), spell, info.at,
                info.alt and " alt" or "", info.current and " current" or ""))
        end
        for skillLine in pairs(ns.Guides) do
            local rows, from, to = ns.Shopping.Build(skillLine)
            for _, r in ipairs(rows) do
                tinsert(out, ("material %d (%s-%s): used %d made %d have %d | fromOwned %d craftBought %d buy %d"
                    .. " | price %s (%s) craft %s known %s"):format(r.item, tostring(from), tostring(to), r.used,
                    r.made, r.have, r.fromOwned, r.craftBought, r.buy, tostring(r.price), tostring(r.priceSource),
                    tostring(r.unitCraft), tostring(r.recipeKnown)))
            end
        end
        if ns.DumpTrainer then ns.DumpTrainer(out) end
        IPG_Settings.debugDump = out
        ns.Print(L.DUMP_SAVED:format(#out))
        return
    end
    if command == "test" then
        ns.Guide.testSpell = tonumber(arg)
        ns.Print(ns.Guide.testSpell and L.TEST_ON:format(ns.Guide.testSpell) or L.TEST_OFF)
        ns.Refresh()
        return
    end
    ns.Print(L.ADDON_NAME, ns.Version())
    local count = 0
    for _ in pairs(ns.Guides) do count = count + 1 end
    ns.Print(L.GUIDES_LOADED:format(count))
    for skillLine, guide in pairs(ns.Guides) do
        if ns.Guide.GetSkill(skillLine) then
            ns.Print(L.GUIDE_LOADED:format(ns.Guide.GetName(skillLine), #guide.steps, guide.built))
        end
        local target = ns.Guide.GetTarget(skillLine)
        if target then
            ns.Print(L.CURRENT_TARGET:format(target.rank, ns.Guide.SpellName(target.craft.spell), target.to,
                target.toGo, target.isMain and L.MAIN_ROUTE or L.ALTERNATIVE,
                target.known and L.KNOWN or L.NOT_KNOWN))
        end
    end
    local needed = {}
    for spell, info in pairs(ns.Guide.GetNeededRecipes()) do
        if not info.alt then tinsert(needed, { at = info.at, text = ns.Guide.SpellName(spell) .. " @" .. info.at }) end
    end
    table.sort(needed, function(a, b) return a.at < b.at end)
    local first = {}
    for i = 1, math.min(4, #needed) do first[i] = needed[i].text end
    ns.Print(L.STILL_NEEDED, table.concat(first, ", ") .. (#needed > 4 and (" +" .. (#needed - 4)) or ""))
    if ns.DebugTrainer then ns.DebugTrainer() end
    if ProfessionsFrame and ProfessionsFrame:IsShown() then
        local id, name = ns.Guide.GetOpenProfessionRaw()
        ns.Print(L.OPEN_PROFESSION:format(tostring(id), tostring(name), tostring(ns.Guide.GetOpenProfession())))
    end
    ns.Refresh()
end
