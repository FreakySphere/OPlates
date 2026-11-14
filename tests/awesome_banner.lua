-- Unit test for the awesome_wotlk login banners (v1.13).
--
-- Two rules are being pinned down here:
--   1. the unpatched warning is a FIRST-RUN notice. Once it has been shown it
--      never comes back, because an unpatched client is a normal setup and many
--      servers forbid client patches outright.
--   2. every banner carries the Warmane warning in red capitals.
--
--   usage: lua5.1 tests/awesome_banner.lua <addon root>

local root = arg and arg[1] or "OPlates"
local addon = { L = setmetatable({}, { __index = function(_, k) return k end }) }

-- Options.lua builds its one-shot login frame at file scope.
local stubFrame = {
    RegisterEvent = function() end,
    UnregisterAllEvents = function() end,
    SetScript = function() end,
}
function CreateFrame() return stubFrame end
function GetTime() return 0 end
OPlates = { db = { profile = { nameplates = {} }, global = {} } }

local chunk = assert(loadfile(root .. "/Nameplates/Options.lua"))
chunk("OPlates", addon)

assert(type(addon.AwesomeBannerKind) == "function", "AwesomeBannerKind is missing")
assert(type(addon.AwesomeBanners) == "table", "AwesomeBanners is missing")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-46s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-46s %s", label, tostring(got)))
    end
end

local function kind(detected, greeted, enabled, missingSeen)
    return addon.AwesomeBannerKind(detected, greeted, enabled, missingSeen)
end

-- 1. unpatched client -------------------------------------------------------
check("unpatched, first launch ever", kind(false, false, false, false), "MISSING")
check("unpatched, seen once before", kind(false, true, false, true), nil)
check("unpatched, greeted but never warned", kind(false, true, false, false), "MISSING")
check("unpatched, option on, already warned", kind(false, true, true, true), nil)

-- 2. patched client ---------------------------------------------------------
check("patched, never greeted", kind(true, false, false, false), "FOUND")
check("patched, greeted and in use", kind(true, true, true, true), nil)
check("patched, greeted but switched off", kind(true, true, false, true), "DISABLED")

-- 3. the wording ------------------------------------------------------------
local WARN = "WARMANE AND OTHER SERVERS THAT FORBID CLIENT MODIFICATIONS"
for _, name in ipairs({ "MISSING", "FOUND", "DISABLED" }) do
    local spec = addon.AwesomeBanners[name]
    assert(spec, "banner " .. name .. " is missing")
    local text = spec.text or ""
    local red = text:find("|cffff3b3b" .. WARN, 1, true)
    check(name .. ": Warmane warning present", red ~= nil, true)
    check(name .. ": warning is closed with |r", text:sub(-2), "|r")
    -- the capitals must be capitals. Skip the colour escape (its hex digits are
    -- lowercase), the closing |r, and the product name, which keeps its spelling.
    local tail = text:sub((red or 1) + 10, -3):gsub("awesome_wotlk", "")
    check(name .. ": warning has no lowercase", tail:find("%l") ~= nil, false)
end

-- 4. titles stay short ------------------------------------------------------
check("MISSING title", addon.AwesomeBanners.MISSING.title, "awesome_wotlk patch not detected")
check("FOUND title", addon.AwesomeBanners.FOUND.title, "awesome_wotlk patch detected!")
-- the first-run warning is a notice, not a wall: 20 seconds, then it fades.
check("MISSING hold", addon.AwesomeBanners.MISSING.hold, 20)
check("FOUND hold", addon.AwesomeBanners.FOUND.hold, 20)
check("DISABLED never auto-fades", addon.AwesomeBanners.DISABLED.hold, nil)

-- 5. the login check actually records the one-time state --------------------
-- An unpatched client must warn on the first login and stay silent afterwards,
-- which is the whole point of the change. The CHAT line is separate: it prints
-- on every login, for all three states, with the short Warmane note.
local shown, chat = {}, {}
addon.ShowAwesomeBanner = function(kind) shown[#shown + 1] = kind end
addon.PRINT = function(message) chat[#chat + 1] = message end
addon.TalentScanner = { DetectAwesomeWotlk = function() return nil end }
OPlates = {
    db = { profile = { nameplates = { useAwesomeWotlkNameplateUnits = false } }, global = {} },
    NotifyOptions = function() end,
}

check("first login on an unpatched client", addon.AwesomeWotlkLoginCheck(), "MISSING")
check("...remembers it was shown", OPlates.db.global.awesomeWotlkMissingSeen, true)
check("second login stays silent", addon.AwesomeWotlkLoginCheck(), nil)
check("third login stays silent", addon.AwesomeWotlkLoginCheck(), nil)
check("banner shown exactly once", #shown, 1)
check("chat line printed every login", #chat, 3)
check("chat still names the state", chat[3]:find("awesome_wotlk patch not detected", 1, true) ~= nil, true)
check("chat carries the Warmane note", chat[3]:find("Warmane: patch not allowed", 1, true) ~= nil, true)
check("chat note is red", chat[3]:find("|cffff3b3bWarmane", 1, true) ~= nil, true)

-- a fresh install of a patched client still gets the green banner once
shown, chat = {}, {}
addon.TalentScanner = { DetectAwesomeWotlk = function() return "native" end,
    _initialized = false, SetPlateUnits = function() end }
OPlates.db.global = {}
check("patched first login", addon.AwesomeWotlkLoginCheck(), "FOUND")
check("...remembers the greeting", OPlates.db.global.awesomeWotlkGreeted, true)
check("patched second login", addon.AwesomeWotlkLoginCheck(), nil)
check("patched chat every login", #chat, 2)
check("patched chat says detected", chat[2]:find("awesome_wotlk patch detected", 1, true) ~= nil, true)
check("patched chat carries the note", chat[2]:find("Warmane: patch not allowed", 1, true) ~= nil, true)
-- the running status is not a greeting: no exclamation mark.
check("chat drops the exclamation", addon.AwesomeBanners.FOUND.chat, "awesome_wotlk patch detected")

-- patched but switched off: banner and chat both every login
shown, chat = {}, {}
OPlates.db.profile.nameplates.useAwesomeWotlkNameplateUnits = false
OPlates.db.global.awesomeWotlkGreeted = true
check("patched but off", addon.AwesomeWotlkLoginCheck(), "DISABLED")
check("...chat says switched off", chat[1]:find("switched off", 1, true) ~= nil, true)
check("...chat carries the note", chat[1]:find("Warmane: patch not allowed", 1, true) ~= nil, true)

-- the state resolver on its own
check("state: unpatched", addon.AwesomeStatusKind(false, false), "MISSING")
check("state: patched and on", addon.AwesomeStatusKind(true, true), "FOUND")
check("state: patched and off", addon.AwesomeStatusKind(true, false), "DISABLED")

print(failures == 0 and "\nall banner expectations met" or ("\n" .. failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
