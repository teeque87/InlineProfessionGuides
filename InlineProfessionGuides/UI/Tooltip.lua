local _, ns = ...
local L = ns.L
local Mark, Guide = ns.Mark, ns.Guide

-- Guide info in tooltips (like Auctionator's price lines): patterns/recipes the guide still needs,
-- materials you still have to buy, and trainer services.

function ns.NeededPatterns()
    return ns.Cached("patterns", Guide.GetNeededPatterns)
end

function ns.NeededMaterials()
    return ns.Cached("materials", ns.Shopping.GetAllBuys)
end

-- which profession's shopping list wants this material, for the tooltip text
local function materialFor(item)
    for skillLine in pairs(ns.Guides) do
        local rows, rank, untilSkill = ns.Shopping.Build(skillLine)
        for _, r in ipairs(rows) do
            if r.item == item and r.buy > 0 then return skillLine, r.buy, rank, untilSkill end
        end
    end
end

local function recipeLine(tooltip, info)
    local color, text = Mark.ForRecipe(info)
    tooltip:AddLine(Mark.Hex(color) .. L.TOOLTIP_RECIPE:format(Guide.GetName(info.skillLine), text) .. "|r")
end

local function addItemLines(tooltip, item)
    if not item or (issecretvalue and issecretvalue(item)) or not ns.IsEnabled("tooltips") then return end
    local pattern = ns.NeededPatterns()[item]
    if pattern then recipeLine(tooltip, pattern) end
    if ns.NeededMaterials()[item] then
        local skillLine, buy, rank, untilSkill = materialFor(item)
        if skillLine then
            tooltip:AddLine(Mark.Hex("now") .. L.TOOLTIP_MATERIAL:format(buy, Guide.GetName(skillLine), rank,
                untilSkill) .. "|r")
        end
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip == GameTooltip or tooltip == ItemRefTooltip then addItemLines(tooltip, data and data.id) end
    end)
else
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local _, link = tooltip:GetItem()
        addItemLines(tooltip, link and tonumber(link:match("item:(%d+)")))
    end)
end

-- trainer list rows: the recipe the service teaches
if GameTooltip.SetTrainerService then hooksecurefunc(GameTooltip, "SetTrainerService", function(tooltip, index)
    local spell = ns.TrainerSpellOf and ns.TrainerSpellOf(index)
    local info = spell and ns.IsEnabled("tooltips") and Guide.GetNeededRecipes()[spell]
    if info then
        recipeLine(tooltip, info)
        tooltip:Show()
    end
end) end
