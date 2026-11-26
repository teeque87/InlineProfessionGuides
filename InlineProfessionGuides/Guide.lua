local _, ns = ...

local Guide = {}
ns.Guide = Guide

local playerFaction = UnitFactionGroup("player")

local function isKnown(spell)
    return C_SpellBook.IsSpellKnown(spell, Enum.SpellBookSpellBank.Player)
end

function Guide.SpellName(spell)
    local info = C_Spell.GetSpellInfo(spell)
    return info and info.name or ("spell " .. spell)
end

function Guide.GetName(skillLine)
    local info = C_SkillInfo.GetSkillLineInfoByID(skillLine)
    return info and info.name or tostring(skillLine)
end

-- what the profession window reports for the open profession (for debugging detection)
function Guide.GetOpenProfessionRaw()
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if info then return info.professionID, info.professionName end
end

-- skill line ID of the guide for the profession window's current profession, or nil
function Guide.GetOpenProfession()
    local id, name = Guide.GetOpenProfessionRaw()
    if id and ns.Guides[id] then return id end
    if not name then return end
    for skillLine in pairs(ns.Guides) do
        local info = C_SkillInfo.GetSkillLineInfoByID(skillLine)
        if info and info.name == name then return skillLine end
    end
end

Guide.IsKnown = isKnown

-- current and max skill, or nil when the player doesn't have the profession
function Guide.GetSkill(skillLine)
    local info = C_SkillInfo.GetSkillLineInfoByID(skillLine)
    if info and info.rank and info.rank > 0 then return info.rank, info.maxRank end
end

-- each craft of an option with its own skill range; a chain runs in order (each until its `to`),
-- a "together" option makes all of its crafts over the whole step
local function craftRanges(option, step)
    local ranges, start = {}, step.from
    for _, craft in ipairs(option) do
        local from, to = craft.from or start, craft.to or step.to
        if option.together then from, to = craft.from or step.from, craft.to or step.to end
        tinsert(ranges, { craft = craft, from = from, to = to })
        start = to
    end
    return ranges
end

-- the craft of an option that covers rank, and where it ends
local function activeCraft(option, step, rank)
    for _, range in ipairs(craftRanges(option, step)) do
        if rank >= range.from and rank < range.to then return range.craft, range.to end
    end
end

local function options(step)
    local list = {}
    if step.main then tinsert(list, { option = step.main, isMain = true }) end
    for _, alt in ipairs(step.alts or {}) do tinsert(list, { option = alt, isMain = false }) end
    return list
end

local function optionKnown(option, step, rank)
    if option.together then
        for _, craft in ipairs(option) do
            if not isKnown(craft.spell) then return false end
        end
        return true
    end
    local craft = activeCraft(option, step, rank)
    return craft ~= nil and isKnown(craft.spell)
end

--[[ Routes: some guides offer complete alternative routes for a skill range (tabs on the page), stored as
     steps with group + track. The chosen route is saved per character; without a choice it's the guide's
     default, unless you know the current recipe of another route and not the default's. ]]
function Guide.GetTracks(skillLine, group)
    local tracks, seen, default = {}, {}, nil
    for _, step in ipairs(ns.Guides[skillLine].steps) do
        if step.group == group and not seen[step.track] then
            seen[step.track] = true
            tinsert(tracks, step.track)
        end
        if step.group == group and step.default then default = step.track end
    end
    return tracks, default or tracks[1]
end

local function chosenTrack(skillLine, group)
    local chosen = IPG_CharData and IPG_CharData.tracks and IPG_CharData.tracks[skillLine]
    return chosen and chosen[group]
end

function Guide.GetTrack(skillLine, group)
    local chosen = chosenTrack(skillLine, group)
    if chosen then return chosen, true end
    local _, default = Guide.GetTracks(skillLine, group)
    local rank = Guide.GetSkill(skillLine)
    if rank then
        local function stepIn(track)
            for _, step in ipairs(ns.Guides[skillLine].steps) do
                if step.group == group and step.track == track and rank >= step.from and rank < step.to then
                    return step
                end
            end
        end
        local defaultStep = stepIn(default)
        if defaultStep and not (defaultStep.main and optionKnown(defaultStep.main, defaultStep, rank)) then
            for _, track in ipairs((Guide.GetTracks(skillLine, group))) do
                local step = track ~= default and stepIn(track)
                if step and step.main and optionKnown(step.main, step, rank) then return track, false end
            end
        end
    end
    return default, false
end

-- next route of the group (wraps around); saved per character
function Guide.CycleTrack(skillLine, group)
    local tracks = Guide.GetTracks(skillLine, group)
    local current = Guide.GetTrack(skillLine, group)
    local nextTrack = tracks[1]
    for i, track in ipairs(tracks) do
        if track == current then nextTrack = tracks[i % #tracks + 1] end
    end
    IPG_CharData.tracks = IPG_CharData.tracks or {}
    IPG_CharData.tracks[skillLine] = IPG_CharData.tracks[skillLine] or {}
    IPG_CharData.tracks[skillLine][group] = nextTrack
end

-- is the step part of the route the player follows (faction + chosen tab)
local function onRoute(skillLine, step)
    if step.faction and step.faction ~= playerFaction then return false end
    return not step.group or step.track == Guide.GetTrack(skillLine, step.group)
end

local function routeSteps(skillLine)
    local list = {}
    for _, step in ipairs(ns.Guides[skillLine].steps) do
        if onRoute(skillLine, step) then tinsert(list, step) end
    end
    return list
end

function Guide.GetStep(skillLine, rank)
    if not ns.Guides[skillLine] then return end
    for _, step in ipairs(routeSteps(skillLine)) do
        if rank >= step.from and rank < step.to then return step end
    end
end

--[[ Smart pick for a step at a skill: the main option if its recipe(s) are known, else the first known
     alternative, else the main option anyway (the panel then says where to learn it).
     Returns { crafts, craft (first unknown, else first), to, toGo, option, isMain, known } or nil. ]]
-- an option the player picked for a step (clicked in the panel), saved per character
local function stepKey(step)
    return step.from .. "-" .. step.to .. (step.track and ("|" .. step.track) or "")
end

function Guide.GetPreferred(skillLine, step)
    local prefs = IPG_CharData and IPG_CharData.preferred and IPG_CharData.preferred[skillLine]
    return prefs and prefs[stepKey(step)]
end

-- index into main + alts (1 = main); nil goes back to the automatic pick
function Guide.SetPreferred(skillLine, step, index)
    IPG_CharData.preferred = IPG_CharData.preferred or {}
    IPG_CharData.preferred[skillLine] = IPG_CharData.preferred[skillLine] or {}
    IPG_CharData.preferred[skillLine][stepKey(step)] = index
end

-- main first, then the alternatives (the order SetPreferred's index refers to)
function Guide.GetOptions(step)
    local list = {}
    for _, candidate in ipairs(options(step)) do tinsert(list, candidate.option) end
    return list
end

local function pick(step, rank, skillLine)
    local candidates = options(step)
    local preferred = skillLine and Guide.GetPreferred(skillLine, step)
    if preferred and candidates[preferred] then
        candidates = { candidates[preferred] }
    end
    local fallback
    for _, candidate in ipairs(candidates) do
        local option = candidate.option
        local craft, to = activeCraft(option, step, rank)
        if craft then
            local crafts = option.together and { unpack(option) } or { craft }
            local first
            for _, c in ipairs(crafts) do
                if not first and not isKnown(c.spell) then first = c end
            end
            local target = { crafts = crafts, craft = first or crafts[1], to = to, rank = rank, toGo = to - rank,
                step = step, option = option, isMain = candidate.isMain, known = first == nil }
            target.preferred = preferred ~= nil and #candidates == 1
            if target.known or target.preferred then return target end
            fallback = fallback or (candidate.isMain and target)
        end
    end
    return fallback
end

function Guide.GetTarget(skillLine)
    local rank = Guide.GetSkill(skillLine)
    if not rank then return end
    local step = Guide.GetStep(skillLine, rank)
    return step and pick(step, rank, skillLine)
end

local function remainingSteps(skillLine, rank)
    local list = {}
    for _, step in ipairs(routeSteps(skillLine)) do
        if step.to > rank then tinsert(list, step) end
    end
    return list
end

--[[ Every guide recipe the player still has to learn, for highlighting at trainers and vendors.
     spellID -> { skillLine, at = skill it's used from, current = used in the current step, alt = only an alternative } ]]
function Guide.GetNeededRecipes()
    local needed = {}
    for skillLine in pairs(ns.Guides) do
        local rank = Guide.GetSkill(skillLine)
        if rank then
            for _, step in ipairs(remainingSteps(skillLine, rank)) do
                for _, candidate in ipairs(options(step)) do
                    for _, range in ipairs(craftRanges(candidate.option, step)) do
                        local spell = range.craft.spell
                        if range.to > rank and not needed[spell] and not isKnown(spell) then
                            needed[spell] = { skillLine = skillLine, at = range.from, alt = not candidate.isMain,
                                current = rank >= step.from and rank < step.to }
                        end
                    end
                end
            end
        end
    end
    return needed
end

-- pattern/recipe item ID -> needed-recipe info (via the source data's `teach` item)
function Guide.GetNeededPatterns()
    local patterns = {}
    for spell, info in pairs(Guide.GetNeededRecipes()) do
        local source = ns.Sources[spell]
        if source and source.teach then patterns[source.teach] = info end
    end
    return patterns
end

local function bracketEnd(skillLine, bracket)
    local last
    for _, step in ipairs(routeSteps(skillLine)) do
        if step.bracket == bracket then last = step.to end
    end
    return last
end

--[[ The plan for the rest of the current bracket (e.g. 150-200 Expert), following the smart pick per step;
     the current step only counts the crafts still left.
     Returns consumed (itemID -> amount used by the planned crafts), produced (itemID -> amount the planned
     crafts make, e.g. bolts), rank, untilSkill. ]]
function Guide.GetBracketPlan(skillLine)
    local rank = Guide.GetSkill(skillLine)
    local current = rank and Guide.GetStep(skillLine, rank)
    if not current then return {}, {}, rank end
    local untilSkill = bracketEnd(skillLine, current.bracket)
    local consumed, produced = {}, {}
    for _, step in ipairs(remainingSteps(skillLine, rank)) do
        if step.from >= untilSkill then break end
        local at = math.max(rank, step.from)
        local target = pick(step, at, skillLine)
        for _, range in ipairs(target and craftRanges(target.option, step) or {}) do
            if range.to > at then
                local count = range.craft.count
                if at > range.from then
                    count = math.ceil(count * (range.to - at) / (range.to - range.from))
                end
                for item, perCraft in pairs(range.craft.reagents or {}) do
                    consumed[item] = (consumed[item] or 0) + perCraft * count
                end
                local source = ns.Sources[range.craft.spell]
                if source and source.creates then
                    produced[source.creates] = (produced[source.creates] or 0) + count
                end
            end
        end
    end
    return consumed, produced, rank, untilSkill
end

-- itemID -> { spell, reagents } for every guide recipe that creates an item (bolts, …)
function Guide.GetRecipeForItem(item)
    for _, guide in pairs(ns.Guides) do
        for _, step in ipairs(guide.steps) do
            for _, candidate in ipairs(options(step)) do
                for _, craft in ipairs(candidate.option) do
                    local source = ns.Sources[craft.spell]
                    if source and source.creates == item then return craft end
                end
            end
        end
    end
end

-- crafts of `craft` still left in the target's step: one per skill point until its range ends
function Guide.CraftsLeft(target, craft)
    for _, range in ipairs(craftRanges(target.option, target.step)) do
        if range.craft == craft then
            return math.max(0, range.to - math.max(target.rank, range.from))
        end
    end
    return target.toGo or 0
end

-- recipes of the open profession window by the item they make, for intermediates the guides don't list;
-- built once per profession (dropped when a recipe is learned)
local openRecipes = {}

local function openProfessionRecipe(item)
    local profession = Guide.GetOpenProfessionRaw()
    if not profession or not C_TradeSkillUI.GetAllRecipeIDs or not C_TradeSkillUI.GetRecipeSchematic then return end
    local map = openRecipes[profession]
    if not map then
        map = {}
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local schematic = C_TradeSkillUI.GetRecipeSchematic(id, false)
            local output = schematic and schematic.outputItemID
            if output and not map[output] then
                local reagents = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                    local reagent = slot.reagents and slot.reagents[1]
                    if reagent and reagent.itemID and slot.quantityRequired and slot.quantityRequired > 0 then
                        reagents[reagent.itemID] = slot.quantityRequired
                    end
                end
                if next(reagents) then
                    map[output] = { spell = id, reagents = reagents, yield = schematic.quantityMin }
                end
            end
        end
        openRecipes[profession] = map
    end
    return map[item]
end

local recipeEvents = CreateFrame("Frame")
recipeEvents:RegisterEvent("NEW_RECIPE_LEARNED")
recipeEvents:SetScript("OnEvent", function() wipe(openRecipes) end)

-- a recipe that makes `item` (bolts, bars, ...): from the guides, else from the open profession window.
-- Returns { spell, reagents = { item = perCraft }, yield } or nil.
function Guide.GetIntermediate(item)
    return Guide.GetRecipeForItem(item) or openProfessionRecipe(item)
end

-- how a recipe skills up right now: 0 orange, 1 yellow, 2 green, 3 grey, or nil when unknown
-- (only answers for the profession that is open)
function Guide.SkillUpDifficulty(spell)
    local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(spell)
    return info and info.relativeDifficulty
end

-- /ipg test <spellID>: pretend this recipe is the target, to check the highlight
Guide.testSpell = nil

-- spellID -> target, for every guided profession the player has
function Guide.GetTargets()
    local targets = {}
    if Guide.testSpell then
        targets[Guide.testSpell] = { craft = { spell = Guide.testSpell }, toGo = 5, known = true }
    end
    for skillLine in pairs(ns.Guides) do
        local target = Guide.GetTarget(skillLine)
        if target then
            target.skillLine = skillLine
            for _, craft in ipairs(target.crafts) do targets[craft.spell] = target end
        end
    end
    return targets
end
