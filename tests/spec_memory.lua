-- Unit test for Class/Spec Memory (v1.15).
--
-- The memory is the LAST source the render path consults, so the rules that
-- matter are the ones about what may overwrite what:
--
--   * off by default, and off means nothing is stored at all
--   * a proven spec always beats a guess, and a guess always beats a bare class
--   * a guess never overwrites a proven spec, and never changes the class
--   * a respec (same class, different spec) replaces the old spec
--   * one name shared by two players is never used by name
--   * the store survives a reload and stays under its cap
--
--   usage: lua5.1 tests/spec_memory.lua <addon root>

local root = arg and arg[1] or "OPlates"
local now = 1763000000

function GetRealmName() return "Lordaeron" end
function time() return now end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end

OPlates = { db = { profile = { nameplates = { persistentTalentCache = false } } } }

local function boot()
    local addon = {}
    local chunk = assert(loadfile(root .. "/Common/SpecMemory.lua"))
    chunk("OPlates", addon)
    return addon.SpecMemory
end

local mem = boot()
assert(type(mem) == "table", "SpecMemory is missing")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-52s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-52s %s", label, tostring(got)))
    end
end

local function spec(guid, name)
    local e = mem:Get(guid, name)
    if not e then return "nil" end
    return tostring(e.class) .. "/" .. tostring(e.spec)
end

---------------------------------------------------------------------------
-- off by default
---------------------------------------------------------------------------
mem:Initialize()
check("disabled: nothing loaded", mem:Enabled(), false)
check("disabled: Remember is inert", mem:Remember("0x01", "Jin", "WARLOCK", "AFFLICTION", false), false)
check("disabled: nothing stored", spec("0x01", "Jin"), "nil")

---------------------------------------------------------------------------
-- on
---------------------------------------------------------------------------
OPlates.db.profile.nameplates.persistentTalentCache = true
OPlatesSpecMemory = nil
mem = boot()
mem:Initialize()
check("enabled", mem:Enabled(), true)

-- a bare class
check("class only is stored", mem:Remember("0x01", "Jin", "WARLOCK", nil, nil), true)
check("class only reads back", spec("0x01", "Jin"), "WARLOCK/nil")

-- a guess beats a bare class
check("guess replaces a bare class", mem:Remember("0x01", "Jin", "WARLOCK", "AFFLICTION", true), true)
check("guess reads back", spec("0x01", "Jin"), "WARLOCK/AFFLICTION")

-- a bare class never beats a guess
check("bare class does not beat a guess", mem:Remember("0x01", "Jin", "WARLOCK", nil, nil), false)
check("guess survives", spec("0x01", "Jin"), "WARLOCK/AFFLICTION")

-- a signature beats a guess
check("signature replaces a guess", mem:Remember("0x01", "Jin", "WARLOCK", "DEMONOLOGY", false), true)
check("signature reads back", spec("0x01", "Jin"), "WARLOCK/DEMONOLOGY")

-- a role is stored with a proven spec (an inspected Feral tank is TANK)
check("proven role is stored", mem:Remember("0x01", "Jin", "WARLOCK", "DEMONOLOGY", false, "DAMAGER"), true)
check("proven role reads back", (mem:Get("0x01") or {}).role, "DAMAGER")
check("a guess never stores a role", mem:Remember("0x06", "Gia", "MAGE", "FROST", true, "DAMAGER"), true)
check("guessed role is dropped", (mem:Get("0x06") or {}).role, nil)

-- a guess never beats a signature
check("guess does not beat a signature", mem:Remember("0x01", "Jin", "WARLOCK", "AFFLICTION", true), false)
check("signature survives a later guess", spec("0x01", "Jin"), "WARLOCK/DEMONOLOGY")

-- a respec inside the same class replaces the spec (and carries its role)
check("respec replaces the spec", mem:Remember("0x01", "Jin", "WARLOCK", "DESTRUCTION", false, "DAMAGER"), true)
check("respec reads back", spec("0x01", "Jin"), "WARLOCK/DESTRUCTION")

-- same spec again is not a change
check("same spec is not a change", mem:Remember("0x01", "Jin", "WARLOCK", "DESTRUCTION", false), false)

---------------------------------------------------------------------------
-- class conflicts
---------------------------------------------------------------------------
-- a guess of another class never flips a class
check("class-only is stored for 0x02", mem:Remember("0x02", "Ana", "MAGE", nil, nil), true)
check("guess of another class is ignored", mem:Remember("0x02", "Ana", "WARLOCK", "AFFLICTION", true), false)
check("class held", spec("0x02", "Ana"), "MAGE/nil")

-- a proven talent may correct a bare class
check("signature corrects a bare class", mem:Remember("0x02", "Ana", "PRIEST", "SHADOW", false), true)
check("corrected class held", spec("0x02", "Ana"), "PRIEST/SHADOW")

-- a proven talent may correct a guess of another class
check("guess for 0x03", mem:Remember("0x03", "Bo", "MAGE", "FROST", true), true)
check("signature corrects a guess's class", mem:Remember("0x03", "Bo", "PRIEST", "HOLY", false), true)
check("corrected guess held", spec("0x03", "Bo"), "PRIEST/HOLY")

---------------------------------------------------------------------------
-- the name index
---------------------------------------------------------------------------
check("second Bob is stored", mem:Remember("0x04", "Bob", "WARRIOR", "ARMS", false), true)
check("first Bob is stored", mem:Remember("0x05", "Bob", "MAGE", "FIRE", false), true)
check("an ambiguous name is not used", mem:Get(nil, "Bob"), nil)
check("the GUID still resolves", spec("0x04", nil), "WARRIOR/ARMS")
check("a realm suffix still resolves", spec(nil, "Jin-Lordaeron"), "WARLOCK/DESTRUCTION")

---------------------------------------------------------------------------
-- the class filter on lookup
---------------------------------------------------------------------------
check("lookup filters a wrong class", mem:Get("0x01", nil, "MAGE"), nil)
check("lookup accepts the right class", (mem:Get("0x01", nil, "WARLOCK") or {}).class, "WARLOCK")

---------------------------------------------------------------------------
-- a Feral's role follows his form
---------------------------------------------------------------------------
check("bear role is stored", mem:Remember("0x0B", "Bear", "DRUID", "FERAL", false, "TANK"), true)
check("bear role survives a re-store", mem:Remember("0x0B", "Bear", "DRUID", "FERAL", false, "TANK"), false)
check("a cat clears the stored tank role", mem:Remember("0x0B", "Bear", "DRUID", "FERAL", false, nil), true)
check("bear record still has the spec", spec("0x0B"), "DRUID/FERAL")

---------------------------------------------------------------------------
-- reload: the store must come back
---------------------------------------------------------------------------
-- a class-only record (a player seen but never inspected or cast on)
check("class-only record for 0x08", mem:Remember("0x08", "Alytena", "DEATHKNIGHT", nil, nil), true)
mem:Serialize()
local saved = OPlatesSpecMemory
check("serialised a realm bucket", type(saved.realms.Lordaeron), "table")
check("record is positional on disk", saved.realms.Lordaeron["0x01"][1], "WARLOCK")
check("record keeps the spec", saved.realms.Lordaeron["0x01"][2], "DESTRUCTION")
check("record keeps the name", saved.realms.Lordaeron["0x01"][3], "Jin")
check("proven record has no weak flag", saved.realms.Lordaeron["0x01"][5], nil)
check("proven record keeps its role", saved.realms.Lordaeron["0x01"][6], "DAMAGER")
check("guess keeps its weak flag", saved.realms.Lordaeron["0x05"][5], nil)
check("class-only keeps the class", saved.realms.Lordaeron["0x08"][1], "DEATHKNIGHT")
check("class-only has no spec", saved.realms.Lordaeron["0x08"][2], nil)
check("class-only keeps the name", saved.realms.Lordaeron["0x08"][3], "Alytena")
check("the cleared tank role is not on disk", saved.realms.Lordaeron["0x0B"][6], nil)
check("a healer role is never cleared by a nil", saved.realms.Lordaeron["0x01"][6], "DAMAGER")

mem = boot()
mem:Initialize()
check("reload: record survives", spec("0x01", "Jin"), "WARLOCK/DESTRUCTION")
check("reload: class-only survives", spec("0x08", "Alytena"), "DEATHKNIGHT/nil")
check("reload: count survives", mem:Count() >= 5, true)

---------------------------------------------------------------------------
-- age pruning on load
---------------------------------------------------------------------------
OPlatesSpecMemory.realms.Lordaeron["0x09"] = { "MAGE", "FIRE", "Old", 1000 }
mem = boot()
mem:Initialize()
check("a record older than 60 days is dropped", spec("0x09", "Old"), "nil")

---------------------------------------------------------------------------
-- the cap
---------------------------------------------------------------------------
mem = boot()
mem:Initialize()
for i = 1, 4100 do
    now = now + 1   -- distinct timestamps, so "oldest" is well defined
    mem:Remember(string.format("0x1%05d", i), "P" .. i, "MAGE", "FIRE", false)
end
check("stays under the cap", mem:Count() <= 4000, true)
check("the oldest were dropped", spec("0x1" .. "00001", "P1"), "nil")
check("the newest survive", spec("0x1" .. "04100", "P4100"), "MAGE/FIRE")

---------------------------------------------------------------------------
-- forget / clear
---------------------------------------------------------------------------
check("forget removes one", (function() mem:Forget("0x01"); return spec("0x01", "Jin") end)(), "nil")
mem:Clear()
check("clear empties everything", mem:Count(), 0)
check("clear keeps an empty store, not nil", type(OPlatesSpecMemory), "table")
check("clear writes an empty realm", next(OPlatesSpecMemory.realms.Lordaeron or {}), nil)

---------------------------------------------------------------------------
-- disabling NEVER deletes what was saved
---------------------------------------------------------------------------
OPlates.db.profile.nameplates.persistentTalentCache = false
OPlatesSpecMemory = { schema = 2, realms = { Lordaeron = { ["0x01"] = { "MAGE", "FIRE", "Old", 1763000000 } } } }
mem = boot()
mem:Initialize()
check("disabled load keeps the store", type(OPlatesSpecMemory), "table")
check("disabled load keeps the record", OPlatesSpecMemory.realms.Lordaeron["0x01"][1], "MAGE")
check("disabled: Get is empty", mem:Get("0x01"), nil)
-- a logout while disabled must not rewrite or drop the file
mem:Serialize()
check("disabled Serialize leaves it alone", OPlatesSpecMemory.realms.Lordaeron["0x01"][2], "FIRE")
-- and enabling again brings the same records back
OPlates.db.profile.nameplates.persistentTalentCache = true
mem = boot()
mem:Initialize()
check("re-enabled: record is back", spec("0x01", "Old"), "MAGE/FIRE")

---------------------------------------------------------------------------
-- switching the option DURING a session must not lose either side
---------------------------------------------------------------------------
-- on -> off: what this session learned is still written at logout
OPlates.db.profile.nameplates.persistentTalentCache = true
OPlatesSpecMemory = { schema = 2, realms = { Lordaeron = { ["0x0A"] = { "MAGE", "FIRE", "Kept", 1763000000 } } } }
mem = boot()
mem:Initialize()
check("enabled load sees the old record", spec("0x0A", "Kept"), "MAGE/FIRE")
check("new record while enabled", mem:Remember("0x0B", "New", "PRIEST", "HOLY", false), true)
OPlates.db.profile.nameplates.persistentTalentCache = false   -- switched off mid-session
mem:Serialize()
check("switching off still saves this session", OPlatesSpecMemory.realms.Lordaeron["0x0B"][1], "PRIEST")
check("switching off keeps the old record", OPlatesSpecMemory.realms.Lordaeron["0x0A"][1], "MAGE")

-- off -> on: the file that was loaded is kept, new records are added
OPlates.db.profile.nameplates.persistentTalentCache = false
OPlatesSpecMemory = { schema = 2, realms = { Lordaeron = { ["0x0C"] = { "SHAMAN", "ELEMENTAL", "Old", 1763000000 } } } }
mem = boot()
mem:Initialize()
check("disabled load hides the record", spec("0x0C", "Old"), "nil")
OPlates.db.profile.nameplates.persistentTalentCache = true
check("enabled mid-session sees it", spec("0x0C", "Old"), "SHAMAN/ELEMENTAL")
check("new record mid-session", mem:Remember("0x0D", "Fresh", "ROGUE", "COMBAT", false), true)
mem:Serialize()
check("mid-session enable keeps the old record", OPlatesSpecMemory.realms.Lordaeron["0x0C"][1], "SHAMAN")
check("mid-session enable writes the new one", OPlatesSpecMemory.realms.Lordaeron["0x0D"][1], "ROGUE")

---------------------------------------------------------------------------
-- schema 1 (no role column) still loads
---------------------------------------------------------------------------
OPlatesSpecMemory = { schema = 1, realms = { Lordaeron = { ["0x07"] = { "DRUID", "RESTORATION", "Old", 1763000000 } } } }
mem = boot()
mem:Initialize()
check("schema 1 record loads", spec("0x07", "Old"), "DRUID/RESTORATION")
check("schema 1 has no role", (mem:Get("0x07") or {}).role, nil)

print(failures == 0 and "\nall Class/Spec Memory checks passed" or ("\n" .. failures .. " failure(s)"))
