-- Unit test for addon.HasFlag (v1.14).
--
-- The combat log describes what an object is with a bit field, and every gate
-- that decides "is this a player", "is he hostile", "is he in my group" reads it.
-- The addon used the `bit` library for that, which is present on 3.3.5a but is
-- replaced or omitted by some servers and addon packs - and three call sites
-- used it unguarded, so a missing `bit` was an error inside the combat-log
-- handler. HasFlag does the arithmetic directly instead.
--
-- The values below are real ones from battleground captures, not invented:
--   1297  a friendly player       (0x511)
--   1352  a hostile player        (0x548)
--   66888 a hostile player with a
--         different affiliation   (0x10548)
--
--   usage: lua5.1 tests/hasflag.lua <addon root>

local root = arg and arg[1] or "OPlates"
local addon = {}

local chunk = assert(loadfile(root .. "/Common/Constants.lua"))
chunk("OPlates", addon)

assert(type(addon.HasFlag) == "function", "HasFlag is missing")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-44s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-44s %s", label, tostring(got)))
    end
end

local F = addon.HasFlag

-- 0x400 player, 0x100 controlled by player, 0x40 hostile, 0x10 friendly,
-- 0x2 party, 0x4 raid
local FRIENDLY, HOSTILE, AFFILIATED = 1297, 1352, 66888

check("friendly player is a player", F(FRIENDLY, 0x400), true)
check("friendly player is friendly", F(FRIENDLY, 0x10), true)
check("friendly player is not hostile", F(FRIENDLY, 0x40), false)
check("friendly player is controlled", F(FRIENDLY, 0x100), true)

check("hostile player is a player", F(HOSTILE, 0x400), true)
check("hostile player is hostile", F(HOSTILE, 0x40), true)
check("hostile player is not friendly", F(HOSTILE, 0x10), false)

check("affiliated hostile is a player", F(AFFILIATED, 0x400), true)
check("affiliated hostile is hostile", F(AFFILIATED, 0x40), true)

-- 0x6 is party-or-raid: two bits, tested separately the way the caller does
local function grouped(v) return F(v, 0x2) or F(v, 0x4) end
check("party member 0x2", grouped(0x406), true)
check("raid member 0x4", grouped(0x404), true)
check("not grouped", grouped(0x400), false)

-- not a player: a creature is 0x800, and 4424 is a real pet flag from a capture
-- (0x1148: pet type, controlled, hostile, no 0x400).
check("creature is not a player", F(0x800, 0x400), false)
check("pet flag 4424 is not a player", F(4424, 0x400), false)

-- junk must not throw and must not claim a flag
check("nil value", F(nil, 0x400), false)
check("string value", F("x", 0x400), false)
check("nil mask", F(0x400, nil), false)
check("zero value", F(0, 0x400), false)
check("negative value", F(-1, 0x400), false)

-- every power of two round-trips
local allGood = true
for i = 0, 30 do
    local m = 2 ^ i
    if not F(m, m) then allGood = false end
    if F(m + m * 2, m) ~= true then allGood = false end
    if m > 1 and F(m * 2, m) then allGood = false end
end
check("every single bit round-trips", allGood, true)

print(failures == 0 and "\nall flag checks passed" or ("\n" .. failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
