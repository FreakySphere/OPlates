local _, addon = ...

---------------------------------------------------------------------------
-- Class/Spec Memory
--
-- What a player was, kept across sessions: class, spec, role, name and when he
-- was last seen, plus whether the spec was proven or only guessed.
--
-- It is the LAST source the render path consults. Everything live outranks it:
-- an inspection, a signature talent, a guess, a class proof from a single spell.
-- A stored entry is therefore a baseline that any new detection overwrites on
-- the spot, which is what makes a respec visible within seconds instead of
-- after a reload.
--
-- Off by default. When off nothing is read and nothing is written, but what is
-- already on disk is left alone: switching the option off is not a delete. Only
-- the "Delete all saved player information" button (Memory:Reset) throws the
-- records away.
--
-- Why a separate SavedVariable and not OPlatesTalentDB: that one is the talent
-- scanner's inspection cache and its records are restored straight into
-- cacheByGUID, which is treated as a real read everywhere. A guessed spec must
-- never enter that cache, because a guess there would look like proof and would
-- block every later combat-log detection for that player.
--
-- 3.3.5a writes every SavedVariable of one addon into one file, so this global
-- still lives in WTF/.../SavedVariables/OPlates.lua. Keeping it a SEPARATE
-- top-level global is what matters: a profile switch, a profile reset or a
-- corrupted option table can never touch it, and this table is never walked by
-- AceDB.
--
-- Shape on disk, positional to keep the file small:
--   OPlatesSpecMemory = {
--       schema = 2,
--       realms = { ["Lordaeron"] = {
--           ["0x0600000000ABCDEF"] = { "WARLOCK", "DEMONOLOGY", "Jin", 1763000000, nil, "DAMAGER" },
--       } },
--   }
-- [5] is `true` for a guessed spec. [6] is the role when one was proven
-- (an inspected Feral tank is TANK even though FERAL alone means DAMAGER).
---------------------------------------------------------------------------

local SCHEMA = 2
-- 4000 records is roughly 320 KB on disk. A player who has met that many
-- distinct people has been playing for years, and the oldest are dropped first.
local MAX_RECORDS = 4000
local KEEP_FRACTION = 0.9
local RETAIN_AGE = 60 * 24 * 60 * 60   -- 60 days

-- tiers, same order as the live stores: a class alone is the weakest thing we
-- can know, a guessed spec beats it, a proven spec beats everything.
local RANK_CLASS, RANK_GUESS, RANK_PROVEN = 1, 2, 3

local memory, byName = {}, {}
local count = 0
local realm = "unknown"
local loaded = false
-- true once the option was ON at any point this session. Serialize uses it, not
-- the CURRENT option value: switching the memory off must never throw away what
-- this session learned, and a login with it off must never rewrite the file.
local loadedEnabled = false

local Memory = {}
addon.SpecMemory = Memory

local function Enabled()
    return OPlates ~= nil and OPlates.db ~= nil and OPlates.db.profile ~= nil
        and OPlates.db.profile.nameplates ~= nil
        and OPlates.db.profile.nameplates.persistentTalentCache == true
end
Memory.Enabled = Enabled

local function ShortName(name)
    if type(name) ~= "string" then return nil end
    return name:match("^[^%-]+") or name
end

local function RankOf(entry)
    if not entry then return 0 end
    if not entry.spec then return RANK_CLASS end
    if entry.weak then return RANK_GUESS end
    return RANK_PROVEN
end

-- only the three roles the client knows; anything else is treated as unknown.
local function ValidRole(role)
    if role == "HEALER" or role == "TANK" or role == "DAMAGER" then return role end
end

local function Index(entry, guid)
    local short = ShortName(entry.name)
    if not short then return end
    local prev = byName[short]
    if prev == false or (prev and prev.guid ~= guid) then
        byName[short] = false      -- one name, two players: never used by name
    else
        byName[short] = entry
        entry.guid = guid          -- one field, set only when the index needs it
    end
end

local function Drop(guid)
    local entry = memory[guid]
    if not entry then return end
    memory[guid] = nil
    count = count - 1
    local short = ShortName(entry.name)
    if short and byName[short] == entry then byName[short] = nil end
end

-- Oldest first, down to KEEP_FRACTION of the cap. Called only when the cap is
-- passed, so the sort is rare and never lands on a normal render.
local function Prune()
    if count <= MAX_RECORDS then return 0 end
    local keys = {}
    for guid in pairs(memory) do keys[#keys + 1] = guid end
    table.sort(keys, function(a, b) return (memory[a].at or 0) < (memory[b].at or 0) end)
    local target = math.floor(MAX_RECORDS * KEEP_FRACTION)
    local removed = 0
    for i = 1, #keys do
        if count <= target then break end
        Drop(keys[i])
        removed = removed + 1
    end
    return removed
end

function Memory:Initialize()
    if loaded then return end
    loaded = true
    realm = GetRealmName and GetRealmName() or "unknown"
    local store = OPlatesSpecMemory
    -- A corrupt/absent store is only replaced while the option is on. With the
    -- option off the global is left exactly as the client loaded it.
    if type(store) ~= "table" or (store.schema ~= SCHEMA and store.schema ~= 1)
        or type(store.realms) ~= "table" then
        if not Enabled() then
            if addon._debugEnabled then
                addon:DebugLog("SPECMEM", "disabled, nothing loaded and nothing written")
            end
            return
        end
        store = { schema = SCHEMA, realms = {} }
        OPlatesSpecMemory = store
    end
    store.schema = SCHEMA
    store.realms[realm] = store.realms[realm] or {}
    local saved = store.realms[realm]
    local now = time and time() or 0
    for guid, raw in pairs(saved) do
        if type(guid) == "string" and type(raw) == "table" and type(raw[1]) == "string" then
            local at = tonumber(raw[4]) or 0
            if now > 0 and at > 0 and now - at > RETAIN_AGE then
                saved[guid] = nil
            else
                -- a corrupted field must never become a bogus spec/name
                local spec = type(raw[2]) == "string" and raw[2] or nil
                local nm = type(raw[3]) == "string" and raw[3] or nil
                memory[guid] = { class = raw[1], spec = spec,
                    name = nm, at = at, weak = (raw[5] == true) or nil,
                    role = ValidRole(raw[6]) }
                count = count + 1
            end
        else
            saved[guid] = nil
        end
    end
    for guid, entry in pairs(memory) do Index(entry, guid) end
    -- The records are parsed even while the option is OFF: they are not used
    -- (Get/Remember refuse) but they must be in hand, or enabling the option
    -- without a reload and then logging out would rewrite the file with only
    -- this session's records.
    loadedEnabled = Enabled()
    if addon._debugEnabled then
        addon:DebugLog("SPECMEM", "loaded %d record(s) for realm %s (enabled=%s)",
            count, tostring(realm), tostring(loadedEnabled))
    end
end

-- Rebuild the SavedVariable from the live map. Runs on logout and reload only:
-- the client writes SavedVariables to disk at that point anyway, so there is no
-- reason to spend time on it during play.
--
-- It writes whenever the option was ON at any point this session, even if it is
-- OFF right now: switching the memory off stops using and recording it, it does
-- not delete what the session already learned. A session that never had it on
-- (loadedEnabled false) leaves the file untouched.
function Memory:Serialize()
    if not loaded or not loadedEnabled then return end
    local store = OPlatesSpecMemory
    if type(store) ~= "table" or store.schema ~= SCHEMA then
        store = { schema = SCHEMA, realms = {} }
        OPlatesSpecMemory = store
    end
    store.realms = store.realms or {}
    local saved = {}
    for guid, entry in pairs(memory) do
        saved[guid] = { entry.class, entry.spec, entry.name, entry.at, entry.weak or nil, entry.role }
    end
    store.realms[realm] = saved
end

-- Anything the addon learns about a player, offered to the memory. Returns true
-- when the stored record changed, so the caller can log it.
function Memory:Remember(guid, name, class, spec, weak, role)
    if not loaded or not Enabled() then return false end
    -- enabled mid-session without a reload: the file was already parsed at
    -- Initialize, so this only flips the "write it back at logout" flag.
    loadedEnabled = true
    if type(guid) ~= "string" or type(class) ~= "string" then return false end
    if spec ~= nil and type(spec) ~= "string" then spec = nil end
    role = ValidRole(role)
    local rank = spec and (weak and RANK_GUESS or RANK_PROVEN) or RANK_CLASS
    local entry = memory[guid]
    local now = time and time() or 0
    if entry then
        -- A player does not change class. The stored class may only be
        -- corrected by a proven talent, and only when what is stored was not
        -- already proven: two different proven signatures for one GUID means a
        -- shared spell name, not a class change.
        if entry.class ~= class then
            if rank < RANK_PROVEN or RankOf(entry) >= RANK_PROVEN then return false end
        end
        local had = RankOf(entry)
        if rank < had then return false end
        if rank == had and entry.class == class and entry.spec == spec then
            entry.at = now
            -- re-index only when the stored name actually changed: this branch
            -- runs for every visible plate on every refresh.
            if name and entry.name ~= name then entry.name = name; Index(entry, guid) end
            -- A proven role may still arrive after the spec (inspection), and a
            -- Feral's role follows his FORM: a bear that respecced to cat must
            -- lose the stored TANK, or he comes back as a tank after a reload.
            -- For every other spec a nil role means "unknown", never "clear".
            if rank == RANK_PROVEN and entry.role ~= role
                and (role or (entry.class == "DRUID" and entry.spec == "FERAL")) then
                entry.role = role
                if addon._debugEnabled then
                    addon:DebugLog("SPECMEM", "role %s %s/%s -> %s",
                        tostring(entry.name), tostring(entry.class), tostring(entry.spec), tostring(role))
                end
                return true
            end
            return false
        end
    end
    if not entry then
        entry = {}
        memory[guid] = entry
        count = count + 1
    end
    entry.class, entry.spec, entry.weak = class, spec, (spec and weak) or nil
    entry.name = name or entry.name
    entry.at = now
    -- a guessed spec never stores a role: only a proven one is worth keeping.
    if rank == RANK_PROVEN then entry.role = role else entry.role = nil end
    Index(entry, guid)
    Prune()
    if addon._debugEnabled then
        addon:DebugLog("SPECMEM", "store %s %s/%s weak=%s role=%s",
            tostring(entry.name), tostring(entry.class), tostring(entry.spec or "-"),
            tostring(entry.weak == true), tostring(entry.role))
    end
    return true
end

-- The remembered record for a plate, or nil. A known class filters it, so a
-- stored warrior can never paint a mage's plate. With the option off nothing is
-- read at all: the file is parsed for preservation, never used.
function Memory:Get(guid, name, classFile)
    if not loaded or not Enabled() then return nil end
    local entry
    if guid then entry = memory[guid] end
    if not entry and name then
        local short = ShortName(name)
        if short then
            local hit = byName[short]
            if hit and hit ~= false then entry = hit end
        end
    end
    if not entry then return nil end
    if classFile and entry.class ~= classFile then return nil end
    return entry
end

function Memory:Forget(guid)
    if not loaded then return end
    if guid then Drop(guid) end
end

-- Empty the live map AND the SavedVariable. This is the only path that throws
-- stored players away; the option toggle and a disabled login never call it.
function Memory:Reset()
    memory, byName, count = {}, {}, 0
    local store = { schema = SCHEMA, realms = {} }
    store.realms[realm] = {}
    OPlatesSpecMemory = store
end

-- kept for callers from v1.15; Clear now means the same as Reset, not "nil the
-- global", because nilling it deleted the file on the next logout.
function Memory:Clear()
    Memory:Reset()
end

function Memory:Count()
    return count
end

-- how many records know the class but not the spec (the [STATS] line reports
-- it: a healthy session fills these in as players cast).
function Memory:CountClassOnly()
    local n = 0
    for _, e in pairs(memory) do
        if not e.spec then n = n + 1 end
    end
    return n
end

function Memory:Realm()
    return realm
end

---------------------------------------------------------------------------
-- logout / reload
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function()
    Memory:Serialize()
end)
