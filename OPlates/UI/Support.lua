local addonName, addon = ...

-- OPlates Support windows. "Support OPlates" (settings rail) closes the
-- settings window and opens a short thank-you message; its heart icon opens the
-- donation window (QR code, copy-address box, link box). The cross of the
-- donation window returns to the message. Nothing is built until first opened.

local T = addon.UITheme
local S = {}
addon.UISupport = S

-- The address, the donation link and the project page shown in the windows.
S.ADDRESS = "TFoVYvxDwCvyxWmsQXxEVwLgZhPkJFwzyk"
S.NETWORK = "USDT TRC20"
S.LINK = "https://reymit.ir/FreakySphere"
S.UPDATES = "https://github.com/FreakySphere/OPlates"

local function authorName()
    local a = GetAddOnMetadata and GetAddOnMetadata(addonName, "Author")
    if type(a) == "string" then a = a:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$") end
    return (a and a ~= "") and a or "FreakySphere"
end
S.AuthorName = authorName

S.MESSAGE = {
    "Hi, I'm %s. I built OPlates to give back to the lovely WotLK 3.3.5a community, and especially to support Warmane players and keep the spirit of this server alive. It took many long hours of work to make every plate and mechanism fixed and stable.",
    "OPlates is completely free, and it always will be. But if it has made your games a little easier or a little more fun, a small donation is deeply appreciated to help keep this project growing and fuel my passion to create even more insane addons like this.",
    "Whether you donate or just share OPlates with a friend, your support means the world to me. Thank you for being part of this community.",
}

local message, donate

-- A movable dark dialog with the gold border, like the settings window.
local function dialog(name, w, h)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetWidth(w); f:SetHeight(h)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(T.WINDOW_BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0.97)
    if UISpecialFrames then tinsert(UISpecialFrames, name) end
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f:SetScript("OnHide", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

-- A centred, wrapped paragraph under the previous region; returns its height.
local function paragraph(f, prev, gap, size, color, text, width)
    local fs = T.Text(f, size, color)
    fs:SetWidth(width)
    fs:SetJustifyH("CENTER")
    fs:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
    fs:SetText(text)
    return fs, fs:GetStringHeight()
end

-------------------------------------------------------------------------------
-- Shared pieces: read-only selectable boxes and the red button. The game cannot
-- write to the clipboard, so "Copy" selects the text and the player presses Ctrl+C.
-------------------------------------------------------------------------------
local BOX_H = 28
local BOX_W = 340
local DON_W = 400
local QR_SIZE = 200
S.COPY_HINT = "Selected! Now press Ctrl+C to copy."
S.IDLE_HINT = "Click a box, then press Ctrl+C to copy."
S.LINK_HINT = "Click the link, then press Ctrl+C to copy it."

-- A read-only, selectable EditBox in the theme's field style. Typing snaps back
-- to the value. Focusing it selects the value and writes the copy hint into
-- owner[key] (a FontString of the window).
local function editBox(holder, value, owner, key)
    local e = CreateFrame("EditBox", nil, holder)
    e:SetPoint("TOPLEFT", holder, "TOPLEFT", 9, -2)
    e:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -9, 2)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetFont(T.FONT, 12)
    e:SetTextColor(1, 1, 1)
    e:SetJustifyH("CENTER")
    e:SetText(value)
    e.value = value
    e.owner = owner
    e.key = key
    e:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= self.value then self:SetText(self.value); self:HighlightText() end
    end)
    e:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        local hint = self.owner and self.owner[self.key]
        if hint then hint:SetText(S.COPY_HINT) end
    end)
    e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

-- A label and a box at y px below the window top. Centred, or left at x=30.
-- Label + box take 14 + 4 + 28 px.
local function copyBox(f, label, value, y, owner, key, centred)
    local l = T.Text(f, 11, T.TEXT_DIM)
    if centred then
        l:SetPoint("TOP", f, "TOP", 0, -y)
    else
        l:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -y)
    end
    l:SetText(label)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetWidth(BOX_W); holder:SetHeight(BOX_H)
    if centred then
        holder:SetPoint("TOP", l, "BOTTOM", 0, -4)
    else
        holder:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -4)
    end
    T.Glass(holder, T.FIELD_BACKDROP, { 0.02, 0.02, 0.03, 0.95 }, { T.RING.SUPPORT[1], T.RING.SUPPORT[2], T.RING.SUPPORT[3], 0.7 })
    local e = editBox(holder, value, owner, key)
    holder.edit = e
    return l, holder, e
end

-- The red button look of the settings window, with a fixed width.
local function button(f, text, w)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetWidth(w); b:SetHeight(22)
    b:SetText(text)
    return b
end

-- Select the whole value of a box and show the copy hint.
local function select_(e)
    e:SetFocus()
    e:HighlightText()
    local hint = e.owner and e.owner[e.key]
    if hint then hint:SetText(S.COPY_HINT) end
end

-------------------------------------------------------------------------------
-- Window 1: the thank-you message, the updates link and the heart button.
-------------------------------------------------------------------------------
local MSG_W = 520
local TEXT_W = MSG_W - 60

local function buildMessage()
    local f = dialog("OPlatesSupportWindow", MSG_W, 480)

    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetWidth(45.2); f.logo:SetHeight(45.2)
    f.logo:SetPoint("TOP", f, "TOP", 0, -17.4)
    T.SetIcon(f.logo, addon.LOGO_ART)
    local y = 20 + 40

    local title = T.Text(f, 18, T.GOLD, "OUTLINE")
    title:SetPoint("TOP", f.logo, "BOTTOM", 0, -7.4)
    title:SetText("Thank you for using " .. (addon.addonTitle or "OPlates"))
    f.title = title
    y = y + 10 + 20

    local prev, h = title, 0
    f.paras = {}
    for i, text in ipairs(S.MESSAGE) do
        local t = (i == 1) and text:format(authorName()) or text
        prev, h = paragraph(f, prev, i == 1 and 14 or 10, 12, T.TEXT, t, TEXT_W)
        f.paras[i] = prev
        y = y + (i == 1 and 14 or 10) + h
    end

    local sign
    sign, h = paragraph(f, prev, 12, 13, T.RING.SUPPORT, "With love, " .. authorName(), TEXT_W)
    f.sign = sign
    y = y + 12 + h

    -- The project page, under the signature: a selectable box like the donation one.
    local updLabel, updHolder, upd = copyBox(f, "For updates visit:", S.UPDATES, y + 14, f, "updHint", true)
    f.updates = upd
    f.updLabel = updLabel
    f.updHolder = updHolder
    f.updHint = T.Text(f, 11, T.TEXT_DIM)
    f.updHint:SetPoint("TOP", updHolder, "BOTTOM", 0, -8)
    f.updHint:SetText(S.LINK_HINT)
    y = y + 14 + 14 + 4 + BOX_H + 8 + 14

    local line = T.Divider(f)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -(y + 14))
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -(y + 14))
    y = y + 14

    -- The heart: a big round button with a breathing rose glow.
    local b = CreateFrame("Button", "OPlatesSupportHeart", f)
    b:SetWidth(81.4); b:SetHeight(81.4)
    b:SetPoint("TOP", f, "TOP", 0, -(y + 16 - 4.7))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    T.SetIcon(b.icon, addon.SUPPORT_ART)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(addon.CLASS_ICON_BORDER)
    local tc = addon.CLASS_ICON_BORDER_TCOORDS
    if tc then b.glow:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    b.glow:SetWidth(72 * 1.42); b.glow:SetHeight(72 * 1.42)
    b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(T.RING.SUPPORT[1], T.RING.SUPPORT[2], T.RING.SUPPORT[3], 0.35)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetTexture(addon.CLASS_ICON_BORDER)
    if tc then b.hl:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    b.hl:SetWidth(72 * 1.22); b.hl:SetHeight(72 * 1.22)
    b.hl:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.hl:SetBlendMode("ADD")
    b.hl:SetVertexColor(1, 1, 1, 0.6)
    -- Only runs while this window is open (one SetAlpha per frame).
    local t0 = 0
    b:SetScript("OnUpdate", function(self, elapsed)
        t0 = (t0 + (elapsed or 0)) % 2.4
        self.glow:SetAlpha(0.35 + 0.45 * (0.5 - 0.5 * math.cos(t0 / 2.4 * 2 * math.pi)))
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Support " .. (addon.addonTitle or "OPlates"), T.RING.SUPPORT[1], T.RING.SUPPORT[2], T.RING.SUPPORT[3])
        GameTooltip:AddLine("Opens the donation details. Thank you!", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() S.OpenDonate() end)
    f.heart = b
    y = y + 16 + 72

    local hint = T.Text(f, 12, T.RING.SUPPORT)
    hint:SetPoint("TOP", b, "BOTTOM", 0, -5.3)
    hint:SetText("Click the heart to support")
    f.hint = hint
    y = y + 10 + 14

    -- Back to the settings window.
    local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    back:SetWidth(140); back:SetHeight(22)
    back:SetPoint("TOP", hint, "BOTTOM", 0, -14)
    back:SetText("Back to settings")
    back:SetScript("OnClick", function() S.BackToSettings() end)
    f.back = back
    y = y + 14 + 22

    f:SetScript("OnShow", function() f.updHint:SetText(S.LINK_HINT) end)
    f:SetHeight(y + 22)
    return f
end

-------------------------------------------------------------------------------
-- Window 2: QR code, copy-address box and link box.
-------------------------------------------------------------------------------
local function buildDonate()
    local f = dialog("OPlatesDonateWindow", DON_W, 600)
    -- The cross returns to the message window (Esc still closes).
    f.close:SetScript("OnClick", function() S.BackToMessage() end)

    local title = T.Text(f, 16, T.GOLD, "OUTLINE")
    title:SetPoint("TOP", f, "TOP", 0, -22)
    title:SetText("Receive " .. S.NETWORK)
    f.title = title
    local y = 22 + 18

    local desc = T.Text(f, 12, T.TEXT_DIM)
    desc:SetWidth(BOX_W)
    desc:SetJustifyH("CENTER")
    desc:SetPoint("TOP", title, "BOTTOM", 0, -8)
    desc:SetText("Send only " .. S.NETWORK .. " to this address,\nor you might lose your funds.")
    f.desc = desc
    y = y + 8 + 30

    -- QR code on its white card, framed in rose.
    local card = CreateFrame("Frame", nil, f)
    card:SetWidth(QR_SIZE + 12); card:SetHeight(QR_SIZE + 12)
    card:SetPoint("TOP", desc, "BOTTOM", 0, -14)
    T.Glass(card, T.CARD_BACKDROP, { 0, 0, 0, 0.6 }, { T.RING.SUPPORT[1], T.RING.SUPPORT[2], T.RING.SUPPORT[3], 0.9 })
    f.qr = card:CreateTexture(nil, "ARTWORK")
    f.qr:SetWidth(QR_SIZE); f.qr:SetHeight(QR_SIZE)
    f.qr:SetPoint("CENTER", card, "CENTER", 0, 0)
    f.qr:SetTexture(addon.SUPPORT_QR_ART)
    f.qr:SetTexCoord(0, 1, 0, 1)
    y = y + 14 + QR_SIZE + 12

    y = y + 12
    local _, addrBox, addr = copyBox(f, S.NETWORK .. " address", S.ADDRESS, y, f, "status")
    f.address = addr
    local copy = button(f, "Copy address", 140)
    copy:SetPoint("TOP", addrBox, "BOTTOM", 0, -8)
    copy:SetScript("OnClick", function() select_(addr) end)
    f.copyAddress = copy
    y = y + 14 + 4 + BOX_H + 8 + 22

    y = y + 14
    local _, linkBox, link = copyBox(f, "Support link", S.LINK, y, f, "status")
    f.link = link
    y = y + 14 + 4 + BOX_H
    local copyLink = button(f, "Copy link", 140)
    copyLink:SetPoint("TOP", linkBox, "BOTTOM", 0, -8)
    copyLink:SetScript("OnClick", function() select_(link) end)
    f.copyLink = copyLink
    y = y + 8 + 22

    f.status = T.Text(f, 11, T.TEXT_DIM)
    f.status:SetPoint("TOP", copyLink, "BOTTOM", 0, -12)
    f.status:SetText(S.IDLE_HINT)
    y = y + 12 + 14

    local thanks = T.Text(f, 12, T.RING.SUPPORT)
    thanks:SetPoint("TOP", f.status, "BOTTOM", 0, -8)
    thanks:SetText("Thank you, from the bottom of my heart.")
    f.thanks = thanks
    y = y + 8 + 14

    f:SetScript("OnShow", function() f.status:SetText(S.IDLE_HINT) end)
    f:SetHeight(y + 24)
    return f
end

-------------------------------------------------------------------------------
-- Navigation between the windows.
-------------------------------------------------------------------------------
function S.Open()
    if donate then donate:Hide() end
    if not message then message = buildMessage() end
    message:Show()
    message:Raise()
end

function S.OpenDonate()
    if message then message:Hide() end
    if not donate then donate = buildDonate() end
    donate:Show()
    donate:Raise()
end

function S.BackToMessage()
    S.Open()
end

function S.BackToSettings()
    if message then message:Hide() end
    if donate then donate:Hide() end
    if addon.UISettings and addon.UISettings.Open then addon.UISettings.Open() end
end

function S.Hide()
    if message then message:Hide() end
    if donate then donate:Hide() end
end

function S.MessageWindow() return message end
function S.DonateWindow() return donate end
