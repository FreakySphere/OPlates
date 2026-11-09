-- Unit test for the v1.10 "Reset window (seconds)" setting.
--
-- Loads the real Common/CrowdControl.lua and checks addon.GetDRResetSeconds()
-- against the profile values the Advanced slider can produce, plus the values
-- it must refuse (out of range, missing, garbage).
--
--   usage: lua5.1 tests/dr_reset_window.lua <addon root>

local root = arg and arg[1] or "OPlates"
local addon = {}

local chunk = assert(loadfile(root .. "/Common/CrowdControl.lua"))
chunk("OPlates", addon)

assert(type(addon.GetDRResetSeconds) == "function", "GetDRResetSeconds is missing")
assert(addon.CROWD_CONTROL_DR_RESET == 18.1,
    "constant default should be 18.1, got " .. tostring(addon.CROWD_CONTROL_DR_RESET))

local function withProfile(value)
    OPlates = { db = { profile = { nameplates = { drResetSeconds = value } } } }
    return addon.GetDRResetSeconds()
end

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-34s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-34s %s", label, tostring(got)))
    end
end

-- every value the slider can produce must survive untouched
check("default 18.1",            withProfile(18.1), 18.1)
check("slider min 15",           withProfile(15),   15)
check("slider max 20",           withProfile(20),   20)
check("mid value 17.3",          withProfile(17.3), 17.3)
check("step 18.4",               withProfile(18.4), 18.4)
check("string from SavedVariables", withProfile("19.5"), 19.5)

-- and everything else must fall back to the constant
check("nil falls back",          withProfile(nil),  18.1)
check("below range falls back",  withProfile(14.9), 18.1)
check("above range falls back",  withProfile(20.1), 18.1)
check("garbage falls back",      withProfile("nope"), 18.1)
check("zero falls back",         withProfile(0),    18.1)

-- profile not loaded yet (first login, before AceDB is ready)
OPlates = nil
check("no OPlates at all", addon.GetDRResetSeconds(), 18.1)

OPlates = { db = {} }
check("db without profile", addon.GetDRResetSeconds(), 18.1)

OPlates = { db = { profile = {} } }
check("profile without nameplates", addon.GetDRResetSeconds(), 18.1)

if failures > 0 then
    error(failures .. " check(s) failed")
end
print("\nall reset-window checks passed")
