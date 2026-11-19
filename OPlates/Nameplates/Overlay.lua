local _, addon = ...

local LibNameplates = LibStub("LibNameplates-1.0", true)

-- uptime for the [STATS] line ("up=...s"): the moment this file loaded.
addon._sessionStartedAt = addon._sessionStartedAt or (GetTime and GetTime() or 0)

local ICON_SIZE = 40
local plates = {}
local cacheByGUID = {}
local cacheByName = {}
local flagCarrierGUIDs = {}
local flagIconByGUID = {}
-- one carrier per flag (a new carrier clears the old one) and a
-- render-only name map for GUID-less plates (stock client). Never binds a GUID.
local flagCarrierByFaction = {}
local flagNameByGUID = {}
local flagByName = {}
local function ShortName(name) return name and (name:match("^([^%-]+)") or name) end
local function ClearFlagCarrier(guid)
    local faction = guid and flagCarrierGUIDs[guid]
    if not faction then return false end
    flagCarrierGUIDs[guid], flagIconByGUID[guid] = nil, nil
    if flagCarrierByFaction[faction] == guid then flagCarrierByFaction[faction] = nil end
    local n = flagNameByGUID[guid]
    if n and flagByName[n] and flagByName[n].guid == guid then flagByName[n] = nil end
    flagNameByGUID[guid] = nil
    return true
end
local function SetFlagCarrier(guid, name, faction, icon)
    local old = flagCarrierByFaction[faction]
    if old and old ~= guid then ClearFlagCarrier(old) end
    if flagCarrierGUIDs[guid] and flagCarrierGUIDs[guid] ~= faction then ClearFlagCarrier(guid) end
    flagCarrierGUIDs[guid] = faction
    flagIconByGUID[guid] = icon or addon.FLAG_ICON_BY_FACTION[faction]
    flagCarrierByFaction[faction] = guid
    local short = ShortName(name)
    if short then
        flagNameByGUID[guid] = short
        flagByName[short] = { guid = guid, faction = faction }
    end
end
local function FlagForPlate(guid, name)
    if guid then return flagCarrierGUIDs[guid] end
    local e = name and flagByName[ShortName(name)]
    return e and e.faction
end
local FLAG_NAMES = { ["Alliance Flag"] = "Alliance", ["Silverwing Flag"] = "Alliance",
    ["Horde Flag"] = "Horde", ["Warsong Flag"] = "Horde", ["Netherstorm Flag"] = "Neutral" }
local ccByGUID = {}
-- every CC on a player, by spell ID (ccByGUID is the one drawn, the top).
local ccStackByGUID, ccStackCount = {}, 0
-- a CC known only from the combat log (never read from a unit) is
-- dropped this long after it started or was refreshed. No player CC lasts
-- longer in PvP (10 s cap; the longest base duration in CrowdControl.lua), so
-- only a stale icon (its SPELL_AURA_REMOVED missed out of combat-log range on
-- the stock client) is removed after CC_STALE_AFTER seconds.
local CC_STALE_AFTER = 10
local specByGUID = {}
local auraByGUID = {}
-- stock-client CC estimates. DR state per GUID + DR category, and the
-- longest real duration read from an aura (spells without a base duration).
local drByGUID, drCount = {}, 0
local learnedDuration, learnedCount = {}, 0
-- render-only player name -> set of GUIDs that have used it, used ONLY to look
-- up the CC/aura store for a GUID-less player plate (stock client after a
-- recycle). Never binds a GUID, never touches identity/spec/inspect, never used
-- for pets. A name can legitimately belong to several players on cross-realm
-- servers, so it maps to a set and AuraKeyForPlate narrows it by class; a name
-- that stays ambiguous is left blank instead of guessing.
local auraGUIDsByName, auraNameByGUID, auraClassByGUID, auraNameCount = {}, {}, {}, 0
-- next allowed exact upgrade read per GUID (estimate on top).
local upgradeAt, upgradeCount = {}, 0
local RefreshAll
local UpdatePlate
local refreshInProgress = false
local function D(tag, msg, ...)
    if addon._debugEnabled then addon:DebugLog(tag, msg, ...) end
end

---------------------------------------------------------------------------
-- [STATS] window
--
-- One summary line every 60 s while debug logging is on. Every counter is
-- bumped on the real code path (an icon actually changing, a CC/aura/flag being
-- recorded, a class/spec store being written) and reset when the line prints,
-- so a capture reads as "what happened in the last minute" instead of thousands
-- of lines. Nothing here runs when debug logging is off.
---------------------------------------------------------------------------
local stats = {
    every = 60, at = 0,
    icons = { friendly = {}, enemy = {} },
    seenF = {}, seenE = {},
    seenCountF = 0, seenCountE = 0,
    cleu = 0, cc = 0, ccNew = 0, aura = 0, auraNew = 0, flags = 0,
    forms = { BEAR = 0, CAT = 0 },
    -- hybrid bookkeeping: kept = a shallower off-tree talent was refused,
    -- moved = a deeper (still sub-40-point) talent named the main tree
    hybridKept = 0, hybridMoved = 0,
}
function stats.Bump(tbl, key)
    key = key or "none"
    tbl[key] = (tbl[key] or 0) + 1
end
function stats.Seen(side, guid)
    if not guid then return end
    if side == "enemy" then
        if not stats.seenE[guid] then
            stats.seenE[guid] = true
            stats.seenCountE = stats.seenCountE + 1
        end
    elseif not stats.seenF[guid] then
        stats.seenF[guid] = true
        stats.seenCountF = stats.seenCountF + 1
    end
end

-- Compact logging - track last log time per GUID+tag to reduce spam
local _lastLog = {}
local function DCompact(tag, guid, msg, ...)
    if not addon._debugEnabled then return end
    local key = tag .. ":" .. tostring(guid)
    local now = GetTime()
    local last = _lastLog[key] or 0
    if now - last < 0.5 then return end  -- Throttle to max 2 logs/sec per GUID+tag
    _lastLog[key] = now
    addon:DebugLog(tag, msg, ...)
end


-- spec/role detection hibernates when no option uses it.
-- Friendly: spec, healer and tank icons all off (class icon alone needs no
-- inspection). Enemy: enemy spec, healer and tank icons all off. Healer-in-CC
-- keeps group inspection alive because it needs the members' specs.
-- a disabled side, CLASS/PET/FLAG and the aura-only modes never need
-- spec/role; HEALER/TANK/CLASS_SPEC always do; "All" follows the icon toggles.
local AURA_MODES = { CC_ONLY = true, BUFFS_ONLY = true, DEBUFFS_ONLY = true }
local SPEC_MODES = { HEALER = true, TANK = true, CLASS_SPEC = true }
addon.NameplateAuraModes = AURA_MODES

local function CurrentDisplayMode(cfg, enemy)
    return enemy and cfg.enemyDisplayMode or cfg.friendlyDisplayMode
end

-- "Enable friendly icons" / "Enable enemy icons".
local function SideEnabled(cfg, enemy)
    if enemy then return cfg.enemyIconsEnabled ~= false end
    return cfg.classIconsEnabled and true or false
end
addon.NameplateSideEnabled = SideEnabled

-- per-side Class Filters / Spec Filters. Only disabled entries are
-- saved, so an empty filter returns at once. A filter hides only its own icon
-- type (class icon / spec icon); role, pet, flag, CC and aura icons ignore it.
local IconFilter = {}
function IconFilter.ClassHidden(cfg, enemy, classFile)
    local t = enemy and cfg.enemyClassFilter or (not enemy and cfg.classFilter)
    if not classFile or type(t) ~= "table" or not next(t) then return false end
    return t[classFile] == true
end
function IconFilter.SpecHidden(cfg, enemy, classFile, spec)
    local t = enemy and cfg.enemySpecFilter or (not enemy and cfg.specFilter)
    if not classFile or not spec or type(t) ~= "table" or not next(t) then return false end
    return t[classFile .. ":" .. spec] == true
end
addon.NameplateIconFilter = IconFilter

-- per-side "Circular aura replacement" (enemy keys are independent).
-- Returns showCC, auraOn, buffs, debuffs; options locked by the display mode
-- are ignored here (their saved values are kept).
local function AuraSettings(cfg, enemy)
    local cc, aura, buffs, debuffs
    if enemy then
        cc, aura = cfg.enemyShowCrowdControl ~= false, cfg.enemyAuraEnabled ~= false
        buffs, debuffs = cfg.enemyShowBuffs == true, cfg.enemyShowDebuffs == true
    else
        cc, aura = cfg.showCrowdControl and true or false, cfg.auraEnabled and true or false
        buffs, debuffs = cfg.showBuffs and true or false, cfg.showDebuffs and true or false
    end
    local mode = CurrentDisplayMode(cfg, enemy)
    if mode == "CC_ONLY" then return true, false, false, false end
    -- Buffs only / Debuffs only lock their "Allow" toggle on.
    if mode == "BUFFS_ONLY" then return cc, true, true, false end
    if mode == "DEBUFFS_ONLY" then return cc, true, false, true end
    return cc, aura, aura and buffs, aura and debuffs
end
addon.NameplateAuraSettings = AuraSettings

local function FriendlyNeedsSpec(cfg)
    if not SideEnabled(cfg, false) then return false end
    local mode = cfg.friendlyDisplayMode or "ALL"
    if mode == "ALL" then
        return cfg.showSpec ~= false or cfg.useHealerIcon ~= false or cfg.useTankIcon ~= false
    end
    -- "Class icons only" needs the store too: a class read from a spell or from
    -- an inspection is what that mode draws.
    return SPEC_MODES[mode] == true or mode == "CLASS"
end

local function EnemyNeedsSpec(cfg)
    if not SideEnabled(cfg, true) then return false end
    local mode = cfg.enemyDisplayMode or "ALL"
    if mode == "ALL" then
        -- "Class icon" counts: a signature spell is a class source too, and on a
        -- stock client it is often the ONLY one for a hostile plate with no
        -- unit token and no bar colour. Without it, turning spec/healer/tank
        -- off silently stopped classes from being learned as well.
        return cfg.enemyShowSpec == true or cfg.enemyHealerIcon == true or cfg.enemyTankIcon == true
            or cfg.enemyShowClass == true
    end
    -- Same for enemies: on a stock client the combat log is the only class
    -- source for a hostile plate without a unit token, so "Class icons only"
    -- must keep the store running even though it never draws a spec.
    return SPEC_MODES[mode] == true or mode == "CLASS"
end

local function GroupNeedsSpec()
    local misc = OPlates and OPlates.db and OPlates.db.profile.misc
    return misc and misc.healerInCrowdControl == true or false
end

addon.FriendlyNeedsSpec = FriendlyNeedsSpec
addon.EnemyNeedsSpec = EnemyNeedsSpec

local function SpecDetectionNeeded(unit)
    local cfg = OPlates and OPlates.db and OPlates.db.profile.nameplates
    if not cfg then return true end
    local friendly = FriendlyNeedsSpec(cfg)
    local enemy = EnemyNeedsSpec(cfg)
    if friendly and enemy then return true end
    local isGroup = unit and (unit:match("^party%d+$") or unit:match("^raid%d+$")) ~= nil
    if isGroup and GroupNeedsSpec() then return true end
    if not friendly and not enemy then return false end
    if not unit then return true end
    if UnitExists and not UnitExists(unit) then return false end
    if isGroup then return friendly end
    if unit:match("^arena%d+$") then return enemy end
    if UnitIsFriend("player", unit) then return friendly end
    return enemy
end
addon.SpecDetectionNeeded = SpecDetectionNeeded

local function QueueSpec(unit, force)
    if not SpecDetectionNeeded(unit) then return end
    if addon.TalentScanner then
        local groupOnly = unit and (unit:match("^party%d+$") or unit:match("^raid%d+$")) ~= nil
        addon.TalentScanner:Queue(unit, force, groupOnly)
    end
end

local deferredRefresh = false
function addon:RequestRefreshNameplateOverlays()
    if addon._debugEnabled then D("OVERLAY", "RequestRefreshNameplateOverlays deferred=%s", tostring(deferredRefresh)) end
    if deferredRefresh then return end
    deferredRefresh = true
    local frame = self._refreshFrame
    if not frame then
        frame = CreateFrame("Frame")
        self._refreshFrame = frame
    end
    frame:SetScript("OnUpdate", function(f)
        f:SetScript("OnUpdate", nil)
        deferredRefresh = false
        if addon._debugEnabled then D("OVERLAY", "FULL refresh executing") end
        RefreshAll()
    end)
end

-- Targeted refresh used when a single player's talent/spec result becomes available.
-- This deliberately avoids a full nameplate refresh and therefore cannot recreate the
-- refresh/inspect recursion.
function addon:RequestRefreshNameplateOverlayGUID(guid)
    if not guid then return end
    if addon._debugEnabled then D("OVERLAY", "TARGETED refresh requested guid=%s", tostring(guid)) end
    local pending = self._pendingOverlayGUIDs
    if not pending then
        pending = {}
        self._pendingOverlayGUIDs = pending
    end
    pending[guid] = true

    if self._targetedRefreshFrame then return end
    local frame = CreateFrame("Frame")
    self._targetedRefreshFrame = frame
    frame._elapsed = 0
    frame._attempt = 0
    frame:SetScript("OnUpdate", function(f, elapsed)
        f._elapsed = f._elapsed + elapsed
        -- Extended from 0.03s to 0.1s per attempt, 50 attempts = 5 seconds
        -- This gives LibNameplates time to GUID-associate plates after sweep
        if f._elapsed < 0.1 then return end
        f._elapsed = 0
        f._attempt = f._attempt + 1
        local queue = self._pendingOverlayGUIDs or {}
        self._pendingOverlayGUIDs = {}
        local unmatched = {}
        for targetGUID in pairs(queue) do
            if addon._debugEnabled then DCompact("OVERLAY", targetGUID, "TARGETED refresh executing guid=%s attempt=%d", tostring(targetGUID), f._attempt) end
            local targetData = addon.TalentScanner and addon.TalentScanner:Get(targetGUID)
            local targetName = targetData and targetData.name
            local matched = false
            for plate, ov in pairs(plates) do
                if plate and ov then
                    local plateGUID = LibNameplates and LibNameplates.GetGUID and LibNameplates:GetGUID(plate)
                    local plateName = LibNameplates and LibNameplates.GetName and LibNameplates:GetName(plate)
                    -- Only match by GUID - never by name alone to prevent cross-contamination
                    if plate:IsShown() and (plateGUID == targetGUID or (not plateGUID and ov._guid == targetGUID)) then
                        UpdatePlate(plate)
                        matched = true
                    end
                end
            end
            if not matched then unmatched[targetGUID] = true end
        end
        -- 20 attempts (2 s) is enough for LibNameplates to associate a plate
        -- that is actually on screen. The old 50 (5 s) kept scanning every
        -- visible plate twice a second for a player who had already left range,
        -- which is what the Orgrimmar capture showed: 46 attempts and then a
        -- full refresh for nobody.
        if next(unmatched) and f._attempt < 20 then
            for targetGUID in pairs(unmatched) do self._pendingOverlayGUIDs[targetGUID] = true end
            return
        end
        if next(unmatched) then
            if addon._debugEnabled then D("OVERLAY", "TARGETED refresh fallback full refresh unmatched=%s after %d attempts", tostring(next(unmatched)), f._attempt) end
            RefreshAll()
        end
        f:SetScript("OnUpdate", nil)
        self._targetedRefreshFrame = nil
    end)
end

local function QueueKnownPlayerUnits()
    for _, unit in ipairs({"target", "focus", "mouseover"}) do QueueSpec(unit) end
    for i = 1, 4 do QueueSpec("party"..i) end
    for i = 1, 40 do QueueSpec("raid"..i) end
    for i = 1, 5 do QueueSpec("arena"..i) end
end

local function DB()
    return OPlates.db.profile.nameplates
end

-- 3.3.5a player GUIDs have a zero high word (creatures 0xF13, pets 0xF14).
-- The high word is a server-side detail though: Warmane hands out 0x06/0x07 for
-- friendly players and 0x0A for hostile ones. The client itself knows which
-- GUIDs are players, so ask it once per GUID and remember the answer. A "no" is
-- only remembered briefly, because an enemy may not be cached yet the first time
-- we see him.
local playerGUIDMemo, playerGUIDCount = {}, 0
local PLAYER_GUID_RETRY = 30

local function IsPlayerGUID(guid)
    if type(guid) ~= "string" then return false end
    if guid:sub(1, 6) == "0x0000" then return true end
    local memo = playerGUIDMemo[guid]
    if memo then
        if memo.player then return true end
        if memo.retryAt and GetTime() < memo.retryAt then return false end
    end
    local isPlayer = false
    if GetPlayerInfoByGUID then
        local ok, classFile = pcall(GetPlayerInfoByGUID, guid)
        isPlayer = ok and type(classFile) == "string" and classFile ~= ""
    end
    playerGUIDCount = playerGUIDCount + 1
    if playerGUIDCount > 2000 then wipe(playerGUIDMemo); playerGUIDCount = 1 end
    playerGUIDMemo[guid] = isPlayer and { player = true } or { retryAt = GetTime() + PLAYER_GUID_RETRY }
    return isPlayer
end

-- The high word is a server-side detail, not a constant: stock cores hand out
-- 0x0000, Warmane uses 0x06/0x07 for friendly players and 0x0A for hostile
-- ones. Whenever the combat log is in hand its player flag is the authority,
-- so nothing here has to guess the layout.
local COMBATLOG_PLAYER = 0x400
local function IsPlayerFlags(flags)
    return addon.HasFlag(flags, COMBATLOG_PLAYER)
end

-- only real player pets (hunter/warlock/DK/frost mage) use 0xF14;
-- totems, guardians, vehicles and NPC summons do not.
local function IsPetGUID(guid)
    return type(guid) == "string" and guid:sub(3, 5):upper() == "F14"
end

-- Vehicles (Strand of the Ancients cannons, demolishers, siege engines) are
-- 0xF15. An empty cannon still has a nameplate and a creature class, so it can
-- look like a pet to the generic creature paths. It belongs to nobody and must
-- never be drawn as one.
local function IsVehicleGUID(guid)
    return type(guid) == "string" and guid:sub(3, 5):upper() == "F15"
end

-- The old "pet$" pattern matched only "pet", never partypetN/raidpetN/
-- arenapetN, and a hovered/targeted pet ("mouseover"/"target") was hidden.
local function IsPetUnit(unit)
    if type(unit) ~= "string" or not UnitExists(unit) or UnitIsPlayer(unit) then return false end
    local guid = UnitGUID(unit)
    if IsVehicleGUID(guid) then return false end
    if IsPetGUID(guid) then return true end
    -- A vehicle occupies the "pet" token while its owner rides it.
    return unit:find("pet%d*$") ~= nil and not IsVehicleGUID(guid)
end

local function IsPlayerOrPetUnit(unit)
    if not unit or not UnitExists(unit) then return false end
    return UnitIsPlayer(unit) or IsPetUnit(unit)
end

-- group members' talent spells, used only by Healer-in-CC when
-- neither inspection nor group communication knows the member's spec yet.
local groupSpecByGUID, groupSpecCount = {}, 0

-- enemy specs: spec-only talent spells seen in the combat log. Kept
-- here (never in the inspection cache, so inspection is never blocked) and
-- used only to draw hostile plates; inspection/group data always wins.
local enemySpecByGUID, enemySpecByName, enemySpecCount = {}, {}, 0
local friendlySpecByGUID, friendlySpecByName, friendlySpecCount = {}, {}, 0
-- Render-only merged view for a friendly plate whose class and spec come from
-- different sources. It must be a STABLE table: FriendlyIconState keeps the
-- class -> spec deadline on the data it is handed, so a fresh table per render
-- re-armed that deadline forever. That was the v1.15 bug where a friendly
-- outsider showed his class and then never his spec.
local friendlyViewByKey, friendlyViewCount = {}, 0
local signatureByName, weakByName
-- Every combat-log subevent that can name a player. Two families behave
-- differently, and only one of them is always trustworthy:
--
--   * ACTOR events name the unit that PERFORMED the action: a cast that starts,
--     fails or is interrupted, a damage tick, a miss, a drain, an interrupt, a
--     dispel, a summon. The source is the actor, always.
--   * EFFECT events name the unit that OWNS the effect. For an AURA that is
--     the caster when it lands on another unit (a debuff on an enemy, a buff on
--     a party member: src ~= dst), and the recipient himself when it is a
--     self-cast, a talent proc, or a party aura the client re-sends on its
--     recipient (src == dst). A self-cast and a received buff are
--     indistinguishable there, so src == dst identifies nobody.
--
--     A HEAL is different again and is not used at all: the client reports the
--     unit the health came FROM, not the caster. Field log, 12 times in one
--     session: "SPELL_HEAL spell=Haunt src=<a hunter> dst=<the warlock>" - it
--     named a hunter, a warrior, a shaman and a paladin as the warlock who cast
--     Haunt. The cast of a heal already names the healer, so nothing is lost.
--
-- In one sentence: an event may only identify its source when the source is the
-- unit that performed the action, never when it is the unit that owns or
-- received the result.
local SIGNATURE_EVENTS = {
    -- actor events
    SPELL_CAST_SUCCESS = true, SPELL_CAST_START = true, SPELL_CAST_FAILED = true,
    SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, SPELL_MISSED = true,
    SPELL_DRAIN = true, SPELL_LEECH = true, SPELL_INTERRUPT = true,
    SPELL_DISPEL = true, SPELL_STOLEN = true, SPELL_EXTRA_ATTACKS = true,
    SPELL_SUMMON = true, SPELL_CREATE = true,
    -- aura events, trusted only when source ~= destination
    SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REFRESH = true,
}

-- Events that can name the REFLECTOR of somebody else's spell. A warrior's
-- Spell Reflection is logged as damage FROM the warrior, with the reflected
-- spell's name: two warriors in one capture "cast" Conflagrate and Chaos Bolt
-- that way. Damage may still fill a class or a spec for a player we know
-- nothing about, but it must never CHANGE a class we already proved - only a
-- cast, an aura on another unit, a summon or a create can do that.
local REFLECTABLE = {
    SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, SPELL_MISSED = true,
    SPELL_DRAIN = true, SPELL_LEECH = true, SPELL_EXTRA_ATTACKS = true,
}

-- Built once, on the first hostile player event, by localized spell name.
local function Signatures()
    if signatureByName then return signatureByName end
    signatureByName = {}
    for id, s in pairs(addon.SPEC_SIGNATURES or {}) do
        local spellName = GetSpellInfo(id)
        local icons = addon.SPEC_TREE_ICONS[s[1]]
        -- a BEAR/CAT signature names the form: use the form texture, never the
        -- spec tree icon (the Feral tree icon is the cat, not the bear).
        local texture = addon.FeralTexture(s[4]) or (icons and icons[s[2]])
        if spellName and texture then
            local old = signatureByName[spellName]
            if old == nil then
                signatureByName[spellName] = { class = s[1], spec = s[2], strength = s[3], texture = texture,
                    kind = s[4],
                    role = addon.SPEC_ROLES[s[1]] and addon.SPEC_ROLES[s[1]][s[2]] }
            elseif old and (old.class ~= s[1] or old.spec ~= s[2]) then
                signatureByName[spellName] = false -- one name, two specs: never trusted
            end
        end
    end
    -- Entries matched by spell ID, for talents whose localized name the client
    -- also reports for another class. Numeric keys live beside the name keys.
    for id, s2 in pairs(addon.SPEC_SIGNATURES_BY_ID or {}) do
        local icons = addon.SPEC_TREE_ICONS[s2[1]]
        local texture = addon.FeralTexture(s2[4]) or (icons and icons[s2[2]])
        if texture then
            signatureByName[id] = { class = s2[1], spec = s2[2], strength = s2[3], texture = texture,
                kind = s2[4], role = addon.SPEC_ROLES[s2[1]] and addon.SPEC_ROLES[s2[1]][s2[2]] }
        end
    end
    return signatureByName
end

-- Weak signals, built the same way and for the same reason: by localized name,
-- so a German or Russian client resolves its own spell names.
local function WeakSignatures()
    if weakByName then return weakByName end
    weakByName = {}
    for id, s in pairs(addon.WEAK_SIGNATURES or {}) do
        local spellName = GetSpellInfo(id)
        local icons = addon.SPEC_TREE_ICONS[s[1]]
        local texture = icons and icons[s[2]]
        if spellName and texture then
            local old = weakByName[spellName]
            if old == nil then
                weakByName[spellName] = { class = s[1], spec = s[2], texture = texture,
                    kind = s[3],
                    role = addon.SPEC_ROLES[s[1]] and addon.SPEC_ROLES[s[1]][s[2]] }
            elseif old and (old.class ~= s[1] or old.spec ~= s[2]) then
                weakByName[spellName] = false -- one name, two specs: never trusted
            end
        end
    end
    return weakByName
end

-- Remember a spec for the plate's name map, the render-only fallback used when
-- a plate has no GUID. Shared by the strong and weak paths.
local function StoreSpecName(name, entry)
    if type(name) ~= "string" then return end
    local short = name:match("^[^%-]+") or name
    local prev = enemySpecByName[short]
    if prev == false or (prev and prev.guid ~= entry.guid) then
        enemySpecByName[short] = false
    else
        enemySpecByName[short] = entry
    end
end

-- 3152 ids parsed once. Three milliseconds on real Lua 5.1, which is too
-- long to spend inside a combat-log event, so the loading screen pre-warms
-- it through addon.WarmSpellClasses.
local spellClassByID
local function SpellClassMap()
    if not spellClassByID then
        spellClassByID = {}
        for classFile, list in pairs(addon.CLASS_SPELL_IDS or {}) do
            for n in tostring(list):gmatch("%d+") do spellClassByID[tonumber(n)] = classFile end
        end
    end
    return spellClassByID
end
addon.WarmSpellClasses = SpellClassMap
local function SpellClass(id) return SpellClassMap()[id] end

-- The spec a talent build proved in THIS session, while that build is still the
-- newest thing we know. It outranks every combat-log guess and every form
-- signal: a cat-talent druid who shifts to bear to survive is still a cat, a
-- bear-talent druid who shifts to cat to travel is still a bear, and a Balance
-- druid who shifts to cat is still Balance. Only a talent that outranks it (see
-- DeeperSpec: a 40-point talent, or a deeper one) or a form that belongs to one
-- spec only may replace it - see ForcedSpec. A build restored from DISK does
-- not lock anything: it is older than what we can see.
function addon.LockedSpec(guid)
    local known = guid and cacheByGUID[guid]
    if known and known.spec and not known.fromDisk then
        return known.spec, known.feralKind
    end
end

-- A talent's row is a lower bound on the points its owner spent in that tree,
-- so the DEEPEST talent we have ever seen names his MAIN tree - which is what a
-- player calls his spec. That is the whole hybrid story:
--
--   Preg paladin 0/28/43   Protection talents stop at row 5 (25 points) while
--                          Retribution proves row 8 (40): Sheath of Light
--                          settles it as RETRIBUTION, never PROTECTION.
--   rogue 38/33/0          Assassination proves row 7 (35) against Combat's
--                          row 6 (30) - Assassination is the main tree.
--   DK 43/26/2 and 24/0/44 the 40+ tree is the main one by definition.
--
-- So a shallower off-tree talent never moves a known spec, and a deeper one
-- always does. A talent at row 8 or deeper (40+ points) is proof on its own:
-- no build can hold 40 points in two trees (40 + 40 > 71), so the newest one is
-- a respec - that is what lets a Balance druid who respecced Feral show up as
-- Feral on his first Mangle even though Starfall is "deeper" than Mangle.
-- Below 40 points equal depth is a coin flip (a 36/35 build) and the first
-- answer stays, which is what stopped the 25/46 warlock flickering
-- Demonology/Affliction inside one teamfight.
function addon.DeeperSpec(strength, old)
    if strength >= 8 then return true end
    return strength > (old and (old.strength or 0) or 0)
end

-- The shapeshift forms that name a spec (see SPEC_FORM_SPELLS in Common/Feral.lua:
-- Tree of Life and Moonkin Form). A druid wearing one is that spec and nothing
-- else can be true. This overrules even a build we read ourselves: the build is
-- older than the shapeshift, which is exactly what a respec looks like from the
-- outside. Returns true when it changed something, so the caller redraws.
function addon.ForcedSpec(spellID, guid, name, spellName, subEvent, destGUID, enemy)
    local spec = spellID and addon.SPEC_FORM_SPELLS and addon.SPEC_FORM_SPELLS[spellID]
    if not spec then return false end
    local icons = addon.SPEC_TREE_ICONS.DRUID
    local texture = icons and icons[spec]
    if not texture then return false end
    local role = addon.RoleForSpec and addon.RoleForSpec("DRUID", spec) or nil
    -- the build we hold is stale the moment he wears the other spec's form:
    -- repair the inspection record too, or the next render would read the old
    -- build back out of the talent cache and undo this
    local talent = addon._TalentCache and addon._TalentCache[guid]
    if talent then
        talent.spec, talent.specTexture, talent.specRole = spec, texture, role
        talent.feralKind = nil
    end
    local known = cacheByGUID[guid]
    if known then
        known.spec, known.specTexture, known.specRole = spec, texture, role
        known.feralKind, known.feralLock, known.fromDisk = nil, nil, nil
        known.isHealer, known.isTank = role == "HEALER", role == "TANK"
    end
    local store = enemy and enemySpecByGUID or friendlySpecByGUID
    local old = store[guid]
    if old and old.spec == spec and not old.weak then
        -- already that spec: nothing to redraw, just keep the memory honest
        if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, "DRUID", spec, false, role) end
        return false
    end
    if not old then
        if enemy then
            enemySpecCount = enemySpecCount + 1
            if enemySpecCount > 2000 then wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 1 end
        else
            friendlySpecCount = friendlySpecCount + 1
            if friendlySpecCount > 2000 then
                wipe(friendlySpecByGUID); wipe(friendlySpecByName); friendlySpecCount = 1
                wipe(friendlyViewByKey); friendlyViewCount = 0
            end
        end
    end
    local entry = { guid = guid, name = name, class = "DRUID", spec = spec,
        texture = texture, role = role, strength = 10, kind = "SPEC" }
    store[guid] = entry
    if enemy then
        StoreSpecName(name, entry)
    elseif type(name) == "string" then
        local short = name:match("^[^%-]+") or name
        local prev = friendlySpecByName[short]
        if prev == false or (prev and prev.guid ~= guid) then friendlySpecByName[short] = false
        else friendlySpecByName[short] = entry end
    end
    if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, "DRUID", spec, false, role) end
    if addon._debugEnabled then
        addon:DebugLog(enemy and "ENEMYSPEC" or "FRIENDSPEC",
            "guid=%s name=%s class=DRUID spec=%s strength=10 via=form sub=%s src=%s dst=%s spell=%s respec",
            tostring(guid), tostring(name), spec, tostring(subEvent), tostring(guid),
            tostring(destGUID), tostring(spellName))
    end
    return true
end

-- A spec-unique signature (row 9+, i.e. 40+ points in that tree) outranks a
-- build we read earlier: the read says what he WAS, the talent says what he is
-- now. Update the render record so the icon changes at once, and retire the
-- inspection so the next render cannot read the old build back. The CLASS is
-- never touched - a real read locks the class for good, not the spec.
function addon.AdoptSpec(guid, name, class, spec, texture, role, kind)
    local known = guid and cacheByGUID[guid]
    if not known or not known.spec or known.class ~= class or known.spec == spec then return false end
    local before = known.spec
    known.spec, known.specTexture, known.specRole = spec, texture, role
    known.feralKind, known.feralLock = kind, nil
    known.fromDisk = nil
    known.isHealer, known.isTank = role == "HEALER", role == "TANK"
    local talent = addon._TalentCache and addon._TalentCache[guid]
    if talent then talent.stale = true end
    if addon._debugEnabled then
        addon:DebugLog("SPECREAD", "guid=%s name=%s %s -> %s (a row-8 talent outranks the read)",
            tostring(guid), tostring(name), tostring(before), tostring(spec))
    end
    return true
end

-- A weak signal fills in a spec ONLY when nothing better is known.
--   * a real signature is never replaced (old.weak is nil)
--   * a player never changes class
--   * a DIFFERENT weak guess of the same class does NOT replace the first one:
--     two class-wide spells are equally weak evidence, so taking the newest made
--     a warlock flicker Affliction <-> Destruction on every Corruption/Immolate
--     tick. The first guess stays until a signature proves one of them.
--   * the one exception is the druid FORM: a cat/bear signal carries a form,
--     which is new, exact information (a cat that shifts to bear is a bear now).
-- Returns true when the stored spec changed.
local function NoteWeakSpec(guid, name, spellName)
    local cfg = DB()
    if not cfg.weakSpecSignals then return false end
    local sig = WeakSignatures()[spellName]
    if not sig then return false end
    -- A guess never touches a talent build read this session, in either
    -- direction: a Balance druid who shifts to cat stays Balance, and a Feral
    -- who throws a Wrath or a Regrowth stays Feral.
    if addon.LockedSpec(guid) then return false end
    -- the client's own class always wins over a spell-id inference
    local apiClass = auraClassByGUID[guid]
    if apiClass and apiClass ~= sig.class then return false end
    local old = enemySpecByGUID[guid]
    if old and not old.weak and not old.classOnly then return false end
    if old and old.class ~= sig.class then return false end
    if old and old.spec == sig.spec then
        -- same guess: only a newly learned FORM is worth a redraw.
        if sig.kind and old.kind ~= sig.kind then
            old.kind = sig.kind
            old.texture = addon.FeralTexture(sig.kind) or old.texture
            old.role = sig.kind == "BEAR" and "TANK" or sig.role
            if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, sig.class, sig.spec, true, old.role) end
            return true
        end
        return false
    end
    if old and old.classOnly then
        -- a bare class from a class proof is weaker than a guess: add the spec
        -- to the existing record instead of starting a second one.
        -- classOnly MUST be cleared here: leaving it set made every later guess
        -- take this branch again, so FROST -> FIRE -> FROST flickered and a
        -- weak guess could even replace a spec a signature had already proven.
        local role = sig.kind == "BEAR" and "TANK" or sig.role
        old.spec, old.texture, old.kind = sig.spec,
            addon.FeralTexture(sig.kind) or sig.texture, sig.kind or "SPEC"
        old.weak, old.classOnly, old.role = true, nil, role
        if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, sig.class, sig.spec, true, role) end
        if addon._debugEnabled then
            addon:DebugLog("WEAKSPEC", "guid=%s name=%s class=%s spec=%s spell=%s (class-only upgraded)",
                tostring(guid), tostring(name), sig.class, sig.spec, tostring(spellName))
        end
        return true
    end
    if old then return false end
    enemySpecCount = enemySpecCount + 1
    if enemySpecCount > 2000 then wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 1 end
    local role = sig.kind == "BEAR" and "TANK" or sig.role
    local entry = { guid = guid, name = name, class = sig.class, spec = sig.spec,
        texture = addon.FeralTexture(sig.kind) or sig.texture,
        role = role, strength = 0, kind = sig.kind or "SPEC", weak = true }
    enemySpecByGUID[guid] = entry
    StoreSpecName(name, entry)
    if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, sig.class, sig.spec, true, role) end
    if addon._debugEnabled then
        addon:DebugLog("WEAKSPEC", "guid=%s name=%s class=%s spec=%s spell=%s",
            tostring(guid), tostring(name), sig.class, sig.spec, tostring(spellName))
    end
    return true
end

-- Returns true when the stored spec of this hostile player changed.
local function NoteEnemySpec(guid, name, spellName, spellID, subEvent, destGUID)
    if addon.ForcedSpec(spellID, guid, name, spellName, subEvent, destGUID, true) then return true end
    local sig = Signatures()[spellName] or (spellID and Signatures()[spellID])
    if not sig then
        if NoteWeakSpec(guid, name, spellName) then return true end
        -- Guessing off, or a spell that is not a guess: any spell exactly one
        -- class can train still proves the CLASS (never the spec). This is what
        -- gives a hostile player a class icon from the first thing he does even
        -- with "Guess a spec" disabled.
        local cls = spellID and SpellClass(spellID) or nil
        if not cls then return false end
        -- never contradict a class the client itself reported for this GUID
        local apiClass = auraClassByGUID[guid]
        if apiClass and apiClass ~= cls then return false end
        local old = enemySpecByGUID[guid]
        if old then return false end -- a spec/class is already known
        local known = cacheByGUID[guid]
        if known and known.class and known.class ~= cls then return false end
        enemySpecCount = enemySpecCount + 1
        if enemySpecCount > 2000 then wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 1 end
        local entry = { guid = guid, name = name, class = cls, strength = 0, kind = "CLASS", classOnly = true }
        enemySpecByGUID[guid] = entry
        StoreSpecName(name, entry)
        if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, cls, nil, nil, nil) end
        if addon._debugEnabled then
            addon:DebugLog("ENEMYSPEC", "guid=%s name=%s class=%s spec=- strength=0 via=spell sub=%s src=%s dst=%s spell=%s",
                tostring(guid), tostring(name), cls, tostring(subEvent), tostring(guid), tostring(destGUID), tostring(spellName or spellID))
        end
        return true
    end
    local old = enemySpecByGUID[guid]
    -- A real read locks the CLASS (above) and silences guesses (NoteWeakSpec),
    -- but it does NOT freeze the spec: a row-8+ talent is proof of a respec, so
    -- it always wins. What the read owns is the cat/bear half of a Feral build -
    -- a cat-talent druid tanking in bear form is still a cat.
    local lockedSpec = addon.LockedSpec(guid)
    if lockedSpec then
        if sig.kind and lockedSpec == "FERAL" then return false end
        if sig.spec ~= lockedSpec and sig.strength < 8 then return false end
    end
    if old and old.class == sig.class and old.spec == sig.spec then
        if old.weak then
            -- a real signature confirms a weak guess: same icon, now proven
            old.weak = nil
            old.classOnly = nil
            old.strength = sig.strength
            old.texture = sig.texture
            old.kind = sig.kind
            -- the guess just became proof: upgrade the stored record too
            if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, sig.class, sig.spec, false, sig.role) end
            if addon._debugEnabled then
                addon:DebugLog("ENEMYSPEC", "guid=%s name=%s class=%s spec=%s strength=%d sub=%s src=%s dst=%s spell=%s confirmed-weak-guess",
                    tostring(guid), tostring(name), sig.class, sig.spec, sig.strength, tostring(subEvent), tostring(guid), tostring(destGUID), tostring(spellName))
            end
            return true
        end
        if old.strength < sig.strength then old.strength = sig.strength end
        if sig.kind and (old.texture ~= sig.texture or old.kind ~= sig.kind) then
            old.texture = sig.texture; old.kind = sig.kind; return true
        end
        return false
    end
    -- A different spec of the SAME class is either a hybrid dip or a respec.
    -- Depth decides: the main tree is the one with the most points, and a
    -- talent's row is a lower bound on those points, so only a DEEPER talent
    -- may move the icon (see DeeperSpec). A 25-point off-tree talent is a hybrid
    -- proc, not a respec - letting those through made a 25/46 warlock flicker
    -- DEMONOLOGY -> AFFLICTION -> DEMONOLOGY inside one teamfight. Depth still
    -- decides between hints that agree on the spec, which the branch above
    -- handles. A weak guess or a bare class is not a spec, so a signature
    -- replaces it at any depth.
    if old and old.class == sig.class and not old.weak and not old.classOnly then
        if not addon.DeeperSpec(sig.strength, old) then
            stats.hybridKept = stats.hybridKept + 1
            if addon._debugEnabled then
                addon:DebugLog("HYBRID", "guid=%s name=%s kept %s (%d) over %s (%d) spell=%s",
                    tostring(guid), tostring(name), tostring(sig.spec), sig.strength,
                    tostring(old.spec), old.strength or 0, tostring(spellName))
            end
            return false
        end
        -- a deeper talent still short of 40 points moved the icon: the main
        -- tree just proved itself (Preg 0/28/43, rogue 38/33)
        if sig.strength < 8 then
            stats.hybridMoved = stats.hybridMoved + 1
            if addon._debugEnabled then
                addon:DebugLog("HYBRID", "guid=%s name=%s moved to %s (%d) over %s (%d) spell=%s",
                    tostring(guid), tostring(name), tostring(sig.spec), sig.strength,
                    tostring(old.spec), old.strength or 0, tostring(spellName))
            end
        end
    end
    -- A player NEVER changes class. A different class may only be a correction
    -- of weak evidence, never of another signature: a shared spell name (or a
    -- client quirk that attributes a party aura to its recipient) used to flip a
    -- proven Death Knight to Warlock on one Haunt line. A bare class proof or a
    -- guess can still be corrected, but only by a deep (row 8+) talent, and only
    -- from a real cast - never from damage, which is what a REFLECTED spell
    -- looks like (Spell Reflection is credited to the warrior who reflected it).
    if old and old.class ~= sig.class then
        if (old.classOnly or old.weak) and sig.strength >= 8 and not REFLECTABLE[subEvent] then
            -- allowed: weak evidence replaced by a deep talent we saw him cast
        else
            if addon._debugEnabled then
                addon:DebugLog("ENEMYSPEC", "guid=%s name=%s ignored-class-change old=%s new=%s strength=%d sub=%s%s src=%s dst=%s spell=%s",
                    tostring(guid), tostring(name), tostring(old.class), tostring(sig.class),
                    sig.strength, tostring(subEvent),
                    REFLECTABLE[subEvent] and " (damage: a reflected spell names the reflector)" or "",
                    tostring(guid), tostring(destGUID), tostring(spellName))
            end
            return false
        end
    end
    -- A player whose real class is known (inspection/unit) never takes another class.
    local known = cacheByGUID[guid]
    if known and known.class and known.class ~= sig.class then return false end
    if not old then
        enemySpecCount = enemySpecCount + 1
        if enemySpecCount > 2000 then wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 1 end
    end
    local entry = { guid = guid, name = name, class = sig.class, spec = sig.spec, texture = sig.texture, role = sig.role, strength = sig.strength, kind = sig.kind }
    enemySpecByGUID[guid] = entry
    StoreSpecName(name, entry)
    -- a Bear-form signature is a tank even though FERAL alone means DAMAGER.
    local role = sig.role
    if sig.kind == "BEAR" then role = "TANK" end
    -- a row-8+ talent replaces a build we read earlier, at once
    addon.AdoptSpec(guid, name, sig.class, sig.spec, sig.texture, role, sig.kind)
    if addon.SpecMemory then addon.SpecMemory:Remember(guid, name, sig.class, sig.spec, false, role) end

    if addon._debugEnabled then
        addon:DebugLog("ENEMYSPEC", "guid=%s name=%s class=%s spec=%s strength=%d sub=%s src=%s dst=%s spell=%s",
            tostring(guid), tostring(name), sig.class, sig.spec, sig.strength, tostring(subEvent), tostring(guid), tostring(destGUID), tostring(spellName))
    end
    return true
end

-- Full wipe of everything the combat log learned about players. Used by the
-- explicit "Delete all saved player information" button and by the login/reload
-- wipe while the memory is off. Never called by a zone change or an instance.
addon.ClearLearnedSpecs = function()
    wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 0
    wipe(friendlySpecByGUID); wipe(friendlySpecByName); friendlySpecCount = 0
    wipe(friendlyViewByKey); friendlyViewCount = 0
end
-- kept for callers that predate the friendly store
addon.ClearEnemySpecs = addon.ClearLearnedSpecs

-- Turning "Guess a spec from common spells" off must remove GUESSES only. A
-- signature or an inspection is not a guess, so a proven spec keeps its icon
-- instead of vanishing until the next loading screen.
local function DropGuesses(store, byNameStore)
    local kept = {}
    for guid, entry in pairs(store) do
        if entry.weak then store[guid] = nil else kept[#kept + 1] = entry end
    end
    wipe(byNameStore)
    for i = 1, #kept do
        local entry = kept[i]
        local short = type(entry.name) == "string" and (entry.name:match("^[^%-]+") or entry.name) or nil
        if short then
            local prev = byNameStore[short]
            if prev == false or (prev and prev.guid ~= entry.guid) then byNameStore[short] = false
            else byNameStore[short] = entry end
        end
    end
end
addon.ClearGuessedSpecs = function()
    DropGuesses(enemySpecByGUID, enemySpecByName)
    DropGuesses(friendlySpecByGUID, friendlySpecByName)
    wipe(friendlyViewByKey); friendlyViewCount = 0
end

-- Friendly players who are NOT in your group. They have no unit token on a
-- stock client, so the talent scanner cannot reach them: the combat log is the
-- only source of a class or a spec. Party and raid members are inspected
-- properly and never come here, and a real read always wins over this store.
--
-- Three tiers, strongest last:
--   class proof  a spell exactly one class can train -> the class, nothing else
--   guess        a weak signal -> class + a guessed spec (off by default)
--   signature    a talent at row 5+ -> class + the real spec
-- A weaker tier never replaces a stronger one, and the class never changes
-- once a signature or a guess has set it.
local function NoteFriendlySpec(guid, name, spellName, spellID, subEvent, destGUID)
    if addon.ForcedSpec(spellID, guid, name, spellName, subEvent, destGUID, false) then return true end
    -- A real read is the strongest CLASS evidence, but it is a snapshot: he can
    -- respec the moment he walks away and we may never hover him again. So the
    -- read locks the CLASS (below) and silences GUESSES, and a row-8+ talent is
    -- still allowed to change the SPEC (see AdoptSpec). A unit token that only
    -- read the class (out of inspect range, standing still) is not authoritative
    -- about the spec at all, so the combat log fills that in. A record restored
    -- from DISK is from an earlier session, so a proven signature may correct it
    -- even below row 8 (the knownStale path below).
    local known = cacheByGUID[guid]
    local knownStale = known and known.fromDisk and known.specTexture

    local sig = Signatures()[spellName] or (spellID and Signatures()[spellID])
    local old = friendlySpecByGUID[guid]
    local want, via
    if sig then
        want, via = sig, "signature"
    else
        local w = DB().weakSpecSignals and WeakSignatures()[spellName] or nil
        if w then
            want = { class = w.class, spec = w.spec,
                texture = addon.FeralTexture(w.kind) or w.texture,
                role = w.kind == "BEAR" and "TANK" or w.role,
                strength = 0, kind = w.kind or "SPEC", weak = true }
            via = "guess"
        else
            -- Any spell exactly one class can train proves the class. This is what
            -- turns the first thing a friendly outsider casts into a class icon
            -- instead of leaving a question mark on his plate.
            local cls = spellID and SpellClass(spellID) or nil
            if not cls then return false end
            want = { class = cls, strength = 0, kind = "CLASS", classOnly = true }
            via = "spell"
        end
    end

    -- a class the client itself reported (UnitClass) is never overridden here
    if known and known.class and known.class ~= want.class then return false end
    -- A build read this session silences GUESSES completely (that is what the
    -- read is for), and owns the cat/bear half of a Feral. It does not freeze
    -- the spec: another spec needs a row-8+ talent, which is proof of a respec.
    local lockedSpec = addon.LockedSpec(guid)
    if lockedSpec then
        if want.weak then return false end
        if sig and sig.kind and lockedSpec == "FERAL" then return false end
        if want.spec ~= lockedSpec and (want.strength or 0) < 8 then return false end
    end
    local apiClass = auraClassByGUID[guid]
    if apiClass and apiClass ~= want.class then return false end
    if knownStale then
        -- a disk record only loses to a proven signature of the same class
        if via ~= "signature" or want.spec == known.spec then return false end
        known.spec, known.specTexture, known.specRole, known.feralKind = nil, nil, nil, nil
        known.isHealer, known.isTank, known.fromDisk = false, false, nil
    end

    -- A class proof only ever ADDS a class. It must never erase a spec that a
    -- signature or a guess already named: a mage who shields himself and then
    -- buffs Arcane Intellect would lose his spec icon on the buff.
    if via == "spell" and old and not old.classOnly then return false end

    if old then
        if old.classOnly then
            -- a single spell is weaker evidence than a talent, so a signature of
            -- another class may correct it; a guess may not, and one class proof
            -- never flips to another class proof. A correction needs a deep
            -- (row 8+) talent we saw him CAST: damage can be a reflected spell.
            if via == "spell" then return false end
            if via == "guess" and old.class ~= want.class then return false end
            if via == "signature" and old.class ~= want.class
                and ((want.strength or 0) < 8 or REFLECTABLE[subEvent]) then return false end
        else
            if old.class ~= want.class then
                if old.weak and via == "signature" and not REFLECTABLE[subEvent] then
                    -- a talent outranks a guess, whatever class the guess named
                else
                    return false
                end
            elseif old.spec == want.spec then
                if old.weak and via ~= "guess" then
                    -- a real signature confirms the guess: same icon, now proven
                    old.weak = nil; old.strength = want.strength
                    old.texture = want.texture; old.kind = want.kind
                    local role = want.role
                    if want.kind == "BEAR" then role = "TANK" end
                    if addon.SpecMemory then
                        addon.SpecMemory:Remember(guid, name, want.class, want.spec, false, role)
                    end
                    if addon._debugEnabled then
                        addon:DebugLog("FRIENDSPEC", "guid=%s name=%s class=%s spec=%s strength=%d spell=%s confirmed-weak-guess",
                            tostring(guid), tostring(name), want.class, want.spec, want.strength, tostring(spellName))
                    end
                    return true
                end
                if old.strength < (want.strength or 0) then old.strength = want.strength end
                -- same spec, but the FORM is new information (a cat that shifted
                -- to bear is a bear now): redraw, never flicker the spec.
                if want.kind and old.kind ~= want.kind
                    and (want.kind == "BEAR" or want.kind == "CAT") then
                    old.kind = want.kind
                    old.texture = addon.FeralTexture(want.kind) or old.texture
                    old.role = want.kind == "BEAR" and "TANK" or want.role
                    return true
                end
                return false
            elseif old.weak and via == "guess" then
                -- Two different guesses of the same class: keep the FIRST one.
                -- Both are equally weak, and taking the newest made a warlock
                -- flicker Affliction <-> Destruction on Corruption/Immolate.
                -- A form signal is the only thing allowed to move it, because a
                -- shapeshift is exact, current information rather than a guess.
                -- A real SIGNATURE is not a guess and never takes this branch:
                -- it falls through to the depth rule below, so a Fire mage who
                -- opened with a Frostbolt is not stuck on FROST for the fight.
                -- A form only refines a FERAL guess. A guessed Balance druid in
                -- cat form is still Balance (every druid can shift to travel);
                -- setting the kind without the spec left spec=BALANCE with
                -- feralKind=CAT in a capture, which is state that cannot exist.
                if old.spec == "FERAL" and (want.kind == "BEAR" or want.kind == "CAT")
                    and old.kind ~= want.kind then
                    old.kind = want.kind
                    old.texture = addon.FeralTexture(want.kind) or old.texture
                    old.role = want.kind == "BEAR" and "TANK" or want.role
                    return true
                end
                return false
            elseif via ~= "signature" then
                return false
            elseif not addon.DeeperSpec(want.strength, old) then
                -- the depth rule stops a hybrid dip moving a KNOWN spec
                stats.hybridKept = stats.hybridKept + 1
                if addon._debugEnabled then
                    addon:DebugLog("HYBRID", "guid=%s name=%s kept %s (%d) over %s (%d) spell=%s",
                        tostring(guid), tostring(name), tostring(want.spec), want.strength or 0,
                        tostring(old.spec), old.strength or 0, tostring(spellName))
                end
                return false
            elseif (want.strength or 0) < 8 then
                -- a deeper talent below 40 points moved it: the main tree won
                stats.hybridMoved = stats.hybridMoved + 1
                if addon._debugEnabled then
                    addon:DebugLog("HYBRID", "guid=%s name=%s moved to %s (%d) over %s (%d) spell=%s",
                        tostring(guid), tostring(name), tostring(want.spec), want.strength or 0,
                        tostring(old.spec), old.strength or 0, tostring(spellName))
                end
            end
        end
    end

    if not old then
        friendlySpecCount = friendlySpecCount + 1
        if friendlySpecCount > 2000 then
            wipe(friendlySpecByGUID); wipe(friendlySpecByName); friendlySpecCount = 1
            wipe(friendlyViewByKey); friendlyViewCount = 0
        end
    end
    local entry = { guid = guid, name = name, class = want.class, spec = want.spec,
        texture = addon.FeralTexture(want.kind) or want.texture,
        role = want.role, strength = want.strength, kind = want.kind,
        weak = want.weak or nil, classOnly = want.classOnly or nil }
    friendlySpecByGUID[guid] = entry
    if type(name) == "string" then
        local short = name:match("^[^%-]+") or name
        local prev = friendlySpecByName[short]
        if prev == false or (prev and prev.guid ~= guid) then friendlySpecByName[short] = false
        else friendlySpecByName[short] = entry end
    end
    -- keep the cross-session memory in step with what the combat log just proved
    local role = want.role
    if want.kind == "BEAR" then role = "TANK" end
    -- a row-8+ talent replaces a build we read earlier, at once
    if not want.weak then
        addon.AdoptSpec(guid, name, want.class, want.spec, entry.texture, role, want.kind)
    end
    if addon.SpecMemory then
        addon.SpecMemory:Remember(guid, name, want.class, want.spec, want.weak, role)
    end
    if addon._debugEnabled then
        addon:DebugLog("FRIENDSPEC", "guid=%s name=%s class=%s spec=%s strength=%d via=%s sub=%s src=%s dst=%s spell=%s",
            tostring(guid), tostring(name), want.class, tostring(want.spec or "-"), want.strength or 0,
            via, tostring(subEvent), tostring(guid), tostring(destGUID), tostring(spellName or spellID))
    end
    return true
end
-- Last resort: what the Class/Spec Memory remembers about this player from an
-- earlier session. Everything live outranks it - inspection, a signature, a
-- guess, a class proof, the bar colour - so a stored record is only ever a
-- baseline that the next detection overwrites.
local function MemoryEntry(guid, name, classFile)
    local mem = addon.SpecMemory
    if not mem then return nil end
    local entry = mem:Get(guid, name, classFile)
    if not entry then return nil end
    local icons = addon.SPEC_TREE_ICONS[entry.class]
    -- The guess toggle also gates GUESSES THAT WERE STORED. Without this a
    -- guessed spec survived turning "Guess a spec from common spells" off,
    -- because the memory handed it back on the next render. The class is not a
    -- guess: it stays.
    local spec = entry.spec
    if spec and entry.weak and not DB().weakSpecSignals then spec = nil end
    local texture = spec and icons and icons[spec] or nil
    local roles = addon.SPEC_ROLES[entry.class]
    -- A Feral stored with a proven TANK role was a bear when we last saw him, so
    -- he comes back as a bear (the tank icon while it is on, the bear texture
    -- while it is off) instead of the generic cat. The record keeps the role,
    -- not the form, which is why this is a derivation and not a stored field.
    local feralKind = (entry.class == "DRUID" and spec == "FERAL" and entry.role == "TANK")
        and "BEAR" or nil
    return { guid = guid, class = entry.class, spec = spec, texture = texture,
        -- a proven role (an inspected Feral tank) beats what the spec implies
        role = (spec and (entry.role or (roles and roles[spec]))) or nil,
        feralKind = feralKind,
        kind = spec and "SPEC" or "CLASS",
        weak = (spec and entry.weak) or nil, fromMemory = true }
end

-- What the combat log learned about a friendly outsider, or nil. A plate with
-- a real class from inspection never asks.
-- A player can change sides inside one session: a duel, a cross-faction
-- battleground, or a paid faction change. The class and the spec do not change
-- with the side, so each store also reads the other side's - otherwise a
-- friendly who becomes hostile would lose the spec we already detected for him.
local function FriendlySpec(guid, name, classFile)
    local entry
    if guid then entry = friendlySpecByGUID[guid] or enemySpecByGUID[guid]
    elseif name then
        -- the name maps are keyed by the SHORT name (StoreSpecName strips a
        -- "-Realm" suffix), so the lookup must strip it too.
        local short = name:match("^[^%-]+") or name
        entry = friendlySpecByName[short]
        if not entry and classFile then
            local other = enemySpecByName[short]
            if other and other ~= false then entry = other end
        end
    end
    if entry and (not classFile or entry.class == classFile) then return entry end
end

-- By exact GUID; by name only for a GUID-less plate whose live class matches.
-- see FriendlySpec: the other side's store is read too, for the same reason.
local function EnemySpec(guid, name, classFile)
    local entry
    if guid then entry = enemySpecByGUID[guid] or friendlySpecByGUID[guid]
    elseif name and classFile then
        local short = name:match("^[^%-]+") or name
        entry = enemySpecByName[short]
        if not entry then
            local other = friendlySpecByName[short]
            if other and other ~= false then entry = other end
        end
    end
    if entry and (not classFile or entry.class == classFile) then return entry end
end

-- built once (same tokens, same order), avoiding repeated ~105-string
-- table on every call, i.e. per plate per refresh and per combat-log event.
local unitCandidates = { "player", "target", "focus", "mouseover", "pet" }
for i = 1, 4 do
    unitCandidates[#unitCandidates + 1] = "party" .. i
    unitCandidates[#unitCandidates + 1] = "partypet" .. i
end
for i = 1, 40 do
    unitCandidates[#unitCandidates + 1] = "raid" .. i
    unitCandidates[#unitCandidates + 1] = "raidpet" .. i
end
for i = 1, 5 do
    unitCandidates[#unitCandidates + 1] = "arena" .. i
    unitCandidates[#unitCandidates + 1] = "arenapet" .. i
end

local function FindUnitByGUID(guid)
    if not guid then return nil end
    for _, unit in ipairs(unitCandidates) do
        if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    end
    return nil
end

local function FindUnitByName(name)
    if not name or name == "" then return nil end
    for _, unit in ipairs(unitCandidates) do
        if UnitExists(unit) and UnitName(unit) == name and IsPlayerOrPetUnit(unit) then
            return unit
        end
    end
    return nil
end

local function GetArenaIndexForGUID(guid, name)
    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitExists(unit) then
            if guid and UnitGUID(unit) == guid then return i end
            if name and UnitName(unit) == name then return i end
        end
    end
end

local function GetArenaIndexForName(name)
    return GetArenaIndexForGUID(nil, name)
end

local function SyncTalentCache(guid, name)
    if not guid or not addon.TalentScanner or not addon.TalentScanner.Get then return end
    local talent = addon.TalentScanner:Get(guid)
    -- a record a live signature already contradicted is not evidence any more
    if not talent or not talent.spec or talent.stale then return end
    -- A record restored from disk comes from an earlier session. A talent
    -- signature seen THIS session is proof of a talent the player has right now,
    -- so if the two name different specs he respecced and the disk record is
    -- stale. Without this an old inspection outranked the live combat log and
    -- the icon only corrected itself on the next mouseover.
    local fromDisk = addon.TalentScanner.IsFromDisk and addon.TalentScanner:IsFromDisk(guid)
    if fromDisk then
        local live = enemySpecByGUID[guid] or friendlySpecByGUID[guid]
        if live and not live.weak and not live.classOnly and live.spec
            and live.spec ~= talent.spec then
            return
        end
    end

    -- Never reuse a mutable nameplate record for a different GUID. Build a fresh
    -- per-GUID render snapshot from the authoritative TalentScanner record, while
    -- preserving only overlay-local state belonging to this exact GUID.
    local old = cacheByGUID[guid] or {}
    local data = {
        guid = guid,
        name = talent.name or old.name or name,
        class = talent.class or old.class,
        spec = talent.spec,
        specTexture = talent.specTexture,
        specRole = talent.specRole,
        -- a build read this session owns the form; a disk build keeps whatever
        -- the live form read already established (RememberUnit), and only a
        -- Feral build can carry a form at all.
        feralKind = talent.feralKind or (talent.spec == "FERAL" and old.feralKind) or nil,
        feralLock = (talent.feralKind and not fromDisk) or nil,
        fromDisk = fromDisk or nil,
        isHealer = talent.specRole == "HEALER",
        isTank = talent.specRole == "TANK",
        isPet = old.isPet,
        _specDisplayAt = old._specDisplayAt,
        _specDisplaySpec = old._specDisplaySpec,
    }
    if data.specRole == "HEALER" then data.isHealer = true end
    if data.specRole == "TANK" then data.isTank = true end
    if addon.ApplyFeralIdentity then addon.ApplyFeralIdentity(data, addon.IsAssignedGroupTank(FindUnitByGUID(guid))) end
    cacheByGUID[guid] = data
    if data.name and data.name ~= "" then cacheByName[data.name] = data end
    -- an inspection is the strongest thing we can know: store it with its role
    -- so the player's icon is back, with the right healer/tank shape, after a
    -- reload even before he is inspected again. A Feral's specRole is nil by
    -- design (the assignment/form decides), so map a bear or an assigned tank
    -- to TANK explicitly or the tank icon would be lost across a reload.
    if addon.SpecMemory then
        local role = data.specRole
        if data.class == "DRUID" and data.spec == "FERAL"
            and (data.isTank or data.feralKind == "BEAR") then
            role = "TANK"
        end
        addon.SpecMemory:Remember(guid, data.name, data.class, data.spec, false, role)
    end
end

-- Sync talent cache by name when GUID not yet known to LibNameplates.
-- Used by full refresh fallback to render spec data on plates that have a name
-- but no GUID association yet. Searches TalentScanner cache for matching name.
local function SyncTalentCacheByName(name)
    if not name or name == "" or not addon._TalentCache then return end
    local match
    for guid, talent in pairs(addon._TalentCache) do
        if talent.name == name and talent.spec and talent.specTexture and not talent.stale then
            if match then cacheByName[name] = nil; return end
            match = guid
        end
    end
    if match then SyncTalentCache(match, name) end
    return match
end

-- only a self-cast healer aura proves a healer. The old path counted
-- the receiver, so a tank wearing a shaman's Earth Shield got the healer icon.
local function UnitHasHealerAura(unit)
    if not unit then return false end
    local i = 1
    while true do
        local name, _, _, _, _, _, _, caster, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        if spellId and addon.HealerBuffAuras[spellId] and caster and UnitIsUnit(caster, unit) then return true end
        i = i + 1
    end
    return false
end

-- 3.3.5a UnitGroupRolesAssigned returns three booleans (tank, healer, damage).
local function AssignedRole(unit)
    if not UnitGroupRolesAssigned or not UnitIsPlayer(unit) then return nil end
    local role, healer, damager = UnitGroupRolesAssigned(unit)
    if type(role) == "string" then return role ~= "NONE" and role or nil end
    return role and "TANK" or healer and "HEALER" or damager and "DAMAGER" or nil
end
addon.GetAssignedGroupRole = AssignedRole

local LearnPetUnit -- defined with the pet memory below

local function RememberUnit(unit)
    if not IsPlayerOrPetUnit(unit) then return end
    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    if not guid then return end
    local isPet = not UnitIsPlayer(unit)
    -- a hovered/targeted pet learns its name (render-only) so the stock
    -- client can redraw its plate without a GUID and across camera recycles.
    if isPet then LearnPetUnit(unit) end
    -- A pet's UnitClass is its creature class (warrior/paladin), never shown.
    local classFile = not isPet and select(2, UnitClass(unit)) or nil
    local talent = not isPet and addon.TalentScanner and addon.TalentScanner:Get(guid)
    if talent and talent.stale then talent = nil end
    if talent and classFile and talent.class ~= classFile then talent = nil end
    -- a disk record is from an earlier session: a live proven signature wins
    local fromDisk = talent and addon.TalentScanner.IsFromDisk
        and addon.TalentScanner:IsFromDisk(guid) or false
    local dropSpec = false
    if fromDisk then
        local live = enemySpecByGUID[guid] or friendlySpecByGUID[guid]
        if live and not live.weak and not live.classOnly and live.spec
            and live.spec ~= talent.spec then
            talent, dropSpec = nil, true
        end
    end
    local old = cacheByGUID[guid] or {}
    if classFile and old.class and old.class ~= classFile then old = {} end
    -- A visible druid's current shapeshift is a live fact read from his buffs,
    -- even when he never casts (a level 12 bear standing still). Only druids are
    -- scanned, so this costs a handful of UnitBuff calls per refresh.
    local formKind = (classFile == "DRUID" and addon.UnitFormKind) and addon.UnitFormKind(unit) or nil
    -- The talent build is the last word on a druid's FORM, not the shapeshift we
    -- happen to see: a cat-talent druid who shifts to bear to survive is still a
    -- cat, and a bear-talent druid who shifts to cat to travel is still a bear.
    -- Only a build read in THIS session locks the form; a build restored from
    -- disk is older than the shapeshift in front of us, so the live form wins
    -- there until the next real inspection.
    local talentKind = talent and talent.feralKind or nil
    local freshBuild = talent and talent.spec and not fromDisk
    local feralKind, feralLock
    if freshBuild and talent.spec ~= "FERAL" then
        feralKind = nil                    -- Balance/Restoration: not a feral at all
    elseif freshBuild and talentKind then
        feralKind, feralLock = talentKind, true
    else
        feralKind = formKind or talentKind -- ambiguous build: the form we can see
    end
    local inspectedRole = talent and talent.specRole or nil
    -- an inspected/group-comm role always wins; before it is
    -- known the queued LFD role, then a self-cast healer aura, decide.
    local isHealer, isTank
    if talent and talent.spec then
        isHealer, isTank = inspectedRole == "HEALER", inspectedRole == "TANK"
    elseif not isPet then
        local role = AssignedRole(unit)
        isHealer = role == "HEALER" or (role == nil and (UnitHasHealerAura(unit) or old.isHealer == true))
        isTank = role == "TANK" or (role == nil and old.isTank == true)
    end
    local data = {
        name = name,
        class = classFile or old.class or (talent and talent.class),
        isHealer = isHealer == true,
        isTank = isTank == true,
        isPet = isPet,
        -- when a stale disk spec was dropped, do not resurrect the copy that was
        -- already in the cache: the live signature is what we know now.
        spec = talent and talent.spec or ((not dropSpec and old.spec) or nil),
        specTexture = talent and talent.specTexture or ((not dropSpec and old.specTexture) or nil),
        specRole = inspectedRole or ((not dropSpec and old.specRole) or nil),
        feralKind = feralKind,
        feralLock = feralLock or nil,
        fromDisk = fromDisk or nil,
        _specDisplayAt = old._specDisplayAt,
        _specDisplaySpec = old._specDisplaySpec,
    }
    -- A shapeshift only means something for a Feral: every druid can enter Cat
    -- and Bear Form, so a Balance druid who shifts to bear to survive is still
    -- Balance - and must never be drawn as a tank.
    if data.spec and data.spec ~= "FERAL" then data.feralKind = nil end
    cacheByGUID[guid] = data
    if addon.ApplyFeralIdentity then addon.ApplyFeralIdentity(data, addon.IsAssignedGroupTank(unit)) end
    -- Pet names ("Wolf", "Imp") are not unique; pets never enter the name cache.
    if name and name ~= "" and not isPet then cacheByName[name] = data end
    -- A visible unit is a real read of the CLASS even when no talent record
    -- exists (out of inspect range, never cast a spell). Store it so the class
    -- icon survives a reload. Remember never downgrades a spec, so this can only
    -- fill a class that was not known yet. The player himself is not "another
    -- player" and is not stored.
    if addon.SpecMemory and not isPet and data.class and unit ~= "player" then
        local role = data.specRole
        if data.class == "DRUID" and data.spec == "FERAL"
            and (data.isTank or data.feralKind == "BEAR") then
            role = "TANK"
        end
        addon.SpecMemory:Remember(guid, name, data.class, data.spec, false, role)
    end
end

-- names of the pets of the player, his group and arena
-- opponents. Render-only, for an NPC-type plate whose GUID is unknown (stock
-- client before any hover); never used to bind a GUID or store identity.
local friendlyPetNames, enemyPetNames = {}, {}

-- render-only pet/guardian memory, used to colour a pet border by its
-- owner's class and to redraw a pet plate after the camera recycles it (stock
-- client). Never binds a GUID and never enters the player caches.
--   petOwnerClassByGUID[petGUID]  = ownerClassFile
--   petOwnerClassByName[petName]  = ownerClassFile, or false when ambiguous
--   petSuppressGUID[petGUID]      = true  (Army of the Dead ghouls: no icon)
local petOwnerClassByGUID, petOwnerClassByName = {}, {}
local petSuppressGUID = {}
local petInfoCount = 0

-- 3.3.5a: Army of the Dead summons. These ghouls are excluded from icons.
local ARMY_OF_THE_DEAD_SPELLS = { [42650] = true, [42651] = true }
local ARMY_GHOUL_NPC = 24207

-- player guardians are 0xF13 creatures like totems and world NPCs, so
-- only these creature IDs (each summoned by exactly one class) get a pet icon.
-- Totems, vehicles and every other NPC are not listed and never get an icon.
local GUARDIAN_OWNER_CLASS = {
    [29264] = "SHAMAN",      -- Spirit Wolf (Feral Spirit)
    [15438] = "SHAMAN",      -- Greater Fire Elemental
    [15352] = "SHAMAN",      -- Greater Earth Elemental
    [19668] = "PRIEST",      -- Shadowfiend
    [1964]  = "DRUID",       -- Treant (Force of Nature)
    [510]   = "MAGE",        -- Water Elemental
    [26125] = "DEATHKNIGHT", -- Ghoul (Raise Dead)
    [27829] = "DEATHKNIGHT", -- Ebon Gargoyle
    [89]    = "WARLOCK",     -- Infernal
    [11859] = "WARLOCK",     -- Doomguard
}

local function IsGuardianGUID(guid)
    -- Guardians/totems/elementals are 0xF13 creatures (not 0xF14 pets).
    return type(guid) == "string" and guid:sub(3, 5):upper() == "F13"
end

-- 3.3.5a creature GUID: 0xF130 + 24-bit creature ID + 24-bit spawn counter.
local function CreatureID(guid)
    if not IsGuardianGUID(guid) then return nil end
    return tonumber(guid:sub(7, 12), 16)
end

local function GuardianClass(guid)
    local id = CreatureID(guid)
    return id and GUARDIAN_OWNER_CLASS[id] or nil
end

local function IsSuppressedPetGUID(guid)
    return guid ~= nil and (petSuppressGUID[guid] == true or CreatureID(guid) == ARMY_GHOUL_NPC)
end

local function NotePetOwner(petGUID, petName, ownerClass)
    if not ownerClass then return false end
    local changed = false
    if petGUID and petOwnerClassByGUID[petGUID] ~= ownerClass then
        if petOwnerClassByGUID[petGUID] == nil then
            petInfoCount = petInfoCount + 1
            if petInfoCount > 4000 then
                wipe(petOwnerClassByGUID); wipe(petOwnerClassByName); petInfoCount = 1
            end
        end
        petOwnerClassByGUID[petGUID] = ownerClass
        changed = true
    end
    if petName and petName ~= "" and petName ~= UNKNOWN then
        local prev = petOwnerClassByName[petName]
        if prev == nil then
            petOwnerClassByName[petName] = ownerClass
        elseif prev ~= ownerClass then
            petOwnerClassByName[petName] = false -- same name, two owner classes
        end
    end
    return changed
end

local petOwnerNameByGUID = {}
local petOwnerNameByPetName = {} -- petName -> ownerName, or false when ambiguous
local function PetOwnerClass(guid, name)
    local c = guid and (petOwnerClassByGUID[guid] or GuardianClass(guid))
    if c then return c end
    -- owner named by the pet tooltip but unknown back then; he may be
    -- known now (hovered later), so the pet updates without another hover.
    local ownerName = guid and petOwnerNameByGUID[guid] or (name and petOwnerNameByPetName[name])
    local cached = ownerName and cacheByName[ownerName]
    if cached and cached.class then
        NotePetOwner(guid, name, cached.class)
        return cached.class
    end
    if name then
        local byName = petOwnerClassByName[name]
        if byName then return byName end
    end
    return nil
end

local function RebuildPetNames()
    wipe(friendlyPetNames); wipe(enemyPetNames)
    local function add(set, petUnit, ownerUnit)
        if UnitExists(petUnit) and not UnitIsPlayer(petUnit) then
            local guid = UnitGUID(petUnit)
            -- A player riding a cannon or demolisher occupies his pet token, so
            -- the vehicle's name would enter the pet-name set and every empty
            -- vehicle on the field would then match KnownPetName and draw a pet
            -- icon. Vehicles are never pets: keep them out of the set entirely.
            if not IsVehicleGUID(guid) then
                local name = UnitName(petUnit)
                if name and name ~= "" and name ~= UNKNOWN then
                    set[name] = true
                    local ownerClass = ownerUnit and UnitExists(ownerUnit) and select(2, UnitClass(ownerUnit)) or nil
                    NotePetOwner(guid, name, ownerClass)
                end
            end
        end
    end
    add(friendlyPetNames, "pet", "player")
    for i = 1, 4 do add(friendlyPetNames, "partypet" .. i, "party" .. i) end
    for i = 1, GetNumRaidMembers and GetNumRaidMembers() or 0 do add(friendlyPetNames, "raidpet" .. i, "raid" .. i) end
    for i = 1, 5 do add(enemyPetNames, "arenapet" .. i, "arena" .. i) end
end

-- (H client): pet names seen on a hovered/targeted pet unit, by reaction.
-- The stock client often never ties a pet plate to a GUID on a quick hover, and
-- a camera move recycles the plate. Remembering the confirmed pet's name lets
-- the GUID-less NPC plate redraw at once, like players do by name. Render-only.
local seenFriendlyPetNames, seenEnemyPetNames = {}, {}
local seenPetCount = 0

-- the owner of a hovered/targeted pet, read from a private scanning
-- tooltip ("<Owner>'s Pet/Minion/Guardian", localized client strings). Only for
-- pet units without a known owner, so it runs at most once per pet GUID.
local ownerPatterns
local scanTip
local function OwnerNameFromTooltip(unit)
    if not CreateFrame then return nil end
    if not ownerPatterns then
        ownerPatterns = {}
        for _, key in ipairs({ "UNITNAME_TITLE_PET", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_GUARDIAN",
            "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_COMPANION" }) do
            local fmt = _G[key]
            if type(fmt) == "string" and fmt:find("%s", 1, true) then
                local escaped = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
                local pattern = escaped:gsub("%%s", "(.+)")
                ownerPatterns[#ownerPatterns + 1] = "^" .. pattern .. "$"
            end
        end
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "OPlatesScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetUnit(unit)
    local owner
    for line = 2, math.min(scanTip:NumLines() or 0, 3) do
        local fs = _G["OPlatesScanTipTextLeft" .. line]
        local text = fs and fs:GetText()
        if text then
            for _, pattern in ipairs(ownerPatterns) do
                owner = text:match(pattern)
                if owner then break end
            end
        end
        if owner then break end
    end
    scanTip:Hide()
    return owner
end

-- (H client): the owner class read from the pet unit itself, locale-free.
-- Only real pets (0xF14): a focus pet is a hunter's, an energy pet is a death
-- knight's ghoul, a mana pet with a creature family is a warlock's demon and a
-- mana pet without one is a mage's (glyphed) Water Elemental. Anything else
-- stays unknown (black border until the owner is known).
local function PetOwnerClassFromUnit(unit, guid)
    if not IsPetGUID(guid) or not UnitPowerType then return nil end
    local power = UnitPowerType(unit)
    if power == 2 then return "HUNTER" end
    if power == 3 then return "DEATHKNIGHT" end
    if power == 0 and UnitCreatureFamily then
        return UnitCreatureFamily(unit) and "WARLOCK" or "MAGE"
    end
    return nil
end
addon.PetOwnerClassFromUnit = PetOwnerClassFromUnit

LearnPetUnit = function(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not (IsPetGUID(guid) or GuardianClass(guid)) then return end
    if IsSuppressedPetGUID(guid) then return end
    local name = UnitName(unit)
    local guardianClass = GuardianClass(guid)
    if guardianClass then NotePetOwner(guid, name, guardianClass) end
    if not name or name == "" or name == UNKNOWN then return end
    local set = UnitIsFriend("player", unit) and seenFriendlyPetNames or seenEnemyPetNames
    if not set[name] then
        seenPetCount = seenPetCount + 1
        if seenPetCount > 2000 then
            wipe(seenFriendlyPetNames); wipe(seenEnemyPetNames); wipe(petOwnerNameByGUID); wipe(petOwnerNameByPetName); seenPetCount = 1
        end
        set[name] = true
    end
    if not petOwnerClassByGUID[guid] and petOwnerNameByGUID[guid] == nil then
        petOwnerNameByGUID[guid] = OwnerNameFromTooltip(unit) or false
    end
    local ownerName = petOwnerNameByGUID[guid]
    if ownerName then
        local prev = petOwnerNameByPetName[name]
        if prev == nil then petOwnerNameByPetName[name] = ownerName
        elseif prev ~= ownerName then petOwnerNameByPetName[name] = false end
    end
    if ownerName and not petOwnerClassByGUID[guid] then
        local ownerUnit = FindUnitByName(ownerName)
        local ownerClass = ownerUnit and UnitIsPlayer(ownerUnit) and select(2, UnitClass(ownerUnit))
        local cached = not ownerClass and cacheByName[ownerName]
        ownerClass = ownerClass or (cached and cached.class)
            or (enemySpecByName[ownerName] and enemySpecByName[ownerName].class) or nil
        if ownerClass then NotePetOwner(guid, name, ownerClass) end
    end
    if not petOwnerClassByGUID[guid] then
        NotePetOwner(guid, name, PetOwnerClassFromUnit(unit, guid))
    end
end

-- is this GUID-less NPC plate a known pet (render-only, by name)?
local function KnownPetName(name, friendly)
    if not name then return false end
    if friendly then return friendlyPetNames[name] or seenFriendlyPetNames[name] or false end
    return enemyPetNames[name] or seenEnemyPetNames[name] or false
end

-- is this GUID a pet/guardian that gets an icon?
local function IsIconPetGUID(guid)
    if not guid or IsSuppressedPetGUID(guid) or IsVehicleGUID(guid) then return false end
    return IsPetGUID(guid) or GuardianClass(guid) ~= nil
end

local function RememberAllUnits()
    RememberUnit("player")
    RememberUnit("pet")
    RememberUnit("target")
    RememberUnit("focus")
    RememberUnit("mouseover")
    for i = 1, 4 do
        RememberUnit("party" .. i)
        RememberUnit("partypet" .. i)
    end
    for i = 1, 40 do
        RememberUnit("raid" .. i)
        RememberUnit("raidpet" .. i)
    end
    for i = 1, 5 do
        RememberUnit("arena" .. i)
        RememberUnit("arenapet" .. i)
    end
end

local function ScanFlag(unit, guid)
    if not unit or not guid or not UnitExists(unit) then return end
    local i = 1
    while true do
        local name, _, icon, _, _, _, _, _, _, _, spellID = UnitBuff(unit, i)
        if not name then break end
        local faction = spellID and addon.FLAG_AURAS[spellID] or FLAG_NAMES[name]
        if faction then
            SetFlagCarrier(guid, UnitName(unit), faction, icon)
            return
        end
        i = i + 1
    end
    ClearFlagCarrier(guid)
end

-- IDs of every rank, then the localized name (any client
-- language, server-specific IDs). Also used by Healer-in-CC (noRoots = true).
-- every CC debuff on the unit; the caller picks the one to draw.
local function AllUnitCC(unit, noRoots)
    local list = {}
    if not unit then return list end
    local i = 1
    while true do
        local name, _, icon, _, debuffType, duration, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end
        local category = addon.GetCrowdControlCategory(spellId, name)
        if category and not (noRoots and (category == "root" or category == "disarm")) then
            local start = duration and duration > 0 and expirationTime and expirationTime - duration or nil
            list[#list + 1] = { icon = icon, spellID = spellId, category = category, debuffType = debuffType,
                start = start, duration = start and duration or nil, expires = start and expirationTime or nil,
                priority = addon.CrowdControlPriority(category, spellId), order = i }
        end
        i = i + 1
    end
    return list
end

-- highest priority wins; a tie goes to the newest (later start, then later slot).
local function NewerCC(e, best)
    if e.priority ~= best.priority then return e.priority > best.priority end
    if (e.start or 0) ~= (best.start or 0) then return (e.start or 0) > (best.start or 0) end
    return e.order > best.order
end

local function GetBestCC(unit, noRoots)
    local best
    for _, e in ipairs(AllUnitCC(unit, noRoots)) do
        if not best or NewerCC(e, best) then best = e end
    end
    if not best then return nil end
    return best.icon, best.spellID, best.start, best.duration, best.category, best.debuffType
end
addon.GetUnitCrowdControl = GetBestCC

-- parsed whitelists are cached by their text (a few entries at most).
local parsedLists, parsedCount = {}, 0
local function ParseList(text)
    text = text or ""
    local set = parsedLists[text]
    if set then return set end
    set = {}
    for id in string.gmatch(text, "%d+") do
        set[tonumber(id)] = true
    end
    if parsedCount >= 8 then wipe(parsedLists); parsedCount = 0 end
    parsedLists[text], parsedCount = set, parsedCount + 1
    return set
end

-- each side has its own whitelists.
local function SideLists(cfg, enemy)
    if enemy then return ParseList(cfg.enemyBuffWhitelist), ParseList(cfg.enemyDebuffWhitelist) end
    return ParseList(cfg.buffWhitelist), ParseList(cfg.debuffWhitelist)
end

-- the longest real duration read for a spell (stock-client estimate
-- for spells without a base duration). Bounded.
local function LearnDuration(spellId, duration)
    if not spellId or not duration or duration <= 0 then return end
    local old = learnedDuration[spellId]
    if old and old >= duration then return end
    if not old then
        learnedCount = learnedCount + 1
        if learnedCount > 500 then wipe(learnedDuration); learnedCount = 1 end
    end
    learnedDuration[spellId] = duration
end

-- per side; no aura is scanned when that side wants none.
local function GetWhitelistedAura(unit, cfg, enemy)
    if not unit then return nil end
    local _, auraOn, wantBuffs, wantDebuffs = AuraSettings(cfg, enemy)
    if not auraOn then return nil end
    local buffSet, debuffSet = SideLists(cfg, enemy)
    wantBuffs = wantBuffs and next(buffSet) ~= nil
    wantDebuffs = wantDebuffs and next(debuffSet) ~= nil
    if not wantBuffs and not wantDebuffs then return nil end
    local best
    local function consider(icon, spellID, duration, expirationTime, kind, priority)
        if spellID and icon then LearnDuration(spellID, duration) end
        if spellID and icon and (not best or priority > best.priority) then
            local start = duration and duration > 0 and expirationTime and expirationTime - duration or nil
            best = { icon = icon, spellID = spellID, start = start, duration = start and duration or nil,
                expires = start and expirationTime or nil, kind = kind, priority = priority, exact = true }
        end
    end
    if wantDebuffs then
        local i = 1
        while true do
            local name, _, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
            if not name then break end
            if debuffSet[spellId] then
                consider(icon, spellId, duration, expirationTime, "debuff", 500)
            end
            i = i + 1
        end
    end
    if wantBuffs then
        local i = 1
        while true do
            local name, _, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
            if not name then break end
            if buffSet[spellId] then
                consider(icon, spellId, duration, expirationTime, "buff", 250)
            end
            i = i + 1
        end
    end
    return best
end

-- a real aura read (exact; replaces any estimate). A side whose icons
-- are disabled keeps nothing and scans nothing.
-- the CC drawn for a player is the highest-priority entry of ccStackByGUID
-- (every CC on him). An exact entry whose real expiry has passed is dropped, so
-- the next CC in the stack takes over at once. Estimates never end by timer.
-- the class is kept with the name (stock GetPlayerInfoByGUID or a live
-- UnitClass) so a plate of another class never uses that name's store.
local function NoteAuraName(guid, name, classFile)
    -- every caller has already established that the GUID is a player: SyncAuras
    -- checks UnitIsPlayer, NamesAndDeaths checks the combat-log player flag. The
    -- old 0x0000 test here rejected every Warmane player and left the name map
    -- empty, which killed the by-name CC lookup for GUID-less plates.
    if type(name) ~= "string" or name == "" then return end
    if name == UNKNOWNOBJECT or name == UNKNOWN then return end
    if not auraClassByGUID[guid] then
        if not classFile and GetPlayerInfoByGUID then
            local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
            if ok then classFile = c end
        end
        if type(classFile) == "string" and classFile ~= "" then auraClassByGUID[guid] = classFile end
    end
    -- The client's own answer is authoritative. If a class was inferred from a
    -- spell id before this player ever appeared in a unit token, correct it here:
    -- a bare class is simply replaced, and a stored spec of the wrong class is
    -- dropped (it can only have come from a shared spell name).
    local apiClass = auraClassByGUID[guid]
    if type(apiClass) == "string" then
        local enemy = enemySpecByGUID[guid]
        if enemy and enemy.classOnly and enemy.class ~= apiClass then
            enemy.class = apiClass
        elseif enemy and enemy.class ~= apiClass then
            enemySpecByGUID[guid] = nil
        end
        local friendly = friendlySpecByGUID[guid]
        if friendly and friendly.classOnly and friendly.class ~= apiClass then
            friendly.class = apiClass
        elseif friendly and friendly.class ~= apiClass then
            friendlySpecByGUID[guid] = nil
        end
    end
    local short = ShortName(name)
    if auraNameByGUID[guid] == short then return end
    if not auraNameByGUID[guid] then
        auraNameCount = auraNameCount + 1
        if auraNameCount > 2000 then
            wipe(auraGUIDsByName); wipe(auraNameByGUID); wipe(auraClassByGUID); auraNameCount = 1
            if type(classFile) == "string" and classFile ~= "" then auraClassByGUID[guid] = classFile end
        end
    end
    auraNameByGUID[guid] = short
    local set = auraGUIDsByName[short]
    if not set then set = {}; auraGUIDsByName[short] = set end
    set[guid] = true
    if addon._debugEnabled then
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        D("AURANAME", "name=%s guid=%s class=%s candidates=%d", tostring(short), tostring(guid),
            tostring(auraClassByGUID[guid]), n)
    end
end

-- The class we believe a GUID has, from the strongest source available: a live
-- unit, a learned enemy spec, or the class the combat log gave us.
local function KnownClass(guid)
    return (cacheByGUID[guid] and cacheByGUID[guid].class)
        or (enemySpecByGUID[guid] and enemySpecByGUID[guid].class)
        or auraClassByGUID[guid]
end

local function PickCC(guid, now)
    local stack = ccStackByGUID[guid]
    if not stack then ccByGUID[guid] = nil; return nil end
    local best
    for spellID, e in pairs(stack) do
        if (e.exact and e.expires and e.expires <= now)
            or (not e.exact and e.start and now - e.start >= CC_STALE_AFTER) then
            stack[spellID] = nil
        elseif not best or e.priority > best.priority
            or (e.priority == best.priority and (e.start or 0) > (best.start or 0)) then
            best = e
        end
    end
    if not next(stack) then ccStackByGUID[guid] = nil end
    ccByGUID[guid] = best
    return best
end

local function SyncAuras(unit)
    if not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local cfg = DB()
    local enemy = not UnitIsFriend("player", unit)
    if not SideEnabled(cfg, enemy) then
        ccStackByGUID[guid], ccByGUID[guid], auraByGUID[guid] = nil, nil, nil
        return
    end
    -- a unit out of visibility range reads no auras; keep the store.
    if UnitIsVisible and not UnitIsVisible(unit) then return end
    if UnitIsPlayer(unit) then NoteAuraName(guid, UnitName(unit), select(2, UnitClass(unit))) end
    local showCC = AuraSettings(cfg, enemy)
    local now = GetTime()
    local stack
    if showCC then
        for _, e in ipairs(AllUnitCC(unit)) do
            stack = stack or {}
            stack[e.spellID] = { icon = e.icon, spellID = e.spellID, category = e.category, priority = e.priority,
                start = e.start, duration = e.duration, expires = e.expires, exact = true }
            if e.spellID and not addon.CrowdControlBaseDuration[e.spellID] then LearnDuration(e.spellID, e.duration) end
        end
        -- the combat log can report a CC a moment before the unit's aura
        -- list shows it; such an entry (under 1 s old) survives this read.
        local old = ccStackByGUID[guid]
        if old then
            for spellID, e in pairs(old) do
                if not e.exact and now - (e.start or 0) < 1 and not (stack and stack[spellID]) then
                    stack = stack or {}
                    stack[spellID] = e
                end
            end
        end
    end
    ccStackByGUID[guid] = stack
    PickCC(guid, now)
    local aura = GetWhitelistedAura(unit, cfg, enemy)
    local oldAura = auraByGUID[guid]
    if not aura and oldAura and not oldAura.exact and now - (oldAura.start or 0) < 1 then aura = oldAura end
    auraByGUID[guid] = aura
end

-- any unit token that is this GUID right now (exact UnitGUID check):
-- target/focus/mouseover and their targets, group/arena units, the awesome_wotlk
-- plate unit (option ON only), then each party/raid member's target.
local SELF_TOKENS = { "target", "focus", "mouseover", "targettarget", "focustarget", "pettarget" }
local partyTargets, raidTargets = {}, {}
for i = 1, 4 do partyTargets[i] = "party" .. i .. "target" end
for i = 1, 40 do raidTargets[i] = "raid" .. i .. "target" end
local function ExactUnitForGUID(guid)
    if not guid then return nil end
    for i = 1, #SELF_TOKENS do
        if UnitGUID(SELF_TOKENS[i]) == guid then return SELF_TOKENS[i] end
    end
    local u = FindUnitByGUID(guid)
    if u then return u end
    local scanner = addon.TalentScanner
    if scanner and scanner.plateMode and scanner.PlateUnitForGUID then
        u = scanner:PlateUnitForGUID(guid)
        if u and UnitGUID(u) == guid then return u end
    end
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local list, n = raidTargets, raid
    if raid == 0 then list, n = partyTargets, GetNumPartyMembers and GetNumPartyMembers() or 0 end
    for i = 1, math.min(n, #list) do
        if UnitGUID(list[i]) == guid then return list[i] end
    end
end

-- an estimated/guessed CC or aura on top gets an exact read from any
-- token at most every 0.5 s per GUID.
local function TryExactUpgrade(guid, now)
    if not guid then return end
    local top = ccByGUID[guid] or auraByGUID[guid]
    if not top or top.exact or (upgradeAt[guid] or 0) > now then return end
    if not upgradeAt[guid] then
        upgradeCount = upgradeCount + 1
        if upgradeCount > 500 then wipe(upgradeAt); upgradeCount = 1 end
    end
    upgradeAt[guid] = now + 0.5
    local u = ExactUnitForGUID(guid)
    if u then SyncAuras(u) end
end

-- the CC/aura store key of a GUID-less player plate, by its name
-- (render-only). A known class that differs from the plate's class rejects it.
--
-- A short name is not proof of identity: cross-realm servers hand out the same
-- name to different players. So the name map is a set of candidates, narrowed
-- by class, and only used when exactly one candidate survives. Anything that
-- stays ambiguous returns nil on purpose - a missing icon is a nuisance, an
-- icon on the wrong player is a lie. Returns the GUID, plus a reason for the
-- debug log.
local function AuraKeyForPlate(name, classFile)
    if type(name) ~= "string" or name == "" then return nil end
    local short = ShortName(name)
    local set = auraGUIDsByName[short]
    local total, accept, acceptN, classHit, classHitN = 0, nil, 0, nil, 0
    if set then
        for guid in pairs(set) do
            total = total + 1
            local known = KnownClass(guid)
            if not classFile or not known or known == classFile then
                accept, acceptN = guid, acceptN + 1
            end
            if classFile and known == classFile then
                classHit, classHitN = guid, classHitN + 1
            end
        end
    end
    local g, why
    if acceptN == 1 then
        g, why = accept, "single"
    elseif classHitN == 1 then
        g, why = classHit, "class"
    elseif total == 0 then
        -- The name map is filled from the combat log and can lag behind a plate
        -- that appears before its owner is seen in an event. When it knows
        -- nothing at all, every CC entry still remembers the short name and
        -- class it was applied to, so the store itself is the fallback - and it
        -- is only trusted when exactly one player matches.
        local hit, hitN = nil, 0
        for guid, stack in pairs(ccStackByGUID) do
            for _, e in pairs(stack) do
                if e.shortName == short then
                    local known = e.class or KnownClass(guid)
                    if not classFile or not known or known == classFile then
                        hit, hitN = guid, hitN + 1
                    end
                    break
                end
            end
        end
        if hitN == 1 then g, why = hit, "store" elseif hitN > 1 then why = "store-ambiguous" end
    else
        -- Two players share the name and the plate does not tell us which one
        -- it is. Guessing here is how a stun ends up on the wrong player, so
        -- leave it blank until a class narrows it.
        why = "ambiguous"
    end
    if g then
        if not (ccStackByGUID[g] or auraByGUID[g]) then g, why = nil, "empty" end
    end
    -- "empty" and "none" are not decisions: they are the normal state of a
    -- player who has no CC or aura to draw. Logging them buried the capture
    -- under thousands of lines and pushed the useful ones out of the scrollback.
    if addon._debugEnabled and why ~= "empty" and (g ~= nil or why ~= nil) then
        DCompact("AURAPICK", short, "name=%s class=%s candidates=%d picked=%s why=%s",
            tostring(short), tostring(classFile), total, tostring(g), tostring(why or "none"))
    end
    if not g then return nil end
    local known = KnownClass(g)
    if classFile and known and known ~= classFile then return nil end
    return g
end
-- exposed so tests/dupe_name.js can drive the resolver through the real combat
-- log without going through the render pipeline. Not used by the addon.
addon.DebugAuraKeyForPlate = AuraKeyForPlate

local function HideOverlay(plate)
    local ov = plates[plate]
    if not ov then return end
    ov:Hide()
    ov.icon:Hide()
    ov.colorBorder:Hide()
    ov.nameText:Hide()
    ov.arenaText:Hide()
    ov.ccTimerText:Hide()
    ov._ccTimerExpires = nil
    ov._auraDropAt = nil
    ov.isTarget = false
    -- Keep the overlay OnUpdate alive while hidden. The overlay can be recycled by
    -- LibNameplates when the camera moves, and the class-to-spec transition timer is
    -- deliberately persistent across hide/show cycles.
end

local function CreateOverlay(plate)
    local f = CreateFrame("Button", nil, plate)
    f:SetFrameStrata("HIGH")
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetPoint("BOTTOM", plate, "TOP", 0, 8)
    f:EnableMouse(false)
    f.plate = plate
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.colorBorder = f:CreateTexture(nil, "OVERLAY")
    f.colorBorder:SetTexture(addon.CLASS_ICON_BORDER)
    f.colorBorder:SetTexCoord(unpack(addon.CLASS_ICON_BORDER_TCOORDS))
    f.colorBorder:SetSize(ICON_SIZE * (addon.CLASS_ICON_BORDER_OUTSET or 1.10), ICON_SIZE * (addon.CLASS_ICON_BORDER_OUTSET or 1.10))
    f.colorBorder:SetPoint("CENTER", f, "CENTER")
    f.colorBorder:Hide()
    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.nameText:Hide()
    f.arenaText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.arenaText:SetTextColor(1, 1, 0)
    f.arenaText:SetPoint("CENTER", f, "BOTTOM", 0, -11)
    f.arenaText:Hide()
    -- coloured remaining time in the centre of a CC/aura icon. A plain
    -- FontString (no Cooldown frame, no swipe: the icons are circular).
    f.ccTimerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.ccTimerText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    f.ccTimerText:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.ccTimerText:Hide()
    f:SetScript("OnUpdate", function(self, elapsed)
        local cfg = DB()
        local now = GetTime()
        if self._ccTimerExpires and now >= (self._ccTimerNext or 0) then
            self._ccTimerNext = now + 0.1
            local remain = self._ccTimerExpires - now
            if remain > 0 then
                local text, r, g, b = addon.FormatCountdown(remain)
                self.ccTimerText:SetText(text)
                self.ccTimerText:SetTextColor(r, g, b)
            else
                self._ccTimerExpires = nil
                self.ccTimerText:Hide()
            end
        end
        -- a real token read's CC or aura icon ends at its real expiry.
        if self._auraDropAt and now >= self._auraDropAt then
            self._auraDropAt = nil
            if self.plate and self:IsShown() then UpdatePlate(self.plate) end
        end
        if self._specTransitionAt and now >= self._specTransitionAt and cfg.showClassIcon ~= false and cfg.showSpec ~= false then
            local transitionGUID = self._specTransitionGUID
            self._specTransitionAt = nil
            self._specTransitionGUID = nil
            if transitionGUID then if addon._debugEnabled then D("DISPLAY", "OnUpdate deadline reached guid=%s now=%.3f", tostring(transitionGUID), now) end end
            if transitionGUID and self._guid == transitionGUID and self.plate then
                UpdatePlate(self.plate)
            elseif transitionGUID and addon.RequestRefreshNameplateOverlayGUID then
                addon:RequestRefreshNameplateOverlayGUID(transitionGUID)
            elseif addon.RequestRefreshNameplateOverlays then
                addon:RequestRefreshNameplateOverlays()
            elseif addon.RefreshNameplateOverlays then
                addon.RefreshNameplateOverlays()
            end
        end
        if not self.isTarget then return end
        self._pulse = (self._pulse or 0) + elapsed
        local a = 0.68 + 0.32 * (0.5 + 0.5 * math.sin(self._pulse * 5.5))
        self.colorBorder:SetAlpha(a)
    end)
    f:Hide()
    return f
end

local function EnsureOverlay(plate)
    if not plates[plate] then plates[plate] = CreateOverlay(plate) end
    return plates[plate]
end

local function SizeBorderToIcon(ov)
    local outset = addon.CLASS_ICON_BORDER_OUTSET or 1.10
    local w = ICON_SIZE * outset
    ov.colorBorder:ClearAllPoints()
    ov.colorBorder:SetSize(w, w)
    ov.colorBorder:SetPoint("CENTER", ov, "CENTER")
end

local function ApplyBaseBorder(ov, classFile, target, question)
    SizeBorderToIcon(ov)
    if target then
        ov.colorBorder:SetVertexColor(1, 0.92, 0.20, 1)
        ov.colorBorder:Show()
        -- restart the pulse only when the plate becomes the target, not on
        -- every refresh (that restart made the pulse irregular).
        if not ov.isTarget then ov._pulse = 0 end
        ov.isTarget = true
        ov:SetFrameStrata("DIALOG")
    elseif question then
        ov.colorBorder:SetVertexColor(0.35, 0.35, 0.35, 1)
        ov.colorBorder:SetAlpha(1)
        ov.colorBorder:Show()
        ov.isTarget = false
        ov:SetFrameStrata("HIGH")
    elseif classFile then
        local r, g, b = addon.GetClassColor(classFile)
        ov.colorBorder:SetVertexColor(r, g, b, 1)
        ov.colorBorder:SetAlpha(1)
        ov.colorBorder:Show()
        ov.isTarget = false
        ov:SetFrameStrata("HIGH")
    else
        ov.colorBorder:Hide()
        ov.isTarget = false
        ov:SetFrameStrata("HIGH")
    end
end

-- "Icon scale" sizes only the ?/class/spec/tank icons. Healer, pet and
-- flag icons use only their own scale slider.
local OWN_SCALE_KINDS = { HEALER = true, PET = true, FLAG = true }
local function IconKindScale(baseScale, iconKind, iconScale)
    if OWN_SCALE_KINDS[iconKind] then return iconScale or 1 end
    return baseScale * (iconScale or 1)
end
addon.IconKindScale = IconKindScale

local function SelectDisplayMode(cfg, enemy, isHealer, isTank, isPet, hasFlag, hasSpec)
    local mode = CurrentDisplayMode(cfg, enemy)
    if mode == "ALL" then return true end
    if AURA_MODES[mode] then return false end
    if mode == "HEALER" then return isHealer end
    if mode == "TANK" then return isTank end
    if mode == "PET" then return isPet end
    if mode == "FLAG" then return hasFlag end
    if mode == "CLASS" then return not isPet end
    if mode == "CLASS_SPEC" then return (not isPet) and hasSpec end
    return true
end

-- centre number only for a real aura duration (a combat-log CC whose
-- duration is guessed shows none), and only while its option is on.
local function SetCenterTimer(ov, enemy, start, duration, guessed)
    local cfg = DB()
    local on
    if enemy then on = cfg.enemyCrowdControlTimer ~= false else on = cfg.crowdControlTimer ~= false end
    local expires = on and not guessed and start and duration and duration > 0 and start + duration
    if expires and expires > GetTime() then
        ov._ccTimerExpires, ov._ccTimerNext = expires, 0
        local text, r, g, b = addon.FormatCountdown(expires - GetTime())
        ov.ccTimerText:SetText(text)
        ov.ccTimerText:SetTextColor(r, g, b)
        ov.ccTimerText:Show()
    else
        ov._ccTimerExpires = nil
        ov.ccTimerText:Hide()
    end
end
addon.NameplateSetCenterTimer = SetCenterTimer

-- an entry stays until its aura is removed (SPELL_AURA_REMOVED clears it,
-- and a live token read replaces it). An estimate only sets the centre number;
-- it never removes the icon. A real token read (exact) ends at its real expiry.
local function LiveEntry(store, guid, now)
    local e = store[guid]
    if not e then return nil end
    if e.exact and e.expires and e.expires <= now then store[guid] = nil; return nil end
    return e, e.exact and e.expires or nil
end

-- CC / whitelisted aura replacement, per side (AuraSettings). Sets
-- ov._auraDropAt so the overlay re-renders by itself when the icon ends.
local function ApplyAuraOverlay(ov, guid, unit, classFile, target, enemy)
    local cfg = DB()
    -- a GUID-less player plate looks the store up by its render-only key.
    guid = guid or ov._auraGUID
    local showCC, auraOn, wantBuffs, wantDebuffs = AuraSettings(cfg, enemy)
    local now = GetTime()
    local entry, dropAt
    if guid and showCC then
        PickCC(guid, now)
        entry, dropAt = LiveEntry(ccByGUID, guid, now)
        -- an unread CC re-renders when it goes stale (see CC_STALE_AFTER).
        if entry and not entry.exact and entry.start then dropAt = entry.start + CC_STALE_AFTER end
    end
    if not entry and guid and auraOn then
        local aura, auraDrop = LiveEntry(auraByGUID, guid, now)
        if aura then
            local buffSet, debuffSet = SideLists(cfg, enemy)
            if (aura.kind == "buff" and wantBuffs and buffSet[aura.spellID])
                or (aura.kind == "debuff" and wantDebuffs and debuffSet[aura.spellID]) then
                entry, dropAt = aura, auraDrop
            end
        end
    end
    if not entry then
        ov._auraDropAt = nil
        SetCenterTimer(ov, enemy, nil)
        return false
    end
    addon.SetCircularTexture(ov.icon, entry.icon)
    ov.icon:Show()
    if classFile then
        ApplyBaseBorder(ov, classFile, target, false)
    elseif target then
        ApplyBaseBorder(ov, nil, target, false)
    else
        ApplyBaseBorder(ov, nil, false, true)
    end
    SetCenterTimer(ov, enemy, entry.start, entry.duration, entry.guessed)
    ov._auraDropAt = dropAt
    return true, entry.spellID
end

local function IsTargetPlate(plate, unit)
    local targetGUID = UnitGUID("target")
    if not targetGUID then return false end
    local ov = plates[plate]
    local guid = LibNameplates and LibNameplates.GetGUID and LibNameplates:GetGUID(plate)
        or (ov and ov._guid)
    if guid then return guid == targetGUID end
    if unit and UnitIsUnit(unit, "target") then return true end
    -- (H client, GUID-less plates such as pets): the plate alpha is stale
    -- for a frame or two after a target change (with no target every plate is
    -- at alpha 1), so the plate name must also be the target's name.
    local name = LibNameplates and LibNameplates.GetName and LibNameplates:GetName(plate)
    if not name or name ~= UnitName("target") then return false end
    return (LibNameplates and LibNameplates.IsTarget and LibNameplates:IsTarget(plate)) or false
end
addon.IsTargetPlate = IsTargetPlate

local function FriendlyIconState(cfg, data, classFile, isPet, hasFlag, now, ov)
    -- Class Filters hide the class icon, Spec Filters the spec icon
    -- (a filtered spec falls back to the class icon). A player whose class or
    -- spec is filtered is known, so he never falls back to the ? icon.
    local classHidden = not isPet and IconFilter.ClassHidden(cfg, false, classFile)
    local specHidden = not isPet and data.specTexture ~= nil and IconFilter.SpecHidden(cfg, false, classFile, data.spec)
    local showClass = cfg.showClassIcon ~= false and not classHidden
    local showSpec = cfg.showSpec ~= false
    -- the ? is a fallback for an unknown PLAYER: never on a pet, and only
    -- while some identity icon on this side could replace it. The pet and lock
    -- checks come last so a profile with ? off pays nothing for them.
    local showUnknown = cfg.showUnknownFriendly ~= false and not classHidden and not specHidden
        and not isPet and not (data.guid and IsIconPetGUID and IsIconPetGUID(data.guid))
        and not addon.UnknownIconLocked(cfg, false)
    local hasSpec = data.specTexture ~= nil and not specHidden

    if not isPet and classFile == "DRUID" and data.spec == "FERAL" then
        -- a known Feral tank (assigned tank, or Bear talents) shows the
        -- TANK icon only while "Show tank icon" is on; otherwise Bear/Cat form.
        if (data.isTank or (data.spec == "FERAL" and data.feralKind == "BEAR"))
            and cfg.useTankIcon ~= false then
            data._specDisplayAt = nil
            data._specDisplaySpec = data.spec
            ov._specTransitionAt = nil
            ov._specTransitionGUID = nil
            return "TANK", addon.TANK_ICON, false, 1
        end
        -- Cat (and Bear with tank icons off) follow the normal
        -- class -> spec delay below; returning SPEC here would skip that delay.
    end
    -- Role icons are deliberately the highest non-CC priority. Once a healer/tank
    -- role is known, display that immediately instead of forcing CLASS -> SPEC -> ROLE.
    if not isPet and data.isHealer and cfg.useHealerIcon ~= false then
        data._specDisplayAt = nil
        data._specDisplaySpec = data.spec
        ov._specTransitionAt = nil
        ov._specTransitionGUID = nil
        return "HEALER", addon.HEALER_ICON, false, cfg.healerIconSize or 1.35
    end
    if not isPet and data.isTank and cfg.useTankIcon ~= false then
        data._specDisplayAt = nil
        data._specDisplaySpec = data.spec
        ov._specTransitionAt = nil
        ov._specTransitionGUID = nil
        return "TANK", addon.TANK_ICON, false, 1
    end

    -- If the user disables the class icon, a known spec is shown immediately.
    if hasSpec and showSpec and not showClass then
        ov._specTransitionAt = nil
        ov._specTransitionGUID = nil
        return "SPEC", data.specTexture, false, 1
    end

    if hasSpec and showSpec and showClass then
        if cfg.classToSpecDelayEnabled == false then
            data._specDisplayAt = nil
            data._specDisplaySpec = data.spec
            ov._specTransitionAt = nil
            ov._specTransitionGUID = nil
            return "SPEC", data.specTexture, false, 1
        end

        -- Persistent per-GUID state: the deadline lives on the cached player data,
        -- not on the recyclable nameplate overlay. Camera movement/nameplate reuse
        -- therefore cannot reset a learned player from SPEC back to CLASS.
        if data._specDisplaySpec ~= data.spec or not data._specDisplayAt then
            data._specDisplaySpec = data.spec
            ov._debugSpecCompleted = nil
            data._specDisplayAt = now + (tonumber(cfg.classToSpecDelay) or 1.0)
            if addon._debugWatchGUID and addon._debugWatchGUID == data.guid then
                if addon._debugEnabled then D("DISPLAY", "SPEC transition ARMED guid=%s spec=%s deadline=%.3f delay=%.3f", tostring(data.guid), tostring(data.spec), data._specDisplayAt, tonumber(cfg.classToSpecDelay) or 1.0) end
            end
        end

        if now >= data._specDisplayAt then
            ov._specTransitionAt = nil
            ov._specTransitionGUID = nil
            if addon._debugWatchGUID and addon._debugWatchGUID == data.guid and ov._debugSpecCompleted ~= data.spec then
                ov._debugSpecCompleted = data.spec
                if addon._debugEnabled then D("DISPLAY", "SPEC transition COMPLETE guid=%s spec=%s tex=%s", tostring(data.guid), tostring(data.spec), tostring(data.specTexture)) end
            end
            return "SPEC", data.specTexture, false, 1
        end

        ov._specTransitionGUID = data.guid
        ov._specTransitionAt = data._specDisplayAt
        if classFile then
            return "CLASS", classFile, false, 1
        end
    else
        data._specDisplayAt = nil
        data._specDisplaySpec = data.spec
        ov._specTransitionAt = nil
        ov._specTransitionGUID = nil
    end

    if showClass and classFile and not isPet then
        return "CLASS", classFile, false, 1
    end
    if showUnknown then
        return "UNKNOWN", addon.UNKNOWN_ICON, true, 1
    end
    return nil
end

-- One line per icon CHANGE, for every plate, while debug is on. The old
-- DISPLAY line only fired for the watched GUID or the mouseover, so a capture
-- could not prove what the other ninety plates were showing. Cheap: a string
-- compare per render, and only when debug is enabled.
local function LogIcon(ov, side, guid, name, cfg, enemy, classFile, data, iconKind, shown)
    if not addon._debugEnabled then return end
    ov._iconSide = side
    stats.Seen(side, guid or name)
    local form = data.feralKind
    local key = tostring(guid) .. "|" .. tostring(name) .. "|" .. tostring(iconKind)
        .. "|" .. tostring(data.spec) .. "|" .. tostring(shown)
        .. "|" .. tostring(data.isHealer) .. "|" .. tostring(data.isTank)
        .. "|" .. tostring(form)
    if ov._iconLogged == key then return end
    ov._iconLogged = key
    stats.Bump(stats.icons[side] or stats.icons.friendly, iconKind)
    if form == "BEAR" or form == "CAT" then stats.Bump(stats.forms, form) end
    D("ICON", "side=%s name=%s guid=%s mode=%s class=%s spec=%s role=%s healer=%s tank=%s form=%s kind=%s shown=%s",
        side, tostring(name), tostring(guid), tostring(CurrentDisplayMode(cfg, enemy)),
        tostring(classFile), tostring(data.spec), tostring(data.specRole),
        tostring(data.isHealer), tostring(data.isTank), tostring(form or "-"), tostring(iconKind), tostring(shown))
end

local function ApplySelectedIcon(ov, cfg, enemy, data, classFile, hasFlag, isPet, target)
    local mode = CurrentDisplayMode(cfg, enemy)
    local now = GetTime()
    local hasSpec = data.specTexture ~= nil

    if not enemy and mode == "ALL" then
        if hasFlag and cfg.useFlagCarrierIcon then
            addon.SetCircularTexture(ov.icon, flagIconByGUID[data.guid] or addon.FLAG_ICON_BY_FACTION[data.flag] or addon.FLAG_ICON_NEUTRAL)
            return true, false, cfg.flagCarrierIconSize or 1.5, "FLAG"
        end
        if isPet and cfg.petIconsEnabled ~= false then
            addon.SetCircularTexture(ov.icon, addon.PET_ICON)
            return true, false, cfg.petIconSize or 0.8, "PET"
        end
    end

    if enemy and mode == "ALL" then
        if hasFlag and cfg.enemyFlagCarrierIcon then
            addon.SetCircularTexture(ov.icon, flagIconByGUID[data.guid] or addon.FLAG_ICON_BY_FACTION[data.flag] or addon.FLAG_ICON_NEUTRAL)
            return true, false, cfg.enemyFlagCarrierIconSize or 1.5, "FLAG"
        end
        if isPet and cfg.enemyPetIcon then
            addon.SetCircularTexture(ov.icon, addon.PET_ICON)
            return true, false, cfg.enemyPetIconSize or 0.8, "PET"
        end
        if data.isHealer and cfg.enemyHealerIcon then
            addon.SetRoleTexture(ov.icon, "HEALER")
            return true, false, cfg.enemyHealerIconSize or 1.35, "HEALER"
        end
        if data.isTank and cfg.enemyTankIcon then
            addon.SetRoleTexture(ov.icon, "TANK")
            return true, false, 1, "TANK"
        end
        -- Spec Filters hide the spec icon (class icon next), Class
        -- Filters the class icon; a filtered known player never shows ?.
        local specHidden = hasSpec and not isPet and IconFilter.SpecHidden(cfg, true, classFile, data.spec)
        local classHidden = not isPet and IconFilter.ClassHidden(cfg, true, classFile)
        if hasSpec and cfg.enemyShowSpec and not specHidden then
            addon.SetCircularTexture(ov.icon, data.specTexture)
            return true, false, 1, "SPEC"
        end
        if classFile and cfg.enemyShowClass and not classHidden then
            addon.SetClassIconTexture(ov.icon, classFile)
            return true, false, 1, "CLASS"
        end
        if cfg.enemyShowUnknown and not specHidden and not classHidden and not isPet
            and not (data.guid and IsIconPetGUID and IsIconPetGUID(data.guid))
            and not addon.UnknownIconLocked(cfg, true) then
            addon.SetCircularTexture(ov.icon, addon.UNKNOWN_ICON)
            return true, true, 1, "UNKNOWN"
        end
        return false, false, 1, nil
    end

    if mode == "FLAG" and hasFlag then
        addon.SetCircularTexture(ov.icon, flagIconByGUID[data.guid] or addon.FLAG_ICON_BY_FACTION[data.flag] or addon.FLAG_ICON_NEUTRAL)
        return true, false, (enemy and cfg.enemyFlagCarrierIconSize or cfg.flagCarrierIconSize) or 1.5, "FLAG"
    elseif mode == "PET" and isPet then
        addon.SetCircularTexture(ov.icon, addon.PET_ICON)
        return true, false, (enemy and cfg.enemyPetIconSize or cfg.petIconSize) or 0.8, "PET"
    elseif mode == "HEALER" and data.isHealer then
        addon.SetRoleTexture(ov.icon, "HEALER")
        return true, false, (enemy and cfg.enemyHealerIconSize or cfg.healerIconSize) or 1.35, "HEALER"
    elseif mode == "TANK" and (data.isTank or (data.spec == "FERAL" and data.feralKind == "BEAR")) then
        addon.SetRoleTexture(ov.icon, "TANK")
        return true, false, 1, "TANK"
    elseif mode == "CLASS_SPEC" then
        -- filter modes ignore the identity toggles (they are locked).
        -- Spec only still follows the Spec Filters.
        if hasSpec and not IconFilter.SpecHidden(cfg, enemy, classFile, data.spec) then
            addon.SetCircularTexture(ov.icon, data.specTexture)
            return true, false, 1, "SPEC"
        end
        return false, false, 1, nil
    elseif mode == "CLASS" then
        -- Class only still follows the Class Filters.
        if classFile and not isPet and not IconFilter.ClassHidden(cfg, enemy, classFile) then
            addon.SetClassIconTexture(ov.icon, classFile)
            return true, false, 1, "CLASS"
        end
        return false, false, 1, nil
    elseif mode == "ALL" and not enemy then
        local kind, texture, question, scale = FriendlyIconState(cfg, data, classFile, isPet, hasFlag, now, ov)
        if kind then
            if kind == "CLASS" then
                addon.SetClassIconTexture(ov.icon, texture)
            elseif kind == "HEALER" or kind == "TANK" then
                addon.SetRoleTexture(ov.icon, kind)
            else
                addon.SetCircularTexture(ov.icon, texture)
            end
            return true, question, scale, kind
        end
        return false, false, 1, nil
    end
    return false, false, 1, nil
end

-- "CC only" / "Buffs only" / "Debuffs only" display modes: draws only
-- the CC/aura icon (players and pets). Returns false (caller hides) when the
-- player has none.
local function ApplyAuraOnly(plate, ov, guid, unit, classFile, enemy, name, isPet)
    local cfg = DB()
    if not guid and not ov._auraGUID then return false end
    ov._specTransitionAt, ov._specTransitionGUID = nil, nil
    ov:ClearAllPoints()
    if enemy then
        ov:SetPoint("BOTTOM", plate, "TOP", cfg.enemyIconOffsetX or 0, 8 + (cfg.enemyIconOffsetY or 0))
        ov:SetScale(isPet and (cfg.enemyPetIconSize or 0.8) or (cfg.enemyIconScale or 100) / 100)
    else
        ov:SetPoint("BOTTOM", plate, "TOP", cfg.classIconHorizontalOffset or 0, 8 + (cfg.classIconOffset or 0))
        ov:SetScale(isPet and (cfg.petIconSize or 0.8) or cfg.classIconSize or 1)
        ov.arenaText:Hide()
    end
    ov:SetSize(ICON_SIZE, ICON_SIZE)
    local target = IsTargetPlate(plate, unit) and not isPet
    if not ApplyAuraOverlay(ov, guid, unit, classFile, target, enemy) then return false end
    if guid then ov._guid = guid end
    ov._isQuestion = false
    local showName = enemy and cfg.enemyShowPlayerName or (not enemy and cfg.showPlayerName)
    if showName and name and not isPet then
        ov.nameText:SetText(name)
        if classFile then ov.nameText:SetTextColor(addon.GetClassColor(classFile)) else ov.nameText:SetTextColor(1, 1, 1) end
        ov.nameText:Show()
    else
        ov.nameText:Hide()
    end
    ov:Show()
    return true
end

-- a player with no icon can still show his name ("Show name even without
-- icon", per side). Pets and NPCs never reach here; the name needs its parent option.
local function ShowNameOnly(plate, ov, cfg, enemy, name, classFile, isPet)
    if isPet or not name then return false end
    local on = enemy and cfg.enemyShowNameWithoutIcon or (not enemy and cfg.showNameWithoutIcon)
    local named = enemy and cfg.enemyShowPlayerName or (not enemy and cfg.showPlayerName)
    if not (on and named) then return false end
    ov.icon:Hide(); ov.colorBorder:Hide(); ov.ccTimerText:Hide(); ov.arenaText:Hide()
    ov._ccTimerExpires, ov._auraDropAt, ov._isQuestion, ov.isTarget = nil, nil, false, false
    ov:ClearAllPoints()
    if enemy then
        ov:SetPoint("BOTTOM", plate, "TOP", cfg.enemyIconOffsetX or 0, 8 + (cfg.enemyIconOffsetY or 0))
        ov:SetScale(1)
    else
        ov:SetPoint("BOTTOM", plate, "TOP", cfg.classIconHorizontalOffset or 0, 8 + (cfg.classIconOffset or 0))
        ov:SetScale(cfg.classIconSize or 1)
    end
    ov:SetSize(ICON_SIZE, ICON_SIZE)
    ov.nameText:SetText(name)
    if classFile then ov.nameText:SetTextColor(addon.GetClassColor(classFile)) else ov.nameText:SetTextColor(1, 1, 1) end
    ov.nameText:Show()
    ov:Show()
    return true
end

local function ApplyFriendly(plate, ov, guid, name, unit, cached)
    local cfg = DB()
    local data = cached or {}
    if unit then
        local unitGUID = UnitGUID(unit)
        RememberUnit(unit)
        guid = unitGUID or guid or data.guid
        data = (guid and cacheByGUID[guid]) or data
    else
        guid = guid or data.guid
        -- Targeted talent refreshes deliberately run after the mouseover token can
        -- disappear. Sync the authoritative TalentScanner cache by GUID before
        -- rendering, otherwise the overlay keeps its stale pre-inspection copy
        -- (the exact cause of the old first-mouseover failure).
        if guid then
            SyncTalentCache(guid, name)
            data = cacheByGUID[guid] or data
        end
    end
    -- A friendly plate with no unit token can still have a class from the client
    -- API (GetPlayerInfoByGUID), which NoteAuraName learned from the combat log
    -- even when the spell was not a class proof. Fill it before the merge so a
    -- plate that only appeared in the log still gets its class icon.
    if not data.class and guid and auraClassByGUID[guid] then
        data = data or {}
        data.class = auraClassByGUID[guid]
        -- store it too: this class came from the client API, not from a spell,
        -- so no other path would have written a class-only record for him.
        if addon.SpecMemory then
            addon.SpecMemory:Remember(guid, name, data.class, nil, nil, nil)
        end
    end
    -- A friendly plate with no unit token has no inspection result: the combat
    -- log and the Class/Spec Memory are the only sources of a class. A real
    -- read always wins, so this only fills in what the cache does not already
    -- have, and it never writes a guess back into the shared cache.
    --
    -- The health-bar colour is deliberately NOT read here. 3.3.5a has exactly
    -- one nameplate class-colour CVar, ShowClassColorInNameplate, and it only
    -- colours hostile plates; there is no friendly variant in the client. A
    -- friendly bar is green, so the read could only ever return nil - and on a
    -- custom nameplate addon it could return a colour that merely resembles a
    -- class and paint a wrong icon.
    -- A cached inspection restored from an earlier session is not proof of what
    -- the player has now. A proven signature seen this session is, so it wins.
    if data.fromDisk and data.spec then
        local live = FriendlySpec(guid, name, data.class)
        if live and not live.weak and not live.fromMemory and live.spec and live.spec ~= data.spec then
            data.spec, data.specTexture, data.specRole, data.feralKind = nil, nil, nil, nil
            data.isHealer, data.isTank, data.fromDisk = false, false, nil
        end
    end
    if not data.class or not data.specTexture then
        local learned = FriendlySpec(guid, name, data.class)
        -- nothing live names a spec: fall back to the memory, which is a
        -- baseline that any detection above replaces on the next render.
        local source = learned
        if not source or not source.spec then
            local mem = MemoryEntry(guid, name, data.class or (learned and learned.class))
            if mem then source = mem end
        end
        if source and (not data.class or data.class == source.class) then
            -- One view per plate identity, rebuilt in place. A brand new table
            -- here throws away the class -> spec deadline that FriendlyIconState
            -- stored on it, so the icon would sit on the class forever while the
            -- deadline re-armed on every render.
            local key = guid and ("g:" .. guid) or (name and ("n:" .. name)) or nil
            local view
            if key then
                view = friendlyViewByKey[key]
                if not view then
                    if friendlyViewCount >= 400 then wipe(friendlyViewByKey); friendlyViewCount = 0 end
                    view = {}
                    friendlyViewByKey[key] = view
                    friendlyViewCount = friendlyViewCount + 1
                end
                local at, atSpec, logged = view._specDisplayAt, view._specDisplaySpec, view._mergeLogged
                for k in pairs(view) do view[k] = nil end
                for k, v in pairs(data) do view[k] = v end
                view._specDisplayAt, view._specDisplaySpec = at, atSpec
                view._mergeLogged = logged
            else
                view = {}
                for k, v in pairs(data) do view[k] = v end
            end
            local hadClass = data.class
            view.guid = view.guid or guid
            if not view.class then view.class = source.class end
            -- a talent build read this session owns the form; a live signal may
            -- only fill it in when the build could not name one
            local lockedForm = view.feralLock
            if not view.specTexture and source.spec and source.class == view.class then
                view.spec, view.specTexture, view.specRole = source.spec, source.texture, source.role
                -- a Mangle (Bear)/(Cat) signature names the FORM, which is what
                -- decides the tank icon and the Bear/Cat texture. The enemy path
                -- already read sig.kind; the friendly merge did not, so a friendly
                -- bear showed the bear-form icon instead of the tank icon.
                if not lockedForm and (source.kind == "BEAR" or source.kind == "CAT") then
                    view.feralKind = source.kind
                end
            elseif source.spec and source.class == view.class and view.spec == source.spec
                and not lockedForm and (source.kind == "BEAR" or source.kind == "CAT") then
                -- the spec is already known (cache, memory, a plain Feral
                -- signature) but a live form signal now says which half it is.
                view.feralKind = source.kind
            end
            data = view
            if addon._debugEnabled then
                -- Once per change, not per render.
                local sig = tostring(view.class) .. "|" .. tostring(view.spec)
                if view._mergeLogged ~= sig then
                    view._mergeLogged = sig
                    DCompact("FRIENDMERGE", key or "?",
                        "name=%s src=%s/%s%s cache=%s -> class=%s spec=%s",
                        tostring(name), tostring(source.class), tostring(source.spec or "-"),
                        source.fromMemory and " (memory)" or "",
                        tostring(hadClass or "nil"), tostring(view.class), tostring(view.spec))
                end
            end
        end
    end
    local classFile = data.class
    -- A live form signal refines a Feral whose spec came from somewhere else
    -- (the cache, the memory, a plain "Feral" signature). Without this a druid
    -- in Bear Form kept the cat texture because the merge above never ran.
    if classFile == "DRUID" and data.spec == "FERAL" and not data.feralLock then
        local live = FriendlySpec(guid, name, classFile)
        if live and live.kind and live.kind ~= data.feralKind and not live.weak then
            data.feralKind = live.kind
        end
    end
    -- A known druid form decides the Feral texture even when the spec itself
    -- came from another source (a signature that only said "Feral", the cache or
    -- the memory): a bear must never be painted with the cat icon, and a cat
    -- must never be painted with a bear.
    if classFile == "DRUID" and data.spec == "FERAL" and data.feralKind then
        data.specTexture = addon.FeralTexture(data.feralKind) or data.specTexture
    end
    -- The role a spec implies is part of the spec: a Restoration druid read from
    -- the combat log is a healer even though nobody inspected him. Without this
    -- a detected player kept his spec icon while "Healer icon" was on and only
    -- switched to the healer icon after a mouseover. It applies to every source
    -- on this side: inspection, signature, guess and Class/Spec Memory.
    local specRole = data.specRole or addon.RoleForSpec(classFile, data.spec)
    -- a Bear-form Feral is a tank even though FERAL alone means DAMAGER; keep
    -- the role field honest so the ICON log and the memory agree with the icon.
    if classFile == "DRUID" and data.spec == "FERAL" and data.feralKind == "BEAR" then
        specRole = "TANK"
    end
    local isHealer = data.isHealer or specRole == "HEALER"
    local isTank = data.isTank or specRole == "TANK"
        or (data.spec == "FERAL" and data.feralKind == "BEAR")
    data.specRole, data.isHealer, data.isTank = specRole, isHealer, isTank
    local isPet = data.isPet or IsPetUnit(unit)
    local flag = not isPet and FlagForPlate(guid, name) or nil
    local hasFlag = flag ~= nil
    local hasSpec = data.specTexture ~= nil

    if not SelectDisplayMode(cfg, false, isHealer, isTank, isPet, hasFlag, hasSpec) then
        if not (AURA_MODES[CurrentDisplayMode(cfg, false)] and ApplyAuraOnly(plate, ov, guid, unit, classFile, false, name, isPet))
            and not ShowNameOnly(plate, ov, cfg, false, name, classFile, isPet) then
            HideOverlay(plate)
        end
        return
    end

    local target = IsTargetPlate(plate, unit) and not isPet
    ov:ClearAllPoints()
    ov:SetPoint("BOTTOM", plate, "TOP", cfg.classIconHorizontalOffset or 0, 8 + (cfg.classIconOffset or 0))
    local baseScale = cfg.classIconSize or 1
    ov:SetScale(baseScale)
    ov:SetSize(ICON_SIZE, ICON_SIZE)

    if guid then
        data.guid = guid
        ov._guid = guid
    end
    data.flag = flag
    if ov._specTransitionGUID and guid and ov._specTransitionGUID ~= guid then
        ov._specTransitionGUID = nil
        ov._specTransitionAt = nil
    end
    ov._isQuestion = false

    local shown, question, iconScale, iconKind = ApplySelectedIcon(ov, cfg, false, data, classFile, hasFlag, isPet, target)
    LogIcon(ov, "friendly", guid, name, cfg, false, classFile, data, iconKind, shown)
    if addon._debugEnabled and guid and (addon._debugWatchGUID == guid or unit == "mouseover") then
        local sig = table.concat({
            tostring(guid), tostring(data.spec), tostring(data.specTexture), tostring(data.specRole),
            tostring(shown), tostring(iconKind), tostring(question), tostring(unit and "unit" or "cache")
        }, "|")
        if ov._debugDisplaySig ~= sig then
            ov._debugDisplaySig = sig
            if addon._debugEnabled then D("DISPLAY", "guid=%s source=%s class=%s spec=%s role=%s kind=%s shown=%s", tostring(guid), tostring(unit and "UNIT" or "GUIDCACHE"), tostring(classFile), tostring(data.spec), tostring(data.specRole), tostring(iconKind), tostring(shown)) end
        end
    end
    if not shown then
        -- a CC/aura icon still draws when the player's own icon is off.
        if ApplyAuraOverlay(ov, guid, unit, classFile, target, false) then
            ov.arenaText:Hide()
            if cfg.showPlayerName and name and not isPet then
                ov.nameText:SetText(name)
                if classFile then ov.nameText:SetTextColor(addon.GetClassColor(classFile)) else ov.nameText:SetTextColor(1, 1, 1) end
                ov.nameText:Show()
            else
                ov.nameText:Hide()
            end
            ov:Show()
            return
        end
        if not ShowNameOnly(plate, ov, cfg, false, name, classFile, isPet) then HideOverlay(plate) end
        return
    end
    ov._isQuestion = question

    ov.icon:Show()
    ov:SetScale(IconKindScale(baseScale, iconKind, iconScale))
    SizeBorderToIcon(ov)
    if iconKind == "UNKNOWN" then ApplyBaseBorder(ov, nil, target, true) else ApplyBaseBorder(ov, classFile, target, false) end

    if cfg.showPlayerName and name and not isPet then
        ov.nameText:SetText(name)
        if classFile then
            local r, g, b = addon.GetClassColor(classFile)
            ov.nameText:SetTextColor(r, g, b)
        else
            ov.nameText:SetTextColor(1, 1, 1)
        end
        ov.nameText:Show()
    else
        ov.nameText:Hide()
    end

    ApplyAuraOverlay(ov, guid, unit, classFile, target, false)
    ov.arenaText:Hide()
    ov:Show()
end

-- pets previously had no working path because every pet plate was hidden. Friendly
-- pets follow "Enable friendly icons" + "Show pet icons", enemy pets "Show
-- enemy pet icons"; both use "Pet icon scale", the display mode (All / Pet
-- only), the target highlight and CC replacement.
-- every pet icon gets a border: yellow when targeted (highlight on), the
-- owner's class colour when known and class-coloured borders are on, else black.
local function ApplyPetBorder(ov, ownerClass, target)
    SizeBorderToIcon(ov)
    if target then
        ov.colorBorder:SetVertexColor(1, 0.92, 0.20, 1)
        if not ov.isTarget then ov._pulse = 0 end
        ov.isTarget = true
        ov:SetFrameStrata("DIALOG")
    else
        if ownerClass then
            local r, g, b = addon.GetClassColor(ownerClass)
            ov.colorBorder:SetVertexColor(r, g, b, 1)
        else
            ov.colorBorder:SetVertexColor(0, 0, 0, 1)
        end
        ov.colorBorder:SetAlpha(1)
        ov.isTarget = false
        ov:SetFrameStrata("HIGH")
    end
    ov.colorBorder:Show()
end

-- One line per pet icon CHANGE while debug is on. Pet plates used to have no
-- log at all, so a capture could not prove whether a CC really replaced the pet
-- icon (or whether the plate was even recognised as a pet). Cheap: a string
-- compare per render, and only when debug is enabled.
local function LogPetIcon(ov, enemy, guid, name, kind, spellID)
    if not addon._debugEnabled then return end
    local key = tostring(guid) .. "|" .. tostring(name) .. "|" .. tostring(kind) .. "|" .. tostring(spellID)
    if ov._petIconLogged == key then return end
    ov._petIconLogged = key
    D("PETICON", "side=%s name=%s guid=%s kind=%s spell=%s",
        enemy and "enemy" or "friendly", tostring(name), tostring(guid), tostring(kind), tostring(spellID))
end

local function ApplyPet(plate, ov, guid, unit, enemy, name)
    local cfg = DB()
    local mode = CurrentDisplayMode(cfg, enemy)
    local hidden
    if enemy then
        hidden = cfg.hideEnemyOutsidePvP and not addon.IsInPvPInstance()
    else
        hidden = cfg.hideOutsidePvP and not addon.IsInPvPInstance()
    end
    -- a disabled side draws no pet icon at all.
    if hidden or not SideEnabled(cfg, enemy) then HideOverlay(plate); return end
    if AURA_MODES[mode] then
        if ApplyAuraOnly(plate, ov, guid, unit, nil, enemy, name, true) then
            ApplyPetBorder(ov, PetOwnerClass(guid, name), IsTargetPlate(plate, unit))
        else
            HideOverlay(plate)
        end
        return
    end
    -- "Pet only" ignores the pet toggles (locked); "All" uses them.
    local allowed = mode == "PET"
        or (mode == "ALL" and (enemy and cfg.enemyPetIcon or (not enemy and cfg.petIconsEnabled ~= false)))
    if not allowed then HideOverlay(plate); return end
    if guid then ov._guid = guid end
    ov._specTransitionAt, ov._specTransitionGUID, ov._isQuestion = nil, nil, false
    ov.nameText:Hide(); ov.arenaText:Hide()
    ov:ClearAllPoints()
    local scale
    if enemy then
        ov:SetPoint("BOTTOM", plate, "TOP", cfg.enemyIconOffsetX or 0, 8 + (cfg.enemyIconOffsetY or 0))
        -- enemy pets have their own "Pet icon scale" (Enemy > Size & position).
        -- the general "Icon scale" no longer applies to pets.
        scale = cfg.enemyPetIconSize or 0.8
    else
        ov:SetPoint("BOTTOM", plate, "TOP", cfg.classIconHorizontalOffset or 0, 8 + (cfg.classIconOffset or 0))
        scale = cfg.petIconSize or 0.8
    end
    ov:SetSize(ICON_SIZE, ICON_SIZE)
    ov:SetScale(scale)
    addon.SetCircularTexture(ov.icon, addon.PET_ICON)
    ov.icon:Show()
    local target = IsTargetPlate(plate, unit)
    local ownerClass = PetOwnerClass(guid, name)
    ApplyPetBorder(ov, ownerClass, target)
    -- CC/aura replacement keeps the pet border (it would otherwise redraw grey).
    local cc, ccSpell = ApplyAuraOverlay(ov, guid, unit, nil, target, enemy)
    if cc then ApplyPetBorder(ov, ownerClass, target) end
    LogPetIcon(ov, enemy, guid, name, cc and "CC" or "PET", ccSpell)
    ov:Show()
end

local function ApplyEnemy(plate, ov, guid, name, unit, cached, liveClass)
    local cfg = DB()
    local data = cached or {}
    -- the class-colored health bar names the class without any unit
    -- token; a name-only snapshot of another class is never used.
    if not unit and not guid and liveClass and data.class and data.class ~= liveClass then data = {} end
    if unit then
        local unitGUID = UnitGUID(unit)
        RememberUnit(unit)
        guid = unitGUID or guid or data.guid
        data = (guid and cacheByGUID[guid]) or data
    else
        guid = guid or data.guid
    end
    -- Remember that this plate is a player, so a later render without a unit
    -- token (after mouseout) still has proof and is not hidden as an NPC.
    if guid then ov._guid = guid; ov._playerGUID = guid end
    local isPet = data.isPet or IsPetUnit(unit)
    -- A live unit or the class-coloured bar first; a signature/memory class is
    -- applied just below, and only then the class the client itself reported for
    -- this GUID (GetPlayerInfoByGUID via NoteAuraName). A hostile plate with no
    -- unit token and no bar colour used to stay "?" even when the combat log had
    -- already named the class. The API answer is the LAST fallback so it can
    -- never override a talent signature that is more specific.
    local classFile = data.class or liveClass
    -- A cached inspection restored from an earlier session loses to a proven
    -- signature seen this session (he respecced since that inspection).
    if data.fromDisk and data.spec then
        local live = EnemySpec(guid, name, data.class)
        if live and not live.weak and live.spec and live.spec ~= data.spec then
            data.spec, data.specTexture, data.specRole, data.feralKind = nil, nil, nil, nil
            data.isHealer, data.isTank, data.fromDisk = false, false, nil
        end
    end
    -- Inspection/group data always wins, a combat-log spec fills the gap, and
    -- the Class/Spec Memory is the last resort when neither knows anything.
    local sig = not isPet and not data.specTexture and EnemySpec(guid, name, classFile)
    if not isPet and not data.specTexture and not sig then
        sig = MemoryEntry(guid, name, classFile)
    end
    -- On a stock client a hostile plate has no unit token and no bar colour, so
    -- the memory can be the ONLY thing that still knows the class after a
    -- reload. Without this line the record was read and then thrown away, and
    -- the plate stayed a question mark: the "enemies are not restored" bug.
    if not classFile and sig and sig.class then classFile = sig.class end
    if not classFile and guid then classFile = auraClassByGUID[guid] end
    -- The class-coloured health bar is a real class read for an enemy plate with
    -- no unit token (the only one on a stock client before any hover). Store it
    -- so the class icon is back after a reload; a stored spec is never
    -- downgraded by a class-only offer.
    if guid and classFile and not isPet and addon.SpecMemory then
        addon.SpecMemory:Remember(guid, name, classFile, nil, nil, nil)
    end
    local view = ov._enemyView or {}
    ov._enemyView = view
    view.guid = guid
    view.class = classFile
    -- the view is reused when the client recycles this plate for another player:
    -- a form left over from a previous druid must never leak onto a DK (it did,
    -- and "Tank icons only" then drew a tank for him).
    view.feralKind = nil
    view.specTexture = data.specTexture or (sig and sig.texture)
    -- the spec name comes from the same source as its texture (filters).
    if data.specTexture then view.spec = data.spec else view.spec = sig and sig.spec or nil end
    -- The form: a talent build read this session decides, then the newest live
    -- signal, then the last form we read from the unit. A Feral in Bear form
    -- counts as a tank when "Show enemy tank icons" is on, matching friendlies.
    local kind
    if data.feralLock then kind = data.feralKind
    else kind = (sig and sig.kind) or data.feralKind end
    local feralBear = kind == "BEAR" and view.spec == "FERAL"
    -- the form also decides the texture, so a cat is never painted as a bear
    if classFile == "DRUID" and view.spec == "FERAL" then
        view.feralKind = kind
        view.specTexture = addon.FeralTexture(kind) or view.specTexture
    end
    -- The role a spec implies counts here exactly as it does for friendlies: a
    -- Protection paladin detected from the combat log is a tank even though
    -- nobody inspected him, so "Show enemy tank icons" applies at once.
    local specRole = data.specRole or (sig and sig.role) or addon.RoleForSpec(classFile, view.spec)
    if feralBear then specRole = "TANK" end
    view.specRole = specRole
    view.isHealer = data.isHealer or specRole == "HEALER" or false
    view.isTank = data.isTank or specRole == "TANK"
        or (feralBear and (cfg.enemyTankIcon == true or CurrentDisplayMode(cfg, true) == "TANK")) or false
    data = view
    local isHealer = data.isHealer
    local isTank = data.isTank
    local flag = not isPet and FlagForPlate(guid, name) or nil
    local hasFlag = flag ~= nil
    local hasSpec = data.specTexture ~= nil
    local inArena = IsActiveBattlefieldArena and IsActiveBattlefieldArena()
    local inBG = select(2, IsInInstance()) == "pvp"

    ov.icon:Hide(); ov.colorBorder:Hide(); ov.nameText:Hide(); ov._isQuestion = false
    ov.ccTimerText:Hide(); ov._ccTimerExpires = nil; ov._auraDropAt = nil
    ov:SetScale(1)
    ov:SetSize(ICON_SIZE, ICON_SIZE)
    ov:ClearAllPoints()
    ov:SetPoint("BOTTOM", plate, "TOP", cfg.enemyIconOffsetX or 0, 8 + (cfg.enemyIconOffsetY or 0))

    local arenaIndex = cfg.arenaNumbersEnabled and GetArenaIndexForGUID(guid, name)
    if arenaIndex then
        ov.arenaText:SetText(tostring(arenaIndex))
        ov.arenaText:ClearAllPoints()
        ov.arenaText:SetPoint("CENTER", plate, "TOP", 0, 10)
        ov.arenaText:Show()
    else
        ov.arenaText:Hide()
    end

    if not inArena and not inBG and cfg.hideEnemyOutsidePvP then
        if not arenaIndex then HideOverlay(plate); return end
    end

    -- "Enable enemy icons" off draws nothing but the arena number.
    if not SideEnabled(cfg, true) then
        if arenaIndex then ov:Show() else HideOverlay(plate) end
        return
    end

    if not SelectDisplayMode(cfg, true, isHealer, isTank, isPet, hasFlag, hasSpec) then
        if AURA_MODES[CurrentDisplayMode(cfg, true)] and ApplyAuraOnly(plate, ov, guid, unit, classFile, true, name, isPet) then return end
        if not arenaIndex and ShowNameOnly(plate, ov, cfg, true, name, classFile, isPet) then return end
        if arenaIndex then ov:Show() else HideOverlay(plate) end
        return
    end

    local target = IsTargetPlate(plate, unit) and not isPet
    data.flag = flag
    local shown, question, iconScale, iconKind = ApplySelectedIcon(ov, cfg, true, data, classFile, hasFlag, isPet, target)
    LogIcon(ov, "enemy", guid, name, cfg, true, classFile, data, iconKind, shown)
    ov._isQuestion = question
    if not shown then
        -- a CC/aura icon still draws when the enemy's own icon is off.
        if ApplyAuraOverlay(ov, guid, unit, classFile, target, true) then
            if cfg.enemyShowPlayerName and name and not isPet then
                ov.nameText:SetText(name)
                if classFile then ov.nameText:SetTextColor(addon.GetClassColor(classFile)) else ov.nameText:SetTextColor(1, 1, 1) end
                ov.nameText:Show()
            else
                ov.nameText:Hide()
            end
            ov:Show()
            return
        end
        if not arenaIndex and ShowNameOnly(plate, ov, cfg, true, name, classFile, isPet) then return end
        if arenaIndex then ov:Show() else HideOverlay(plate) end
        return
    end

    -- the old path hid the icon above and never showed it again (enemies had nothing).
    ov.icon:Show()
    ov:SetScale(IconKindScale((cfg.enemyIconScale or 100) / 100, iconKind, iconScale))
    SizeBorderToIcon(ov)
    if iconKind == "UNKNOWN" then ApplyBaseBorder(ov, nil, target, true) else ApplyBaseBorder(ov, classFile, target, false) end

    if cfg.enemyShowPlayerName and name and not isPet then
        ov.nameText:SetText(name)
        if classFile then
            ov.nameText:SetTextColor(addon.GetClassColor(classFile))
        else
            ov.nameText:SetTextColor(1, 1, 1)
        end
        ov.nameText:Show()
    else
        ov.nameText:Hide()
    end

    ApplyAuraOverlay(ov, guid, unit, classFile, target, true)
    ov:Show()
end

UpdatePlate = function(plate)
    if not LibNameplates or not plate then return end
    local ov = EnsureOverlay(plate)
    ov._auraGUID = nil
    local reaction = LibNameplates:GetReaction(plate)
    local name = LibNameplates:GetName(plate)
    local guid = LibNameplates:GetGUID(plate)
    if not guid and addon.TalentScanner then
        -- option ON + native awesome_wotlk only; nil otherwise.
        guid = addon.TalentScanner:PlateGUID(LibNameplates.realPlate and LibNameplates.realPlate[plate] or plate)
    end
    local unit = FindUnitByGUID(guid)
    local ptype = LibNameplates:GetType(plate)
    local isFriendly = reaction == "FRIENDLY" or (unit and UnitIsFriend("player", unit))
    local isPlayerPlate = ptype == "PLAYER"

    -- Army of the Dead ghouls (and any suppressed GUID) get no icon.
    if IsSuppressedPetGUID(guid) then HideOverlay(plate); return end
    -- A vehicle is nobody's pet: no icon at all, whatever its plate reports.
    if IsVehicleGUID(guid) then HideOverlay(plate); return end
    if unit then LearnPetUnit(unit) end

    -- pets and guardians by exact pet GUID/unit (0xF14), a confirmed
    -- guardian creature (0xF13 summoned by a player), or - GUID unknown on the
    -- stock client - an NPC-colored plate whose name is a known/seen pet name
    -- (render-only; lets quick hovers and camera moves keep the pet icon).
    if (unit and IsPetUnit(unit)) or IsIconPetGUID(guid)
        or (not guid and not unit and ptype == "NPC" and name and KnownPetName(name, isFriendly)) then
        if unit then SyncAuras(unit) end
        ApplyPet(plate, ov, guid, unit, not isFriendly, name)
        return
    end

    if unit then
        RememberUnit(unit)
        local uGuid = UnitGUID(unit)
        if uGuid then
            ScanFlag(unit, uGuid)
            SyncAuras(unit)
            guid = uGuid
        end
    end
    -- Nameplate unit tokens can disappear before the targeted refresh executes.
    -- Import the authoritative GUID talent cache even when unit == nil.
    SyncTalentCache(guid, name)
    -- A recycled plate can be visible before LibNameplates rediscovers its GUID.
    -- Use the exact learned full name only as a temporary render snapshot; never
    -- use this fallback to inspect, store, or mutate identity data.
    local data
    if guid then
        data = cacheByGUID[guid]
    elseif name then
        SyncTalentCacheByName(name)
        data = cacheByName[name]
    end
    local watched = addon._debugEnabled and ((guid and addon._debugWatchGUID == guid) or (unit == "mouseover"))
    if watched then
        DCompact("PLATE", guid, "UpdatePlate name=%s guid=%s unit=%s reaction=%s type=%s friendly=%s class=%s spec=%s tex=%s healer=%s tank=%s | guid player=%s pet=%s guardian=%s creature=%s iconPet=%s playerPlate=%s", tostring(name), tostring(guid), tostring(unit), tostring(reaction), tostring(ptype), tostring(isFriendly), tostring(data and data.class), tostring(data and data.spec), tostring(data and data.specTexture), tostring(data and data.isHealer), tostring(data and data.isTank), tostring(IsPlayerGUID(guid)), tostring(IsPetGUID(guid)), tostring(GuardianClass(guid) ~= nil), tostring(CreatureID(guid)), tostring(IsIconPetGUID(guid)), tostring(isPlayerPlate))
    end

    -- Never draw player identity icons on NPCs/creatures/training dummies.
    if unit and not IsPlayerOrPetUnit(unit) then
        HideOverlay(plate)
        return
    end
    -- A newly shown player plate can exist for a short time before
    -- LibNameplates resolves its GUID. Keep the overlay visible in that window
    -- so the player starts with the configured unknown icon. GUID ownership is
    -- still required before any learned class/spec data is imported.
    -- hostile plates without a unit token: a player GUID (awesome_wotlk,
    -- or LibNameplates on mouseover/target) or, GUID unknown, a class-colored
    -- bar (ShowClassColorInNameplate) proves a player. A red bar may be an NPC
    -- and a grey (tapped) bar is an NPC, so neither is drawn without proof.
    local liveClass
    if not isFriendly and not unit then
        -- The bar colour is the only class source when there is no unit token, so
        -- read it whatever the GUID looks like.
        liveClass = LibNameplates.GetClass and LibNameplates:GetClass(plate) or nil
        -- A player GUID does not always start with 0x0000: the high word is a
        -- server-side detail and some servers (Warmane) use a different one. Prove
        -- "player" by any of: a player-shaped GUID, a class-coloured bar, an
        -- identity we already cached for this GUID, or a plate we already drew as
        -- a player. Anything left is an NPC and gets no icon.
        -- A stored Class/Spec Memory record is proof too: after a reload the
        -- cache is empty and GetPlayerInfoByGUID can stay silent for a moment,
        -- and without this a remembered enemy was hidden before his record was
        -- ever consulted.
        local provenPlayer = IsPlayerGUID(guid) or liveClass ~= nil
            or (guid ~= nil and (cacheByGUID[guid] ~= nil or ov._playerGUID == guid))
            or (guid ~= nil and addon.SpecMemory and addon.SpecMemory:Get(guid) ~= nil)
        if not provenPlayer then
            HideOverlay(plate)
            return
        end
    elseif not unit and not isPlayerPlate then
        HideOverlay(plate)
        return
    end

    -- no unit token: an estimate on top gets an exact read from any token
    -- (group member's target, plate unit). A GUID-less player plate finds its
    -- CC/aura by name (render-only key; never a GUID binding).
    if not unit then
        local key, path
        if guid then
            TryExactUpgrade(guid, GetTime())
            key, path = guid, "GUID"
        else
            key = AuraKeyForPlate(name, isFriendly and data and data.class or liveClass)
            path = "NAME"
            if key then
                TryExactUpgrade(key, GetTime())
                ov._auraGUID = key
            end
        end
        -- Log only the case worth proving: this plate actually has a CC or aura
        -- to draw. Hostile plates normally carry a GUID and take the exact path
        -- above, which the old name-only line could never show.
        if addon._debugEnabled and key and (ccStackByGUID[key] or auraByGUID[key]) then
            local t = GetTime()
            local side = isFriendly and "F" or "H"
            addon._auraKeyLogAt = addon._auraKeyLogAt or {}
            if t - (addon._auraKeyLogAt[side] or 0) >= 1 then
                addon._auraKeyLogAt[side] = t
                D("AURAKEY", "path=%s name=%s guid=%s key=%s friendly=%s",
                    path, tostring(name), tostring(guid), tostring(key), tostring(isFriendly))
            end
        end
    end

    if isFriendly then
        local cfg = DB()
        if not SideEnabled(cfg, false) or (cfg.hideOutsidePvP and not addon.IsInPvPInstance()) then
            HideOverlay(plate)
            return
        end
        ApplyFriendly(plate, ov, guid, name, unit, data)
    else
        ApplyEnemy(plate, ov, guid, name, unit, data, liveClass)
    end
end

RefreshAll = function()
    if not LibNameplates or refreshInProgress then return end
    refreshInProgress = true
    for plate in pairs(plates) do
        if plate:IsShown() then 
            UpdatePlate(plate) 
            -- After UpdatePlate, if plate has name but no GUID, try to sync talent cache by name
            local ov = plates[plate]
            if ov then
                local plateGUID = LibNameplates and LibNameplates.GetGUID and LibNameplates:GetGUID(plate)
                local plateName = LibNameplates and LibNameplates.GetName and LibNameplates:GetName(plate)
                if plateName and plateName ~= "" and not plateGUID and not ov._guid then
                    SyncTalentCacheByName(plateName)
                    UpdatePlate(plate) -- Re-render with synced data
                end
            end
        else 
            HideOverlay(plate) 
        end
    end
    -- LibNameplates.IteratePlates is useful during initial discovery, but running
    -- both loops on every refresh doubles work and can amplify callbacks from other
    -- nameplate addons. The `plates` registry is the canonical active set after setup.
    refreshInProgress = false
end

local eventFrame = CreateFrame("Frame")
local events = {
    "COMBAT_LOG_EVENT_UNFILTERED",
    "PLAYER_LOGIN",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "UNIT_AURA",
    "UNIT_TARGET",
    "PARTY_MEMBERS_CHANGED",
    "RAID_ROSTER_UPDATE",
    "UNIT_PET",
    "ARENA_OPPONENT_UPDATE",
    "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL",
    }
for _, event in ipairs(events) do eventFrame:RegisterEvent(event) end

-- Combat-log heartbeat. If a capture shows no CLEU lines at all, the handler is
-- not being reached and nothing downstream (CC, specs, flags) can work; if it
-- does, the printed flags tell us exactly what the server sends.
local cleuCount = 0
-- Rolling throughput meter. A combat log that keeps delivering during a dense
-- fight and a plate that simply cannot be attributed look identical in a bug
-- report, so the debug log reports the arrival rate itself.
-- Kept on `addon`, not in locals: the event dispatcher below is already at Lua
-- 5.1's 60-upvalue ceiling and two more locals stop the file compiling.
addon._cleuRateAt, addon._cleuRateSeen = 0, 0

-- high-frequency events (combat log, auras) coalesce into one full
-- refresh on the next frame instead of one per event.
local refreshSoonFrame = CreateFrame("Frame")
local nextCombatRefresh = 0
local unresolvedUntil, unresolvedCount = {}, 0
local function RefreshSoon()
    refreshSoonFrame:Show()
end
refreshSoonFrame:Hide()
refreshSoonFrame:SetScript("OnUpdate", function(f)
    f:Hide()
    RefreshAll()
end)

-- after a target change the client updates plate alphas a frame or two
-- later, so the target highlight is redrawn once on the next frame and once
-- 0.15 s later (sets the new target's border, clears the old one).
local targetFollowFrame = CreateFrame("Frame")
targetFollowFrame:Hide()
targetFollowFrame:SetScript("OnUpdate", function(f, elapsed)
    f.elapsed = (f.elapsed or 0) + elapsed
    if not f.firstDone then
        f.firstDone = true
        RefreshAll()
    elseif f.elapsed >= 0.15 then
        f:Hide()
        RefreshAll()
    end
end)
local function TargetFollowUp()
    targetFollowFrame.elapsed, targetFollowFrame.firstDone = 0, nil
    targetFollowFrame:Show()
end

-- (option ON, patched client): a player's nameplate unit appeared, so
-- his class is readable at once by the client's own GUID. Class only; specs
-- are still learned by hover/target inspection exactly as before.
addon.OnPlayerNamePlateAdded = function(unit)
    RememberUnit(unit)
    -- a carrier who already held the flag when his plate appeared
    -- (no combat-log pickup seen) gets the flag icon at once, by his exact GUID.
    local guid = UnitGUID(unit)
    if guid then ScanFlag(unit, guid) end
    -- a CC/aura already present when the plate appears gets its exact time.
    SyncAuras(unit)
    RefreshSoon()
end

-- CC / whitelisted aura icons from the combat log. A live unit token
-- (target/focus/mouseover, group, arena, awesome_wotlk plate) gives the exact
-- duration. Without one (stock client, player outside the group) the CC
-- duration is estimated from its PvP base duration and diminishing returns.
local DR_FACTORS = { 1, 0.5, 0.25 }
local DR_ALWAYS = { ctrlstun = true, rndstun = true, cheapshot = true, charge = true, cyclone = true }

-- Reset window used by the estimate path. The player can tune it in Advanced;
-- fall back to the built-in constant before the profile is ready.
local function DRReset()
    return (addon.GetDRResetSeconds and addon.GetDRResetSeconds())
        or addon.CROWD_CONTROL_DR_RESET or 18.1
end

-- true = enemy plate, false = friendly plate, nil = unknown flags.
local function DestSide(flags)
    if type(flags) ~= "number" then return nil end
    return not addon.HasFlag(flags, 0x10)
end

-- every side gets an estimate when no token can read the aura yet
-- (group members and plate-unit mode too); an exact read always replaces it.
local function LiveUnitForGUID(guid)
    return ExactUnitForGUID(guid)
end

local function CCWanted(cfg, side)
    if side == nil then return CCWanted(cfg, true) or CCWanted(cfg, false) end
    return SideEnabled(cfg, side) and (AuraSettings(cfg, side)) and true or false
end

-- Returns the duration factor (1, 0.5, 0.25) and the DR state to time.
local function ApplyDR(guid, drCat, now, flags, refresh)
    if not drCat then return 1 end
    if not DR_ALWAYS[drCat] and not addon.HasFlag(flags, 0x100) then return 1 end
    local states = drByGUID[guid]
    if not states then
        drCount = drCount + 1
        if drCount > 300 then wipe(drByGUID); drCount = 1 end
        states = {}
        drByGUID[guid] = states
    end
    local s = states[drCat]
    -- A refresh of the CC that is still running keeps its DR step.
    if refresh and s and s.level > 0 and now < (s.resetAt or 0) then
        return DR_FACTORS[s.level], s
    end
    -- Expired, or an application we "knew" would be immune: start again.
    if not s or now >= (s.resetAt or 0) or s.level >= 3 then
        s = s or {}
        s.level = 0
        states[drCat] = s
    end
    s.level = s.level + 1
    return DR_FACTORS[s.level], s
end

local function DRCategory(spellID, category)
    local drCat = addon.CrowdControlDR[spellID]
    if drCat == false then return nil end
    return drCat or (category and addon.CrowdControlDRByCategory[category])
end

local function NoteCrowdControl(destGUID, flags, spellID, category, now, refresh, destName)
    local cfg = DB()
    if not CCWanted(cfg, DestSide(flags)) then
        if addon._debugEnabled then D("CC", "skip guid=%s spell=%s side=%s (side or CC option off)", tostring(destGUID), tostring(spellID), tostring(DestSide(flags))) end
        return false
    end
    -- the DR step always advances (a later estimate must know it), on
    -- every side; an exact read below still wins for the drawn duration.
    local reset = DRReset()
    local base = addon.CrowdControlBaseDuration[spellID] or learnedDuration[spellID]
    local drCat = DRCategory(spellID, category)
    local factor, state = ApplyDR(destGUID, drCat, now, flags, refresh)
    if addon._debugEnabled then D("CC", "apply guid=%s spell=%s cat=%s dr=%s factor=%s base=%s flags=%s refresh=%s", tostring(destGUID), tostring(spellID), tostring(category), tostring(drCat), tostring(factor), tostring(base), tostring(flags), tostring(refresh)) end
    if state then state.resetAt = now + (base and base * factor or 8) + reset end
    local unit = LiveUnitForGUID(destGUID)
    if unit then
        SyncAuras(unit)
        local stack = ccStackByGUID[destGUID]
        local e = stack and stack[spellID]
        if e and e.exact then
            if state and e.expires then state.resetAt = e.expires + reset end
            return true
        end
    end
    local entry = { icon = addon.GetSpellTexture(spellID), spellID = spellID, category = category, start = now,
        priority = addon.CrowdControlPriority(category, spellID) }
    -- the combat log carries the destination name; keep the short form on the
    -- entry so a plate that has never been hovered can find its CC by name even
    -- when the name->GUID map has not caught up yet (see AuraKeyForPlate).
    if type(destName) == "string" and destName ~= "" then entry.shortName = ShortName(destName) end
    -- the class travels with the CC so a GUID-less plate can be narrowed by
    -- class when several players share its short name (AuraKeyForPlate).
    entry.class = auraClassByGUID[destGUID]
    if base then
        local est = base * factor
        entry.estimated, entry.duration, entry.expires = true, est, now + est
    else
        entry.guessed = true
    end
    -- every CC is kept; the highest priority one is drawn (PickCC).
    local stack = ccStackByGUID[destGUID]
    if not stack then
        ccStackCount = ccStackCount + 1
        stats.ccNew = stats.ccNew + 1
        if ccStackCount > 300 then wipe(ccStackByGUID); wipe(ccByGUID); ccStackCount = 1 end
        stack = {}
        ccStackByGUID[destGUID] = stack
    end
    stats.cc = stats.cc + 1
    stack[spellID] = entry
    PickCC(destGUID, now)
    return true
end

local function AuraWantedSide(cfg, side, spellID, kind)
    if not SideEnabled(cfg, side) then return false end
    local _, auraOn, wantBuffs, wantDebuffs = AuraSettings(cfg, side)
    if not auraOn then return false end
    local buffSet, debuffSet = SideLists(cfg, side)
    if kind == "buff" then return wantBuffs and buffSet[spellID] == true end
    return wantDebuffs and debuffSet[spellID] == true
end

local function NoteWhitelistedAura(destGUID, flags, spellID, auraType, now)
    local cfg = DB()
    local kind = auraType == "BUFF" and "buff" or "debuff"
    local side = DestSide(flags)
    local wanted
    if side == nil then
        wanted = AuraWantedSide(cfg, true, spellID, kind) or AuraWantedSide(cfg, false, spellID, kind)
    else
        wanted = AuraWantedSide(cfg, side, spellID, kind)
    end
    if not wanted then return false end
    local unit = LiveUnitForGUID(destGUID)
    if unit then
        SyncAuras(unit)
        local e = auraByGUID[destGUID]
        if e and e.exact then return true end
    end
    local priority = kind == "debuff" and 500 or 250
    local old = auraByGUID[destGUID]
    if old and (not old.expires or old.expires > now) and old.spellID ~= spellID and old.priority > priority then
        return false
    end
    local entry = { icon = addon.GetSpellTexture(spellID), spellID = spellID, kind = kind, priority = priority, start = now }
    local learned = learnedDuration[spellID]
    if learned then
        entry.estimated, entry.duration, entry.expires = true, learned, now + learned
    else
        entry.guessed = true
    end
    auraByGUID[destGUID] = entry
    stats.aura = stats.aura + 1
    if not old then stats.auraNew = stats.auraNew + 1 end
    return true
end

-- the CC/aura that ended; the DR timer runs from its removal.
local function NoteAuraRemoved(destGUID, spellID, spellName, now, auraType)
    local changed = false
    local stack = ccStackByGUID[destGUID]
    if stack and stack[spellID] then
        stack[spellID] = nil
        PickCC(destGUID, now)
        changed = true
    end
    local aura = auraByGUID[destGUID]
    if aura and aura.spellID == spellID then auraByGUID[destGUID] = nil; changed = true end
    -- Only a DEBUFF can be a CC, so only a debuff may re-arm the DR window.
    -- A BUFF that shares a CC name (Mage Impact) expiring used to push a real
    -- stun's reset 18 s into the future, making the next stun read half.
    if auraType ~= "BUFF" then
        local states = drByGUID[destGUID]
        if states then
            local drCat = DRCategory(spellID, addon.GetCrowdControlCategory(spellID, spellName))
            local s = drCat and states[drCat]
            if s then s.resetAt = now + DRReset() end
        end
    end
    return changed
end

-- a dead/destroyed unit loses every CC and aura icon at once. Its DR
-- is kept in arenas (DRData: UNIT_DIED is unreliable there).
local function NoteUnitDied(destGUID)
    local changed = ccStackByGUID[destGUID] ~= nil or auraByGUID[destGUID] ~= nil
    ccStackByGUID[destGUID], ccByGUID[destGUID], auraByGUID[destGUID] = nil, nil, nil
    if not (IsActiveBattlefieldArena and IsActiveBattlefieldArena()) then drByGUID[destGUID] = nil end
    return changed
end

-- kept outside the event handler in one table (Lua 5.1 allows 60
-- upvalues per function; the handler is at that limit).
local CCEvents = { CrowdControl = NoteCrowdControl, WhitelistedAura = NoteWhitelistedAura, AuraRemoved = NoteAuraRemoved,
    FriendlySpec = NoteFriendlySpec, WipeLearnedSpecs = addon.ClearLearnedSpecs }
function CCEvents.NamesAndDeaths(subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags)
    do
        if addon.HasFlag(destFlags, 0x400) then NoteAuraName(destGUID, destName) end
        if addon.HasFlag(sourceFlags, 0x400) then NoteAuraName(sourceGUID, sourceName) end
    end
    if destGUID and (subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED") then return NoteUnitDied(destGUID) end
    return false
end

function CCEvents.WipeNames()
    wipe(auraGUIDsByName); wipe(auraNameByGUID); wipe(auraClassByGUID); auraNameCount = 0
    wipe(upgradeAt); upgradeCount = 0
end

-- a group member now targets a player whose CC/aura is only an
-- estimate: read the exact one from his target token. Returns true on a read.
function CCEvents.GroupTargetChanged(unit)
    if type(unit) ~= "string" or not (unit:find("^party%d") or unit:find("^raid%d")) then return false end
    local tu = unit .. "target"
    local tg = UnitGUID(tu)
    local top = tg and (ccByGUID[tg] or auraByGUID[tg])
    if not top or top.exact then return false end
    SyncAuras(tu)
    return true
end

-- cached once per option change, read per combat-log event.
local enemySpecActive = true
-- CC/aura combat-log tracking hibernates when both sides are disabled.
local auraTrackActive = true
local function UpdateHibernation()
    local cfg = OPlates and OPlates.db and OPlates.db.profile.nameplates
    enemySpecActive = not cfg or EnemyNeedsSpec(cfg)
    -- Deliberately no wipe here. Turning the enemy icons (or a mode) off used to
    -- throw the learned enemy specs away, which is one more automatic deletion
    -- the player never asked for. Detection simply pauses; the store stays and
    -- resumes the moment the option is back on.
    auraTrackActive = not cfg or SideEnabled(cfg, false) or SideEnabled(cfg, true)
    if not auraTrackActive then
        wipe(ccByGUID); wipe(ccStackByGUID); ccStackCount = 0; wipe(auraByGUID); wipe(drByGUID); drCount = 0
        CCEvents.WipeNames()
    end
end
addon.UpdateSpecHibernation = UpdateHibernation

eventFrame:SetScript("OnEvent", function(_, event, ...)
    -- A session starts at login and at /reload, and both fire PLAYER_LOGIN
    -- exactly once before the first PLAYER_ENTERING_WORLD. The flag is kept on
    -- `addon`, not in a local: this handler is already at the 60-upvalue
    -- ceiling, and one more local stops the file compiling.
    if event == "PLAYER_LOGIN" then
        addon._freshSession = true
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- WotLK 3.3.5 fires the classic COMBAT_LOG_EVENT_UNFILTERED payload directly.
        -- read by position; no table allocated per combat-log event.
        local _, subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, _, auraType = ...
        local changed = false
        cleuCount = cleuCount + 1
        stats.cleu = stats.cleu + 1
        if addon._debugEnabled and cleuCount % 100 == 1 then
            D("CLEU", "#%d sub=%s spell=%s dst=%s dstName=%s dstFlags=%s srcFlags=%s", cleuCount, tostring(subEvent), tostring(spellID), tostring(destGUID), tostring(destName), tostring(destFlags), tostring(sourceFlags))
        end

        -- a player's summon names the pet/guardian's owner by GUID. Army
        -- of the Dead ghouls are suppressed; other summons of a player (Feral
        -- Spirit, Shadowfiend, Treants, Elementals, Ghoul, Water Elemental, demons,
        -- hunter pets) get an owner-class border. Totems/vehicles never come here
        -- as icons: only 0xF14 pets and 0xF13 guardians recorded below are drawn.
        if subEvent == "SPELL_SUMMON" and destGUID and IsPlayerGUID(sourceGUID) then
            if spellID and ARMY_OF_THE_DEAD_SPELLS[spellID] then
                petSuppressGUID[destGUID] = true
                changed = true
            elseif IsPetGUID(destGUID) or GuardianClass(destGUID) then
                local ownerClass = GuardianClass(destGUID)
                    or (cacheByGUID[sourceGUID] and cacheByGUID[sourceGUID].class)
                    or (enemySpecByGUID[sourceGUID] and enemySpecByGUID[sourceGUID].class)
                if not ownerClass then
                    local ownerUnit = FindUnitByGUID(sourceGUID)
                    ownerClass = ownerUnit and select(2, UnitClass(ownerUnit)) or nil
                end
                if NotePetOwner(destGUID, destName, ownerClass) then changed = true end
            end
        end

        local now = GetTime()
        -- heartbeat for the combat-log watchdog in Core.lua. Silence is the only
        -- reliable sign that 3.3.5a has stopped delivering: its entry counter
        -- reads low until the log has filled once, which is why the threshold
        -- alone could not protect the first battleground of a session.
        addon._cleuLastAt = now
        addon._cleuRateSeen = addon._cleuRateSeen + 1
        -- the very first event of a session used to divide by (now - 0), which
        -- printed "0.0 events/s over 125487s" in every capture.
        if addon._cleuRateAt == 0 then
            addon._cleuRateAt = now
        elseif now - addon._cleuRateAt >= 10 then
            if addon._debugEnabled then
                D("CLEU", "rate %.1f events/s over %.0fs (%d events)", addon._cleuRateSeen / (now - addon._cleuRateAt), now - addon._cleuRateAt, addon._cleuRateSeen)
            end
            addon._cleuRateAt, addon._cleuRateSeen = now, 0
        end
        -- only players can gain a class here, and a player without a
        -- unit token is looked up at most every 2 s instead of scanning ~105 unit
        -- tokens for every creature event and every tokenless enemy event.
        if spellID and (IsPlayerFlags(sourceFlags) or IsPlayerGUID(sourceGUID)) and not cacheByGUID[sourceGUID]
            and (unresolvedUntil[sourceGUID] or 0) <= now then
            local sourceUnit = FindUnitByGUID(sourceGUID)
            if sourceUnit then
                RememberUnit(sourceUnit); changed = true
            else
                if not unresolvedUntil[sourceGUID] then
                    unresolvedCount = unresolvedCount + 1
                    if unresolvedCount > 2000 then wipe(unresolvedUntil); unresolvedCount = 1 end
                end
                unresolvedUntil[sourceGUID] = now + 2
            end
        end
        -- EFFECT events name the unit that OWNS the effect. src == dst is a
        -- self-cast, a proc, or a party aura re-sent on its recipient - and a
        -- self-cast cannot be told from a received buff, so it identifies
        -- nobody. src ~= dst is a real cast on another unit: the source is the
        -- caster (a debuff on an enemy, a buff or heal on a party member).
        local effectEvent = subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_APPLIED_DOSE"
            or subEvent == "SPELL_AURA_REFRESH" or subEvent == "SPELL_HEAL"
            or subEvent == "SPELL_PERIODIC_HEAL" or subEvent == "SPELL_ENERGIZE"
        local trustedSource = not effectEvent or destGUID ~= sourceGUID
        -- A shapeshift is logged as an aura on the druid himself, so the gate
        -- above would drop the one event that proves his form. That gate exists
        -- because a party aura names its OWNER, not its caster; a form aura is
        -- different - Moonkin Form can only be worn by the druid who shifted
        -- into it, so here the destination IS the player and the aura is exact,
        -- current information about him. Enemies and friendly outsiders only;
        -- party and raid members are inspected properly.
        if spellID and addon.SPEC_FORM_SPELLS and addon.SPEC_FORM_SPELLS[spellID]
            and destGUID == sourceGUID and type(destFlags) == "number"
            and addon.HasFlag(destFlags, 0x400)
            and (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") then
            if addon.HasFlag(destFlags, 0x40) and enemySpecActive then
                if addon.ForcedSpec(spellID, destGUID, destName, spellName, subEvent, destGUID, true) then
                    changed = true
                end
            elseif addon.HasFlag(destFlags, 0x10) and addon.HasFlag(destFlags, 0x8) then
                if addon.ForcedSpec(spellID, destGUID, destName, spellName, subEvent, destGUID, false) then
                    changed = true
                end
            end
        end
        -- enemy specs: one table lookup per hostile player spell event.
        -- skipped entirely when no enemy option uses spec/role (hibernation).
        if trustedSource and enemySpecActive and spellName and SIGNATURE_EVENTS[subEvent] and type(sourceFlags) == "number"
            and addon.HasFlag(sourceFlags, 0x400) and addon.HasFlag(sourceFlags, 0x40)
            and NoteEnemySpec(sourceGUID, sourceName, spellName, spellID, subEvent, destGUID) then
            changed = true
        end
        -- party/raid members' talent spells (affiliation 0x6,
        -- player 0x400) for Healer-in-CC until inspection/comm knows them.
        if trustedSource and spellName and SIGNATURE_EVENTS[subEvent] and type(sourceFlags) == "number"
            and addon.HasFlag(sourceFlags, 0x400)
            and (addon.HasFlag(sourceFlags, 0x2) or addon.HasFlag(sourceFlags, 0x4)) then
            local sig = Signatures()[spellName]
            local old = sig and groupSpecByGUID[sourceGUID]
            -- same class -> the deeper tree wins (DeeperSpec); another class
            -- only when strictly stronger (a shared spell name never flips a
            -- class).
            if sig and (not old or (old.class == sig.class and addon.DeeperSpec(sig.strength, old))
                or (old.class ~= sig.class and sig.strength > old.strength)) then
                if not old then
                    groupSpecCount = groupSpecCount + 1
                    if groupSpecCount > 200 then wipe(groupSpecByGUID); groupSpecCount = 1 end
                end
                groupSpecByGUID[sourceGUID] = sig
            end
        end

        -- friendly players who are NOT in your group: no unit token on a stock
        -- client, so the combat log is the only source of a class or a spec.
        -- Party and raid are inspected properly and never reach this branch.
        if trustedSource and (spellName or spellID) and SIGNATURE_EVENTS[subEvent] and addon.HasFlag(sourceFlags, 0x400)
            and addon.HasFlag(sourceFlags, 0x10) and addon.HasFlag(sourceFlags, 0x8)
            and CCEvents.FriendlySpec(sourceGUID, sourceName, spellName, spellID, subEvent, destGUID) then
            changed = true
        end
        -- render-only name map (players only, by the combat-log player
        -- flag); a dead/destroyed unit loses its CC/aura icons.
        if auraTrackActive and CCEvents.NamesAndDeaths(subEvent, sourceGUID, sourceName, sourceFlags,
            destGUID, destName, destFlags) then
            changed = true
        end
        if spellID and destGUID then
            if (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") then
                if addon.FLAG_AURAS[spellID] then
                    SetFlagCarrier(destGUID, destName, addon.FLAG_AURAS[spellID], addon.GetSpellTexture(spellID))
                    stats.flags = stats.flags + 1
                    changed = true
                end
                -- players and their pets only (estimate + DR, see NoteCrowdControl).
                -- The combat-log player flag, not the GUID prefix, decides who is a
                -- player: Warmane players are 0x06/0x07/0x0A, stock cores 0x0000.
                -- A crowd control aura is a DEBUFF on the victim. A BUFF that
                -- merely shares a CC name is a proc on the caster: Mage Impact
                -- (64343, "your next Fire Blast stuns...") lands on the mage
                -- himself and used to draw a stun icon on him - and advance his
                -- stun DR - for its whole duration. Every real stun/fear/root/
                -- silence/disarm is a debuff, so excluding BUFFs cannot hide a
                -- real CC. Anything that is not explicitly a BUFF stays a
                -- candidate, so a client that omits auraType keeps working.
                local category = (auraType ~= "BUFF") and addon.GetCrowdControlCategory(spellID, spellName) or nil
                if addon._debugEnabled and category then
                    D("CCIN", "guid=%s spell=%s cat=%s flags=%s track=%s playerFlag=%s playerGUID=%s pet=%s",
                        tostring(destGUID), tostring(spellID), tostring(category), tostring(destFlags),
                        tostring(auraTrackActive), tostring(IsPlayerFlags(destFlags)), tostring(IsPlayerGUID(destGUID)),
                        tostring(IsIconPetGUID(destGUID)))
                end
                if auraTrackActive and (IsPlayerFlags(destFlags) or IsPlayerGUID(destGUID) or IsIconPetGUID(destGUID)) then
                    if category then
                        if CCEvents.CrowdControl(destGUID, destFlags, spellID, category, now, subEvent == "SPELL_AURA_REFRESH", destName) then changed = true end
                    elseif (auraType == "BUFF" or auraType == "DEBUFF")
                        and CCEvents.WhitelistedAura(destGUID, destFlags, spellID, auraType, now) then
                        changed = true
                    end
                end
            elseif subEvent == "SPELL_AURA_REMOVED" then
                if addon.FLAG_AURAS[spellID] and ClearFlagCarrier(destGUID) then
                    changed = true
                end
                if CCEvents.AuraRemoved(destGUID, spellID, spellName, now, auraType) then changed = true end
            elseif subEvent == "SPELL_AURA_BROKEN" or subEvent == "SPELL_AURA_BROKEN_SPELL" then
                -- a CC broken by damage/a spell is gone at once.
                if CCEvents.AuraRemoved(destGUID, spellID, spellName, now, auraType) then changed = true end
            end
        end
        -- the old path refreshed every plate on every frame with combat-log
        -- traffic; now at once on a change, otherwise at most twice a second.
        if changed or now >= nextCombatRefresh then
            nextCombatRefresh = now + 0.5
            RefreshSoon()
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        wipe(flagCarrierGUIDs); wipe(flagIconByGUID); wipe(ccByGUID); wipe(ccStackByGUID); ccStackCount = 0; wipe(auraByGUID)
        wipe(drByGUID); drCount = 0
        CCEvents.WipeNames()
        wipe(flagCarrierByFaction); wipe(flagNameByGUID); wipe(flagByName)
        -- a new battleground/arena starts with fresh enemy specs (respecs).
        if event == "PLAYER_ENTERING_WORLD" then
            -- Class/Spec Memory on: learned specs survive a loading screen on
            -- purpose, which is the whole point of the option.
            --
            -- Only the FIRST entering-world of a session is a login or a
            -- /reload. Every zone change, battleground, arena and dungeon also
            -- fires this event, and none of them may wipe learned players any
            -- more: an icon that disappears on every portal is worse than a
            -- stale one. Off: the login/reload wipe below still applies.
            if addon._freshSession then
                addon._freshSession = false
                if not (addon.SpecMemory and addon.SpecMemory:Enabled()) then
                    CCEvents.WipeLearnedSpecs()
                end
            end
            -- parse the spell -> class table now, not mid-fight
            if addon.WarmSpellClasses then addon.WarmSpellClasses() end
            wipe(unresolvedUntil); unresolvedCount = 0
            wipe(groupSpecByGUID); groupSpecCount = 0
            -- pet/guardian render memory starts fresh per world/instance.
            wipe(petOwnerClassByGUID); wipe(petOwnerClassByName); wipe(petSuppressGUID); petInfoCount = 0
            wipe(seenFriendlyPetNames); wipe(seenEnemyPetNames); wipe(petOwnerNameByGUID); wipe(petOwnerNameByPetName); seenPetCount = 0
        end
        RebuildPetNames(); RememberAllUnits(); RefreshAll(); return
    end
    if event == "UNIT_PET" or event == "ARENA_OPPONENT_UPDATE" then
        RebuildPetNames(); RefreshSoon(); return
    end
    -- the battleground announcement reaches everyone, even when
    -- the carrier is beyond combat-log range. A capture or drop only ever
    -- clears that flag's carrier; it never sets one.
    if event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or event == "CHAT_MSG_BG_SYSTEM_HORDE" or event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        local msg = type((...)) == "string" and string.lower((...)) or ""
        if (msg:find("captured", 1, true) or msg:find("dropped", 1, true)) and msg:find("flag", 1, true) then
            local faction = msg:find("alliance flag", 1, true) and "Alliance"
                or msg:find("horde flag", 1, true) and "Horde" or "Neutral"
            local guid = flagCarrierByFaction[faction]
            if guid and ClearFlagCarrier(guid) then RefreshSoon() end
        end
        return
    end
    if event == "UPDATE_MOUSEOVER_UNIT" then
        local mguid = UnitGUID("mouseover")
        local mname = UnitFullName and UnitFullName("mouseover") or UnitName("mouseover")
        local _, mclass = UnitClass("mouseover")
        local mtalent = mguid and addon._TalentCache and addon._TalentCache[mguid]
        if addon._debugEnabled then D("MOUSEOVER", "UPDATE_MOUSEOVER_UNIT name=%s guid=%s class=%s cacheSpec=%s cacheTex=%s role=%s", tostring(mname), tostring(mguid), tostring(mclass), tostring(mtalent and mtalent.spec), tostring(mtalent and mtalent.specTexture), tostring(mtalent and mtalent.specRole)) end
        RememberUnit("mouseover"); SyncAuras("mouseover")
        LearnPetUnit("mouseover") -- also guardians (0xF13), which RememberUnit skips
        if addon.TalentScanner and SpecDetectionNeeded("mouseover") then addon.TalentScanner:Mouseover() end
        local guid = UnitGUID("mouseover")
        if guid then ScanFlag("mouseover", guid) end
        RefreshAll(); return
    end
    if event == "UNIT_TARGET" then
        if auraTrackActive and CCEvents.GroupTargetChanged((...)) then RefreshSoon() end
        return
    end
    if event == "UNIT_AURA" then
        local unit = ...
        if type(unit) ~= "string" then return end
        RememberUnit(unit); SyncAuras(unit)
        local guid = UnitGUID(unit); if guid then ScanFlag(unit, guid) end
        RefreshSoon(); return
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        RebuildPetNames(); RememberAllUnits(); QueueKnownPlayerUnits(); RefreshAll(); return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        RememberUnit("target"); RememberUnit("focus")
        LearnPetUnit("target"); LearnPetUnit("focus")
        if addon.TalentScanner then
            if SpecDetectionNeeded("target") then addon.TalentScanner:InspectNow("target") end
            if SpecDetectionNeeded("focus") then addon.TalentScanner:InspectNow("focus") end
        end
        -- ONE pass is enough. RefreshAll() recomputes every visible plate -
        -- including the old and the new target - and UpdatePlate reads the
        -- current target itself. Asking for a per-GUID refresh here as well
        -- did the same work twice, and when the target had no plate (a
        -- creature, a pet, a player out of view) it retried 20 times over 2 s
        -- and then fell back to a SECOND full refresh. TargetFollowUp() below
        -- already redraws the border on the next frame and again 0.15 s later,
        -- so the old border is cleared and the new one set regardless.
        RefreshAll()
        if event == "PLAYER_TARGET_CHANGED" then TargetFollowUp() end
        return
    end
end)

local callbackOwner = {}
function callbackOwner:LibNameplates_NewNameplate(_, plate)
    local name = LibNameplates:GetName(plate)
    if name then SyncTalentCacheByName(name) end
    UpdatePlate(plate)
end
function callbackOwner:LibNameplates_RecycleNameplate(_, plate)
    local ov = plates[plate]
    if ov then 
        ov._guid = nil
        ov._specTransitionAt = nil
        ov._specTransitionGUID = nil
        ov._specDisplayAt = nil
        ov._specDisplaySpec = nil
    end
    HideOverlay(plate)
end
function callbackOwner:LibNameplates_FoundGUID(_, plate, guid, unit)
    if unit and IsPlayerOrPetUnit(unit) then
        RememberUnit(unit); ScanFlag(unit, guid); SyncAuras(unit)
        if UnitIsPlayer(unit) then QueueSpec(unit) end
    elseif guid then
        local u = FindUnitByGUID(guid)
        if u then RememberUnit(u); ScanFlag(u, guid); SyncAuras(u) end
    end
    UpdatePlate(plate)
end
function callbackOwner:LibNameplates_TargetNameplate() RefreshAll() end

addon.GetCachedUnitData = function(unit)
    if not unit or not UnitExists(unit) then return nil end
    local guid = UnitGUID(unit)
    return guid and cacheByGUID[guid] or nil
end

-- a group member's combat-log talent signature (or nil).
addon.GetGroupSpecSignature = function(guid)
    return guid and groupSpecByGUID[guid] or nil
end

addon.QueuePlayerInspect = QueueSpec

function OPlates:SetupNameplateOverlays()
    if not LibNameplates then
        addon.PRINT("LibNameplates-1.0 missing - nameplate icons disabled")
        return
    end
    LibNameplates.RegisterCallback(callbackOwner, "LibNameplates_NewNameplate")
    LibNameplates.RegisterCallback(callbackOwner, "LibNameplates_RecycleNameplate")
    LibNameplates.RegisterCallback(callbackOwner, "LibNameplates_FoundGUID")
    LibNameplates.RegisterCallback(callbackOwner, "LibNameplates_TargetNameplate")
    UpdateHibernation()
    RebuildPetNames()
    RememberAllUnits()
    QueueKnownPlayerUnits()
    if LibNameplates.IteratePlates then
        for _, plate in LibNameplates:IteratePlates() do
            if plate then
                if not plates[plate] then plates[plate] = CreateOverlay(plate) end
                UpdatePlate(plate)
            end
        end
    else
        RefreshAll()
    end
end

function OPlates:RefreshNameplateOverlays()
    UpdateHibernation()
    RememberAllUnits()
    QueueKnownPlayerUnits()
    RefreshAll()
end

addon.RefreshNameplateOverlays = function() addon:RequestRefreshNameplateOverlays() end












---------------------------------------------------------------------------
-- [STATS] one line every 60 s while debug logging is on
--
-- Everything the log can summarise, in one line, for the window that just
-- ended: plates drawn, every icon kind per side, players seen, each class/spec
-- store by tier, the Class/Spec Memory, live CC/auras/DR, pets and owners,
-- flags, druid forms, the active modes and filters, the toggles, and what the
-- player is currently hovering/targeting. Counters reset when the line prints,
-- so a capture reads minute by minute instead of line by line.
---------------------------------------------------------------------------
function stats.Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function stats.CountTrue(t)
    local n = 0
    if type(t) == "table" then for _, v in pairs(t) do if v == true then n = n + 1 end end end
    return n
end

function stats.Tiers(store)
    local proven, guess, class = 0, 0, 0
    for _, e in pairs(store) do
        if not e.spec then class = class + 1
        elseif e.weak then guess = guess + 1
        else proven = proven + 1 end
    end
    return proven, guess, class
end

function stats.Unit(unit)
    if not UnitExists or not UnitExists(unit) then return "-" end
    if UnitIsPlayer and UnitIsPlayer(unit) then return "PLAYER" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return "DEAD" end
    return "NPC"
end

function stats.Emit()
    local cfg = DB()
    local now = GetTime()
    local window = stats.at > 0 and (now - stats.at) or stats.every
    if window <= 0 then window = 1 end
    local plates_, drawn, noicon, drawnF, drawnE = 0, 0, 0, 0, 0
    for _, ov in pairs(plates) do
        plates_ = plates_ + 1
        if ov:IsShown() then
            if ov.icon and ov.icon:IsShown() then
                drawn = drawn + 1
                if ov._iconSide == "enemy" then drawnE = drawnE + 1 else drawnF = drawnF + 1 end
            else
                noicon = noicon + 1
            end
        end
    end
    local fP, fG, fC = stats.Tiers(friendlySpecByGUID)
    local eP, eG, eC = stats.Tiers(enemySpecByGUID)
    local mem = addon.SpecMemory
    local memCount = mem and mem:Count() or 0
    local memClass = mem and mem.CountClassOnly and mem:CountClassOnly() or 0
    local owners, ownerSeen = 0, {}
    for _, cls in pairs(petOwnerClassByGUID) do
        if cls and not ownerSeen[cls] then ownerSeen[cls] = true; owners = owners + 1 end
    end
    local f, e = stats.icons.friendly, stats.icons.enemy
    local p = {}
    p[#p + 1] = string.format("t=%.0f up=%.0fs", now, now - (addon._sessionStartedAt or now))
    p[#p + 1] = string.format("cleu=%d (%.1f/s)", stats.cleu, stats.cleu / window)
    p[#p + 1] = string.format("plates=%d drawn=%d (F%d/E%d) noicon=%d", plates_, drawn, drawnF, drawnE, noicon)
    p[#p + 1] = string.format("icons F c%d s%d h%d t%d u%d p%d f%d", f.CLASS or 0, f.SPEC or 0,
        f.HEALER or 0, f.TANK or 0, f.UNKNOWN or 0, f.PET or 0, f.FLAG or 0)
    p[#p + 1] = string.format("E c%d s%d h%d t%d u%d p%d f%d", e.CLASS or 0, e.SPEC or 0,
        e.HEALER or 0, e.TANK or 0, e.UNKNOWN or 0, e.PET or 0, e.FLAG or 0)
    p[#p + 1] = string.format("seen F=%d E=%d", stats.seenCountF, stats.seenCountE)
    p[#p + 1] = string.format("store F p%d g%d c%d | E p%d g%d c%d", fP, fG, fC, eP, eG, eC)
    local memOn = mem and mem:Enabled()
    p[#p + 1] = string.format("mem=%d classonly=%d on=%s%s", memCount, memClass,
        tostring(memOn), (mem and not memOn and memCount > 0) and " (kept)" or "")
    p[#p + 1] = string.format("cc live=%d new=%d seen=%d", stats.Count(ccByGUID), stats.ccNew, stats.cc)
    p[#p + 1] = string.format("aura live=%d new=%d seen=%d", stats.Count(auraByGUID), stats.auraNew, stats.aura)
    p[#p + 1] = string.format("dr=%d pets=%d owners=%d flags=%d", stats.Count(drByGUID),
        stats.Count(petOwnerClassByGUID), owners, stats.Count(flagIconByGUID))
    p[#p + 1] = string.format("forms bear=%d cat=%d", stats.forms.BEAR or 0, stats.forms.CAT or 0)
    p[#p + 1] = string.format("spec hybrid kept=%d moved=%d", stats.hybridKept, stats.hybridMoved)
    p[#p + 1] = string.format("mode F=%s E=%s", tostring(CurrentDisplayMode(cfg, false)),
        tostring(CurrentDisplayMode(cfg, true)))
    p[#p + 1] = string.format("filter F c%d s%d | E c%d s%d",
        stats.CountTrue(cfg.classFilter), stats.CountTrue(cfg.specFilter),
        stats.CountTrue(cfg.enemyClassFilter), stats.CountTrue(cfg.enemySpecFilter))
    p[#p + 1] = string.format("toggles guess=%s mem=%s", tostring(cfg.weakSpecSignals == true),
        tostring(cfg.persistentTalentCache == true))
    p[#p + 1] = string.format("hover=%s target=%s", stats.Unit("mouseover"), stats.Unit("target"))
    D("STATS", "%s", table.concat(p, " | "))
    -- reset the window
    stats.at = now
    stats.cleu, stats.cc, stats.ccNew = 0, 0, 0
    stats.aura, stats.auraNew, stats.flags = 0, 0, 0
    stats.seenCountF, stats.seenCountE = 0, 0
    wipe(stats.seenF); wipe(stats.seenE)
    wipe(stats.icons.friendly); wipe(stats.icons.enemy)
    stats.forms.BEAR, stats.forms.CAT = 0, 0
    stats.hybridKept, stats.hybridMoved = 0, 0
end
addon.PrintStats = stats.Emit

stats.frame = CreateFrame("Frame")
stats.frame:Hide()
stats.frame:SetScript("OnUpdate", function(_, elapsed)
    local now = GetTime()
    if stats.at == 0 then stats.at = now; return end
    if now - stats.at >= stats.every then stats.Emit() end
end)
-- shown only while debug logging is on: a normal player pays nothing.
addon.OnDebugChanged = function(on)
    if on then
        stats.at = GetTime()
        stats.frame:Show()
    else
        stats.frame:Hide()
    end
end
if addon._debugEnabled then addon.OnDebugChanged(true) end
