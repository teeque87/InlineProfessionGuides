local _, ns = ...
local L = ns.L
local Guide = ns.Guide

-- Panel docked to the right of ProfessionsFrame: current step, "N to go", how to learn the recipe
-- if it isn't known yet (trainer / vendor / quest / drop / reputation), guide notes and the next step.

local WIDTH, PADDING = 280, 12
local playerFaction = UnitFactionGroup("player")
local panel, lines, used

local COLORS = {
    title = { 1, 0.82, 0 },
    heading = { 1, 0.82, 0 },
    text = { 1, 1, 1 },
    craft = { 1, 1, 1 },
    good = { 0.2, 1, 0.2 },
    bad = { 1, 0.35, 0.35 },
    alert = { 1, 0.35, 0.35 },
    note = { 0.7, 0.7, 0.7 },
}

local function forFaction(entry)
    return not entry.faction or entry.faction == playerFaction
end

local function areaName(entry)
    local area = entry.area or (entry.areas and entry.areas[1])
    local info = area and area > 0 and C_Map.GetAreaInfo(area)
    return info or nil
end

-- the created item's icon; a crafting spell's own icon is a generic placeholder
local function icon(spell, size)
    local source = ns.Sources[spell]
    local texture = source and source.creates and C_Item.GetItemIconByID(source.creates)
        or C_Spell.GetSpellTexture(spell)
    size = size or 16
    return texture and ("|T" .. texture .. ":" .. size .. ":" .. size .. "|t ") or ""
end

local function add(text, style, indent, gap)
    used = used + 1
    local line = lines[used]
    if not line then
        line = panel:CreateFontString(nil, "OVERLAY")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        lines[used] = line
    end
    indent = indent or 0
    line:SetFontObject((style == "title" or style == "alert") and "GameFontNormalLarge"
        or (style == "heading" and "GameFontNormal")
        or (style == "note" and "GameFontHighlightSmall")
        or (style == "craft" and (_G.GameFontHighlightMedium and "GameFontHighlightMedium" or "GameFontHighlight"))
        or "GameFontHighlight")
    line:SetTextColor(unpack(COLORS[style or "text"]))
    line:ClearAllPoints()
    local previous = lines[used - 1]
    if used == 1 then
        line:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING + indent, -PADDING)
    else
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", indent - (previous.indent or 0), -(gap or 3))
    end
    line.indent = indent
    line.gap = used == 1 and 0 or (gap or 3)
    line:SetWidth(WIDTH - 2 * PADDING - indent)
    line:SetText(text)
    line:Show()
end

-- clickable lines: invisible buttons laid over the line, reused across renders
local links, linksUsed = {}, 0

-- adds a line that runs onClick; title/hint make the tooltip
local function addLink(text, style, indent, gap, onClick, title, hint)
    add(text, style, indent, gap)
    linksUsed = linksUsed + 1
    local link = links[linksUsed]
    if not link then
        link = CreateFrame("Button", nil, panel)
        link:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        link:SetScript("OnClick", function(self) self.onClick() end)
        link:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title or "")
            if self.hint then GameTooltip:AddLine(self.hint, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        link:SetScript("OnLeave", GameTooltip_Hide)
        links[linksUsed] = link
    end
    link.onClick, link.title, link.hint = onClick, title, hint
    link:ClearAllPoints()
    link:SetAllPoints(lines[used])
    link:Show()
end

local function addNpc(text, npc, style, indent, gap)
    indent = indent or 16
    if not ns.Waypoint.CanShow(npc) then
        add(text, style or "note", indent, gap)
        return
    end
    addLink(text .. L.MAP_LINK, style or "note", indent, gap, function() ns.Waypoint.Show(npc) end, npc.name,
        L.MAP_LINK_TOOLTIP)
end

-- the rank the player has to learn next, when at (or within 10 of) the skill cap
local function capInfo(skillLine)
    local rank, maxRank = Guide.GetSkill(skillLine)
    if not rank or not maxRank or maxRank >= 300 or maxRank - rank > 10 then return end
    local nextStep = Guide.GetStep(skillLine, maxRank)
    local bracket = nextStep and nextStep.bracket
    if bracket then return rank, maxRank, bracket end
end

-- trainers for a rank. Guides list no Journeyman trainers when every trainer teaches it, so Journeyman
-- falls back to the Apprentice list. Returns the list and whether it is that fallback.
local function trainersFor(guide, bracket)
    local list = guide.trainers and guide.trainers[bracket]
    if not list and bracket == "Journeyman" and guide.trainers and guide.trainers.Apprentice then
        return guide.trainers.Apprentice, true
    end
    return list or {}, false
end

-- entries { text, faction, npcs = { npc, ... } } for this faction, each with its nearest NPC (an entry can
-- name one per town), sorted nearest first; other continents (no distance) follow in the guide's order
local function byDistance(list)
    local result = {}
    for _, entry in ipairs(list) do
        if forFaction(entry) then
            local best, bestDistance
            for _, npc in ipairs(entry.npcs or {}) do
                local distance = ns.Waypoint.Distance(npc)
                if not best or (distance and (not bestDistance or distance < bestDistance)) then
                    best, bestDistance = npc, distance
                end
            end
            tinsert(result, { text = entry.text, npc = best, distance = bestDistance, order = #result + 1 })
        end
    end
    table.sort(result, function(a, b)
        if a.distance and b.distance then return a.distance < b.distance end
        if a.distance or b.distance then return a.distance ~= nil end
        return a.order < b.order
    end)
    return result
end

-- lists opened with "+N more" this session, by key
local expandedLists = {}
local LIST_SHOWN = 4 -- besides the nearest

-- NPCs nearest first: the nearest gets its own green "Nearest ... - N yd" line and a white name, the rest
-- are dimmed below and cut after a few with a "+N more" / "show less" toggle
local function addNpcList(key, list, nearestLabel, othersLabel, indent)
    local entries = byDistance(list)
    if #entries == 0 then return end
    local first = 1
    if entries[1].distance then
        add(nearestLabel:format(entries[1].distance), "good", indent, 6)
        addNpc(entries[1].text, entries[1].npc, "text", indent + 8, 2)
        if #entries > 1 then add(othersLabel, "note", indent, 6) end
        first = 2
    end
    local limit = first - 1 + LIST_SHOWN
    local expanded = expandedLists[key]
    local last = expanded and #entries or math.min(#entries, limit)
    for i = first, last do
        addNpc("• " .. entries[i].text, entries[i].npc, nil, indent + 8)
    end
    local toggle
    if last < #entries then
        toggle = L.LIST_MORE:format(#entries - last)
    elseif expanded and #entries > limit then
        toggle = L.LIST_LESS
    end
    if toggle then
        addLink("|cff66aaff" .. toggle .. "|r", "note", indent + 8, nil, function()
            expandedLists[key] = not expanded or nil
            ns.Refresh()
        end, toggle, expanded and L.LIST_LESS_HINT or L.LIST_MORE_HINT)
    end
end

-- at (or near) the skill cap: a prominent block on top - which rank to learn and where, nearest first
local function addCap(skillLine)
    local rank, maxRank, bracket = capInfo(skillLine)
    if not rank then return end
    local guide = ns.Guides[skillLine]
    if rank >= maxRank then
        add(L.CAP_REACHED:format(maxRank), "alert", 0, 10)
    else
        add(L.CAP_SOON:format(maxRank, maxRank - rank), "heading", 0, 10)
    end
    add(L.CAP_LEARN:format(bracket, Guide.GetName(skillLine), maxRank), "note", 0, 3)

    local trainers, fallback = trainersFor(guide, bracket)
    -- the guide's note matters when it names a book or a special trainer; the Journeyman fallback
    -- notes only say "visit your trainer", which the list below already shows
    local note = guide.rankNotes and guide.rankNotes[bracket]
    if note and not fallback then add(note, "note", 8, 4) end
    addNpcList("cap", trainers, L.NEAREST_TRAINER, L.OTHER_TRAINERS, 8)
end

local function shorten(text, max)
    if #text <= max then return text end
    return text:sub(1, max - 3) .. "..."
end

local function addSource(craft, target, step, skillLine, named)
    local spell = craft.spell
    local source = ns.Sources[spell]
    add(named and L.HOW_TO_LEARN_NAMED:format(Guide.SpellName(spell)) or L.HOW_TO_LEARN, "heading", 0, 10)
    if not source or not source.source then
        add(L.SOURCE_UNKNOWN, "note", 8)
        return
    end
    local rank = target.rank
    if source.skill and rank < source.skill then
        add(L.NEEDS_SKILL:format(source.skill), "bad", 8)
    end
    for _, kind in ipairs(source.source) do
        if kind == "trainer" then
            local formatMoney = GetCoinTextureString or GetMoneyString
            add(L.SOURCE_TRAINER:format(source.cost and formatMoney(source.cost) or "?"), "text", 8)
            local guide = ns.Guides[skillLine]
            local trainers = trainersFor(guide, step.bracket)
            local listed = 0
            for _, trainer in ipairs(trainers) do
                if forFaction(trainer) then listed = listed + 1 end
            end
            addNpcList("trainer:" .. spell, trainers, L.NEAREST_TRAINER, L.OTHER_TRAINERS, 16)
            local note = guide.rankNotes and guide.rankNotes[step.bracket]
            if listed == 0 and note then add(note, "note", 16) end
        elseif kind == "vendor" then
            add(L.SOURCE_VENDOR, "text", 8)
            local vendors = {}
            for _, vendor in ipairs(source.vendors or {}) do
                local where = areaName(vendor)
                tinsert(vendors, {
                    text = (vendor.name or ("NPC " .. vendor.npc)) .. (where and (" - " .. where) or ""),
                    faction = vendor.faction,
                    npcs = vendor.x and { { name = vendor.name, area = vendor.area, x = vendor.x, y = vendor.y } },
                })
            end
            addNpcList("vendor:" .. spell, vendors, L.NEAREST_VENDOR, L.OTHER_VENDORS, 16)
        elseif kind == "quest" then
            for _, quest in ipairs(source.quests or {}) do
                if forFaction(quest) then
                    local where = areaName(quest)
                    add(L.SOURCE_QUEST:format(quest.name or ("#" .. quest.id), quest.level or "?")
                        .. (where and (" - " .. where) or ""), "text", 8)
                end
            end
        elseif kind == "drop" then
            add(L.SOURCE_DROP, "text", 8)
        else
            add(kind, "text", 8)
        end
    end
    -- the guide's free-text source ("World drop, on the Auction House"), unless NPCs are already listed
    local listsNpcs = (source.vendors and #source.vendors > 0) or tContains(source.source, "trainer")
    if target.option.sourceText and not listsNpcs then add(shorten(target.option.sourceText, 90), "note", 16) end
    if source.reputation then
        local factionID, standing = source.reputation[1], source.reputation[2]
        local data = C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
        local factionName = data and data.name or ("#" .. factionID)
        add(L.REQUIRES_REP:format(factionName, _G["FACTION_STANDING_LABEL" .. standing] or standing), "bad", 8)
    end
    if source.bound then add(L.BIND_ON_PICKUP, "note", 8) end
    if source.faction and source.faction ~= playerFaction then add(L.OTHER_FACTION, "bad", 8) end
end

local listButton, shoppingRows, listName

local function money(copper)
    if not copper then return "?" end
    if copper >= 10000 then copper = math.floor(copper / 100) * 100 end -- hide copper above 1g
    return (GetCoinTextureString or GetMoneyString)(copper)
end

local function itemLabel(item)
    local name = C_Item.GetItemNameByID(item)
    if not name then C_Item.RequestLoadItemDataByID(item) end -- GET_ITEM_INFO_RECEIVED refreshes
    local texture = C_Item.GetItemIconByID(item)
    return (texture and ("|T" .. texture .. ":14:14|t ") or "") .. (name or ("item " .. item))
end

local function shoppingAdvice(r)
    local parts = {}
    if r.made > 0 then tinsert(parts, L.SHOP_MADE:format(r.made)) end
    if r.fromOwned > 0 then tinsert(parts, L.SHOP_CRAFT_OWNED:format(r.fromOwned)) end
    if r.craftBought > 0 then
        if r.unitCraft and r.price then
            tinsert(parts, L.SHOP_CRAFT_BOUGHT:format(r.craftBought, money(r.unitCraft), money(r.price)))
        elseif r.unitCraft then -- not on the AH: crafting is the only option with a price
            tinsert(parts, L.SHOP_CRAFT_BOUGHT_ONLY:format(r.craftBought, money(r.unitCraft)))
        else
            tinsert(parts, L.SHOP_CRAFT_NO_PRICE:format(r.craftBought))
        end
    end
    if r.buy > 0 then
        if r.intermediate and not r.recipeKnown then
            tinsert(parts, L.SHOP_BUY_UNKNOWN:format(r.buy, money(r.price)))
        elseif r.intermediate and r.unitCraft then
            tinsert(parts, L.SHOP_BUY_CHEAPER:format(r.buy, money(r.price), money(r.unitCraft)))
        elseif r.priceSource == "vendor" then
            tinsert(parts, r.price and L.SHOP_BUY_VENDOR:format(r.buy, money(r.price))
                or L.SHOP_BUY_VENDOR_NO_PRICE:format(r.buy))
        elseif r.price then
            tinsert(parts, L.SHOP_BUY:format(r.buy, money(r.price)))
        else
            tinsert(parts, L.SHOP_BUY_NO_PRICE:format(r.buy))
        end
    end
    if r.buy == 0 and r.craftBought == 0 and r.fromOwned == 0 and r.made == 0 then tinsert(parts, L.SHOP_ENOUGH) end
    return table.concat(parts, "; "), r.buy > 0
end

local function isCollapsed(key)
    return IPG_Settings.collapsed and IPG_Settings.collapsed[key] or false
end

-- a clickable heading that folds its section; returns true when the section is open
local function section(key, text, style, gap)
    local collapsed = isCollapsed(key)
    addLink(text .. (collapsed and "  |cff66aaff[+]|r" or "  |cff66aaff[-]|r"), style or "heading", 0, gap, function()
        IPG_Settings.collapsed = IPG_Settings.collapsed or {}
        IPG_Settings.collapsed[key] = not collapsed
        ns.Refresh()
    end, text, collapsed and L.SECTION_EXPAND or L.SECTION_COLLAPSE)
    return not collapsed
end

-- returns true if the Auctionator button should be shown below the last line
local function addShopping(skillLine)
    local rows, rank, untilSkill = ns.Shopping.Build(skillLine)
    if #rows == 0 then return end
    shoppingRows = rows
    listName = ("IPG: %s %d-%d"):format(Guide.GetName(skillLine), rank, untilSkill)
    if not section("shopping", L.SHOPPING_HEADER:format(rank, untilSkill), "heading", 12) then return end

    for _, r in ipairs(rows) do
        local color = r.have >= r.used and "|cff33ff33" or "|cffffffff"
        add(itemLabel(r.item) .. "  " .. color .. r.have .. "/" .. r.used .. "|r", "text", 8, 5)
        local advice, buying = shoppingAdvice(r)
        add(advice, buying and "note" or "good", 26, 1)
    end

    local total, unpriced = ns.Shopping.TotalCost(rows)
    add(L.SHOP_TOTAL:format(money(total)) .. (unpriced > 0 and L.SHOP_UNPRICED:format(unpriced) or ""), "text", 0, 8)
    if not ns.Prices.Available() then add(L.SHOP_NO_AUCTIONATOR, "note", 0) end
    local age = ns.Inventory.BankAge()
    local bankText = not age and L.BANK_NOT_CACHED
        or age < 60 and L.BANK_CACHED_NOW
        or L.BANK_CACHED:format(SecondsToTime(age, true))
    add(bankText, "note", 0)
    if ns.Prices.Available() then
        -- age of the oldest Auction House price the list uses (Auctionator tracks days since each item was seen)
        local oldest, anyAh, veryOld
        for _, r in ipairs(rows) do
            if r.priceSource == "ah" then
                anyAh = true
                if r.priceAge == nil then veryOld = true -- Auctionator gives no age past 21 days
                elseif not oldest or r.priceAge > oldest then oldest = r.priceAge end
            end
        end
        local lastScan = ns.Prices.LastScan()
        if not anyAh then
            add(L.AH_NO_PRICES, "note", 0)
        elseif lastScan then
            local ago = time() - lastScan
            add(L.AH_LAST_SCAN:format(SecondsToTime(math.max(ago, 60), true)), ago > 3 * 86400 and "bad" or "note", 0)
        elseif veryOld then
            add(L.AH_SCANNED:format(L.AGE_OLD), "bad", 0)
        elseif oldest then
            local when = oldest == 0 and L.AGE_TODAY or oldest == 1 and L.AGE_YESTERDAY or L.AGE_DAYS:format(oldest)
            add(L.AH_SCANNED:format(when), oldest > 3 and "bad" or "note", 0)
        end
    end
    return ns.Prices.Available() and #ns.Shopping.AuctionBuys(rows) > 0
end

-- intermediates the current recipe uses (bolts, bars, ...) that you can craft yourself and don't have
-- enough of for the crafts left: how many, how many your bags can make now, and whether they still skill up
local DIFFICULTY_COLORS = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040", [3] = "|cff808080" }

local function addPrep(target)
    local rows = {}
    for _, craft in ipairs(target.crafts) do
        local left = Guide.CraftsLeft(target, craft)
        for item, per in pairs(craft.reagents or {}) do
            local recipe = Guide.GetIntermediate(item)
            if recipe and recipe.spell ~= craft.spell and Guide.IsKnown(recipe.spell) then
                local needed, have = per * left, ns.Inventory.Have(item)
                if have < needed then
                    local yield = recipe.yield and recipe.yield > 0 and recipe.yield or 1
                    local canMake = math.ceil((needed - have) / yield)
                    for raw, rawPer in pairs(recipe.reagents) do
                        canMake = math.min(canMake, math.floor(ns.Inventory.Bags(raw) / rawPer))
                    end
                    tinsert(rows, { item = item, needed = needed, have = have, canMake = canMake,
                        difficulty = Guide.SkillUpDifficulty(recipe.spell) })
                end
            end
        end
    end
    if #rows == 0 then return end
    add(L.CRAFT_FIRST, "heading", 0, 10)
    for _, r in ipairs(rows) do
        add(itemLabel(r.item) .. "  " .. r.have .. "/" .. r.needed, "text", 8, 5)
        local parts = { r.canMake > 0 and L.PREP_CAN_MAKE:format(r.canMake) or L.PREP_NO_MATS }
        if r.difficulty and L["SKILLUP_" .. r.difficulty] then
            tinsert(parts, DIFFICULTY_COLORS[r.difficulty] .. L["SKILLUP_" .. r.difficulty] .. "|r")
        end
        add(table.concat(parts, " - "), "note", 26, 1)
    end
end

local function render()
    used = 0
    for _, link in ipairs(links) do link:Hide() end
    linksUsed = 0
    if listButton then listButton:Hide() end
    local showListButton
    local skillLine = Guide.GetOpenProfession()
    local target = skillLine and Guide.GetTarget(skillLine)
    if not skillLine or not ns.IsEnabled("panel") then
        panel:Hide()
        return
    end
    local open = section("panel", L.PANEL_TITLE:format(Guide.GetName(skillLine)), "title")
    if not open then
        -- minimized: one summary line
        local rank, maxRank, bracket = capInfo(skillLine)
        if rank and rank >= maxRank then
            add(L.CAP_MINIMIZED:format(maxRank, bracket, Guide.GetName(skillLine)), "bad", 0, 4)
        elseif target then
            add(L.MINIMIZED:format(Guide.SpellName(target.craft.spell), target.to, target.toGo), "note", 0, 4)
        end
    else
        addCap(skillLine)
    end

    if not open then -- nothing else while minimized
    elseif not target then
        local rank, max = Guide.GetSkill(skillLine)
        add(rank and rank >= 300 and L.GUIDE_DONE or L.NO_STEP:format(rank or 0), "note", 0, 8)
    else
        local step = target.step
        -- capped: this step only matters after training. Keep the recipe, where to get it and the shopping
        -- list (worth picking up on the same trip); drop alternatives, notes and the next-step preview.
        local rank, maxRank = Guide.GetSkill(skillLine)
        local capped = rank and maxRank and rank >= maxRank and capInfo(skillLine) and true or false
        add((capped and L.AFTER_TRAINING or "") .. L.STEP_HEADER:format(step.from, step.to, step.bracket),
            "heading", 0, capped and 14 or 8)
        if step.group then
            local tracks = Guide.GetTracks(skillLine, step.group)
            local track, chosen = Guide.GetTrack(skillLine, step.group)
            local text = L.ROUTE:format(track, chosen and "" or L.ROUTE_AUTO)
            if #tracks > 1 then
                addLink(text .. L.ROUTE_SWITCH, "note", 0, 2, function()
                    Guide.CycleTrack(skillLine, step.group)
                    ns.Refresh()
                end, L.ROUTE_TITLE, L.ROUTE_HINT:format(table.concat(tracks, ", ")))
            else
                add(text, "note", 0, 2)
            end
        end
        if target.option.label then add(target.option.label, "note", 0, 2) end
        -- how many are still left to craft, not the step's total
        for i, craft in ipairs(target.crafts) do
            local known = Guide.IsKnown(craft.spell)
            add(icon(craft.spell, 20) .. Guide.SpellName(craft.spell)
                .. L.CRAFT_LEFT:format(Guide.CraftsLeft(target, craft))
                .. (#target.crafts > 1 and (known and "" or (" |cffff5555" .. L.NOT_LEARNED_SHORT .. "|r")) or ""),
                "craft", 0, i == 1 and 5 or 3)
        end
        if target.option.together then add(L.MAKE_ALL, "note", 8) end
        if not target.isMain and not target.preferred then add(L.USING_ALTERNATIVE, "note", 8) end
        if target.known then
            addPrep(target) -- nothing to say when learned; instead what to craft first (bolts, ...)
        else
            add(L.NOT_LEARNED, "bad", 8)
            for _, craft in ipairs(target.crafts) do
                if not Guide.IsKnown(craft.spell) then
                    addSource(craft, target, step, skillLine, #target.crafts > 1)
                end
            end
        end

        -- other ways to do this step; clicking one makes it this step's choice
        if target.preferred then
            addLink(L.YOUR_CHOICE, "note", 8, nil, function()
                Guide.SetPreferred(skillLine, step, nil)
                ns.Refresh()
            end, L.YOUR_CHOICE_TITLE, L.YOUR_CHOICE_HINT)
        end
        local others = {}
        for index, option in ipairs(Guide.GetOptions(step)) do
            if option ~= target.option then
                for _, craft in ipairs(option) do
                    tinsert(others, { craft = craft, option = option, index = index })
                end
            end
        end
        if not capped and #others > 0 and section("alternatives", L.ALTERNATIVES, "heading", 10) then
            for _, other in ipairs(others) do
                local craft = other.craft
                local known = Guide.IsKnown(craft.spell)
                local range = (craft.from or craft.to) and (" (" .. (craft.from or step.from) .. "-" .. (craft.to or step.to) .. ")") or ""
                addLink(icon(craft.spell) .. Guide.SpellName(craft.spell) .. range
                    .. (other.option.label and (" - " .. other.option.label) or "")
                    .. (known and (" |cff33ff33" .. L.KNOWN .. "|r") or "") .. L.USE_LINK, "note", 8, nil,
                    function()
                        Guide.SetPreferred(skillLine, step, other.index)
                        ns.Refresh()
                    end, Guide.SpellName(craft.spell), L.USE_HINT)
            end
        end

        if not capped and step.notes and section("notes", L.NOTES, "heading", 10) then
            for _, note in ipairs(step.notes) do add(note, "note", 8) end
        end

        if ns.IsEnabled("shopping") then showListButton = addShopping(skillLine) end
    end

    for i = used + 1, #lines do lines[i]:Hide() end
    local height = PADDING * 2
    for i = 1, used do height = height + lines[i]:GetStringHeight() + lines[i].gap end
    if showListButton then
        listButton:ClearAllPoints()
        listButton:SetPoint("TOPLEFT", lines[used], "BOTTOMLEFT", -(lines[used].indent or 0), -8)
        listButton:Show()
        height = height + listButton:GetHeight() + 8
    end
    panel:SetHeight(height + 10)
    panel:Show()
end

-- Docking: Blizzard lays its panels (professions, AH, merchant, bank, ...) out side by side; the guide
-- sits right of the rightmost one, so it moves along when another window opens or closes. With no room
-- left on screen it hugs the right screen edge instead of running off it.
local PROFESSION_GAP = 60 -- clears the profession tabs sticking out of ProfessionsFrame's right side
local PANEL_GAP, EDGE_GAP, TOP_OFFSET = 12, 8, -20
local PANEL_AREAS = { "left", "center", "right", "doublewide" }
local dockedTo, dockedMode

-- frame's right / top edge in UIParent units
local function rightOf(frame) return frame:GetRight() * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() end
local function topOf(frame) return frame:GetTop() * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() end

local function rightmostPanel()
    local best, bestRight = ProfessionsFrame, ProfessionsFrame:GetRight() and rightOf(ProfessionsFrame)
    if not bestRight or not GetUIPanel then return ProfessionsFrame end
    for _, area in ipairs(PANEL_AREAS) do
        local frame = GetUIPanel(area)
        if frame and frame ~= ProfessionsFrame and frame:IsShown() and frame:GetRight() then
            local right = rightOf(frame)
            if right > bestRight then best, bestRight = frame, right end
        end
    end
    return best
end

local function dock()
    if not panel or not ProfessionsFrame:IsShown() then return end
    local target = rightmostPanel()
    local gap = target == ProfessionsFrame and PROFESSION_GAP or PANEL_GAP
    local fits = true
    if target:GetRight() then
        local scale = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
        fits = rightOf(target) + (gap + WIDTH) * scale <= UIParent:GetRight() - EDGE_GAP
    end
    local mode = fits and "beside" or "edge"
    if target == dockedTo and mode == dockedMode then return end
    dockedTo, dockedMode = target, mode
    panel:ClearAllPoints()
    if fits then
        panel:SetPoint("TOPLEFT", target, "TOPRIGHT", gap, TOP_OFFSET)
    else
        local scale = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
        panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -EDGE_GAP / scale,
            (topOf(target) - UIParent:GetTop()) / scale + TOP_OFFSET)
    end
end

local function attach()
    if not ProfessionsFrame then return end
    -- a child of the recipe page, so it hides with it (overview / specialization tabs)
    local page = ProfessionsFrame.CraftingPage or ProfessionsFrame
    panel = CreateFrame("Frame", "InlineProfessionGuidesPanel", page, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetClampedToScreen(true)
    panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", PROFESSION_GAP, TOP_OFFSET)
    dockedTo, dockedMode = ProfessionsFrame, "beside"
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    panel:Hide()
    lines, used = {}, 0

    listButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    listButton:SetSize(WIDTH - 2 * PADDING, 22)
    listButton:SetText(L.CREATE_LIST)
    listButton:SetScript("OnClick", function()
        if shoppingRows then ns.Prices.CreateShoppingList(listName, ns.Shopping.AuctionBuys(shoppingRows)) end
    end)
    listButton:Hide()

    page:HookScript("OnShow", render)

    -- re-dock when Blizzard shows / hides / repositions a panel (next frame, once its layout settled);
    -- a light poll catches windows closed some other way (e.g. walking away from the auctioneer)
    local function redock() RunNextFrame(dock) end
    for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
        if _G[name] then hooksecurefunc(name, redock) end
    end
    panel:HookScript("OnShow", dock)
    local elapsedSinceDock = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceDock = elapsedSinceDock + elapsed
        if elapsedSinceDock < 0.2 then return end
        elapsedSinceDock = 0
        dock()
    end)
    EventRegistry:RegisterCallback("Professions.ProfessionSelected", function() RunNextFrame(render) end, panel)
    ns.OnRefresh(function()
        if page:IsVisible() then render() end
    end)

    -- trainer / vendor distances go stale as the player moves: while the panel shows, redraw every 2 s
    -- once the player has moved more than 20 yards since the last draw
    local lastX, lastY
    C_Timer.NewTicker(2, function()
        if not panel:IsVisible() then return end
        local y, x = UnitPosition("player")
        if not x then return end
        if lastX and (x - lastX) ^ 2 + (y - lastY) ^ 2 < 400 then return end
        lastX, lastY = x, y
        render()
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", attach)
