local _, addon = ...

-- OPlates themed option widgets. Each constructor returns a widget object
-- with { frame, Refresh, GetHeight } built at a fixed width (the settings window
-- does not resize, like the filter windows). A widget renders ONE leaf option
-- from the existing AceConfig tables; the engine (UI/Settings.lua) hands it a
-- "model" of already-resolved callbacks, so every original get/set/disabled
-- function keeps working unchanged.
--
--   model = {
--     type, name, desc,            -- strings
--     get = function() return v end,
--     set = function(v) end,       -- toggle / range / select / input
--     run = function() end,        -- execute
--     disabled = function() return bool end,
--     min, max, step, isPercent,   -- range
--     values = { key = text },     -- select
--     sorting = { key, ... },      -- select, optional fixed order
--     multiline,                   -- input (number of lines or false)
--     openFilter = function() end, -- filter button
--   }

local T = addon.UITheme
local W = {}
addon.UIWidgets = W

local function tip(frame, model)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if not model.name or model.name == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(model.name, T.GOLD[1], T.GOLD[2], T.GOLD[3])
        local desc = model.desc
        if type(desc) == "string" and desc ~= "" then
            GameTooltip:AddLine(desc, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Strip Ace colour codes for a clean label; the theme recolours text itself.
local function clean(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-------------------------------------------------------------------------------
-- Toggle
-------------------------------------------------------------------------------
local CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"

function W.Toggle(parent, model, width)
    local f = CreateFrame("Button", nil, parent)
    f:SetWidth(width); f:SetHeight(26)

    local box = CreateFrame("Frame", nil, f)
    box:SetWidth(20); box:SetHeight(20)
    box:SetPoint("LEFT", f, "LEFT", 2, 0)
    box:SetBackdrop(T.FIELD_BACKDROP)
    box:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    box:SetBackdropBorderColor(0.5, 0.42, 0.12, 1)

    local check = box:CreateTexture(nil, "ARTWORK")
    check:SetTexture(CHECK_TEX)
    check:SetWidth(22); check:SetHeight(22)
    check:SetPoint("CENTER", box, "CENTER", 0, 0)
    check:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])

    local label = T.Text(f, 12, T.TEXT)
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(clean(model.name))

    local hl = T.HoverTex(f, T.ACCENT)

    local widget = { frame = f, box = box, check = check, label = label }
    function widget:GetHeight() return 26 end
    function widget:Refresh()
        local on = model.get() and true or false
        if on then check:Show() else check:Hide() end
        local dis = model.disabled and model.disabled() or false
        if dis then
            label:SetTextColor(T.unpack(T.TEXT_MUTE))
            box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            check:SetVertexColor(0.4, 0.4, 0.4)
            hl:Hide()
        else
            label:SetTextColor(T.unpack(T.TEXT))
            box:SetBackdropBorderColor(0.5, 0.42, 0.12, 1)
            check:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
            hl:Show()
        end
        widget.disabled = dis
    end
    f:SetScript("OnClick", function()
        if widget.disabled then return end
        model.set(not (model.get() and true or false))
        if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
        widget:Refresh()
    end)
    tip(f, model)
    widget:Refresh()
    return widget
end

-------------------------------------------------------------------------------
-- Execute button (red UIPanelButtonTemplate, the loved Test-button look)
-------------------------------------------------------------------------------
function W.Button(parent, model, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(30)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetHeight(24)
    b:SetText(clean(model.name))
    local fs = b:GetFontString()
    local tw = (fs and fs:GetStringWidth() or 80) + 30
    b:SetWidth(math.min(width, math.max(90, tw)))
    b:SetPoint("LEFT", f, "LEFT", 2, 0)

    local widget = { frame = f, button = b }
    function widget:GetHeight() return 30 end
    function widget:Refresh()
        local dis = model.disabled and model.disabled() or false
        if dis then b:Disable() else b:Enable() end
        widget.disabled = dis
    end
    b:SetScript("OnClick", function()
        if widget.disabled then return end
        model.run()
    end)
    tip(b, model)
    widget:Refresh()
    return widget
end

-------------------------------------------------------------------------------
-- Filter button (short red button that opens a Class/Spec Filter window). Same
-- red/yellow look; placed by the engine on the right of its toggle's row.
-------------------------------------------------------------------------------
function W.FilterButton(parent, model)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetHeight(22)
    b:SetText(clean(model.name))
    local fs = b:GetFontString()
    local tw = (fs and fs:GetStringWidth() or 80) + 22
    local bw = math.max(96, tw)
    b:SetWidth(bw)
    f:SetWidth(bw)
    b:SetAllPoints(f)

    local widget = { frame = f, button = b }
    function widget:GetHeight() return 24 end
    function widget:Refresh()
        local dis = model.disabled and model.disabled() or false
        if dis then b:Disable() else b:Enable() end
        widget.disabled = dis
    end
    b:SetScript("OnClick", function()
        if widget.disabled then return end
        model.openFilter()
    end)
    tip(b, model)
    widget:Refresh()
    return widget
end

-------------------------------------------------------------------------------
-- Section header (gold text + flanking gold lines)
-------------------------------------------------------------------------------
function W.Header(parent, model, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(24)
    local text = T.Text(f, 12, T.GOLD, "OUTLINE")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetText(clean(model.name))
    local tw = text:GetStringWidth()
    local left = T.Divider(f)
    left:SetPoint("LEFT", f, "LEFT", 4, 0)
    left:SetPoint("RIGHT", f, "CENTER", -(tw / 2) - 8, 0)
    local right = T.Divider(f)
    right:SetPoint("LEFT", f, "CENTER", (tw / 2) + 8, 0)
    right:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    local widget = { frame = f }
    function widget:GetHeight() return 24 end
    function widget:Refresh() end
    return widget
end

-------------------------------------------------------------------------------
-- Description (wrapped muted text; supports Ace colour codes as-is)
-------------------------------------------------------------------------------
function W.Description(parent, model, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    local size = model.fontSize == "large" and 14 or (model.fontSize == "medium" and 12 or 11)
    local text = T.Text(f, size, T.TEXT_DIM)
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
    text:SetWidth(width - 4)
    text:SetJustifyH("LEFT")
    text:SetText(model.name or "")
    local h = math.max(14, text:GetStringHeight() + 4)
    f:SetHeight(h)
    local widget = { frame = f, text = text }
    function widget:GetHeight() return h end
    function widget:Refresh()
        if model.getName then model.name = model.getName() end
        text:SetText(model.name or "")
        local nh = math.max(14, text:GetStringHeight() + 4)
        if nh ~= h then h = nh; f:SetHeight(h) end
    end
    return widget
end

-------------------------------------------------------------------------------
-- Slider (range). Dark track, gold thumb, editable value box. While dragging we
-- only call model.set(live) (which maps to the drag-safe setRange and does NOT
-- rebuild the window), so the thumb never dies mid-drag. The engine never
-- rebuilds a slider; it only re-reads the value on Refresh.
-------------------------------------------------------------------------------
local function roundStep(value, min, step)
    if step and step > 0 then
        value = math.floor((value - min) / step + 0.5) * step + min
    end
    return value
end

function W.Slider(parent, model, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(44)

    local label = T.Text(f, 12, T.TEXT)
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
    label:SetText(clean(model.name))

    local valueBox = CreateFrame("EditBox", nil, f)
    valueBox:SetAutoFocus(false)
    valueBox:SetFontObject("GameFontHighlightSmall")
    valueBox:SetWidth(52); valueBox:SetHeight(18)
    valueBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)
    valueBox:SetJustifyH("CENTER")
    valueBox:SetBackdrop(T.FIELD_BACKDROP)
    valueBox:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    valueBox:SetBackdropBorderColor(0.5, 0.42, 0.12, 1)
    valueBox:SetTextInsets(2, 2, 1, 1)

    local slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -24)
    slider:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    slider:SetHeight(16)
    local min = model.min or 0
    local max = model.max or 100
    local step = model.step or 0
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step > 0 and step or 0.01)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    track:SetVertexColor(0.10, 0.10, 0.12, 0.95)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(5)
    local trackEdge = slider:CreateTexture(nil, "BORDER")
    trackEdge:SetTexture(0.5, 0.42, 0.12, 0.8)
    trackEdge:SetPoint("TOPLEFT", track, "TOPLEFT", -1, 1)
    trackEdge:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 1, -1)
    track:SetDrawLayer("BORDER", 1)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.45)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(5)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetWidth(20); thumb:SetHeight(20)
    slider:SetThumbTexture(thumb)

    local function fmt(v)
        if model.isPercent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
        if step and step < 1 and step > 0 then return string.format("%.2f", v) end
        return tostring(math.floor(v + 0.5))
    end

    local function updateFill()
        local v = slider:GetValue()
        local frac = (max > min) and ((v - min) / (max - min)) or 0
        local w = slider:GetWidth()
        if w and w > 0 then fill:SetWidth(math.max(1, frac * w)) end
    end

    local widget = { frame = f, slider = slider }
    local sliding, updating, last = false, false, nil
    function widget:GetHeight() return 44 end
    function widget:Refresh()
        if sliding then return end
        local v = model.get()
        if type(v) ~= "number" then v = min end
        -- SetValue fires OnValueChanged; never write the value back from here.
        updating = true
        slider:SetValue(v)
        updating = false
        last = v
        valueBox:SetText(fmt(v))
        updateFill()
        local dis = model.disabled and model.disabled() or false
        if dis then
            slider:EnableMouse(false); slider:SetAlpha(0.4)
            valueBox:EnableKeyboard(false); valueBox:EnableMouse(false)
            label:SetTextColor(T.unpack(T.TEXT_MUTE))
        else
            slider:EnableMouse(true); slider:SetAlpha(1)
            valueBox:EnableKeyboard(true); valueBox:EnableMouse(true)
            label:SetTextColor(T.unpack(T.TEXT))
        end
        widget.disabled = dis
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if updating or widget.disabled then return end
        value = roundStep(value, min, step)
        valueBox:SetText(fmt(value))
        updateFill()
        if value == last then return end
        last = value
        model.set(value)
    end)
    slider:SetScript("OnMouseDown", function() sliding = true end)
    slider:SetScript("OnMouseUp", function()
        sliding = false
        widget:Refresh()
        -- Like AceConfigDialog, the rest of the page refreshes on release.
        if model.onRelease then model.onRelease() end
    end)
    valueBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber((self:GetText():gsub("%%", "")))
        if v then
            if model.isPercent then v = v / 100 end
            v = math.max(min, math.min(max, roundStep(v, min, step)))
            if v ~= last then last = v; model.set(v) end
        end
        self:ClearFocus()
        widget:Refresh()
        if model.onRelease then model.onRelease() end
    end)
    valueBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); widget:Refresh() end)
    tip(f, model)
    tip(slider, model)
    widget:Refresh()
    return widget
end

-------------------------------------------------------------------------------
-- Dropdown (select). A field that opens a themed list menu below it.
-------------------------------------------------------------------------------
local openMenu

function W.Dropdown(parent, model, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(44)

    local label = T.Text(f, 12, T.TEXT)
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
    label:SetText(clean(model.name))

    local field = CreateFrame("Button", nil, f)
    field:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -20)
    field:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    field:SetHeight(22)
    field:SetBackdrop(T.FIELD_BACKDROP)
    field:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    field:SetBackdropBorderColor(0.5, 0.42, 0.12, 1)
    T.HoverTex(field, T.ACCENT)

    local sel = T.Text(field, 12, T.GOLD)
    sel:SetPoint("LEFT", field, "LEFT", 8, 0)
    sel:SetPoint("RIGHT", field, "RIGHT", -20, 0)
    sel:SetJustifyH("LEFT")

    local arrow = field:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetWidth(16); arrow:SetHeight(16)
    arrow:SetPoint("RIGHT", field, "RIGHT", -4, 0)

    local widget = { frame = f, field = field }
    function widget:GetHeight() return 44 end
    function widget:Refresh()
        if model.refreshValues then model.refreshValues() end
        local v = model.get()
        local values = model.values or {}
        sel:SetText(values[v] or "")
        local dis = model.disabled and model.disabled() or false
        if dis then
            field:EnableMouse(false); field:SetAlpha(0.45)
            label:SetTextColor(T.unpack(T.TEXT_MUTE))
        else
            field:EnableMouse(true); field:SetAlpha(1)
            label:SetTextColor(T.unpack(T.TEXT))
        end
        widget.disabled = dis
        if openMenu and openMenu.owner == widget then openMenu:Hide() end
    end
    field:SetScript("OnClick", function()
        if widget.disabled then return end
        W.ShowDropdownMenu(widget, model, field)
    end)
    tip(field, model)
    widget:Refresh()
    return widget
end

-- Builds / reuses a single shared menu frame for dropdowns.
function W.ShowDropdownMenu(owner, model, anchor)
    if not openMenu then
        local m = CreateFrame("Frame", "OPlatesDropdownMenu", UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetToplevel(true)
        m:SetBackdrop(T.PANEL_BACKDROP)
        m:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
        m:SetBackdropBorderColor(T.unpack(T.GOLD))
        m.rows = {}
        m:SetScript("OnHide", function(self) self.owner = nil end)
        openMenu = m
    end
    local m = openMenu
    if m:IsShown() and m.owner == owner then m:Hide(); return end
    m.owner = owner
    for _, r in ipairs(m.rows) do r:Hide() end

    -- a list with a fixed order (model.sorting) keeps it; any other key
    -- follows, sorted by its text for a stable order.
    if model.refreshValues then model.refreshValues() end
    local values = model.values or {}
    local keys, listed = {}, {}
    if type(model.sorting) == "table" then
        for _, k in ipairs(model.sorting) do
            if values[k] ~= nil and not listed[k] then keys[#keys + 1] = k; listed[k] = true end
        end
    end
    local rest = {}
    for k in pairs(values) do if not listed[k] then rest[#rest + 1] = k end end
    table.sort(rest, function(a, b)
        return tostring(values[a]):upper() < tostring(values[b]):upper()
    end)
    for _, k in ipairs(rest) do keys[#keys + 1] = k end

    local width = anchor:GetWidth()
    local y, rowH = -4, 20
    local current = model.get()
    for i, k in ipairs(keys) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m)
            r:SetHeight(rowH)
            r.text = T.Text(r, 12, T.TEXT)
            r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.text:SetJustifyH("LEFT")
            T.HoverTex(r, T.ACCENT)
            m.rows[i] = r
        end
        r:SetWidth(width - 8)
        r:SetPoint("TOPLEFT", m, "TOPLEFT", 4, y)
        r.text:SetText(values[k])
        if k == current then r.text:SetTextColor(T.unpack(T.GOLD)) else r.text:SetTextColor(T.unpack(T.TEXT)) end
        r:SetScript("OnClick", function()
            model.set(k)
            m:Hide()
            owner:Refresh()
        end)
        r:Show()
        y = y - rowH
    end
    m:SetWidth(width)
    m:SetHeight(-y + 4)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    m:Show()
    m:Raise()
end

-------------------------------------------------------------------------------
-- Input / multiline. Glass edit field + a small Save button (changes commit on
-- Save or Enter, matching Ace's OnEnterPressed).
-------------------------------------------------------------------------------
function W.Input(parent, model, width)
    local multiline = model.multiline and tonumber(model.multiline) or (model.multiline and 3)
    local lines = multiline or 1
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    local boxH = lines > 1 and (14 * lines + 10) or 22
    local labelH = 18
    f:SetHeight(labelH + boxH + 6)

    local label = T.Text(f, 12, T.TEXT)
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
    label:SetText(clean(model.name))

    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -labelH)
    holder:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    holder:SetHeight(boxH)
    holder:SetBackdrop(T.FIELD_BACKDROP)
    holder:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    holder:SetBackdropBorderColor(0.5, 0.42, 0.12, 1)

    local edit = CreateFrame("EditBox", nil, holder)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -4)
    edit:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 4)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(lines > 1)
    edit:SetTextInsets(0, 0, 0, 0)
    if lines > 1 then edit:SetMaxLetters(0) end

    local widget = { frame = f, edit = edit }
    function widget:GetHeight() return labelH + boxH + 6 end
    -- Commit only a real change (an untouched or emptied "new profile" box
    -- must never create a blank-named profile).
    local function commit()
        local text = edit:GetText() or ""
        local cur = model.get()
        if type(cur) ~= "string" then cur = "" end
        if text ~= cur and not widget.disabled then model.set(text) end
        widget:Refresh()
    end
    function widget:Refresh()
        local v = model.get()
        if type(v) ~= "string" then v = "" end
        if not edit:HasFocus() then edit:SetText(v) end
        local dis = model.disabled and model.disabled() or false
        if dis then
            edit:EnableKeyboard(false); edit:EnableMouse(false); holder:SetAlpha(0.45)
            label:SetTextColor(T.unpack(T.TEXT_MUTE))
        else
            edit:EnableKeyboard(true); edit:EnableMouse(true); holder:SetAlpha(1)
            label:SetTextColor(T.unpack(T.TEXT))
        end
        widget.disabled = dis
    end
    edit:SetScript("OnEnterPressed", function(self)
        if lines > 1 then return end
        commit(); self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); widget:Refresh() end)
    edit:SetScript("OnEditFocusLost", commit)
    tip(holder, model)
    tip(edit, model)
    widget:Refresh()
    return widget
end
