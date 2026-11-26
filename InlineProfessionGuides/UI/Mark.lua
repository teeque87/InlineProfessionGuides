local _, ns = ...

-- A colored border + short label drawn over a row/slot of a Blizzard list.
-- Overlays are kept in a weak table so we never write fields onto Blizzard frames.

local Mark = {}
ns.Mark = Mark

Mark.COLORS = {
    now = { 0.1, 0.9, 0.1 },     -- needed for the current step
    later = { 1, 0.82, 0 },      -- needed for a later step
    alt = { 0.35, 0.65, 1 },     -- only used by an alternative route
}

local overlays = setmetatable({}, { __mode = "k" })

local function create(owner, textPoint, outset)
    local overlay = CreateFrame("Frame", nil, owner, "BackdropTemplate")
    if outset then
        overlay:SetPoint("TOPLEFT", -outset, outset)
        overlay:SetPoint("BOTTOMRIGHT", outset, -outset)
    else
        overlay:SetAllPoints()
    end
    overlay:SetFrameLevel(owner:GetFrameLevel() + 5)
    overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.text:SetPoint(textPoint or "RIGHT", overlay, textPoint or "RIGHT", -6, textPoint == "BOTTOMRIGHT" and 4 or 0)
    overlays[owner] = overlay
    return overlay
end

-- color: a key of Mark.COLORS; textPoint defaults to "RIGHT"; outset grows the border past the owner
function Mark.Show(owner, color, text, textPoint, outset)
    local overlay = overlays[owner] or create(owner, textPoint, outset)
    local c = Mark.COLORS[color] or Mark.COLORS.now
    overlay:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
    overlay.text:SetTextColor(c[1], c[2], c[3])
    overlay.text:SetText(text or "")
    overlay:Show()
end

-- Mark for profession list rows in Blizzard's own style: the row's "selected" highlight art,
-- desaturated and tinted, so it looks like a native selection in the mark color.
-- Falls back to a slim underline when the row has no such art.
local fancy = setmetatable({}, { __mode = "k" })
Mark.TEXT_NUDGE = 1 -- pixels up from the row's center

local function copyArt(texture, source)
    local atlas = source.GetAtlas and source:GetAtlas()
    if atlas then
        texture:SetAtlas(atlas)
    elseif source:GetTexture() then
        texture:SetTexture(source:GetTexture())
        texture:SetTexCoord(source:GetTexCoord())
    else
        return false
    end
    -- only the art; size it to our row (the source's anchors can point at the whole list)
    texture:SetAllPoints()
    return true
end

local function createFancy(owner)
    local f = CreateFrame("Frame", nil, owner)
    f:SetAllPoints()
    f:SetFrameLevel(owner:GetFrameLevel() + 1)

    f.art = f:CreateTexture(nil, "BACKGROUND")
    local source = owner.SelectedOverlay or owner.HighlightOverlay
    f.native = source ~= nil and copyArt(f.art, source)
    if f.native then
        f.art:SetDesaturated(true)
        f.art:SetBlendMode("ADD")
    else
        f.art:ClearAllPoints()
        f.art:SetPoint("BOTTOMLEFT", 4, 0)
        f.art:SetPoint("BOTTOMRIGHT", -4, 0)
        f.art:SetHeight(1)
    end

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("RIGHT", -6, 0)
    f.text:SetShadowOffset(1, -1)

    fancy[owner] = f
    return f
end

function Mark.ShowFancy(owner, color, text)
    local f = fancy[owner] or createFancy(owner)
    local c = Mark.COLORS[color] or Mark.COLORS.now
    if f.native then
        f.art:SetVertexColor(c[1], c[2], c[3], 0.7)
    else
        f.art:SetColorTexture(c[1], c[2], c[3], 0.8)
    end
    f.text:SetTextColor(c[1], c[2], c[3])
    f.text:SetText(text or "")
    -- the row's recipe name sits slightly above the row's center; match it
    f.text:ClearAllPoints()
    f.text:SetPoint("RIGHT", f, "RIGHT", -6, Mark.TEXT_NUDGE)
    f:Show()
end

function Mark.Hide(owner)
    local overlay = overlays[owner]
    if overlay then overlay:Hide() end
    local f = fancy[owner]
    if f then f:Hide() end
end

-- calls fn(row, elementData) every time a (recycled) ScrollBox row is filled
function Mark.HookScrollBox(scrollBox, fn)
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row, data) fn(row, data) end, ns, true)
    else
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame,
            function(_, row, data) fn(row, data) end, ns)
    end
end

-- color + label for a needed-recipe entry from Guide.GetNeededRecipes()
function Mark.ForRecipe(info)
    local L = ns.L
    if info.current then return info.alt and "alt" or "now", info.alt and L.MARK_ALT_NOW or L.MARK_NOW end
    return info.alt and "alt" or "later", (info.alt and L.MARK_ALT_AT or L.MARK_AT):format(info.at)
end

function Mark.Hex(color)
    local c = Mark.COLORS[color] or Mark.COLORS.now
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end
