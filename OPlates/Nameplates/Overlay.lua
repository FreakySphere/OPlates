local _, addon = ...

local LibNameplates = LibStub("LibNameplates-1.0", true)

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
-- render-only player name -> GUID map, used ONLY to look up the CC/aura
-- store for a GUID-less player plate (stock client after a recycle). Never
-- binds a GUID, never touches identity/spec/inspect, never used for pets. A
-- short name seen with two GUIDs maps to false and is never used.
local auraGUIDByName, auraNameByGUID, auraClassByGUID, auraNameCount = {}, {}, {}, 0
-- next allowed exact upgrade read per GUID (estimate on top).
local upgradeAt, upgradeCount = {}, 0
local prevTargetGUID
local RefreshAll
local UpdatePlate
local refreshInProgress = false
local function D(tag, msg, ...)
    if addon._debugEnabled then addon:DebugLog(tag, msg, ...) end
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
    return SPEC_MODES[mode] == true
end

local function EnemyNeedsSpec(cfg)
    if not SideEnabled(cfg, true) then return false end
    local mode = cfg.enemyDisplayMode or "ALL"
    if mode == "ALL" then
        return cfg.enemyShowSpec == true or cfg.enemyHealerIcon == true or cfg.enemyTankIcon == true
    end
    return SPEC_MODES[mode] == true
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
            if addon._debugEnabled then D("OVERLAY", "TARGETED refresh executing guid=%s attempt=%d", tostring(targetGUID), f._attempt) end
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
        -- Extended from 8 attempts (0.24s) to 50 attempts (5s)
        if next(unmatched) and f._attempt < 50 then
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
local function IsPlayerGUID(guid)
    return type(guid) == "string" and guid:sub(1, 6) == "0x0000"
end

-- only real player pets (hunter/warlock/DK/frost mage) use 0xF14;
-- totems, guardians, vehicles and NPC summons do not.
local function IsPetGUID(guid)
    return type(guid) == "string" and guid:sub(3, 5):upper() == "F14"
end

-- The old "pet$" pattern matched only "pet", never partypetN/raidpetN/
-- arenapetN, and a hovered/targeted pet ("mouseover"/"target") was hidden.
local function IsPetUnit(unit)
    if type(unit) ~= "string" or not UnitExists(unit) or UnitIsPlayer(unit) then return false end
    local guid = UnitGUID(unit)
    if IsPetGUID(guid) then return true end
    -- A vehicle (0xF15) occupies the "pet" token while its owner rides it.
    return unit:find("pet%d*$") ~= nil and not (type(guid) == "string" and guid:sub(3, 5):upper() == "F15")
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
local signatureByName
local SIGNATURE_EVENTS = { SPELL_CAST_SUCCESS = true, SPELL_CAST_START = true, SPELL_AURA_APPLIED = true, SPELL_SUMMON = true }
local CAT_ICON = "Interface\\Icons\\Ability_Druid_CatForm"

-- Built once, on the first hostile player event, by localized spell name.
local function Signatures()
    if signatureByName then return signatureByName end
    signatureByName = {}
    for id, s in pairs(addon.SPEC_SIGNATURES or {}) do
        local spellName = GetSpellInfo(id)
        local icons = addon.SPEC_TREE_ICONS[s[1]]
        local texture = s[4] == "CAT" and CAT_ICON or icons and icons[s[2]]
        if spellName and texture then
            local old = signatureByName[spellName]
            if old == nil then
                signatureByName[spellName] = { class = s[1], spec = s[2], strength = s[3], texture = texture,
                    kind = s[4], role = addon.SPEC_ROLES[s[1]] and addon.SPEC_ROLES[s[1]][s[2]] }
            elseif old and (old.class ~= s[1] or old.spec ~= s[2]) then
                signatureByName[spellName] = false -- one name, two specs: never trusted
            end
        end
    end
    return signatureByName
end

-- Returns true when the stored spec of this hostile player changed.
local function NoteEnemySpec(guid, name, spellName)
    local sig = Signatures()[spellName]
    if not sig then return false end
    local old = enemySpecByGUID[guid]
    if old and old.class == sig.class and old.spec == sig.spec then
        if old.strength < sig.strength then old.strength = sig.strength end
        if sig.kind and (old.texture ~= sig.texture or old.kind ~= sig.kind) then
            old.texture = sig.texture; old.kind = sig.kind; return true
        end
        return false
    end
    -- A weaker hint never overrides a deep talent of another tree.
    if old and old.class == sig.class and old.strength > sig.strength then return false end
    -- a player never changes class. Another class's signature (a shared
    -- localized spell name) only replaces a known class when strictly stronger.
    if old and old.class ~= sig.class and old.strength >= sig.strength then return false end
    -- A player whose real class is known (inspection/unit) never takes another class.
    local known = cacheByGUID[guid]
    if known and known.class and known.class ~= sig.class then return false end
    if not old then
        enemySpecCount = enemySpecCount + 1
        if enemySpecCount > 2000 then wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 1 end
    end
    local entry = { guid = guid, class = sig.class, spec = sig.spec, texture = sig.texture, role = sig.role, strength = sig.strength, kind = sig.kind }
    enemySpecByGUID[guid] = entry
    if type(name) == "string" then
        -- Render-only fallback for plates whose GUID is unknown (stock client).
        -- Two players with one short name make the name unusable.
        local short = name:match("^[^%-]+") or name
        local prev = enemySpecByName[short]
        if prev == false or (prev and prev.guid ~= guid) then
            enemySpecByName[short] = false
        else
            enemySpecByName[short] = entry
        end
    end
    if addon._debugEnabled then
        addon:DebugLog("ENEMYSPEC", "guid=%s name=%s class=%s spec=%s strength=%d spell=%s",
            tostring(guid), tostring(name), sig.class, sig.spec, sig.strength, tostring(spellName))
    end
    return true
end

-- By exact GUID; by name only for a GUID-less plate whose live class matches.
local function EnemySpec(guid, name, classFile)
    local entry
    if guid then entry = enemySpecByGUID[guid]
    elseif name and classFile then entry = enemySpecByName[name] or nil end
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
    if not talent or not talent.spec then return end

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
        feralKind = talent.feralKind,
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
end

-- Sync talent cache by name when GUID not yet known to LibNameplates.
-- Used by full refresh fallback to render spec data on plates that have a name
-- but no GUID association yet. Searches TalentScanner cache for matching name.
local function SyncTalentCacheByName(name)
    if not name or name == "" or not addon._TalentCache then return end
    local match
    for guid, talent in pairs(addon._TalentCache) do
        if talent.name == name and talent.spec and talent.specTexture then
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
    if talent and classFile and talent.class ~= classFile then talent = nil end
    local old = cacheByGUID[guid] or {}
    if classFile and old.class and old.class ~= classFile then old = {} end
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
        spec = talent and talent.spec or old.spec,
        specTexture = talent and talent.specTexture or old.specTexture,
        specRole = inspectedRole or old.specRole,
        feralKind = talent and talent.feralKind,
        _specDisplayAt = old._specDisplayAt,
        _specDisplaySpec = old._specDisplaySpec,
    }
    cacheByGUID[guid] = data
    if addon.ApplyFeralIdentity then addon.ApplyFeralIdentity(data, addon.IsAssignedGroupTank(unit)) end
    -- Pet names ("Wolf", "Imp") are not unique; pets never enter the name cache.
    if name and name ~= "" and not isPet then cacheByName[name] = data end
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
            local name = UnitName(petUnit)
            if name and name ~= "" and name ~= UNKNOWN then
                set[name] = true
                local guid = UnitGUID(petUnit)
                local ownerClass = ownerUnit and UnitExists(ownerUnit) and select(2, UnitClass(ownerUnit)) or nil
                NotePetOwner(guid, name, ownerClass)
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
    if not guid or IsSuppressedPetGUID(guid) then return false end
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
    if type(name) ~= "string" or name == "" or not IsPlayerGUID(guid) then return end
    if name == UNKNOWNOBJECT or name == UNKNOWN then return end
    if not auraClassByGUID[guid] then
        if not classFile and GetPlayerInfoByGUID then
            local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
            if ok then classFile = c end
        end
        if type(classFile) == "string" and classFile ~= "" then auraClassByGUID[guid] = classFile end
    end
    local short = ShortName(name)
    if auraNameByGUID[guid] == short then return end
    if not auraNameByGUID[guid] then
        auraNameCount = auraNameCount + 1
        if auraNameCount > 2000 then
            wipe(auraGUIDByName); wipe(auraNameByGUID); wipe(auraClassByGUID); auraNameCount = 1
            if type(classFile) == "string" and classFile ~= "" then auraClassByGUID[guid] = classFile end
        end
    end
    auraNameByGUID[guid] = short
    local old = auraGUIDByName[short]
    if old == nil or old == guid then auraGUIDByName[short] = guid else auraGUIDByName[short] = false end
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
local function AuraKeyForPlate(name, classFile)
    if type(name) ~= "string" or name == "" then return nil end
    local g = auraGUIDByName[ShortName(name)]
    if not g then return nil end
    if not (ccStackByGUID[g] or auraByGUID[g]) then return nil end
    local known = (cacheByGUID[g] and cacheByGUID[g].class) or (enemySpecByGUID[g] and enemySpecByGUID[g].class)
        or auraClassByGUID[g]
    if classFile and known and known ~= classFile then return nil end
    return g
end

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
    return true
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
    local showUnknown = cfg.showUnknownFriendly ~= false and not classHidden and not specHidden
    local hasSpec = data.specTexture ~= nil and not specHidden

    if not isPet and classFile == "DRUID" and data.spec == "FERAL" then
        -- a known Feral tank (assigned tank, or Bear talents) shows the
        -- TANK icon only while "Show tank icon" is on; otherwise Bear/Cat form.
        if (data.isTank or data.feralKind == "BEAR") and cfg.useTankIcon ~= false then
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
            if addon._debugWatchGUID == data.guid then
                if addon._debugEnabled then D("DISPLAY", "SPEC transition ARMED guid=%s spec=%s deadline=%.3f delay=%.3f", tostring(data.guid), tostring(data.spec), data._specDisplayAt, tonumber(cfg.classToSpecDelay) or 1.0) end
            end
        end

        if now >= data._specDisplayAt then
            ov._specTransitionAt = nil
            ov._specTransitionGUID = nil
            if addon._debugWatchGUID == data.guid and ov._debugSpecCompleted ~= data.spec then
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
    if showUnknown and not isPet then
        return "UNKNOWN", addon.UNKNOWN_ICON, true, 1
    end
    return nil
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
        if cfg.enemyShowUnknown and not specHidden and not classHidden then
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
    elseif mode == "TANK" and (data.isTank or data.feralKind == "BEAR") then
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
    local classFile = data.class
    local isHealer = data.isHealer
    local isTank = data.isTank or data.feralKind == "BEAR"
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
    if ApplyAuraOverlay(ov, guid, unit, nil, target, enemy) then ApplyPetBorder(ov, ownerClass, target) end
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
    if guid then ov._guid = guid end
    local classFile = data.class or liveClass
    local isPet = data.isPet or IsPetUnit(unit)
    -- Inspection/group data always wins; a combat-log spec only fills the gap.
    local sig = not isPet and not data.specTexture and EnemySpec(guid, name, classFile)
    local view = ov._enemyView or {}
    ov._enemyView = view
    view.guid = guid
    view.specTexture = data.specTexture or (sig and sig.texture)
    -- the spec name comes from the same source as its texture (filters).
    if data.specTexture then view.spec = data.spec else view.spec = sig and sig.spec or nil end
    view.isHealer = data.isHealer or (sig and sig.role == "HEALER") or false
    -- a Feral in Bear form (Mangle Bear signature or inspected Bear talents)
    -- counts as a tank when "Show enemy tank icons" is on, matching friendly bears.
    local feralBear = (sig and sig.kind == "BEAR") or data.feralKind == "BEAR"
    view.isTank = data.isTank or (sig and sig.role == "TANK")
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
        DCompact("PLATE", guid, "UpdatePlate name=%s guid=%s unit=%s reaction=%s type=%s friendly=%s class=%s spec=%s tex=%s healer=%s tank=%s", tostring(name), tostring(guid), tostring(unit), tostring(reaction), tostring(ptype), tostring(isFriendly), tostring(data and data.class), tostring(data and data.spec), tostring(data and data.specTexture), tostring(data and data.isHealer), tostring(data and data.isTank))
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
        liveClass = (guid == nil or IsPlayerGUID(guid)) and LibNameplates.GetClass and LibNameplates:GetClass(plate) or nil
        if not IsPlayerGUID(guid) and not liveClass then
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
        if guid then
            TryExactUpgrade(guid, GetTime())
        else
            local key = AuraKeyForPlate(name, isFriendly and data and data.class or liveClass)
            if key then
                TryExactUpgrade(key, GetTime())
                ov._auraGUID = key
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
    if type(flags) ~= "number" or not bit then return nil end
    return bit.band(flags, 0x10) == 0
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
    if not DR_ALWAYS[drCat] and type(flags) == "number" and bit and bit.band(flags, 0x100) == 0 then return 1 end
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

local function NoteCrowdControl(destGUID, flags, spellID, category, now, refresh)
    local cfg = DB()
    if not CCWanted(cfg, DestSide(flags)) then return false end
    -- the DR step always advances (a later estimate must know it), on
    -- every side; an exact read below still wins for the drawn duration.
    local reset = DRReset()
    local base = addon.CrowdControlBaseDuration[spellID] or learnedDuration[spellID]
    local factor, state = ApplyDR(destGUID, DRCategory(spellID, category), now, flags, refresh)
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
        if ccStackCount > 300 then wipe(ccStackByGUID); wipe(ccByGUID); ccStackCount = 1 end
        stack = {}
        ccStackByGUID[destGUID] = stack
    end
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
    return true
end

-- the CC/aura that ended; the DR timer runs from its removal.
local function NoteAuraRemoved(destGUID, spellID, spellName, now)
    local changed = false
    local stack = ccStackByGUID[destGUID]
    if stack and stack[spellID] then
        stack[spellID] = nil
        PickCC(destGUID, now)
        changed = true
    end
    local aura = auraByGUID[destGUID]
    if aura and aura.spellID == spellID then auraByGUID[destGUID] = nil; changed = true end
    local states = drByGUID[destGUID]
    if states then
        local drCat = DRCategory(spellID, addon.GetCrowdControlCategory(spellID, spellName))
        local s = drCat and states[drCat]
        if s then s.resetAt = now + DRReset() end
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
local CCEvents = { CrowdControl = NoteCrowdControl, WhitelistedAura = NoteWhitelistedAura, AuraRemoved = NoteAuraRemoved }
function CCEvents.NamesAndDeaths(subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags)
    if bit then
        if type(destFlags) == "number" and bit.band(destFlags, 0x400) ~= 0 then NoteAuraName(destGUID, destName) end
        if type(sourceFlags) == "number" and bit.band(sourceFlags, 0x400) ~= 0 then NoteAuraName(sourceGUID, sourceName) end
    end
    if destGUID and (subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED") then return NoteUnitDied(destGUID) end
    return false
end

function CCEvents.WipeNames()
    wipe(auraGUIDByName); wipe(auraNameByGUID); wipe(auraClassByGUID); auraNameCount = 0
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
    if not enemySpecActive then
        wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 0
    end
    auraTrackActive = not cfg or SideEnabled(cfg, false) or SideEnabled(cfg, true)
    if not auraTrackActive then
        wipe(ccByGUID); wipe(ccStackByGUID); ccStackCount = 0; wipe(auraByGUID); wipe(drByGUID); drCount = 0
        CCEvents.WipeNames()
    end
end
addon.UpdateSpecHibernation = UpdateHibernation

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- WotLK 3.3.5 fires the classic COMBAT_LOG_EVENT_UNFILTERED payload directly.
        -- read by position; no table allocated per combat-log event.
        local _, subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, _, auraType = ...
        local changed = false

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
        -- only players can gain a class here, and a player without a
        -- unit token is looked up at most every 2 s instead of scanning ~105 unit
        -- tokens for every creature event and every tokenless enemy event.
        if spellID and IsPlayerGUID(sourceGUID) and not cacheByGUID[sourceGUID]
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
        -- enemy specs: one table lookup per hostile player spell event.
        -- skipped entirely when no enemy option uses spec/role (hibernation).
        if enemySpecActive and spellName and SIGNATURE_EVENTS[subEvent] and type(sourceFlags) == "number" and bit
            and bit.band(sourceFlags, 0x440) == 0x440 and IsPlayerGUID(sourceGUID)
            and NoteEnemySpec(sourceGUID, sourceName, spellName) then
            changed = true
        end
        -- party/raid members' talent spells (affiliation 0x6,
        -- player 0x400) for Healer-in-CC until inspection/comm knows them.
        if spellName and SIGNATURE_EVENTS[subEvent] and type(sourceFlags) == "number" and bit
            and bit.band(sourceFlags, 0x400) ~= 0 and bit.band(sourceFlags, 0x6) ~= 0 and IsPlayerGUID(sourceGUID) then
            local sig = Signatures()[spellName]
            local old = sig and groupSpecByGUID[sourceGUID]
            -- same class -> the stronger/equal hint wins; another class only
            -- when strictly stronger (a shared spell name never flips a class).
            if sig and (not old or (old.class == sig.class and old.strength <= sig.strength)
                or (old.class ~= sig.class and sig.strength > old.strength)) then
                if not old then
                    groupSpecCount = groupSpecCount + 1
                    if groupSpecCount > 200 then wipe(groupSpecByGUID); groupSpecCount = 1 end
                end
                groupSpecByGUID[sourceGUID] = sig
            end
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
                    changed = true
                end
                -- players and their pets only (estimate + DR, see NoteCrowdControl).
                if auraTrackActive and (IsPlayerGUID(destGUID) or IsIconPetGUID(destGUID)) then
                    local category = addon.GetCrowdControlCategory(spellID, spellName)
                    if category then
                        if CCEvents.CrowdControl(destGUID, destFlags, spellID, category, now, subEvent == "SPELL_AURA_REFRESH") then changed = true end
                    elseif (auraType == "BUFF" or auraType == "DEBUFF")
                        and CCEvents.WhitelistedAura(destGUID, destFlags, spellID, auraType, now) then
                        changed = true
                    end
                end
            elseif subEvent == "SPELL_AURA_REMOVED" then
                if addon.FLAG_AURAS[spellID] and ClearFlagCarrier(destGUID) then
                    changed = true
                end
                if CCEvents.AuraRemoved(destGUID, spellID, spellName, now) then changed = true end
            elseif subEvent == "SPELL_AURA_BROKEN" or subEvent == "SPELL_AURA_BROKEN_SPELL" then
                -- a CC broken by damage/a spell is gone at once.
                if CCEvents.AuraRemoved(destGUID, spellID, spellName, now) then changed = true end
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
            wipe(enemySpecByGUID); wipe(enemySpecByName); enemySpecCount = 0
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
        local oldTargetGUID = prevTargetGUID
        prevTargetGUID = UnitGUID("target")
        RememberUnit("target"); RememberUnit("focus")
        LearnPetUnit("target"); LearnPetUnit("focus")
        if addon.TalentScanner then
            if SpecDetectionNeeded("target") then addon.TalentScanner:InspectNow("target") end
            if SpecDetectionNeeded("focus") then addon.TalentScanner:InspectNow("focus") end
        end
        -- Force refresh for both old and new target to ensure target highlight updates correctly
        if oldTargetGUID and oldTargetGUID ~= prevTargetGUID then
            addon:RequestRefreshNameplateOverlayGUID(oldTargetGUID)
        end
        if prevTargetGUID then
            addon:RequestRefreshNameplateOverlayGUID(prevTargetGUID)
        end
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











