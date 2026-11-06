local addonName, addon = ...

-- OPlates settings engine. A custom, frame-based options window drawn in
-- the Class/Spec Filter-window language. It does NOT invent its own options: it
-- reads the SAME AceConfig option tables the addon already registers and calls
-- their original get/set/func/disabled/hidden/validate/confirm exactly the way
-- AceConfigDialog does (see GetOptionsMemberValue / ActivateControl in
-- Libs/AceConfig-3.0/.../AceConfigDialog-3.0.lua). Because every option member
-- is resolved and called identically, all existing behaviour is preserved by
-- construction: locks (ApplyLocks), drag-safe sliders (setRange), the filter
-- buttons, profile import/export/switch, everything.

local T = addon.UITheme
local W = addon.UIWidgets

local S = {}
addon.UISettings = S

-- AceConfigRegistry rejects a uiName without "Name-<digit>" (e.g. "MyLib-1.2").
local UI_NAME = "OPlates-1.0"
S.UI_NAME = UI_NAME

-------------------------------------------------------------------------------
-- Option-member resolution, a faithful port of AceConfigDialog's rules so the
-- same info table reaches every callback.
-------------------------------------------------------------------------------
local isInherited = { set = true, get = true, func = true, confirm = true, validate = true, disabled = true, hidden = true }
local stringIsLiteral = { name = true, desc = true, icon = true, usage = true, width = true, image = true, fontSize = true }
local allIsLiteral = { type = true, descStyle = true, imageWidth = true, imageHeight = true }

local function subOption(group, key)
    if not group then return nil end
    if group.plugins then
        for _, t in pairs(group.plugins) do
            if t[key] then return t[key] end
        end
    end
    return group.args and group.args[key]
end
S.subOption = subOption

-- Build the per-call info table (mirrors AceConfigDialog).
local function makeInfo(root, option, path, appName, extraArg)
    local info = {}
    local handler = root.handler
    local group = root
    for i = 1, #path do
        group = subOption(group, path[i])
        info[i] = path[i]
        if group and group.handler then handler = group.handler end
    end
    info[0] = appName
    info.options = root
    info.appName = appName
    info.arg = option and option.arg
    info.handler = handler
    info.option = option
    info.type = option and option.type
    info.uiType = "dialog"
    info.uiName = UI_NAME
    return info, handler
end
S.makeInfo = makeInfo

-- Resolve a member value, calling functions / handler methods with info.
local function member(membername, option, root, path, appName, ...)
    local m
    if isInherited[membername] then
        local group = root
        if group[membername] ~= nil then m = group[membername] end
        for i = 1, #path do
            group = subOption(group, path[i])
            if group and group[membername] ~= nil then m = group[membername] end
        end
    else
        m = option[membername]
    end

    if (not allIsLiteral[membername])
        and (type(m) == "function" or ((not stringIsLiteral[membername]) and type(m) == "string")) then
        local info, handler = makeInfo(root, option, path, appName)
        if type(m) == "function" then
            return m(info, ...)
        elseif handler and handler[m] then
            return handler[m](handler, info, ...)
        else
            return nil
        end
    end
    return m
end
S.member = member

-- Nearest-ancestor function for set / func / confirm / validate, used by run().
local function nearest(name, root, path)
    local f = root[name]
    local group = root
    for i = 1, #path do
        group = subOption(group, path[i])
        if group and group[name] ~= nil then f = group[name] end
    end
    return f
end

-- Execute a set / func exactly like ActivateControl, including validate +
-- confirm. value... are the new value(s). Returns true when a confirm dialog
-- took over (caller should not refresh yet).
local function activate(root, option, path, appName, isExecute, ...)
    local info, handler = makeInfo(root, option, path, appName)
    local funcname = isExecute and "func" or "set"
    local func = nearest(funcname, root, path)
    local validate = nearest("validate", root, path)
    local confirm = nearest("confirm", root, path)

    -- input pattern check
    if not isExecute and option.type == "input" and type(option.pattern) == "string" then
        local v = ...
        if type(v) ~= "string" or not v:match(option.pattern) then
            if PlaySound then PlaySound("igPlayerInviteDecline") end
            return false
        end
    end

    -- validate
    if not isExecute and validate then
        local ok, res
        if type(validate) == "function" then
            ok, res = pcall(validate, info, ...)
        elseif handler and handler[validate] then
            ok, res = pcall(handler[validate], handler, info, ...)
        else
            ok = true
        end
        if not ok then res = false end
        if type(res) == "string" or res == false then
            if PlaySound then PlaySound("igPlayerInviteDecline") end
            return false
        end
    end

    -- confirm
    local confirmText = option.confirmText
    if confirm ~= nil then
        local c = confirm
        if type(confirm) == "function" then
            local ok, r = pcall(confirm, info, ...)
            c = ok and r or false
        elseif type(confirm) == "string" then
            if handler and handler[confirm] then
                local ok, r = pcall(handler[confirm], handler, info, ...)
                c = ok and r or false
            else
                c = false
            end
        end
        if type(c) == "string" then confirmText = c; c = true end
        if c == true then
            if not confirmText then
                local nm = member("name", option, root, path, appName)
                local ds = member("desc", option, root, path, appName)
                confirmText = nm or ""
                if ds then confirmText = confirmText .. " - " .. ds end
            end
            local args = { ... }
            S.ConfirmPopup(confirmText, function()
                if type(func) == "function" then func(info, unpack(args))
                elseif handler and handler[func] then handler[func](handler, info, unpack(args)) end
                S.RefreshOpen()
            end)
            return true
        end
    end

    if type(func) == "function" then
        func(info, ...)
    elseif type(func) == "string" and handler and handler[func] then
        handler[func](handler, info, ...)
    end
    return false
end
S.activate = activate

-- A simple themed confirm popup (used by profile delete etc.).
local confirmFrame
function S.ConfirmPopup(text, onAccept)
    if not confirmFrame then
        local f = CreateFrame("Frame", "OPlatesConfirmPopup", UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetWidth(360); f:SetHeight(130)
        f:SetPoint("CENTER")
        f:EnableMouse(true)
        f:SetBackdrop(T.WINDOW_BACKDROP)
        f:SetBackdropColor(0, 0, 0, 0.97)
        f.text = T.Text(f, 12, T.TEXT)
        f.text:SetPoint("TOP", f, "TOP", 0, -24)
        f.text:SetWidth(320); f.text:SetJustifyH("CENTER")
        f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.ok:SetWidth(110); f.ok:SetHeight(24); f.ok:SetText(ACCEPT or "Accept")
        f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
        f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.cancel:SetWidth(110); f.cancel:SetHeight(24); f.cancel:SetText(CANCEL or "Cancel")
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
        if UISpecialFrames then tinsert(UISpecialFrames, "OPlatesConfirmPopup") end
        f:Hide()
        confirmFrame = f
    end
    confirmFrame.text:SetText(text or "")
    confirmFrame.ok:SetScript("OnClick", function() confirmFrame:Hide(); if onAccept then onAccept() end end)
    confirmFrame.cancel:SetScript("OnClick", function() confirmFrame:Hide() end)
    confirmFrame:Show(); confirmFrame:Raise()
end

-------------------------------------------------------------------------------
-- Sorting (same rules as AceConfigDialog compareOptions: default order 100,
-- negative orders go last, ties sort by name).
-------------------------------------------------------------------------------
local function sortedKeys(group, root, path, appName)
    local keys, orders, names = {}, {}, {}
    local function add(k, v)
        if orders[k] ~= nil then return end
        keys[#keys + 1] = k
        path[#path + 1] = k
        orders[k] = member("order", v, root, path, appName) or 100
        local n = member("name", v, root, path, appName)
        names[k] = type(n) == "string" and n or ""
        path[#path] = nil
    end
    if group.plugins then
        for _, t in pairs(group.plugins) do for k, v in pairs(t) do add(k, v) end end
    end
    for k, v in pairs(group.args or {}) do add(k, v) end
    table.sort(keys, function(a, b)
        local oa, ob = orders[a], orders[b]
        if oa == ob then return names[a]:upper() < names[b]:upper() end
        if oa < 0 and ob > 0 then return false end
        if oa > 0 and ob < 0 then return true end
        return oa < ob
    end)
    return keys
end
S.sortedKeys = sortedKeys

local function isHidden(option, root, path, appName)
    local h = option.dialogHidden
    if h == nil then h = option.guiHidden end
    if h ~= nil then return h and true or false end
    return member("hidden", option, root, path, appName) and true or false
end

local function isDisabled(option, root, path, appName)
    local d = option.dialogDisabled
    if d == nil then d = option.guiDisabled end
    if d ~= nil then return d and true or false end
    return member("disabled", option, root, path, appName) and true or false
end
S.isHidden, S.isDisabled = isHidden, isDisabled

local function copyPath(path)
    local p = {}
    for i = 1, #path do p[i] = path[i] end
    return p
end

-- Widget model for one leaf option. All callbacks re-resolve the option
-- members at call time, so dynamic names / values / disabled stay live.
local FILTER_CONTROL = "OPlatesFilterButton"

local function buildModel(option, root, path, appName)
    local p = copyPath(path)
    local m = { type = option.type, option = option, path = p }
    m.name = member("name", option, root, p, appName)
    m.desc = member("desc", option, root, p, appName)
    m.width = member("width", option, root, p, appName)
    m.fontSize = member("fontSize", option, root, p, appName)
    m.disabled = function() return isDisabled(option, root, p, appName) end
    m.get = function(...) return member("get", option, root, p, appName, ...) end

    if option.type == "execute" then
        m.run = function()
            activate(root, option, p, appName, true)
            S.RefreshOpen()
        end
    elseif option.type == "input" and option.dialogControl == FILTER_CONTROL then
        m.type = "filterbutton"
        m.openFilter = function()
            local F = addon.NameplateFilters
            local side, kind
            if F and F.ParseArg then
                side, kind = F.ParseArg(option.arg)
            elseif type(option.arg) == "string" then
                side, kind = option.arg:match("^(%a+):(%a+)$")
            end
            if side and kind and addon.OpenNameplateFilters then addon.OpenNameplateFilters(side, kind) end
        end
    else
        m.set = function(...)
            local tookOver = activate(root, option, p, appName, false, ...)
            -- A slider drag calls set every step; its own (drag-safe) setter
            -- decides whether to notify. Everything else refreshes once.
            if not tookOver and option.type ~= "range" then S.RefreshOpen() end
        end
    end

    if option.type == "range" then
        m.min = option.softMin or option.min or 0
        m.max = option.softMax or option.max or 100
        m.step = option.bigStep or option.step or 0
        m.isPercent = option.isPercent
        m.onRelease = function() S.RefreshOpen() end
    elseif option.type == "select" then
        m.refreshValues = function()
            local v = member("values", option, root, p, appName)
            m.values = type(v) == "table" and v or {}
            m.sorting = addon.SelectOrder and addon.SelectOrder[m.values] or nil
        end
        m.refreshValues()
    elseif option.type == "input" then
        m.multiline = option.multiline
    elseif option.type == "description" then
        if type(option.name) == "function" or type(option.name) == "string" and option.name ~= m.name then
            m.getName = function() return member("name", option, root, p, appName) or "" end
        end
    end
    return m
end
S.buildModel = buildModel

-------------------------------------------------------------------------------
-- Card / page layout.
-------------------------------------------------------------------------------
local CARD_PAD, CARD_GAP, COL_GAP, ROW_GAP = 14, 12, 16, 4

local function widthFor(model, inner)
    local w = model.width
    local t = model.type
    if t == "header" then return inner, true end
    if t == "description" then
        if w == nil or w == "full" or w == "fill" then return inner, true end
        return math.floor((inner - COL_GAP) / 2), false
    end
    if w == "full" or w == "fill" or w == "double" then return inner, true end
    if t == "input" and model.multiline then return inner, true end
    if w == "half" then return math.floor((inner - 3 * COL_GAP) / 4), false end
    if t == "execute" then return math.floor((inner - 2 * COL_GAP) / 3), false end
    return math.floor((inner - COL_GAP) / 2), false
end

local CONSTRUCTORS = {
    toggle = "Toggle", range = "Slider", select = "Dropdown", input = "Input",
    execute = "Button", header = "Header", description = "Description",
}

-- Lays out the leaf options of one group into a card. Returns the card and
-- its height. live is the page's list of widgets to Refresh().
local function buildCard(parent, title, group, root, path, appName, width, live, sig)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(width)
    card:SetBackdrop(T.CARD_BACKDROP)
    card:SetBackdropColor(0.055, 0.055, 0.065, 0.92)
    card:SetBackdropBorderColor(0.42, 0.35, 0.10, 0.9)

    local top = CARD_PAD - 2
    if title and title ~= "" then
        local bar = card:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.9)
        bar:SetWidth(3); bar:SetHeight(14)
        bar:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD + 1)
        local t = T.Text(card, 13, T.GOLD)
        t:SetPoint("LEFT", bar, "RIGHT", 7, 0)
        t:SetText(title)
        top = CARD_PAD + 22
    end

    local inner = width - 2 * CARD_PAD
    local x, y, rowH = 0, 0, 0
    local prev
    local count = 0
    for _, k in ipairs(sortedKeys(group, root, path, appName)) do
        local v = subOption(group, k)
        path[#path + 1] = k
        local hidden = isHidden(v, root, path, appName)
        sig[#sig + 1] = hidden and "1" or "0"
        if not hidden and v.type ~= "group" then
            local model = buildModel(v, root, path, appName)
            if model.type == "filterbutton" then
                local wdg = W.FilterButton(card, model)
                if prev then
                    wdg.frame:SetPoint("RIGHT", prev.frame, "RIGHT", -2, 0)
                    -- keep the toggle label clear of the button
                    if prev.label then prev.label:SetPoint("RIGHT", prev.frame, "RIGHT", -(wdg.frame:GetWidth() + 10), 0) end
                else
                    wdg.frame:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -top)
                end
                wdg.frame:SetFrameLevel(card:GetFrameLevel() + 5)
                wdg.key, wdg.model = k, model
                live[#live + 1] = wdg
            else
                local ctor = W[CONSTRUCTORS[model.type] or ""]
                if ctor then
                    local w, own = widthFor(model, inner)
                    if x > 0 and (own or x + w > inner + 1) then
                        y = y + rowH + ROW_GAP; x = 0; rowH = 0
                    end
                    local wdg = ctor(card, model, w)
                    wdg.frame:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + x, -(top + y))
                    local h = wdg:GetHeight()
                    if h > rowH then rowH = h end
                    if own then
                        y = y + rowH + ROW_GAP; x = 0; rowH = 0
                    else
                        x = x + w + COL_GAP
                    end
                    wdg.key, wdg.model = k, model
                    live[#live + 1] = wdg
                    prev = wdg
                    count = count + 1
                end
            end
        end
        path[#path] = nil
    end
    if rowH > 0 then y = y + rowH + ROW_GAP end
    local height = top + y + CARD_PAD - ROW_GAP
    if count == 0 then height = top + CARD_PAD end
    card:SetHeight(height)
    return card, height, count
end

-- Renders a whole options group as a page: loose leaves first (one untitled
-- card), then one card per inline (or nested) child group.
local function renderGroup(page, group, root, path, appName, width)
    local live, sig = {}, {}
    local y = 0
    -- loose leaves
    local loose = { args = {} }
    local hasLoose = false
    for _, k in ipairs(sortedKeys(group, root, path, appName)) do
        local v = subOption(group, k)
        if v.type ~= "group" then loose.args[k] = v; hasLoose = true end
    end
    if hasLoose then
        local card, h, n = buildCard(page, nil, loose, root, path, appName, width, live, sig)
        if n > 0 then
            card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            y = y + h + CARD_GAP
        else
            card:Hide()
        end
    end
    for _, k in ipairs(sortedKeys(group, root, path, appName)) do
        local v = subOption(group, k)
        if v.type == "group" then
            path[#path + 1] = k
            local hidden = isHidden(v, root, path, appName)
            sig[#sig + 1] = hidden and "1" or "0"
            if not hidden then
                local title = member("name", v, root, path, appName)
                local card, h, n = buildCard(page, title, v, root, path, appName, width, live, sig)
                if n > 0 then
                    card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
                    y = y + h + CARD_GAP
                else
                    card:Hide()
                end
            end
            path[#path] = nil
        end
    end
    page:SetHeight(math.max(1, y))
    return live, table.concat(sig)
end
S.renderGroup = renderGroup

-- Hidden-state signature of a group (to know when a re-layout is needed).
function S.HiddenSignature(group, root, path, appName)
    local sig = {}
    local function walk(g)
        for _, k in ipairs(sortedKeys(g, root, path, appName)) do
            local v = subOption(g, k)
            path[#path + 1] = k
            sig[#sig + 1] = isHidden(v, root, path, appName) and "1" or "0"
            if v.type == "group" then walk(v) end
            path[#path] = nil
        end
    end
    walk(group)
    return table.concat(sig)
end

-------------------------------------------------------------------------------
-- The window: header (logo / title / version / awesome note / close), a left
-- nav rail grouped in sections (live pages + greyed SOON entries for reserved
-- features, each in the section where it will live), and a scrolling content
-- area. Pages are built once per category and cached (no frame churn).
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 760, 600
local NAV_W = 184
local appName = addonName

-- Nav layout. path = keys into the registered options table (entries whose
-- path does not exist are skipped). reserved = future feature (SOON).
-- ring = border colour of the icon (UI/Theme.lua T.RING).
local ART = "Interface\\AddOns\\OPlates\\Art\\"
local ICON_FRIENDLY = ART .. "Friendly"
local ICON_HEALERCC = ART .. "HealerCC"
local NAV = {
    { path = { "home" }, icon = ART .. "Home", ring = "HOME" },
    { section = "NAMEPLATES" },
    { path = { "nameplates", "friendly" }, icon = ICON_FRIENDLY, ring = "FRIENDLY" },
    { path = { "nameplates", "enemy" }, icon = ART .. "Enemy", ring = "ENEMY" },
    { reserved = "Plate Filters", icon = ART .. "PlateFilters", ring = "PLATES",
      desc = "Hide any part of friendly or enemy nameplates: names, health bars, cast bars, raid marks and more, for players, pets, totems, NPCs and bosses." },
    { reserved = "Aura Filters", icon = ART .. "AuraFilters", ring = "AURAS",
      desc = "A full list of every crowd control, buff and debuff. Switch each one on or off." },
    { path = { "nameplates", "advanced" }, icon = ART .. "Advanced", ring = "ADVANCED" },
    { section = "ALERTS" },
    { path = { "healercc" }, icon = ICON_HEALERCC, ring = "HEALERCC" },
    { reserved = "Raid & Dungeon", icon = ART .. "RaidDungeon", ring = "RAID",
      desc = "Important boss abilities, raid debuffs and dungeon effects shown right on the affected players' circular icons." },
    { section = "GENERAL" },
    { path = { "misc" }, icon = ART .. "Tools", ring = "TOOLS" },
    { path = { "profileSharing" }, icon = ART .. "Share", ring = "SHARE" },
    { path = { "profiles" }, icon = ART .. "Profiles", ring = "PROFILES" },
}
S.NAV = NAV
-- Support is live. It opens the donation window (UI/Support.lua).
S.SUPPORT = { name = "Support OPlates", icon = ART .. "Support", ring = "SUPPORT",
    desc = "Enjoying OPlates? Here is how you can support it. Thank you!" }

local win

local function getRoot()
    local reg = LibStub("AceConfigRegistry-3.0", true)
    local app = reg and reg:GetOptionsTable(appName)
    if not app then return nil end
    -- A registry error must never leave the window half-built.
    local ok, root = pcall(app, "dialog", UI_NAME)
    if ok then return root end
    if geterrorhandler then geterrorhandler()(root) end
    return nil
end

local function groupAt(root, path)
    local g = root
    for i = 1, #path do
        g = subOption(g, path[i])
        if not g then return nil end
    end
    return g
end

local function navKey(path) return table.concat(path, "\001") end

local function makeNavButton(parent, text, iconPath, reserved, ringKey)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(reserved and 26 or 28)
    b:SetWidth(NAV_W - 14)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    b.bg:SetVertexColor(0.3, 0.5, 1, 0)
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetTexture(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
    b.mark:SetWidth(2)
    b.mark:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -3)
    b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 3)
    b.mark:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    local slot = reserved and 18 or 20
    b.icon:SetWidth(reserved and 21.6 or 24); b.icon:SetHeight(reserved and 21.6 or 24)
    b.icon:SetPoint("CENTER", b, "LEFT", 9 + slot / 2, 0)
    if iconPath then T.SetIcon(b.icon, iconPath) end
    b.label = T.Text(b, reserved and 11 or 12, reserved and T.TEXT_MUTE or T.TEXT)
    b.label:SetPoint("LEFT", b, "LEFT", 9 + slot + 7, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", reserved and -44 or -4, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetText(text)
    if reserved then
        if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
        b.icon:SetAlpha(0.6)
        b.badge = T.SoonBadge(b)
        b.badge:SetPoint("RIGHT", b, "RIGHT", -3, 0)
    else
        T.HoverTex(b, T.ACCENT)
    end
    return b
end

local function reservedTip(b, entry)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.reserved, T.GOLD[1], T.GOLD[2], T.GOLD[3])
        if entry.desc then GameTooltip:AddLine(entry.desc, 1, 1, 1, true) end
        GameTooltip:AddLine("Coming soon", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Build (or rebuild) the cached page of one nav path.
local function buildPage(key, path)
    if path[1] == "home" then
        local entry = S.BuildHome(win.scrollChild)
        entry.path, entry.home = path, true
        win.pages[key] = entry
        return entry
    end
    local root = getRoot()
    if not root then return nil end
    win.root = root
    local group = groupAt(root, path)
    if not group then return nil end
    local old = win.pages[key]
    if old then old.frame:Hide() end
    local page = CreateFrame("Frame", nil, win.scrollChild)
    page:SetPoint("TOPLEFT", win.scrollChild, "TOPLEFT", 0, 0)
    page:SetWidth(win.scrollChild:GetWidth())
    -- Page title + subtitle (the group's own name / desc).
    local p = {}
    for i = 1, #path do p[i] = path[i] end
    local title = member("name", group, root, p, appName) or ""
    local desc = member("desc", group, root, p, appName)
    local head = T.Text(page, 16, T.GOLD, "OUTLINE")
    head:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -2)
    head:SetText(title)
    local topY = 26
    if type(desc) == "string" and desc ~= "" then
        local sub = T.Text(page, 11, T.TEXT_DIM)
        sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
        sub:SetWidth(page:GetWidth() - 4)
        sub:SetJustifyH("LEFT")
        sub:SetText(desc)
        topY = topY + sub:GetStringHeight() + 6
    end
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(topY + 6))
    body:SetWidth(page:GetWidth())
    local live = renderGroup(body, group, root, p, appName, page:GetWidth())
    page:SetHeight(topY + 6 + body:GetHeight() + 8)
    local entry = { frame = page, live = live, path = p, sig = S.HiddenSignature(group, root, p, appName) }
    win.pages[key] = entry
    return entry
end

local function selectPath(path, keepScroll)
    if not win then return end
    local key = navKey(path)
    win.selected = key
    for k, nb in pairs(win.nav) do
        local on = (k == key)
        nb.bg:SetVertexColor(0.3, 0.5, 1, on and 0.18 or 0)
        nb.label:SetTextColor(T.unpack(on and T.GOLD or T.TEXT))
        if on then nb.mark:Show() else nb.mark:Hide() end
    end
    for k, e in pairs(win.pages) do if k ~= key then e.frame:Hide() end end
    local entry = win.pages[key] or buildPage(key, path)
    if not entry then return end
    entry.frame:Show()
    for _, wdg in ipairs(entry.live) do if wdg.Refresh then wdg:Refresh() end end
    win.scrollChild:SetHeight(math.max(entry.frame:GetHeight(), 1))
    if win.scroll.UpdateScrollChildRect then win.scroll:UpdateScrollChildRect() end
    if not keepScroll then
        win.scroll:SetVerticalScroll(0)
        if win.scrollBar then win.scrollBar:SetValue(0) end
    end
end
S.SelectPath = selectPath

-- Re-read every live widget without rebuilding. Only when an option appears
-- or disappears (hidden state changed) is the current page rebuilt. A slider
-- being dragged ignores this (it refreshes itself on release).
function S.RefreshOpen()
    if not win or not win:IsShown() then return end
    local entry = win.selected and win.pages[win.selected]
    if entry then
        local root = (not entry.home) and getRoot()
        local group = root and groupAt(root, entry.path)
        if group and S.HiddenSignature(group, root, entry.path, appName) ~= entry.sig then
            win.pages[win.selected] = nil
            entry.frame:Hide()
            selectPath(entry.path, true)
        else
            for _, wdg in ipairs(entry.live) do if wdg.Refresh then wdg:Refresh() end end
        end
    end
    S.UpdateAwesomeNote()
end

function S.UpdateAwesomeNote()
    if not win or not win.awesome then return end
    if addon.AwesomeStatusText then
        win.awesome:SetText(addon.AwesomeStatusText())
        win.awesome:Show()
    else
        win.awesome:Hide()
    end
end

-------------------------------------------------------------------------------
-- Home page: a welcome banner and one tile per area with a live status line.
-- Clicking a tile opens that page. Status is read straight from the profile.
-------------------------------------------------------------------------------
local function onOff(v) return v and "|cff4dff6bOn|r" or "|cffff5757Off|r" end

-- tile texts measured in the game font to fit one line (tile text ~176 px).
local HOME_TILES = {
    { path = { "nameplates", "friendly" }, title = "Friendly Plates", icon = ICON_FRIENDLY, ring = "FRIENDLY",
      text = "See your team at a glance.",
      status = function(db) return "Icons: " .. onOff(db.nameplates.classIconsEnabled) end },
    { path = { "nameplates", "enemy" }, title = "Enemy Plates", icon = ART .. "Enemy", ring = "ENEMY",
      text = "Read every enemy at a glance.",
      status = function(db) return "Icons: " .. onOff(db.nameplates.enemyIconsEnabled) end },
    { path = { "healercc" }, title = "Healer CC", icon = ICON_HEALERCC, ring = "HEALERCC",
      text = "Alert when your healer is CCed.",
      status = function(db) return "Alerts: " .. onOff(db.misc.healerInCrowdControl) end },
    { path = { "nameplates", "advanced" }, title = "Advanced", icon = ART .. "Advanced", ring = "ADVANCED",
      text = "Talent cache and timing.",
      status = function(db) return "Plate units: " .. onOff(db.nameplates.useAwesomeWotlkNameplateUnits) end },
}
S.HOME_TILES = HOME_TILES
-- one line that fits the banner (was 487 px in a ~406 px space).
S.WELCOME_TEXT = "Class, spec, role and CC icons for friends and foes."

local function tileFrame(parent, w, h)
    local t = CreateFrame("Button", nil, parent)
    t:SetWidth(w); t:SetHeight(h)
    t:SetBackdrop(T.CARD_BACKDROP)
    t:SetBackdropColor(0.055, 0.055, 0.065, 0.92)
    t:SetBackdropBorderColor(0.42, 0.35, 0.10, 0.9)
    return t
end

function S.BuildHome(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local width = parent:GetWidth()
    page:SetWidth(width)

    -- Banner
    local banner = tileFrame(page, width, 92)
    banner:EnableMouse(false)
    banner:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    banner:SetBackdropColor(0.09, 0.07, 0.02, 0.95)
    banner:SetBackdropBorderColor(T.unpack(T.GOLD))
    local logo = banner:CreateTexture(nil, "ARTWORK")
    logo:SetWidth(67.8); logo:SetHeight(67.8)
    logo:SetPoint("LEFT", banner, "LEFT", 12.1, 0)
    T.SetIcon(logo, addon.LOGO_ART)
    local title = T.Text(banner, 22, T.GOLD, "OUTLINE")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12.1, -7.9)
    title:SetText("Welcome to " .. (addon.addonTitle or "OPlates"))
    local sub = T.Text(banner, 12, T.TEXT)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetPoint("RIGHT", banner, "RIGHT", -14, 0)
    sub:SetJustifyH("LEFT")
    sub:SetText(S.WELCOME_TEXT)
    page.welcome = sub

    -- Tiles (2 columns)
    local live = {}
    local gap = 12
    local tw = math.floor((width - gap) / 2)
    local th = 76
    local y = 92 + 16
    local head = T.Text(page, 13, T.GOLD)
    head:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -y)
    head:SetText("Quick start")
    y = y + 22
    for i, d in ipairs(HOME_TILES) do
        local col = (i - 1) % 2
        local t = tileFrame(page, tw, th)
        t:SetPoint("TOPLEFT", page, "TOPLEFT", col * (tw + gap), -y)
        T.HoverTex(t, T.ACCENT)
        local ic = t:CreateTexture(nil, "ARTWORK")
        ic:SetWidth(45.2); ic:SetHeight(45.2)
        ic:SetPoint("CENTER", t, "LEFT", 34, 0)
        T.SetIcon(ic, d.icon)
        local tt = T.Text(t, 14, T.GOLD)
        tt:SetPoint("TOPLEFT", ic, "TOPRIGHT", 9.4, -0.6)
        tt:SetText(d.title)
        local tx = T.Text(t, 11, T.TEXT_DIM)
        tx:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -3)
        tx:SetPoint("RIGHT", t, "RIGHT", -10, 0)
        tx:SetJustifyH("LEFT")
        tx:SetText(d.text)
        local st = T.Text(t, 11, T.TEXT)
        st:SetPoint("TOPLEFT", tx, "BOTTOMLEFT", 0, -4)
        local path = d.path
        t:SetScript("OnClick", function() S.SelectPath(path) end)
        live[#live + 1] = { Refresh = function()
            local db = OPlates and OPlates.db and OPlates.db.profile
            if db then st:SetText(d.status(db)) end
        end }
        if col == 1 then y = y + th + gap end
    end
    if #HOME_TILES % 2 == 1 then y = y + th + gap end

    -- Coming soon strip
    y = y + 4
    local soon = T.Text(page, 13, T.GOLD)
    soon:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -y)
    soon:SetText("Coming soon")
    y = y + 22
    local items = {}
    for _, e in ipairs(S.NAV) do if e.reserved then items[#items + 1] = e end end
    local cw = math.floor((width - gap * (#items - 1)) / #items)
    for i, e in ipairs(items) do
        local c = tileFrame(page, cw, 64)
        c:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (cw + gap), -y)
        c:SetBackdropColor(0.04, 0.04, 0.045, 0.85)
        c:SetBackdropBorderColor(0.3, 0.27, 0.15, 0.8)
        local ic = c:CreateTexture(nil, "ARTWORK")
        ic:SetWidth(29.4); ic:SetHeight(29.4)
        ic:SetPoint("TOP", c, "TOP", 0, -6.3)
        T.SetIcon(ic, e.icon)
        if ic.SetDesaturated then ic:SetDesaturated(true) end
        ic:SetAlpha(0.7)
        local tx = T.Text(c, 10, T.TEXT_MUTE)
        tx:SetPoint("TOP", ic, "BOTTOM", 0, -3.3)
        tx:SetWidth(cw - 8)
        tx:SetText(e.reserved)
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(e.reserved, T.GOLD[1], T.GOLD[2], T.GOLD[3])
            if e.desc then GameTooltip:AddLine(e.desc, 1, 1, 1, true) end
            GameTooltip:AddLine("Coming soon", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y + 64 + 10
    local tip = T.Text(page, 10, T.TEXT_MUTE)
    tip:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -y)
    tip:SetText("Tip: type /op to open this window. Hover any option for a short explanation.")
    y = y + 16
    page:SetHeight(y)
    return { frame = page, live = live }
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local function buildWindow()
    local f = CreateFrame("Frame", "OPlatesSettingsWindow", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetWidth(WIN_W); f:SetHeight(WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(T.WINDOW_BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0.97)
    if UISpecialFrames then tinsert(UISpecialFrames, "OPlatesSettingsWindow") end
    f.pages, f.nav = {}, {}

    -- Header
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetWidth(40.7); f.logo:SetHeight(40.7)
    f.logo:SetPoint("TOPLEFT", f, "TOPLEFT", 15.65, -11.65)
    T.SetIcon(f.logo, addon.LOGO_ART)
    f.title = T.Text(f, 20, T.GOLD, "OUTLINE")
    f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 7.65, -3.35)
    f.title:SetText(addon.addonTitle or "OPlates")
    f.version = T.Text(f, 10, T.TEXT_DIM)
    f.version:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 1, -2)
    f.version:SetText(addon.UIVersionText or "")
    f.awesome = T.Text(f, 9, T.TEXT_DIM)
    f.awesome:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -16)
    f.awesome:SetJustifyH("RIGHT")
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.divider = T.Divider(f)
    f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -60)
    f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -60)

    -- Nav rail
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -68)
    rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    rail:SetWidth(NAV_W)
    rail:SetBackdrop(T.PANEL_BACKDROP)
    rail:SetBackdropColor(0.03, 0.03, 0.04, 0.9)
    rail:SetBackdropBorderColor(0.42, 0.35, 0.10, 0.8)
    f.rail = rail

    local root = getRoot()
    local y = -7
    for _, e in ipairs(NAV) do
        if e.section then
            y = y - 5
            local s = T.Text(rail, 9, T.GOLD_DIM, "OUTLINE")
            s:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, y)
            s:SetText(e.section)
            local line = T.Divider(rail)
            line:SetPoint("LEFT", s, "RIGHT", 6, 0)
            line:SetPoint("RIGHT", rail, "RIGHT", -10, 0)
            y = y - 15
        elseif e.reserved then
            local b = makeNavButton(rail, e.reserved, e.icon, true, e.ring)
            b:SetPoint("TOPLEFT", rail, "TOPLEFT", 7, y)
            reservedTip(b, e)
            y = y - (b:GetHeight() + 1)
        else
            local g = root and groupAt(root, e.path)
            local text = e.path[1] == "home" and "Home" or (g and member("name", g, root, e.path, appName))
            if text then
                local b = makeNavButton(rail, text, e.icon, false, e.ring)
                b:SetPoint("TOPLEFT", rail, "TOPLEFT", 7, y)
                local path = e.path
                b:SetScript("OnClick", function() selectPath(path) end)
                f.nav[navKey(path)] = b
                y = y - (b:GetHeight() + 1)
            end
        end
    end
    -- Support pinned to the bottom of the rail.
    -- live. Closes this window and opens the donation window.
    local sup = makeNavButton(rail, S.SUPPORT.name, S.SUPPORT.icon, false, S.SUPPORT.ring)
    sup:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 7, 7)
    sup.label:SetTextColor(T.unpack(T.RING.SUPPORT))
    sup:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(S.SUPPORT.name, T.RING.SUPPORT[1], T.RING.SUPPORT[2], T.RING.SUPPORT[3])
        GameTooltip:AddLine(S.SUPPORT.desc, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sup:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sup:SetScript("OnClick", function() S.OpenSupport() end)
    f.support = sup
    local supLine = T.Divider(rail)
    supLine:SetPoint("BOTTOMLEFT", sup, "TOPLEFT", 4, 4)
    supLine:SetPoint("BOTTOMRIGHT", sup, "TOPRIGHT", -4, 4)

    -- Content
    local scroll = CreateFrame("ScrollFrame", "OPlatesSettingsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", rail, "TOPRIGHT", 14, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 18)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(WIN_W - 14 - NAV_W - 14 - 36)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    f.scroll, f.scrollChild = scroll, child
    f.scrollBar = _G["OPlatesSettingsScrollScrollBar"]

    f:SetScript("OnShow", function() S.UpdateAwesomeNote() end)
    f:SetScript("OnHide", function()
        GameTooltip:Hide()
        local m = _G.OPlatesDropdownMenu
        if m then m:Hide() end
    end)
    f:Hide()
    return f
end

-- The options table can be rebuilt by RegisterOptionsTable; pages are cheap to
-- rebuild, so drop the cache whenever the table identity changes.
function S.Open(path)
    if not win then win = buildWindow() end
    local root = getRoot()
    if root ~= win.root then
        for _, e in pairs(win.pages) do e.frame:Hide() end
        win.pages = {}
        win.root = root
    end
    win:Show()
    win:Raise()
    S.UpdateAwesomeNote()
    if path then selectPath(path); return end
    local entry = win.selected and win.pages[win.selected]
    if entry then selectPath(entry.path) else selectPath({ "home" }) end
end

-- the Support button. The donation windows live in UI/Support.lua.
function S.OpenSupport()
    if win then win:Hide() end
    if addon.UISupport and addon.UISupport.Open then addon.UISupport.Open() end
end

function S.IsShown() return win and win:IsShown() and true or false end
function S.Hide() if win then win:Hide() end end
function S.Window() return win end
