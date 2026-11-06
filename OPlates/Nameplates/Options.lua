local _, addon = ...
local L = addon.L

local function refresh()
    OPlates.db.profile.nameplates.lastModified = GetTime()
    OPlates:RefreshNameplateOverlays()
    OPlates:NotifyOptions()
end

local function get(info)
    return OPlates.db.profile.nameplates[info[#info]]
end

local function set(info, value)
    OPlates.db.profile.nameplates[info[#info]] = value
    refresh()
end

-- sliders dragged as buttons. AceConfigDialog rebuilds the whole
-- dialog on every ConfigTableChange (NotifyChange), which destroys the slider thumb
-- mid-drag. Range options only need to write the value and refresh the game visuals,
-- never the options GUI, so this setter skips NotifyOptions and the drag stays smooth.
local function setRange(info, value)
    OPlates.db.profile.nameplates[info[#info]] = value
    OPlates.db.profile.nameplates.lastModified = GetTime()
    OPlates:RefreshNameplateOverlays()
end

local function whitelistDesc(which)
    if which == "buffWhitelist" then
        return "WotLK spell IDs, separated by commas or spaces. While active, a listed buff takes the icon's place. Crowd control still wins."
    end
    return "WotLK spell IDs, separated by commas or spaces. While active, a listed debuff takes the icon's place. Crowd control still wins."
end

local function awesomeDetected()
    local scanner = addon.TalentScanner
    return scanner and scanner.DetectAwesomeWotlk and scanner:DetectAwesomeWotlk() ~= nil or false
end

-- login banner (replaces the old popup). Pure decision, tested:
-- MISSING every login while unpatched; FOUND once ever (auto-enables the
-- option); DISABLED every login while patched but switched off by the user.
addon.AwesomeBannerKind = function(detected, greeted, enabled)
    if not detected then return "MISSING" end
    if not greeted then return "FOUND" end
    if not enabled then return "DISABLED" end
end

-- the awesome_wotlk download link, shown only under not-patched banners.
local AWESOME_LINK = "https://github.com/FreakySphere/awesome_wotlk/releases/latest"

-- hold values are the base durations plus 6 seconds.
-- DISABLED has no hold, so its Yes/No prompt never auto-fades.
local BANNERS = {
    MISSING = { r = 1, g = 0.27, b = 0.27, hold = 26, link = true,
        title = "awesome_wotlk patch not detected",
        text = "Good news: you are one tiny step away from the full OPlates experience! Right now your client is unpatched, so players only reveal their class after you mouseover them. Install the free FreakySphere awesome_wotlk client patch and every visible player instantly shows class colors, icons and borders, no mouseover needed. Click the link below to select it, copy it, and download the patch:" },
    FOUND = { r = 0.25, g = 1, b = 0.4, hold = 21,
        title = "awesome_wotlk patch detected!",
        text = "OPlates now reads nameplate units straight from your client: every visible player gets class colors, icons and borders instantly, no mouseover needed. You can switch this off in /op > Advanced. Enjoy your sweeps!" },
    DISABLED = { r = 1, g = 0.27, b = 0.27, ask = true,
        title = "awesome_wotlk is installed, but switched off",
        text = "Your client has the awesome_wotlk patch, but OPlates is not using its nameplate units, so you are missing instant class colors, icons and borders on every visible player. Turn it on now?" },
}

local function EnableAwesome()
    OPlates.db.profile.nameplates.useAwesomeWotlkNameplateUnits = true
    local scanner = addon.TalentScanner
    if scanner and scanner._initialized then scanner:SetPlateUnits(true) end
    OPlates:NotifyOptions()
end

local banner
local linkFont
local function ShowBanner(kind)
    local spec = BANNERS[kind]
    if not spec or not UIParent then return end
    if not banner then
        local f = CreateFrame("Frame", "OPlatesBanner", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetWidth(520)
        f:SetPoint("TOP", UIParent, "TOP", 0, -110)
        f:EnableMouse(true)
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetWidth(40); f.icon:SetHeight(40)
        f.icon:SetPoint("TOPLEFT", 14, -14)
        f.icon:SetTexture(addon.LOGO_ART)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -2)
        f.title:SetWidth(420); f.title:SetJustifyH("LEFT")
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
        f.text:SetWidth(434); f.text:SetJustifyH("LEFT")
        -- a read-only, click-to-copy link box shown only under not-patched banners.
        f.link = CreateFrame("EditBox", nil, f)
        f.link:SetAutoFocus(false)
        f.link:SetFontObject("GameFontHighlightSmall")
        f.link:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -8)
        f.link:SetWidth(434); f.link:SetHeight(20)
        f.link:SetTextInsets(6, 6, 2, 2)
        f.link:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f.link:SetBackdropColor(0.05, 0.05, 0.05, 1)
        f.link:SetBackdropBorderColor(0.4, 0.6, 1, 1)
        -- a 3.3.5a EditBox filled before its first layout draws nothing
        -- until the text changes. While unfocused, a plain FontString shows the
        -- URL (always visible) and the box text is transparent; on focus the box
        -- text itself is re-set, shown and highlighted for Ctrl+C.
        f.linkText = f.link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.linkText:SetPoint("LEFT", f.link, "LEFT", 6, 0)
        f.linkText:SetPoint("RIGHT", f.link, "RIGHT", -6, 0)
        f.linkText:SetJustifyH("LEFT")
        -- the URL is sized by measurement. Start 4 below the base font and
        -- step down (floor 4 pt) until it fits the blue box. The same font object
        -- drives the idle text and the EditBox, so both states look the same. The
        -- box size is unchanged and the URL never wraps.
        f.linkText:SetText(AWESOME_LINK)
        local fontObj = GameFontHighlightSmall
        local fontPath, fontSize, fontFlags = fontObj and fontObj.GetFont and fontObj:GetFont()
        if fontPath and fontSize then
            local avail = f.link:GetWidth() - 14
            local linkSize = math.max(4, fontSize - 4)
            f.linkText:SetFont(fontPath, linkSize, fontFlags)
            while linkSize > 4 and (f.linkText:GetStringWidth() or 0) > avail do
                linkSize = linkSize - 1
                f.linkText:SetFont(fontPath, linkSize, fontFlags)
            end
            if not linkFont then linkFont = CreateFont("OPlatesLinkFont") end
            linkFont:SetFont(fontPath, linkSize, fontFlags)
            f.link:SetFontObject(linkFont)
            f.linkText:SetFontObject(linkFont)
        end
        local function LinkIdle(eb)
            f._linkFocus = nil
            eb:SetTextColor(1, 1, 1, 0)
            eb:SetCursorPosition(0)
            f.linkText:Show()
        end
        f.link:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
        f.link:SetScript("OnEditFocusLost", LinkIdle)
        -- Keep it read-only: revert any typed change and keep the URL highlighted.
        f.link:SetScript("OnTextChanged", function(eb)
            if eb:GetText() ~= AWESOME_LINK then eb:SetText(AWESOME_LINK); eb:HighlightText() end
        end)
        f.link:SetScript("OnEditFocusGained", function(eb)
            f._linkFocus = true
            f.linkText:Hide()
            eb:SetTextColor(1, 1, 1, 1)
            eb:SetText("") -- a real change forces the EditBox to redraw its text
            eb:SetText(AWESOME_LINK)
            eb:SetCursorPosition(0)
            eb:HighlightText()
        end)
        f.link:SetScript("OnMouseUp", function(eb) eb:SetFocus(); eb:HighlightText() end)
        f.link._idle = LinkIdle
        f.linkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.linkLabel:SetPoint("TOPLEFT", f.link, "BOTTOMLEFT", 2, -2)
        f.linkLabel:SetWidth(434); f.linkLabel:SetJustifyH("LEFT")
        f.linkLabel:SetText("Click the link, press Ctrl+C to copy, then paste it into your web browser.")
        f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.close:SetPoint("TOPRIGHT", -2, -2)
        f.yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.yes:SetWidth(140); f.yes:SetHeight(22); f.yes:SetText("Yes, enable it")
        f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 12)
        f.yes:SetScript("OnClick", function()
            EnableAwesome(); f:Hide()
            addon.PRINT("|cff40ff40awesome_wotlk nameplate units enabled.|r")
        end)
        f.no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.no:SetWidth(140); f.no:SetHeight(22); f.no:SetText("No, not now")
        f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 12)
        f.no:SetScript("OnClick", function() f:Hide() end)
        -- Never keep the keyboard captured by a hidden link box.
        f:SetScript("OnHide", function() f.link:ClearFocus(); f._linkFocus = nil end)
        f:SetScript("OnUpdate", function(self, elapsed)
            if not self.hold then return end
            if self._linkFocus or (MouseIsOver and MouseIsOver(self)) then self.left = self.hold; self:SetAlpha(1); return end
            self.left = self.left - elapsed
            if self.left <= 0 then self:Hide()
            elseif self.left < 1.5 then self:SetAlpha(self.left / 1.5) end
        end)
        banner = f
    end
    banner:SetBackdropColor(0, 0, 0, 0.92)
    banner:SetBackdropBorderColor(spec.r, spec.g, spec.b, 1)
    banner.title:SetTextColor(spec.r, spec.g, spec.b)
    banner.title:SetText(spec.title)
    banner.text:SetText(spec.text)
    if spec.ask then banner.yes:Show(); banner.no:Show() else banner.yes:Hide(); banner.no:Hide() end
    local linkHeight = 0
    if spec.link then
        banner.link:SetText(AWESOME_LINK)
        banner.link:ClearFocus()
        banner.link._idle(banner.link)
        banner.link:Show(); banner.linkLabel:Show()
        linkHeight = 8 + banner.link:GetHeight() + 2 + banner.linkLabel:GetHeight()
    else
        banner.link:Hide(); banner.linkLabel:Hide()
    end
    banner:SetHeight(14 + banner.title:GetHeight() + 6 + banner.text:GetHeight() + linkHeight + (spec.ask and 44 or 16))
    banner.hold, banner.left = spec.hold, spec.hold
    banner:SetAlpha(1)
    banner:Show()
    addon.PRINT(string.format("|cff%02x%02x%02x%s|r", spec.r * 255, spec.g * 255, spec.b * 255, spec.title))
end
addon.ShowAwesomeBanner = ShowBanner

-- Runs once per login, a few seconds after entering the world.
addon.AwesomeWotlkLoginCheck = function()
    local cfg = OPlates.db.profile.nameplates
    local global = OPlates.db.global
    local scanner = addon.TalentScanner
    local detected = awesomeDetected()
    local kind = addon.AwesomeBannerKind(detected, global.awesomeWotlkGreeted == true, cfg.useAwesomeWotlkNameplateUnits == true)
    if kind == "FOUND" then
        global.awesomeWotlkGreeted = true
        EnableAwesome()
    elseif detected and cfg.useAwesomeWotlkNameplateUnits == true and scanner and not scanner.plateMode then
        scanner:SetPlateUnits(true) -- proof may only appear in the world (live nameplate unit)
        OPlates:NotifyOptions()
    end
    if kind then addon.ShowAwesomeBanner(kind) end
    return kind
end

-- One check per login, 3 s after entering the world; the frame then goes idle.
do
    local login, at = CreateFrame("Frame"), nil
    login:RegisterEvent("PLAYER_ENTERING_WORLD")
    login:SetScript("OnEvent", function() at = at or GetTime() + 3 end)
    login:SetScript("OnUpdate", function(f)
        if not at or GetTime() < at then return end
        f:SetScript("OnUpdate", nil); f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
        if OPlates and OPlates.db then addon.AwesomeWotlkLoginCheck() end
    end)
end

local function awesomeStatus()
    local scanner = addon.TalentScanner
    local cfg = OPlates.db.profile.nameplates
    local mode, proof = nil, "unknown"
    if scanner and scanner.DetectAwesomeWotlk then mode, proof = scanner:DetectAwesomeWotlk() end
    local patch = mode and ("|cff40ff40detected|r (" .. proof .. ")") or "|cffff6060not detected|r"
    local active = scanner and scanner.plateMode and "|cff40ff40in use|r" or "not in use"
    return "awesome_wotlk patch: " .. patch .. "\nNameplate units: "
        .. (cfg.useAwesomeWotlkNameplateUnits and active or "off")
end
-- also shown in the top-right corner of the main options window.
addon.AwesomeStatusText = awesomeStatus

-- display modes of both sides. The three aura modes draw only CC /
-- whitelisted aura icons (no ?, class, spec, role, pet or flag icon).
local DISPLAY_MODES = { ALL = "Everything", HEALER = "Healers only", TANK = "Tanks only", CLASS = "Class icons only",
    CLASS_SPEC = "Spec icons only", PET = "Pets only", FLAG = "Flag carriers only",
    CC_ONLY = "Crowd control only", BUFFS_ONLY = "Buffs only", DEBUFFS_ONLY = "Debuffs only" }
-- the order the Icon mode list shows its entries (saved keys unchanged).
-- This AceConfig version has no select "sorting" member, so the themed window
-- reads the order from here (addon.SelectOrder, keyed by the values table).
local DISPLAY_MODE_ORDER = { "ALL", "CLASS", "CC_ONLY", "CLASS_SPEC", "HEALER", "TANK",
    "BUFFS_ONLY", "DEBUFFS_ONLY", "FLAG", "PET" }
addon.SelectOrder = addon.SelectOrder or setmetatable({}, { __mode = "k" })
addon.SelectOrder[DISPLAY_MODES] = DISPLAY_MODE_ORDER
addon.DisplayModeOrder = DISPLAY_MODE_ORDER
local DISPLAY_MODE_DESC = "Pick which icons may appear. \"Crowd control only\" shows CC icons only (gone the moment the CC ends). \"Buffs only\" / \"Debuffs only\" show your listed spells (plus CC when \"Show crowd control\" is on). Options a mode doesn't use turn grey and keep their values."
local TIMER_DESC = "Seconds left, in the center of CC and aura icons. White from 1 minute, yellow under 1 minute, red from 5 seconds (then tenths). Only for effects with a known duration."

-- grey + lock rules. A locked option keeps its saved value and is
-- ignored while locked (Overlay AuraSettings / display modes).
local LOCK_CATEGORY = {
    friendlyDisplayMode = "general", hideOutsidePvP = "general",
    enemyDisplayMode = "general", hideEnemyOutsidePvP = "general",
    showUnknownFriendly = "identity", showClassIcon = "identity", showSpec = "identity",
    classToSpecDelayEnabled = "identity", classToSpecDelay = "identity", useHealerIcon = "identity",
    useTankIcon = "identity", petIconsEnabled = "identity", useFlagCarrierIcon = "identity",
    enemyShowClass = "identity", enemyShowSpec = "identity", enemyHealerIcon = "identity", enemyTankIcon = "identity",
    enemyPetIcon = "identity", enemyFlagCarrierIcon = "identity", enemyShowUnknown = "identity",
    showPlayerName = "appearance", enemyShowPlayerName = "appearance",
    showNameWithoutIcon = "appearance", enemyShowNameWithoutIcon = "appearance",
    classIconSize = "placement", healerIconSize = "placement", petIconSize = "placement", flagCarrierIconSize = "placement",
    classIconOffset = "placement", classIconHorizontalOffset = "placement",
    enemyIconScale = "placement", enemyHealerIconSize = "placement", enemyPetIconSize = "placement",
    enemyFlagCarrierIconSize = "placement", enemyIconOffsetY = "placement", enemyIconOffsetX = "placement",
    showCrowdControl = "ccReplace", enemyShowCrowdControl = "ccReplace",
    crowdControlTimer = "timer", enemyCrowdControlTimer = "timer",
    auraEnabled = "auraEnable", enemyAuraEnabled = "auraEnable",
    showBuffs = "allowBuffs", enemyShowBuffs = "allowBuffs",
    buffWhitelist = "buffList", enemyBuffWhitelist = "buffList",
    showDebuffs = "allowDebuffs", enemyShowDebuffs = "allowDebuffs",
    debuffWhitelist = "debuffList", enemyDebuffWhitelist = "debuffList",
}
addon.NameplateLockCategory = LOCK_CATEGORY

-- "Buffs only" / "Debuffs only" force their "Allow" toggle on (locked).
local function ForceAllowForMode(cfg, enemy, mode)
    if mode == "BUFFS_ONLY" then
        if enemy then cfg.enemyShowBuffs = true else cfg.showBuffs = true end
    elseif mode == "DEBUFFS_ONLY" then
        if enemy then cfg.enemyShowDebuffs = true else cfg.showDebuffs = true end
    end
end
addon.NameplateForceAllow = ForceAllowForMode

local function set_(...) local s = {} for i = 1, select("#", ...) do s[select(i, ...)] = true end return s end
local OPEN_BY_MODE = {
    FILTER = set_("general", "appearance", "placement", "ccReplace", "timer", "auraEnable",
        "allowBuffs", "buffList", "allowDebuffs", "debuffList"),
    CC_ONLY = set_("general", "appearance", "placement", "timer"),
    -- Buffs only / Debuffs only: the matching "Allow" toggle is forced on and locked.
    BUFFS_ONLY = set_("general", "appearance", "placement", "ccReplace", "timer", "buffList"),
    DEBUFFS_ONLY = set_("general", "appearance", "placement", "ccReplace", "timer", "debuffList"),
}

addon.NameplateOptionLocked = function(cfg, side, category)
    if not category then return false end
    local enemy = side == "enemy"
    local enabled
    if addon.NameplateSideEnabled then
        enabled = addon.NameplateSideEnabled(cfg, enemy)
    elseif enemy then
        enabled = cfg.enemyIconsEnabled ~= false
    else
        enabled = cfg.classIconsEnabled and true or false
    end
    if not enabled then return category ~= "buffList" and category ~= "debuffList" end
    local mode = (enemy and cfg.enemyDisplayMode or cfg.friendlyDisplayMode) or "ALL"
    if mode == "ALL" then return false end
    return not (OPEN_BY_MODE[mode] or OPEN_BY_MODE.FILTER)[category]
end

-- An option's own disabled rule (e.g. the class to spec delay) still applies.
local function ApplyLocks(tab, side)
    for _, group in pairs(tab.args) do
        for key, opt in pairs(group.args or {}) do
            local category = LOCK_CATEGORY[key]
            if category then
                local own = opt.disabled
                opt.disabled = function(info)
                    if addon.NameplateOptionLocked(OPlates.db.profile.nameplates, side, category) then return true end
                    if type(own) == "function" then return own(info) end
                    return own
                end
            end
        end
    end
end

-- Class Filters / Spec Filters. A button is greyed while its side is
-- off or the display mode never draws that icon type (Class Filters: All and
-- Class only; Spec Filters: All and Spec only).
local FILTER_MODES = { class = { ALL = true, CLASS = true }, spec = { ALL = true, CLASS_SPEC = true } }
addon.NameplateFilterLocked = function(cfg, side, kind)
    local enemy = side == "enemy"
    local enabled
    if addon.NameplateSideEnabled then
        enabled = addon.NameplateSideEnabled(cfg, enemy)
    elseif enemy then
        enabled = cfg.enemyIconsEnabled ~= false
    else
        enabled = cfg.classIconsEnabled and true or false
    end
    if not enabled then return true end
    local mode = (enemy and cfg.enemyDisplayMode or cfg.friendlyDisplayMode) or "ALL"
    return not FILTER_MODES[kind][mode]
end

-- The button is a custom AceGUI widget (Nameplates/Filters.lua) drawn just
-- after the label of the toggle in front of it. It opens the filter window
-- itself; the option's get/set are never used.
local function FilterButton(side, kind, order)
    return {
        order = order, type = "input", dialogControl = "OPlatesFilterButton",
        name = kind == "class" and "Class Filters" or "Spec Filters",
        desc = kind == "class"
            and "Choose which classes show their class icon. A hidden class still shows its spec, healer/tank, CC and aura icons."
            or "Choose which specs show their spec icon. A hidden spec shows the class icon instead (when class icons are on and that class is not hidden).",
        arg = side .. ":" .. kind,
        get = function() return "" end,
        set = function() end,
        disabled = function() return addon.NameplateFilterLocked(OPlates.db.profile.nameplates, side, kind) end,
    }
end

addon.GetWotLKNameplateOptions = function(order)
    local function inline(name, order, args)
        return { order = order, type = "group", inline = true, name = name, args = args }
    end

    local t = {
        order = order,
        type = "group",
        childGroups = "tab",
        name = "Nameplates",
        get = get,
        set = set,
        args = {
            friendly = {
                order = 1,
                type = "group",
                name = "Friendly Plates",
                desc = "Clean circular icons for your allies.",
                args = {
                    general = inline("Essentials", 1, {
                        classIconsEnabled = { order = 1, type = "toggle", width = "full", name = "Friendly icons", desc = "Master switch for every icon on friendly players and pets." },
                        friendlyDisplayMode = {
                            order = 2, type = "select", name = "Icon mode",
                            values = DISPLAY_MODES,
                            desc = DISPLAY_MODE_DESC,
                            set = function(_, value)
                                local cfg = OPlates.db.profile.nameplates
                                cfg.friendlyDisplayMode = value
                                ForceAllowForMode(cfg, false, value)
                                refresh()
                            end,
                        },
                        hideOutsidePvP = { order = 4, type = "toggle", width = "full", name = "Arenas & battlegrounds only", desc = "Hide friendly icons everywhere else." },
                    }),
                    identity = inline("Identity", 2, {
                        showUnknownFriendly = { order = 1, type = "toggle", width = "full", name = "Unknown player (?)", desc = "A question mark until the player's class or spec is known." },
                        showClassIcon = { order = 2, type = "toggle", width = "double", name = "Class icon", desc = "With spec icons on, a new player shows the class first, then the spec after the delay set in Advanced." },
                        classFilterButton = FilterButton("friendly", "class", 2.1),
                        showSpec = { order = 3, type = "toggle", width = "double", name = "Spec icon", desc = "Shown once the player's talents are known. Healer and tank icons take priority when they are on." },
                        specFilterButton = FilterButton("friendly", "spec", 3.1),
                        useHealerIcon = { order = 6, type = "toggle", width = "full", name = "Healer icon" },
                        useTankIcon = { order = 7, type = "toggle", width = "full", name = "Tank icon" },
                        petIconsEnabled = { order = 8, type = "toggle", width = "full", name = "Pet icons" },
                        useFlagCarrierIcon = { order = 9, type = "toggle", width = "full", name = "Flag carrier icon" },
                    }),
                    appearance = inline("Names", 3, {
                        showPlayerName = { order = 1, type = "toggle", width = "full", name = "Name under icon" },
                        showNameWithoutIcon = { order = 2, type = "toggle", width = "full", name = "Name even without an icon",
                            desc = "Also names players who have no icon. Needs \"Name under icon\".",
                            disabled = function() return not OPlates.db.profile.nameplates.showPlayerName end },
                    }),
                    placement = inline("Size & Position", 4, {
                        classIconSize = { order = 1, type = "range", name = "Icon size", min = 0.5, max = 2, step = 0.05, set = setRange,
                            desc = "Size of the ?, class, spec and tank icons. Healer, pet and flag icons have their own size." },
                        healerIconSize = { order = 2, type = "range", name = "Healer icon size", min = 0.5, max = 2, step = 0.05, set = setRange },
                        petIconSize = { order = 3, type = "range", name = "Pet icon size", min = 0.4, max = 2, step = 0.05, set = setRange },
                        flagCarrierIconSize = { order = 4, type = "range", name = "Flag icon size", min = 0.5, max = 2.5, step = 0.05, set = setRange },
                        classIconOffset = { order = 5, type = "range", name = "Move up / down", min = -50, max = 80, step = 1, set = setRange },
                        classIconHorizontalOffset = { order = 6, type = "range", name = "Move left / right", min = -80, max = 80, step = 1, set = setRange },
                    }),
                    aura = inline("Crowd Control & Auras", 5, {
                        showCrowdControl = { order = 1, type = "toggle", width = "full", name = "Show crowd control", desc = "The icon becomes the active CC while it lasts. CC always wins over buffs and debuffs." },
                        crowdControlTimer = { order = 1.5, type = "toggle", width = "full", name = "Countdown in the icon",
                            desc = TIMER_DESC },
                        auraEnabled = { order = 2, type = "toggle", width = "full", name = "Buff & debuff lists", desc = "Let the spells you list below take the icon's place while active." },
                        showBuffs = { order = 3, type = "toggle", width = "full", name = "Use buff list" },
                        buffWhitelist = { order = 4, type = "input", multiline = 3, width = "full", name = "Buff spell IDs", desc = whitelistDesc("buffWhitelist") },
                        showDebuffs = { order = 5, type = "toggle", width = "full", name = "Use debuff list" },
                        debuffWhitelist = { order = 6, type = "input", multiline = 3, width = "full", name = "Debuff spell IDs", desc = whitelistDesc("debuffWhitelist") },
                    }),
                },
            },
            enemy = {
                order = 2,
                type = "group",
                name = "Enemy Plates",
                desc = "Read every enemy at a glance: class, spec, role and crowd control.",
                args = {
                    general = inline("Essentials", 1, {
                        enemyIconsEnabled = { order = 0.5, type = "toggle", width = "full", name = "Enemy icons",
                            desc = "Master switch for every icon on enemy players and pets. Arena numbers still show, and enemy tracking sleeps while off." },
                        enemyDisplayMode = {
                            order = 1, type = "select", name = "Icon mode",
                            values = DISPLAY_MODES,
                            desc = DISPLAY_MODE_DESC,
                            set = function(_, value)
                                local cfg = OPlates.db.profile.nameplates
                                cfg.enemyDisplayMode = value
                                ForceAllowForMode(cfg, true, value)
                                refresh()
                            end,
                        },
                        hideEnemyOutsidePvP = { order = 2, type = "toggle", width = "full", name = "Arenas & battlegrounds only", desc = "Hide enemy icons everywhere else." },
                        arenaNumbersEnabled = { order = 3, type = "toggle", width = "full", name = "Arena numbers (1-5)", desc = "Shows Arena 1 to 5 on enemy plates in arenas." },
                    }),
                    identity = inline("Identity", 2, {
                        enemyShowClass = { order = 1, type = "toggle", width = "double", name = "Class icon" },
                        enemyClassFilterButton = FilterButton("enemy", "class", 1.1),
                        enemyShowSpec = { order = 2, type = "toggle", width = "double", name = "Spec icon", desc = "Shown once the player's talents are known." },
                        enemySpecFilterButton = FilterButton("enemy", "spec", 2.1),
                        enemyHealerIcon = { order = 3, type = "toggle", width = "full", name = "Healer icon" },
                        enemyTankIcon = { order = 4, type = "toggle", width = "full", name = "Tank icon" },
                        enemyPetIcon = { order = 5, type = "toggle", width = "full", name = "Pet icons" },
                        enemyFlagCarrierIcon = { order = 6, type = "toggle", width = "full", name = "Flag carrier icon" },
                        enemyShowUnknown = { order = 7, type = "toggle", width = "full", name = "Unknown player (?)", desc = "A question mark until the player's class or spec is known." },
                    }),
                    -- same layout as Friendly > Size & position. The saved
                    -- keys enemyIconScale (%) and enemyIconOffsetX/Y are unchanged.
                    placement = inline("Size & Position", 3, {
                        enemyIconScale = { order = 1, type = "range", name = "Icon size", min = 0.5, max = 2, step = 0.05,
                            desc = "Size of the ?, class, spec and tank icons. Healer, pet and flag icons have their own size.",
                            get = function() return (OPlates.db.profile.nameplates.enemyIconScale or 100) / 100 end,
                            set = function(info, value) setRange(info, math.floor(value * 100 + 0.5)) end },
                        enemyHealerIconSize = { order = 2, type = "range", name = "Healer icon size", min = 0.5, max = 2, step = 0.05, set = setRange },
                        enemyPetIconSize = { order = 3, type = "range", name = "Pet icon size", min = 0.4, max = 2, step = 0.05, set = setRange },
                        enemyFlagCarrierIconSize = { order = 4, type = "range", name = "Flag icon size", min = 0.5, max = 2.5, step = 0.05, set = setRange },
                        enemyIconOffsetY = { order = 5, type = "range", name = "Move up / down", min = -50, max = 80, step = 1, set = setRange },
                        enemyIconOffsetX = { order = 6, type = "range", name = "Move left / right", min = -80, max = 80, step = 1, set = setRange },
                    }),
                    appearance = inline("Names", 4, {
                        enemyShowPlayerName = { order = 1, type = "toggle", width = "full", name = "Name under icon" },
                        enemyShowNameWithoutIcon = { order = 2, type = "toggle", width = "full", name = "Name even without an icon",
                            desc = "Also names enemy players who have no icon. Needs \"Name under icon\".",
                            disabled = function() return not OPlates.db.profile.nameplates.enemyShowPlayerName end },
                    }),
                    -- same options as Friendly, independent saved keys.
                    aura = inline("Crowd Control & Auras", 5, {
                        enemyShowCrowdControl = { order = 1, type = "toggle", width = "full", name = "Show crowd control", desc = "The icon becomes the active CC while it lasts. CC always wins over buffs and debuffs." },
                        enemyCrowdControlTimer = { order = 1.5, type = "toggle", width = "full", name = "Countdown in the icon",
                            desc = TIMER_DESC },
                        enemyAuraEnabled = { order = 2, type = "toggle", width = "full", name = "Buff & debuff lists", desc = "Let the spells you list below take the icon's place while active." },
                        enemyShowBuffs = { order = 3, type = "toggle", width = "full", name = "Use buff list" },
                        enemyBuffWhitelist = { order = 4, type = "input", multiline = 3, width = "full", name = "Buff spell IDs", desc = whitelistDesc("buffWhitelist") },
                        enemyShowDebuffs = { order = 5, type = "toggle", width = "full", name = "Use debuff list" },
                        enemyDebuffWhitelist = { order = 6, type = "input", multiline = 3, width = "full", name = "Debuff spell IDs", desc = whitelistDesc("debuffWhitelist") },
                    }),
                },
            },
            -- settings shared by both sides, moved out of Friendly.
            advanced = {
                order = 3,
                type = "group",
                name = "Advanced",
                desc = "Shared by Friendly and Enemy plates.",
                args = {
                    talents = inline("Talent Memory", 1, {
                        persistentTalentCache = {
                            order = 1, type = "toggle", width = "full", name = "Remember specs between sessions",
                            desc = "Keeps learned specs after a reload or logout, for friends and foes. Changing this reloads your UI. Turning it off clears the saved specs.",
                            set = function(_, value)
                                local cfg = OPlates.db.profile.nameplates
                                if (cfg.persistentTalentCache == true) == value then return end
                                cfg.persistentTalentCache = value
                                if not value then OPlatesTalentDB = nil end
                                ReloadUI()
                            end,
                        },
                    }),
                    awesome = inline("awesome_wotlk", 2, {
                        useAwesomeWotlkNameplateUnits = {
                            order = 1, type = "toggle", width = "full", name = "Use awesome_wotlk nameplate units",
                            desc = "Needs the FreakySphere or a compatible awesome_wotlk client patch (switched on automatically the first time it is found). Every visible player gets icons right away, no mouseover needed. Greyed out without compatible support.",
                            disabled = function() return not awesomeDetected() end,
                            get = function()
                                return OPlates.db.profile.nameplates.useAwesomeWotlkNameplateUnits == true and awesomeDetected()
                            end,
                            set = function(_, value)
                                local cfg = OPlates.db.profile.nameplates
                                cfg.useAwesomeWotlkNameplateUnits = value == true
                                local scanner = addon.TalentScanner
                                if scanner and scanner._initialized then scanner:SetPlateUnits(value == true) end
                                OPlates:NotifyOptions()
                            end,
                        },
                        awesomeWotlkStatus = {
                            order = 2, type = "description", width = "full", fontSize = "medium",
                            name = awesomeStatus,
                        },
                    }),
                    transition = inline("Class to Spec", 3, {
                        classToSpecDelayEnabled = { order = 1, type = "toggle", width = "full", name = "Show the class first", desc = "Keep the class icon briefly before the spec replaces it. Off: switch at once. Friendly players only, while Class icon and Spec icon are both on.", disabled = function() local n = OPlates.db.profile.nameplates return not (n.showClassIcon ~= false and n.showSpec ~= false) end },
                        classToSpecDelay = { order = 2, type = "range", width = "full", name = "Delay (seconds)", desc = "How long the class icon stays before the spec replaces it.", min = 0.5, max = 3, step = 0.05, set = setRange, disabled = function() local n = OPlates.db.profile.nameplates return not (n.showClassIcon ~= false and n.showSpec ~= false and n.classToSpecDelayEnabled ~= false) end },
                    }),
                },
            },
        },
    }
    ApplyLocks(t.args.friendly, "friendly")
    ApplyLocks(t.args.enemy, "enemy")
    -- the delay options act on friendly plates, so they keep the
    -- Friendly locks (greyed when friendly icons are off or a mode skips them).
    ApplyLocks(t.args.advanced, "friendly")
    return t
end
