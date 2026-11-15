-- Unit test for the combat-log keep-alive (v1.14).
--
-- Two things can make the log go quiet in 3.3.5a:
--   * it fills up (the counter reaches the soft cap), or
--   * it stalls while the counter still reads low, which is what a capture
--     showed for the whole first battleground of a session.
--
-- The second case is the reason the silence watchdog exists, so the important
-- assertion here is that an UNREADABLE counter cannot stop the clear.
--
--   usage: lua5.1 tests/combatlog_watch.lua <addon root>

local root = arg and arg[1] or "OPlates"
local addon = {}

local cleared, now = 0, 1000
local entriesValue = 0
local frame

function GetTime() return now end
function CreateFrame()
    frame = { SetScript = function(self, _, fn) self.OnUpdate = fn end }
    return frame
end
function CombatLogClearEntries() cleared = cleared + 1 end
function CombatLogGetNumEntries() return entriesValue end

local chunk = assert(loadfile(root .. "/Common/CombatLog.lua"))
chunk("OPlates", addon)

assert(type(addon.CombatLogWatch) == "function", "CombatLogWatch is missing")
assert(frame and frame.OnUpdate, "the keep-alive frame was never created")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-46s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-46s %s", label, tostring(got)))
    end
end

local function watch(t, lastEvent, lastClear, entries, inPvP)
    return addon.CombatLogWatch(t, lastEvent, lastClear, entries, inPvP)
end

-- 1. the rule ---------------------------------------------------------------
check("full log, open world", watch(100, 99, 0, 500, false), "cap")
check("full log, battleground", watch(100, 99, 0, 500, true), "cap")
check("399 entries, open world", watch(100, 99, 0, 399, false), nil)
check("quiet 5 s in a battleground", watch(100, 95, 0, 100, true), nil)
check("quiet 7 s in a battleground", watch(100, 93, 0, 100, true), nil)
check("quiet 9 s in a battleground", watch(100, 91, 0, 100, true), "silence")
check("quiet 11 s in a battleground", watch(100, 89, 0, 100, true), "silence")
check("quiet 11 s in the open world", watch(100, 89, 0, 100, false), nil)

-- the whole point: a counter that cannot be read must not block the clear
check("counter unreadable, quiet 11 s", watch(100, 89, 0, nil, true), "silence")
check("counter zero, quiet 12 s", watch(100, 88, 0, 0, true), "silence")

-- never seen an event at all
check("no event ever, battleground", watch(100, nil, 0, nil, true), "silence")
check("no event ever, open world", watch(100, nil, 0, nil, false), nil)

-- cooldown after a clear
check("quiet 40 s, cleared 10 s ago", watch(100, 60, 90, 100, true), nil)
check("quiet 40 s, cleared 31 s ago", watch(100, 60, 69, 100, true), "silence")
check("quiet 40 s, never cleared", watch(100, 60, 0, 100, true), "silence")

-- 2. the frame actually clears ---------------------------------------------
local function tick(seconds)
    now = now + seconds
    frame.OnUpdate(frame, seconds)
end

addon.IsInPvPInstance = function() return false end
addon._cleuLastAt = nil
entriesValue = 0
cleared = 0

tick(6)
check("open world, silent, nothing cleared", cleared, 0)

addon.IsInPvPInstance = function() return true end
addon._cleuLastAt = now
tick(6)
check("battleground but events flowing", cleared, 0)

addon._cleuLastAt = now - 20
tick(6)
check("battleground, silent 20 s, cleared once", cleared, 1)

tick(6)
check("still silent, cooldown holds it", cleared, 1)

tick(30)
check("cooldown expired, cleared again", cleared, 2)

entriesValue = 500
addon._cleuLastAt = now
addon.IsInPvPInstance = function() return false end
tick(6)
check("open world but the log is full", cleared, 3)

-- a near-full clear must NOT delay the stall watchdog. The v1.14 capture showed
-- a stall starting right after a cap clear, and the shared timestamp kept the
-- watchdog blind for the whole 30 s cooldown.
entriesValue = 0
tick(40)                                   -- let the last silence cooldown expire
check("quiet but open world, still no clear", cleared, 3)

entriesValue = 500
addon._cleuLastAt = now
addon.IsInPvPInstance = function() return true end
tick(6)
check("battleground, log full, cap clear", cleared, 4)

entriesValue = 0
addon._cleuLastAt = now - 11
tick(6)
check("stall right after a cap clear", cleared, 5)

print(failures == 0 and "\nall combat-log checks passed" or ("\n" .. failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
