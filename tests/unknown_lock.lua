-- Unit test for the "Unknown player (?)" rule (v1.20).
--
-- The question mark is the last-resort icon for a player we know nothing about.
-- It may only appear while at least one identity icon on that side (class,
-- spec, healer, tank) is allowed, because otherwise it is the only thing the
-- plate could ever show and nothing could replace it.
--
--   * all four off  -> locked, and the stored value is forced to false
--   * any one on    -> unlocked, but the value stays false until the user turns
--                      it on again (no automatic restore)
--   * per side      -> friendly and enemy are independent
--   * flag carrier, pet and CC/aura icons are NOT identity icons and must not
--     affect the rule
--
--   usage: lua5.1 tests/unknown_lock.lua <addon root>

local root = arg and arg[1] or "OPlates"
local addon = {}

local chunk = assert(loadfile(root .. "/Common/Constants.lua"))
chunk("OPlates", addon)

assert(type(addon.UnknownIconLocked) == "function", "UnknownIconLocked is missing")
assert(type(addon.SanitizeUnknownIcons) == "function", "SanitizeUnknownIcons is missing")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-52s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-52s %s", label, tostring(got)))
    end
end

-- every identity icon on, both sides, plus the unrelated layers on
local function base()
    return {
        showClassIcon = true, showSpec = true, useHealerIcon = true, useTankIcon = true,
        showUnknownFriendly = false,
        enemyShowClass = true, enemyShowSpec = true, enemyHealerIcon = true, enemyTankIcon = true,
        enemyShowUnknown = false,
        petIconsEnabled = true, useFlagCarrierIcon = true,
        enemyPetIcon = true, enemyFlagCarrierIcon = true,
        showCrowdControl = true, enemyShowCrowdControl = true,
    }
end

local L = addon.UnknownIconLocked
local S = addon.SanitizeUnknownIcons

-- 1. nothing locked with the shipped defaults
local c = base()
check("defaults: friendly unlocked", L(c, false), false)
check("defaults: enemy unlocked", L(c, true), false)

-- 2. all four off on a side locks it
c = base(); c.showClassIcon, c.showSpec, c.useHealerIcon, c.useTankIcon = false, false, false, false
check("friendly: all four off locks", L(c, false), true)
check("friendly: all four off leaves enemy alone", L(c, true), false)

c = base(); c.enemyShowClass, c.enemyShowSpec, c.enemyHealerIcon, c.enemyTankIcon = false, false, false, false
check("enemy: all four off locks", L(c, true), true)
check("enemy: all four off leaves friendly alone", L(c, false), false)

-- 3. one identity icon back on is enough to unlock
c = base(); c.showClassIcon, c.showSpec, c.useHealerIcon, c.useTankIcon = true, false, false, false
check("friendly: class icon alone unlocks", L(c, false), false)
c = base(); c.showClassIcon, c.showSpec, c.useHealerIcon, c.useTankIcon = false, false, true, false
check("friendly: healer icon alone unlocks", L(c, false), false)
c = base(); c.enemyShowClass, c.enemyShowSpec, c.enemyHealerIcon, c.enemyTankIcon = false, false, false, true
check("enemy: tank icon alone unlocks", L(c, true), false)

-- 4. pet / flag / cc are not identity icons
c = base()
c.petIconsEnabled, c.useFlagCarrierIcon, c.showCrowdControl = false, false, false
c.showClassIcon, c.showSpec, c.useHealerIcon, c.useTankIcon = false, false, false, false
check("friendly: pet/flag/cc off does not unlock", L(c, false), true)

-- 5. sanitizer forces the value off while locked ...
c = base()
c.showUnknownFriendly, c.enemyShowUnknown = true, true
c.showClassIcon, c.showSpec, c.useHealerIcon, c.useTankIcon = false, false, false, false
S(c)
check("sanitize: locked friendly unchecks ?", c.showUnknownFriendly, false)
check("sanitize: unlocked enemy keeps ?", c.enemyShowUnknown, true)

-- 6. ... and does NOT restore it when the lock lifts
c.showClassIcon = true
S(c)
check("sanitize: unlocking does not restore ?", c.showUnknownFriendly, false)

-- 7. the user can turn it on again once unlocked
c.showUnknownFriendly = true
S(c)
check("sanitize: manual ? stays on while unlocked", c.showUnknownFriendly, true)

-- 8. and it is forced off again if the side locks again
c.showClassIcon = false
S(c)
check("sanitize: relocking unchecks ? again", c.showUnknownFriendly, false)

-- 9. the unrelated layers are never touched
c = base(); c.showUnknownFriendly = true
S(c)
check("sanitize: leaves flag carrier alone", c.useFlagCarrierIcon, true)
check("sanitize: leaves pet icons alone", c.petIconsEnabled, true)
check("sanitize: leaves cc alone", c.showCrowdControl, true)

-- 10. nil safety (a fresh profile before the DB exists)
check("nil config: not locked", L(nil, false), false)
local ok = pcall(S, nil)
check("nil config: sanitize is a no-op", ok, true)

print(failures == 0 and "\nall Unknown player (?) checks passed"
    or string.format("\n%d Unknown player (?) check(s) failed", failures))
if failures > 0 then os.exit(1) end
