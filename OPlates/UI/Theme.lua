local _, addon = ...

-- OPlates shared UI theme. One place for the colours, backdrops, fonts
-- and small frame helpers so the whole settings window matches the look of the
-- Class / Spec Filter windows: black glass body, thin gold trim, class-coloured
-- accents. Nothing here creates frames on load; it only defines constants and
-- helper functions used by UI/Widgets.lua and UI/Settings.lua.

local T = {}
addon.UITheme = T

T.FONT = "Fonts\\FRIZQT__.TTF"

-- Palette (r, g, b[, a]).
T.GOLD      = { 1.00, 0.82, 0.00 }
T.GOLD_DIM  = { 0.62, 0.50, 0.12 }
T.TEXT      = { 0.92, 0.92, 0.92 }
T.TEXT_DIM  = { 0.62, 0.62, 0.62 }
T.TEXT_MUTE = { 0.45, 0.45, 0.45 }
T.ACCENT    = { 0.30, 0.62, 1.00 }  -- selected / interactive blue
T.GREEN     = { 0.30, 1.00, 0.42 }
T.RED       = { 1.00, 0.34, 0.34 }
T.YELLOW    = { 1.00, 0.82, 0.00 }

-- The window chrome is the exact dark dialog + gold border the filter windows use.
T.WINDOW_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}
-- Flat glass panel for the nav rail and the scroll area.
T.PANEL_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
-- A soft card for one inline group of options.
T.CARD_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
-- A small inset control track (toggle box, slider rail, dropdown field).
T.FIELD_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function unpackc(c, a)
    return c[1], c[2], c[3], a or c[4] or 1
end
T.unpack = unpackc

-- Create a FontString with our font and a colour (defaults to T.TEXT).
function T.Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(T.FONT, size or 12, flags)
    fs:SetTextColor(unpackc(color or T.TEXT))
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

-- A thin horizontal gold divider line anchored by the caller.
function T.Divider(parent)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    tex:SetTexture(1, 0.82, 0, 0.35)
    return tex
end

-- A 1 px inner border highlight (used for hover / selected states).
function T.Glass(frame, backdrop, bg, border)
    frame:SetBackdrop(backdrop or T.PANEL_BACKDROP)
    if bg then frame:SetBackdropColor(unpackc(bg)) end
    if border then frame:SetBackdropBorderColor(unpackc(border)) end
    return frame
end

-- Gold "SOON" ribbon for the reserved (not-yet-built) nav entries.
function T.SoonBadge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetWidth(38); b:SetHeight(14)
    b:SetBackdrop(T.FIELD_BACKDROP)
    b:SetBackdropColor(0.20, 0.16, 0.02, 0.95)
    b:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    b.text = T.Text(b, 9, T.GOLD, "OUTLINE")
    b.text:SetPoint("CENTER")
    b.text:SetText("SOON")
    return b
end

-- ring colours of the settings icons. Friendly green, Enemy red, the
-- others match what the page is about (all softened to sit on black glass).
T.RING = {
    HOME     = { 1.00, 0.82, 0.00 },  -- gold, the OPlates trim
    FRIENDLY = { 0.18, 1.00, 0.28 },  -- full green
    ENEMY    = { 1.00, 0.12, 0.12 },  -- full red
    PLATES   = { 0.80, 0.82, 0.88 },  -- silver (plate parts)
    AURAS    = { 0.72, 0.42, 1.00 },  -- arcane purple (CC / buffs / debuffs)
    ADVANCED = { 0.40, 0.66, 1.00 },  -- steel blue (engine settings)
    HEALERCC = { 0.20, 0.92, 0.78 },  -- healing teal
    RAID     = { 1.00, 0.55, 0.14 },  -- boss-warning orange
    TOOLS    = { 0.86, 0.58, 0.26 },  -- bronze
    SHARE    = { 0.36, 0.82, 1.00 },  -- sky blue
    PROFILES = { 0.96, 0.86, 0.60 },  -- parchment
    SUPPORT  = { 1.00, 0.46, 0.66 },  -- warm rose
}

-- A circular icon. Pre-rounded OPlates art (Art\*.tga) is drawn as it is;
-- game icons go through the portrait renderer like everywhere else.
function T.SetIcon(tex, path)
    if type(path) == "string" and path:find("\\AddOns\\", 1, true) then
        tex:SetTexture(path)
        tex:SetTexCoord(0, 1, 0, 1)
    else
        addon.SetCircularTexture(tex, path)
    end
end

-- The nameplate ring, tinted, around a circular icon of the given size.
function T.Ring(parent, icon, size, color, alpha)
    local ring = parent:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(addon.CLASS_ICON_BORDER)
    local tc = addon.CLASS_ICON_BORDER_TCOORDS
    if tc then ring:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    local s = size * (size <= 24 and 1.20 or 1.13)
    ring:SetWidth(s); ring:SetHeight(s)
    ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local c = color or T.GOLD
    ring:SetVertexColor(c[1], c[2], c[3], alpha or 1)
    return ring
end

-- Shared hover-glow helper for clickable rows. Returns a HIGHLIGHT texture.
function T.HoverTex(frame, color)
    local hl = frame:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(frame)
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(unpackc(color or T.ACCENT, 0.12))
    hl:SetBlendMode("ADD")
    return hl
end
