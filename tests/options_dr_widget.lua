-- Verifies the v1.10 Advanced page really carries the new Diminishing Returns
-- widget, with the bounds the brief asked for, and that it sits after
-- "Class to Spec" rather than somewhere else on the page.
--
--   usage: lua5.1 tests/options_dr_widget.lua <addon root>

local root = arg and arg[1] or "OPlates"

-- minimal environment the options builder expects
addon = { L = setmetatable({}, { __index = function(_, k) return k end }) }

GetTime = function() return 0 end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
strsplit = function(sep, s)
    local o = {}
    for f in string.gmatch(s, "([^" .. sep .. "]+)") do o[#o + 1] = f end
    return unpack(o)
end
format = string.format
tinsert, tremove = table.insert, table.remove

-- the file registers a one-shot login check frame at load time
CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    function f:UnregisterAllEvents() end
    return f
end

OPlates = {
    db = { profile = { nameplates = {
        drResetSeconds = 18.1,
        classToSpecDelay = 1.0,
        classToSpecDelayEnabled = true,
        showClassIcon = true,
        showSpec = true,
        classIconsEnabled = true,
        friendlyDisplayMode = "ALL",
        enemyDisplayMode = "ALL",
    } } },
    RefreshNameplateOverlays = function() end,
    NotifyOptions = function() end,
}

addon.NameplateOptionLocked = function() return false end
addon.NameplateFilterLocked = function() return false end
addon.TalentScanner = nil
addon.GetWotLKNameplateOptions = nil

local chunk = assert(loadfile(root .. "/Nameplates/Options.lua"))
chunk("OPlates", addon)

assert(type(addon.GetWotLKNameplateOptions) == "function", "options builder missing")
local t = addon.GetWotLKNameplateOptions(1)

local advanced = t.args and t.args.advanced
assert(advanced and advanced.args, "no Advanced page")

local transition = advanced.args.transition
local diminishing = advanced.args.diminishing

assert(transition, "Class to Spec group vanished")
assert(diminishing, "Diminishing Returns group is missing from Advanced")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-32s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-32s %s", label, tostring(got)))
    end
end

-- group shape: must be an inline group, exactly like Class to Spec
check("group type",        diminishing.type, "group")
check("group inline",      diminishing.inline, true)
check("group name",        diminishing.name, "Diminishing Returns")
check("group order",       diminishing.order, 4)
check("sits after Class to Spec", diminishing.order > transition.order, true)

local widget = diminishing.args and diminishing.args.drResetSeconds
assert(widget, "drResetSeconds widget missing")

check("widget type",   widget.type, "range")
check("widget width",  widget.width, "full")
check("widget name",   widget.name, "Reset window (seconds)")
check("widget min",    widget.min, 15)
check("widget max",    widget.max, 20)
check("widget step",   widget.step, 0.1)
check("widget order",  widget.order, 1)
check("setter is the shared one", widget.set, transition.args.classToSpecDelay.set)
check("has a description", type(widget.desc) == "string" and #widget.desc > 80, true)
check("not disabled", widget.disabled, nil)

-- the default the widget will show before anyone touches it
check("default from profile", OPlates.db.profile.nameplates.drResetSeconds, 18.1)

if failures > 0 then
    error(failures .. " check(s) failed")
end
print("\nall options-widget checks passed")
