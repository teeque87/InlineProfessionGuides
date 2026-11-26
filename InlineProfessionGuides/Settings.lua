local addonName, ns = ...
local L = ns.L

-- On/off switches for every feature (account-wide, IPG_Settings), and the options page under
-- Game Menu > Options > AddOns.

local OPTIONS = {
    { key = "panel", label = "OPT_PANEL" },
    { key = "shopping", label = "OPT_SHOPPING", parent = "panel" },
    { key = "recipeBorder", label = "OPT_RECIPE_BORDER" },
    { key = "vendorBorder", label = "OPT_VENDOR_BORDER" },
    { key = "trainerBorder", label = "OPT_TRAINER_BORDER" },
    { key = "tooltips", label = "OPT_TOOLTIPS" },
}

function ns.IsEnabled(key)
    local value = IPG_Settings and IPG_Settings[key]
    return value == nil or value == true
end

function ns.SetEnabled(key, enabled)
    IPG_Settings[key] = enabled and true or false
    ns.Refresh()
end

-- forget the routes and alternatives picked in the panel
function ns.ResetChoices()
    IPG_CharData.tracks, IPG_CharData.preferred = nil, nil
    ns.Refresh()
end

local category

local function buildPage()
    local page = CreateFrame("Frame")
    page.name = L.ADDON_NAME
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.ADDON_NAME)
    local version = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

    local boxes = {}
    for i, option in ipairs(OPTIONS) do
        local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        if i == 1 then
            box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
        else -- children are indented under their parent
            local indent = (option.parent and 24 or 0) - (OPTIONS[i - 1].parent and 24 or 0)
            box:SetPoint("TOPLEFT", boxes[i - 1], "BOTTOMLEFT", indent, -4)
        end
        local label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", box, "RIGHT", 4, 0)
        label:SetText(L[option.label])
        box:SetScript("OnClick", function(self)
            ns.SetEnabled(option.key, self:GetChecked())
            for _, b in ipairs(boxes) do b.update() end
        end)
        box.update = function()
            box:SetChecked(ns.IsEnabled(option.key))
            box:SetEnabled(not option.parent or ns.IsEnabled(option.parent))
        end
        tinsert(boxes, box)
    end

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(220, 24)
    reset:SetPoint("TOPLEFT", boxes[#boxes], "BOTTOMLEFT", -(OPTIONS[#OPTIONS].parent and 24 or 0), -16)
    reset:SetText(L.OPT_RESET)
    reset:SetScript("OnClick", function()
        ns.ResetChoices()
        ns.Print(L.CHOICES_RESET)
    end)
    local hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.OPT_HINT)

    page:SetScript("OnShow", function()
        for _, box in ipairs(boxes) do box.update() end
    end)
    return page
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(L.ADDON_NAME)
    end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    local page = buildPage()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(page, L.ADDON_NAME)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
end)
