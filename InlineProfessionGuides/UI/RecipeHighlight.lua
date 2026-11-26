local _, ns = ...
local L = ns.L
local Mark = ns.Mark

-- Marks the guide's current recipe in ProfessionsFrame.CraftingPage.RecipeList:
-- green border + "13 to go" (target skill - current skill, so a craft without a skill-up keeps the number).

local targets = {}
local scrollBox

local function recipeIDOf(node)
    local data = node and node.GetData and node:GetData()
    local info = type(data) == "table" and data.recipeInfo
    local id = info and info.recipeID
    if id == nil or (issecretvalue and issecretvalue(id)) then return end
    return id
end

local function decorate(row, node)
    local target = ns.IsEnabled("recipeBorder") and targets[recipeIDOf(node)]
    if target then
        Mark.ShowFancy(row, "now", L.TO_GO:format(target.toGo))
    else
        Mark.Hide(row)
    end
end

local function refresh()
    targets = ns.Guide.GetTargets()
    if scrollBox and scrollBox:IsVisible() then
        scrollBox:ForEachFrame(function(row) decorate(row, row:GetElementData()) end)
    end
end
ns.OnRefresh(refresh)

local function attach()
    local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
    scrollBox = list and list.ScrollBox
    if not scrollBox then
        ns.Print("recipe list not found, highlight disabled")
        return
    end
    Mark.HookScrollBox(scrollBox, decorate)
    ProfessionsFrame:HookScript("OnShow", refresh)
    refresh()
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", attach)
