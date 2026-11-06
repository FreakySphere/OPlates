local addonName, addon = ...

-- Class Filters / Spec Filters windows, the red "Enable" reminder, the
-- options-row filter button and the awesome_wotlk note in the main window.
-- Everything here is created only when first used and costs nothing while
-- hidden. Saved data (Core defaults): classFilter / enemyClassFilter keyed by
-- class file, specFilter / enemySpecFilter keyed by "CLASS:SPEC"; only
-- DISABLED entries are stored (true = hidden).

local Filters = {}
addon.NameplateFilters = Filters

-- Display order of the classes in both windows (WotLK class list).
Filters.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local SPEC_NAMES = {
    ARMS = "Arms", FURY = "Fury", PROTECTION = "Protection", HOLY = "Holy", RETRIBUTION = "Retribution",
    BEAST_MASTERY = "Beast Mastery", MARKSMANSHIP = "Marksmanship", SURVIVAL = "Survival",
    ASSASSINATION = "Assassination", COMBAT = "Combat", SUBTLETY = "Subtlety",
    DISCIPLINE = "Discipline", SHADOW = "Shadow", BLOOD = "Blood", FROST = "Frost", UNHOLY = "Unholy",
    ELEMENTAL = "Elemental", ENHANCEMENT = "Enhancement", RESTORATION = "Restoration",
    ARCANE = "Arcane", FIRE = "Fire", AFFLICTION = "Affliction", DEMONOLOGY = "Demonology",
    DESTRUCTION = "Destruction", BALANCE = "Balance", FERAL = "Feral",
}

-- Localized class name when the client has it, English otherwise.
function Filters.ClassName(classFile)
    local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
    return loc or CLASS_NAMES[classFile] or classFile
end
function Filters.SpecName(spec) return SPEC_NAMES[spec] or spec end

local function Cfg() return OPlates.db.profile.nameplates end

-- Saved-table key per side and kind.
local FILTER_KEYS = {
    friendly = { class = "classFilter", spec = "specFilter" },
    enemy = { class = "enemyClassFilter", spec = "enemySpecFilter" },
}
-- The "Show class/spec icon" toggle a filter needs to have any effect.
local TOGGLE_KEYS = {
    friendly = { class = "showClassIcon", spec = "showSpec" },
    enemy = { class = "enemyShowClass", spec = "enemyShowSpec" },
}
Filters.FILTER_KEYS, Filters.TOGGLE_KEYS = FILTER_KEYS, TOGGLE_KEYS

function Filters.Table(cfg, side, kind)
    local key = FILTER_KEYS[side][kind]
    local t = cfg[key]
    if type(t) ~= "table" then t = {}; cfg[key] = t end
    return t
end

function Filters.SpecKey(classFile, spec) return classFile .. ":" .. spec end

function Filters.IsHidden(cfg, side, kind, key)
    local t = cfg[FILTER_KEYS[side][kind]]
    return type(t) == "table" and t[key] == true
end

-- Toggles one class or spec; stores only hidden entries. Returns hidden.
function Filters.Toggle(cfg, side, kind, key)
    local t = Filters.Table(cfg, side, kind)
    if t[key] then t[key] = nil else t[key] = true end
    return t[key] == true
end

function Filters.SetAll(cfg, side, kind, hidden)
    local t = Filters.Table(cfg, side, kind)
    for k in pairs(t) do t[k] = nil end
    if not hidden then return end
    for _, classFile in ipairs(Filters.CLASS_ORDER) do
        if kind == "class" then
            t[classFile] = true
        else
            local specs = addon.TALENT_TAB_SPECS[classFile]
            for i = 1, 3 do t[Filters.SpecKey(classFile, specs[i])] = true end
        end
    end
end

-- Count of shown entries out of the total (10 classes or 30 specs).
function Filters.CountShown(cfg, side, kind)
    local total = kind == "class" and 10 or 30
    local hidden = 0
    for _, v in pairs(Filters.Table(cfg, side, kind)) do if v == true then hidden = hidden + 1 end end
    return total - hidden, total
end

-- Whether the matching "Show ... icon" toggle is off. The reminder only
-- matters in "All selected icons" mode: Class only / Spec only ignore it.
function Filters.ToggleOff(cfg, side, kind)
    local mode = (side == "enemy" and cfg.enemyDisplayMode or cfg.friendlyDisplayMode) or "ALL"
    if mode ~= "ALL" then return false end
    local v = cfg[TOGGLE_KEYS[side][kind]]
    if side == "enemy" then return v ~= true end
    return v == false
end

local function Changed()
    local cfg = Cfg()
    cfg.lastModified = GetTime()
    OPlates:RefreshNameplateOverlays()
end
Filters.Changed = Changed

-------------------------------------------------------------------------------
-- Options-row button: a short red button with yellow text (the same 3.3.5a
-- UIPanelButtonTemplate as the Healer CC "Test" button). The AceGUI widget has
-- a 1 px layout footprint so the Flow layout keeps it on the row of the toggle
-- in front of it; the visible button is placed right after that toggle's label.
-------------------------------------------------------------------------------
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
local BUTTON_TYPE, BUTTON_VERSION = "OPlatesFilterButton", 2

-- "friendly:class" -> "friendly", "class". (The first build used
-- "x and s:match()", which keeps only the first capture, so kind was nil and
-- the button did nothing.)
function Filters.ParseArg(arg)
    if type(arg) ~= "string" then return nil end
    local side, kind = arg:match("^(%a+):(%a+)$")
    return side, kind
end

local function PreviousSibling(widget)
    local parent = widget.parent
    local kids = parent and parent.children
    if not kids then return nil end
    for i = 2, #kids do
        if kids[i] == widget then return kids[i - 1] end
    end
end

-- Places the visible button at the right edge of the group box, on the row of
-- the toggle in front of it. The rail spans from this widget's top-left (the
-- toggle's row) to the content's bottom-right, so the button's TOPRIGHT gets
-- its x from the box edge and its y from the row; both follow resizes.
local function PlaceButton(widget)
    local button, rail = widget.button, widget.rail
    local content = widget.frame:GetParent()
    button:ClearAllPoints()
    rail:ClearAllPoints()
    if content and content ~= UIParent then
        rail:SetPoint("TOPLEFT", widget.frame, "TOPLEFT", 0, 0)
        rail:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        button:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -4, -2)
    else
        button:SetPoint("LEFT", widget.frame, "LEFT", 0, 0)
    end
    local prev = PreviousSibling(widget)
    local level = prev and prev.frame and prev.frame:GetFrameLevel() or widget.frame:GetFrameLevel() or 1
    button:SetFrameLevel(level + 3)
end

if AceGUI and (AceGUI:GetWidgetVersion(BUTTON_TYPE) or 0) < BUTTON_VERSION then
    local methods = {
        OnAcquire = function(self)
            self:SetWidth(1)
            self:SetHeight(24)
            self.disabled = false
            self.button:Enable()
            self.button:Show()
            self.frame:SetScript("OnUpdate", function(f)
                -- One placement after the layout settled, then idle.
                f:SetScript("OnUpdate", nil)
                PlaceButton(self)
            end)
        end,
        OnRelease = function(self)
            self.frame:SetScript("OnUpdate", nil)
            self.button:ClearAllPoints()
            self.rail:ClearAllPoints()
        end,
        SetLabel = function(self, text)
            self.button:SetText(text or "")
            local fs = self.button:GetFontString()
            local w = fs and fs:GetStringWidth() or 70
            self.button:SetWidth(math.max(64, w + 20))
        end,
        SetText = function() end,
        -- AceConfigDialog gives every input 170 px; the footprint stays 1 px
        -- so the button shares the row of the toggle in front of it.
        SetWidth = function(self)
            self.frame:SetWidth(1)
            self.frame.width = 1
        end,
        SetDisabled = function(self, disabled)
            self.disabled = disabled and true or false
            if disabled then self.button:Disable() else self.button:Enable() end
        end,
        SetMaxLetters = function() end,
        DisableButton = function() end,
        SetNumLines = function() end,
    }

    local function Constructor()
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:Hide()
        frame:SetWidth(1); frame:SetHeight(24)
        -- Invisible, mouse-transparent anchor rail (see PlaceButton).
        local rail = CreateFrame("Frame", nil, frame)
        rail:EnableMouse(false)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetHeight(20)
        button:SetWidth(90)
        -- Yellow (gold) label like the Healer CC Test button; grey when off.
        if button.SetNormalFontObject then button:SetNormalFontObject(GameFontNormalSmall) end
        if button.SetHighlightFontObject then button:SetHighlightFontObject(GameFontHighlightSmall) end
        if button.SetDisabledFontObject then button:SetDisabledFontObject(GameFontDisableSmall) end
        local widget = { frame = frame, button = button, rail = rail, type = BUTTON_TYPE }
        button:SetScript("OnClick", function()
            if widget.disabled then return end
            if PlaySound then PlaySound("igMainMenuOption") end
            local user = widget:GetUserDataTable()
            local side, kind = Filters.ParseArg(user and user.option and user.option.arg)
            if side and kind and addon.OpenNameplateFilters then addon.OpenNameplateFilters(side, kind) end
        end)
        button:SetScript("OnEnter", function()
            widget:Fire("OnEnter")
            -- AceConfig anchors the tooltip to the 1 px layout frame; move it
            -- to the visible button.
            if GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner() == frame then
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", 0, 2)
            end
        end)
        button:SetScript("OnLeave", function() widget:Fire("OnLeave") end)
        for name, fn in pairs(methods) do widget[name] = fn end
        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(BUTTON_TYPE, Constructor, BUTTON_VERSION)
end

-------------------------------------------------------------------------------
-- awesome_wotlk note in the top-right corner of the main options window. The
-- text is the same red/green status the Advanced tab shows. AceGUI recycles
-- its frames, so the note checks (only while shown, 4x a second) that the
-- window is still ours and hides itself otherwise.
-------------------------------------------------------------------------------
local statusNote
local function OptionsFrame()
    local acd = LibStub("AceConfigDialog-3.0", true)
    local w = acd and acd.OpenFrames and acd.OpenFrames[addonName]
    return w and w.frame
end

function Filters.UpdateStatusNote()
    local host = OptionsFrame()
    if not host or not host:IsShown() or not addon.AwesomeStatusText then
        if statusNote then statusNote:Hide() end
        return
    end
    if not statusNote then
        statusNote = CreateFrame("Frame", nil, host)
        statusNote:SetWidth(220); statusNote:SetHeight(22)
        statusNote.text = statusNote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- Two short lines that fit the header band above the options pane.
        local path, _, flags = statusNote.text:GetFont()
        if path then statusNote.text:SetFont(path, 9, flags) end
        statusNote.text:SetPoint("TOPRIGHT", statusNote, "TOPRIGHT", 0, 0)
        statusNote.text:SetJustifyH("RIGHT")
        statusNote.text:SetJustifyV("TOP")
        local acc = 0
        statusNote:SetScript("OnUpdate", function(self, elapsed)
            acc = acc + elapsed
            if acc < 0.25 then return end
            acc = 0
            local h = OptionsFrame()
            if h ~= self._host or not h or not h:IsShown() then self:Hide() end
        end)
    end
    if statusNote._host ~= host then
        statusNote:SetParent(host)
        statusNote:ClearAllPoints()
        statusNote:SetPoint("TOPRIGHT", host, "TOPRIGHT", -22, -9)
        statusNote._host = host
        -- AceGUI hands this frame to other addons later: hide with it.
        if not host._opNoteHook and host.HookScript then
            host._opNoteHook = true
            host:HookScript("OnHide", function(h)
                if statusNote and statusNote._host == h then statusNote:Hide() end
            end)
        end
    end
    statusNote:SetFrameLevel((host:GetFrameLevel() or 1) + 10)
    statusNote.text:SetText(addon.AwesomeStatusText())
    statusNote:Show()
end

-------------------------------------------------------------------------------
-- Shared look: dark glass panel, thin gold edge, circular icons with the same
-- class-coloured ring the nameplates use.
-------------------------------------------------------------------------------
local PANEL_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local OFF_MARK = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- One circular icon button: icon, class ring, hover glow, OFF mark.
local function CreateRoundIcon(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(size); b:SetHeight(size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture(addon.CLASS_ICON_BORDER)
    b.ring:SetTexCoord(unpack(addon.CLASS_ICON_BORDER_TCOORDS))
    local outset = (addon.CLASS_ICON_BORDER_OUTSET or 1.08) + 0.04
    b.ring:SetWidth(size * outset); b.ring:SetHeight(size * outset)
    b.ring:SetPoint("CENTER", b, "CENTER")
    b.glow = b:CreateTexture(nil, "HIGHLIGHT")
    b.glow:SetTexture(addon.CLASS_ICON_BORDER)
    b.glow:SetTexCoord(unpack(addon.CLASS_ICON_BORDER_TCOORDS))
    b.glow:SetWidth(size * (outset + 0.12)); b.glow:SetHeight(size * (outset + 0.12))
    b.glow:SetPoint("CENTER", b, "CENTER")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 1, 1, 0.55)
    b.off = b:CreateTexture(nil, "OVERLAY", nil)
    b.off:SetTexture(OFF_MARK)
    b.off:SetWidth(size * 0.42); b.off:SetHeight(size * 0.42)
    b.off:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", size * 0.08, -size * 0.08)
    b.off:Hide()
    return b
end

-- Shown: full colour, class ring. Hidden: greyscale, dimmed, grey ring, OFF.
local function PaintRoundIcon(b, classFile, hidden)
    local r, g, bl = addon.GetClassColor(classFile)
    if hidden then
        local grey = b.icon.SetDesaturated and b.icon:SetDesaturated(true)
        b.icon:SetVertexColor(0.55, 0.55, 0.55)
        b.icon:SetAlpha(grey and 0.6 or 0.3)
        b.ring:SetVertexColor(0.35, 0.35, 0.35, 1)
        b.ring:SetAlpha(0.8)
        b.off:Show()
    else
        if b.icon.SetDesaturated then b.icon:SetDesaturated(false) end
        b.icon:SetVertexColor(1, 1, 1)
        b.icon:SetAlpha(1)
        b.ring:SetVertexColor(r, g, bl, 1)
        b.ring:SetAlpha(1)
        b.off:Hide()
    end
end
Filters.PaintRoundIcon = PaintRoundIcon

local function SmallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(22)
    b:SetText(text)
    return b
end

local SIDE_TITLES = { friendly = "Friendly", enemy = "Enemy" }
-- The header icon of each side: the new round art with its own ring.
local SIDE_ART = {
    friendly = "Interface\\AddOns\\OPlates\\Art\\Friendly",
    enemy = "Interface\\AddOns\\OPlates\\Art\\Enemy",
}

local win -- the one filter window (class and spec pages share it)

local function IconTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local cfg = Cfg()
    local hidden = Filters.IsHidden(cfg, win.side, win.kind, b.key)
    local r, g, bl = addon.GetClassColor(b.classFile)
    GameTooltip:SetText(b.label, r, g, bl)
    if hidden then
        GameTooltip:AddLine("Hidden - click to show", 1, 0.35, 0.35)
    else
        GameTooltip:AddLine("Shown - click to hide", 0.35, 1, 0.45)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- The window. Class page: 2 rows x 5 large icons with names. Spec page: 10
-- class cards (2 columns x 5 rows), each card = class name + its 3 specs.
-------------------------------------------------------------------------------
local CLASS_SIZE, SPEC_SIZE = 46, 34

local function Refresh()
    if not win or not win:IsShown() then return end
    local cfg = Cfg()
    local page = win.kind == "class" and win.classPage or win.specPage
    for _, b in ipairs(page.icons) do
        local hidden = Filters.IsHidden(cfg, win.side, win.kind, b.key)
        PaintRoundIcon(b, b.classFile, hidden)
        if b.name then
            if hidden then b.name:SetTextColor(0.45, 0.45, 0.45)
            else b.name:SetTextColor(addon.GetClassColor(b.classFile)) end
        end
    end
    local shown, total = Filters.CountShown(cfg, win.side, win.kind)
    local color = shown == total and "|cff40ff40" or (shown == 0 and "|cffff5050" or "|cffffd100")
    win.count:SetText(string.format("%s%d|r / %d shown", color, shown, total))
    -- A short line under the title when the filter cannot act right now.
    local warn
    if addon.NameplateFilterLocked and addon.NameplateFilterLocked(cfg, win.side, win.kind) then
        warn = win.side == "enemy" and "Enemy icons are off or the display mode hides this icon type."
            or "Friendly icons are off or the display mode hides this icon type."
    elseif Filters.ToggleOff(cfg, win.side, win.kind) then
        warn = win.kind == "class" and "Class icons are turned off for this side." or "Spec icons are turned off for this side."
    end
    if warn then win.warn:SetText("|cffff6060" .. warn .. "|r"); win.warn:Show() else win.warn:Hide() end
end
Filters.Refresh = Refresh

local function OnIconClick(b)
    Filters.Toggle(Cfg(), win.side, win.kind, b.key)
    if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
    Changed()
    Refresh()
    if GameTooltip and GameTooltip:GetOwner() == b then IconTooltip(b) end
end

local function WireIcon(b)
    b:SetScript("OnClick", OnIconClick)
    b:SetScript("OnEnter", IconTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildClassPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -78)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 52)
    page.icons = {}
    local colW, rowH = 82, 92
    for i, classFile in ipairs(Filters.CLASS_ORDER) do
        local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
        local b = CreateRoundIcon(page, CLASS_SIZE)
        b:SetPoint("TOP", page, "TOPLEFT", 41 + col * colW, -8 - row * rowH)
        addon.SetClassIconTexture(b.icon, classFile)
        b.classFile, b.key, b.label = classFile, classFile, Filters.ClassName(classFile)
        b.name = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.name:SetPoint("TOP", b, "BOTTOM", 0, -7)
        b.name:SetText(b.label)
        WireIcon(b)
        page.icons[#page.icons + 1] = b
    end
    return page, 18 + 5 * colW + 18, 78 + 2 * rowH + 52
end

local function BuildSpecPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -78)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 52)
    page.icons = {}
    local cardW, cardH, gap = 214, 74, 6
    for i, classFile in ipairs(Filters.CLASS_ORDER) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local card = CreateFrame("Frame", nil, page)
        card:SetWidth(cardW); card:SetHeight(cardH)
        card:SetPoint("TOPLEFT", page, "TOPLEFT", col * (cardW + gap), -row * (cardH + gap))
        card:SetBackdrop(PANEL_BACKDROP)
        local r, g, bl = addon.GetClassColor(classFile)
        card:SetBackdropColor(r * 0.12, g * 0.12, bl * 0.12, 0.85)
        card:SetBackdropBorderColor(r, g, bl, 0.55)
        local crest = card:CreateTexture(nil, "ARTWORK")
        crest:SetWidth(16); crest:SetHeight(16)
        crest:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        addon.SetClassIconTexture(crest, classFile)
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("LEFT", crest, "RIGHT", 5, 0)
        title:SetText(Filters.ClassName(classFile))
        title:SetTextColor(r, g, bl)
        local specs = addon.TALENT_TAB_SPECS[classFile]
        for s = 1, 3 do
            local spec = specs[s]
            local b = CreateRoundIcon(card, SPEC_SIZE)
            b:SetPoint("TOP", card, "TOPLEFT", 38 + (s - 1) * 69, -26)
            addon.SetCircularTexture(b.icon, addon.GetSpecIcon(classFile, spec))
            b.classFile, b.key = classFile, Filters.SpecKey(classFile, spec)
            b.label = Filters.SpecName(spec) .. " " .. Filters.ClassName(classFile)
            WireIcon(b)
            page.icons[#page.icons + 1] = b
        end
    end
    return page, 14 + 2 * cardW + gap + 14, 78 + 5 * cardH + 4 * gap + 52
end

local function OpenMainOptions()
    if addon.OpenOptions then addon.OpenOptions() return end
    local acd = LibStub("AceConfigDialog-3.0", true)
    if acd then acd:Open(addonName) end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "OPlatesFilterWindow", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropColor(0, 0, 0, 0.95)
    -- Escape closes it like any Blizzard panel.
    if UISpecialFrames then tinsert(UISpecialFrames, "OPlatesFilterWindow") end

    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetWidth(30); f.logo:SetHeight(30)
    f.logo:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    f.logo:SetTexCoord(0, 1, 0, 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 8, -1)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.sub:SetTextColor(0.75, 0.75, 0.75)
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -20)
    f.warn = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.warn:SetPoint("TOPLEFT", f.logo, "BOTTOMLEFT", 0, -10)
    f.warn:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.warn:SetJustifyH("LEFT")
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetHeight(1)
    f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -70)
    f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -70)
    f.divider:SetTexture(1, 0.82, 0, 0.35)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    f.showAll = SmallButton(f, "Show all", 90)
    f.showAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 18)
    f.showAll:SetScript("OnClick", function()
        Filters.SetAll(Cfg(), f.side, f.kind, false); Changed(); Refresh()
    end)
    f.hideAll = SmallButton(f, "Hide all", 90)
    f.hideAll:SetPoint("LEFT", f.showAll, "RIGHT", 6, 0)
    f.hideAll:SetScript("OnClick", function()
        Filters.SetAll(Cfg(), f.side, f.kind, true); Changed(); Refresh()
    end)
    f.back = SmallButton(f, "Back to options", 130)
    f.back:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    f.back:SetScript("OnClick", function() f:Hide(); OpenMainOptions() end)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 44)
    f.hint:SetText("Click an icon to show or hide it. Changes apply instantly.")

    f:SetScript("OnHide", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

local function ShowPage(side, kind)
    if not win then win = BuildWindow() end
    win.side, win.kind = side, kind
    win.logo:SetTexture(SIDE_ART[side] or addon.LOGO_ART)
    if kind == "class" then
        if not win.classPage then win.classPage, win.classW, win.classH = BuildClassPage(win) end
        if win.specPage then win.specPage:Hide() end
        win.classPage:Show()
        win:SetWidth(win.classW); win:SetHeight(win.classH + 16)
        win.title:SetText(SIDE_TITLES[side] .. " Class Filters")
        win.sub:SetText("Hide the class icon for chosen classes")
    else
        if not win.specPage then win.specPage, win.specW, win.specH = BuildSpecPage(win) end
        if win.classPage then win.classPage:Hide() end
        win.specPage:Show()
        win:SetWidth(win.specW); win:SetHeight(win.specH + 16)
        win.title:SetText(SIDE_TITLES[side] .. " Spec Filters")
        win.sub:SetText("Hide the spec icon for chosen specs")
    end
    win:Show()
    win:Raise()
    Refresh()
end
Filters.ShowPage = ShowPage

-------------------------------------------------------------------------------
-- Red reminder: shown over the filter window when its "Show ... icon" toggle
-- is off, so the filter would have nothing to act on. "Enable" turns the
-- toggle on; "Not now" just closes the reminder.
-------------------------------------------------------------------------------
local REMINDER = {
    class = { title = "Class icons are off",
        text = "Class Filters only work while \"%s\" is on. Turn it on now?" },
    spec = { title = "Spec icons are off",
        text = "Spec Filters only work while \"%s\" is on. Turn it on now?" },
}
local TOGGLE_NAMES = {
    friendly = { class = "Class icon", spec = "Spec icon" },
    enemy = { class = "Class icon", spec = "Spec icon" },
}

local reminder
local function BuildReminder()
    local f = CreateFrame("Frame", "OPlatesFilterReminder", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetToplevel(true)
    f:SetWidth(340); f:SetHeight(118)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.22, 0.02, 0.02, 0.96)
    f:SetBackdropBorderColor(1, 0.2, 0.2, 1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetWidth(24); f.icon:SetHeight(24)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.title:SetTextColor(1, 0.35, 0.35)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -8)
    f.text:SetWidth(312)
    f.text:SetJustifyH("LEFT")
    f.enable = SmallButton(f, "Enable", 100)
    f.enable:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
    f.enable:SetScript("OnClick", function()
        local cfg = Cfg()
        cfg[TOGGLE_KEYS[f.side][f.kind]] = true
        Changed()
        OPlates:NotifyOptions()
        f:Hide()
        Refresh()
    end)
    f.later = SmallButton(f, "Not now", 100)
    f.later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
    f.later:SetScript("OnClick", function() f:Hide() end)
    if UISpecialFrames then tinsert(UISpecialFrames, "OPlatesFilterReminder") end
    f:Hide()
    return f
end

function Filters.ShowReminder(side, kind)
    if not reminder then reminder = BuildReminder() end
    reminder.side, reminder.kind = side, kind
    reminder.title:SetText(REMINDER[kind].title)
    reminder.text:SetText(string.format(REMINDER[kind].text, TOGGLE_NAMES[side][kind]))
    reminder:Show()
    reminder:Raise()
end

-- Main entry: the options-row buttons call this. The options window closes,
-- the filter window opens, and the reminder pops up when it is needed.
addon.OpenNameplateFilters = function(side, kind)
    if not FILTER_KEYS[side] or not FILTER_KEYS[side][kind] then return end
    local acd = LibStub("AceConfigDialog-3.0", true)
    if acd then acd:Close(addonName) end
    if addon.UISettings then addon.UISettings.Hide() end
    ShowPage(side, kind)
    if Filters.ToggleOff(Cfg(), side, kind) then
        Filters.ShowReminder(side, kind)
    elseif reminder then
        reminder:Hide()
    end
end

-- Every way of opening the options goes through here so the awesome_wotlk
-- note follows the window. The filter window closes when options open.
addon.OpenOptions = function()
    if win and win:IsShown() then win:Hide() end
    if reminder and reminder:IsShown() then reminder:Hide() end
    -- the themed settings window (it shows the awesome_wotlk note in
    -- its own header); the classic window stays available via /op classic.
    if addon.UISettings then
        local acd = LibStub("AceConfigDialog-3.0", true)
        if acd and acd.OpenFrames and acd.OpenFrames[addonName] then acd:Close(addonName) end
        addon.UISettings.Open()
        return
    end
    LibStub("AceConfigDialog-3.0"):Open(addonName)
    Filters.UpdateStatusNote()
end
