local _, ns = ...
local Mark = ns.Mark
local Guide = ns.Guide

-- At a trainer: marks guide recipes you still need to learn ("now" / "at 170" / "alt").
-- Rows are matched by service index when the row data exposes one, else by the recipe name shown in the row.

local needed, byName, scrollBox = {}, {}, nil

-- Forever's trainer rows hold a tree node; the service fields live in node:GetData()
local function rowData(data)
    if type(data) == "table" and type(data.GetData) == "function" then return data:GetData() end
    return data
end

local function serviceIndexOf(data)
    data = rowData(data)
    if type(data) == "number" then return data end
    if type(data) == "table" then
        local index = data.skillIndex or data.serviceIndex or data.index
        return type(index) == "number" and index or nil
    end
end

-- spell ID taught by a trainer service: tooltip data first, then the created item, then the name
local function spellOf(index)
    local tooltip = C_TooltipInfo and C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(index)
    local id = tooltip and tooltip.id
    if id and not (issecretvalue and issecretvalue(id)) then
        if needed[id] then return id end
        for spell, source in pairs(ns.Sources) do
            if source.creates == id and needed[spell] then return spell end
        end
    end
    local name = GetTrainerServiceInfo(index)
    return name and byName[name]
end
ns.TrainerSpellOf = spellOf -- for the trainer tooltip

-- a needed spell whose name is one of the row's texts (row regions and its direct children)
local function spellByRowText(row)
    local frames = { row, row:GetChildren() }
    for _, frame in ipairs(frames) do
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                local text = region:GetText()
                if text and not (issecretvalue and issecretvalue(text)) and byName[text] then return byName[text] end
            end
        end
    end
end

local function decorate(row, data)
    local index = serviceIndexOf(data)
    local spell = (index and spellOf(index)) or spellByRowText(row)
    local info = spell and ns.IsEnabled("trainerBorder") and needed[spell]
    if info then
        Mark.Show(row, (Mark.ForRecipe(info))) -- border only; the text is in the tooltip
    else
        Mark.Hide(row)
    end
end

local function refresh()
    if not (ClassTrainerFrame and ClassTrainerFrame:IsShown() and scrollBox) then return end
    needed, byName = Guide.GetNeededRecipes(), {}
    for spell in pairs(needed) do byName[Guide.SpellName(spell)] = spell end
    scrollBox:ForEachFrame(function(row) decorate(row, row:GetElementData()) end)
end

-- /ipg while a trainer is open: which guide recipes this trainer has, and how a row's data looks
function ns.DebugTrainer()
    if not (scrollBox and ClassTrainerFrame:IsShown()) then return end
    local matched, total = {}, 0
    for index = 1, GetNumTrainerServices() do
        local name, serviceType = GetTrainerServiceInfo(index)
        if serviceType ~= "header" then
            total = total + 1
            if name and byName[name] then tinsert(matched, name .. " (" .. tostring(serviceType) .. ")") end
        end
    end
    ns.Print(("trainer: %d services, guide recipes here: %s"):format(total,
        #matched > 0 and table.concat(matched, ", ") or "none"))
    local done = false
    scrollBox:ForEachFrame(function(row)
        if done then return end
        done = true
        local data, keys = rowData(row:GetElementData()), {}
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(v) ~= "function" and type(v) ~= "table" then tinsert(keys, tostring(k) .. "=" .. tostring(v)) end
            end
        end
        ns.Print("trainer row data:", type(data), table.concat(keys, ", "))
    end)
end

-- /ipg dump: full trainer details into the saved variables file
function ns.DumpTrainer(out)
    if not (scrollBox and ClassTrainerFrame and ClassTrainerFrame:IsShown()) then
        tinsert(out, "trainer: not open")
        return
    end
    for index = 1, GetNumTrainerServices() do
        local name, serviceType = GetTrainerServiceInfo(index)
        local tooltip = C_TooltipInfo and C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(index)
        tinsert(out, ("service %d: %s [%s] tooltipType=%s id=%s -> guide spell %s"):format(index, tostring(name),
            tostring(serviceType), tostring(tooltip and tooltip.type), tostring(tooltip and tooltip.id),
            tostring(spellOf(index))))
    end
    local rowNumber = 0
    scrollBox:ForEachFrame(function(row)
        rowNumber = rowNumber + 1
        local data, keys = rowData(row:GetElementData()), {}
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(v) ~= "function" then tinsert(keys, tostring(k) .. "=" .. tostring(v)) end
            end
        end
        local texts = {}
        for _, frame in ipairs({ row, row:GetChildren() }) do
            for _, region in ipairs({ frame:GetRegions() }) do
                if region:GetObjectType() == "FontString" and region:GetText() then tinsert(texts, region:GetText()) end
            end
        end
        tinsert(out, ("row %d: data(%s) %s | texts: %s | marked by text: %s"):format(rowNumber, type(data),
            table.concat(keys, ", "), table.concat(texts, " / "), tostring(spellByRowText(row))))
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", function()
    scrollBox = ClassTrainerFrame and ClassTrainerFrame.ScrollBox
    if not scrollBox then return end
    Mark.HookScrollBox(scrollBox, decorate)
    local events = CreateFrame("Frame")
    events:RegisterEvent("TRAINER_UPDATE")
    events:RegisterEvent("TRAINER_SHOW")
    events:SetScript("OnEvent", function() RunNextFrame(refresh) end)
    ClassTrainerFrame:HookScript("OnShow", function() RunNextFrame(refresh) end)
    refresh()
end)
ns.OnRefresh(refresh)
