local _, addon = ...

-- One worker reads the game API for an immutable GUID transaction.
-- client rule (verified against historical logs): INSPECT_TALENT_READY
-- fires only for a reply whose GUID equals the most recent NotifyInspect GUID,
-- whoever called it. The buffer therefore always belongs to lastNotifyGUID.
-- External NotifyInspect calls (TipTac, GearScore, MRT, InspectFrame...) are
-- observed and their replies harvested from the global buffer only; no addon
-- caches are read and no calls are suppressed or replaced.
local Scanner = {}
addon.TalentScanner = Scanner
addon._TalentCache = {}
local frame = CreateFrame("Frame")
local queue, queued = {}, {}
local cooldown = {}
local active, sending, saved
local generation, nextTick = 0, 0
local lastNotifyGUID, lastNotifyUnit, lastNotifyAt = nil, nil, 0
local foreignGUID, foreignUntil = nil, 0
local pumpBlock
local handoffPending = false
local nextGroupScan = 0
local lastGroupAttempt = {}
local REQUEST_TIMEOUT, READ_TIMEOUT, FOREIGN_GRACE = 1.5, 0.4, 0.30
local CACHE_AGE, RETAIN_AGE, MAX_RECORDS = 1800, 604800, 1000
local MAX_ATTEMPTS, WAIT_AGE = 3, 120

local function D(tag, text, ...)
    if addon.DebugLog then addon:DebugLog(tag, text, ...) end
end

local function IsPlayer(unit)
    return unit and UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player")
end

local function Complete(data)
    return data and data.spec and data.specTexture and data.class
end

local function Fresh(data)
    return Complete(data) and data.learnedAt and time() - data.learnedAt >= 0
        and time() - data.learnedAt < CACHE_AGE
end

local units = { "mouseover", "target", "focus", "targettarget", "focustarget", "mouseovertarget", "pettarget" }
for i = 1, 4 do
    units[#units + 1] = "party" .. i
    units[#units + 1] = "party" .. i .. "target"
    units[#units + 1] = "partypet" .. i .. "target"
end
for i = 1, 40 do
    units[#units + 1] = "raid" .. i
    units[#units + 1] = "raid" .. i .. "target"
    units[#units + 1] = "raidpet" .. i .. "target"
end
for i = 1, 5 do
    units[#units + 1] = "arena" .. i
    units[#units + 1] = "arena" .. i .. "target"
end

-- optional awesome_wotlk client patch support (option default OFF).
-- While plateMode is nil nothing below registers events, allocates tables or
-- runs, and Resolve keeps the same behavior. When ON, a stranger stays addressable
-- through his nameplate unit after the mouseover token has left him; the
-- token is only ever used after an exact UnitGUID(token) == guid check.
local plateMode, plateFrame, plateGUID, plateToken, plateLookup, plateFrameGUID
local plateMax, plateRescanAt = 0, 0

-- (option ON + native C_NamePlate.GetGUIDForNamePlate only): the
-- client's own GUID for a nameplate frame, for plates LibNameplates has not
-- bound yet. Returns nil otherwise; never guesses by name.
local function IsZeroGUID(guid)
    -- "0x0", "0x0000000000000000": a plate slot that has no owner yet. Every
    -- player-GUID test in this addon is a prefix test (players are the only
    -- units whose high half is zero), so the zero GUID would read as a player
    -- and an NPC would be drawn as an unknown player. Never an owner.
    return guid:lower():match("^0x0+$") ~= nil
end

function Scanner:PlateGUID(plate)
    if not plateFrameGUID or type(plate) ~= "table" then return nil end
    local ok, guid = pcall(plateFrameGUID, plate)
    if ok and type(guid) == "string" and guid ~= "" and not IsZeroGUID(guid) then return guid end
end

local function PlateUnit(guid)
    local ok, unit
    if plateLookup then
        -- the detected native function itself is kept; no global is indexed here.
        ok, unit = pcall(plateLookup, guid)
    else
        ok, unit = true, plateGUID and plateGUID[guid]
    end
    if ok and type(unit) == "string" and IsPlayer(unit) and UnitGUID(unit) == guid then return unit end
    if plateMode ~= "events" or GetTime() < plateRescanAt then return end
    -- A plate slot can be reused for another unit without an event: rebuild
    -- the map at most every 0.25s, never per queued player.
    plateRescanAt = GetTime() + 0.25
    wipe(plateGUID); wipe(plateToken)
    for i = 1, plateMax do
        unit = "nameplate" .. i
        local g = UnitIsPlayer(unit) and UnitGUID(unit)
        if g then plateGUID[g], plateToken[unit] = unit, g end
    end
    unit = plateGUID[guid]
    if unit and IsPlayer(unit) and UnitGUID(unit) == guid then return unit end
end

-- a player's nameplate unit (option ON only; nil otherwise). Exact
-- UnitGUID(token) == guid check inside PlateUnit.
function Scanner:PlateUnitForGUID(guid)
    if plateMode and guid then return PlateUnit(guid) end
end

local function Resolve(guid)
    for _, unit in ipairs(units) do
        if IsPlayer(unit) and UnitGUID(unit) == guid then return unit end
    end
    if plateMode then return PlateUnit(guid) end
end

local function Inspectable(unit)
    if not IsPlayer(unit) then return false, "not-player" end
    local level = UnitLevel(unit)
    if level and level ~= -1 and level < 10 then return false, "level-below-10" end
    if CanInspect and not CanInspect(unit) then return false, "CanInspect=false" end
    if CheckInteractDistance and not CheckInteractDistance(unit, 4) then return false, "out-of-inspect-distance" end
    if UnitIsConnected and not UnitIsConnected(unit) then return false, "disconnected" end
    return true
end

local function Refresh(guid)
    addon._debugWatchGUID = guid
    if addon.RequestRefreshNameplateOverlayGUID then addon:RequestRefreshNameplateOverlayGUID(guid) end
    if addon.RequestRefreshNameplateOverlays then addon:RequestRefreshNameplateOverlays() end
end

local function Remove(request)
    queued[request.guid] = nil
    for i, entry in ipairs(queue) do
        if entry == request then table.remove(queue, i); return end
    end
end

-- An interrupted revalidation of an already-known player is not retried from
-- the queue: the next hover revalidates again. Unknown players stay queued.
local function Revalidation(request)
    return not request.groupOnly and Complete(addon._TalentCache[request.guid])
end

local function Finish(reason, retry)
    local tx = active
    active = nil -- drops ALL deferred read state with the immutable transaction
    if not tx then return end
    if addon._debugEnabled then D("RESULT", "id=%d guid=%s state=%s attempts=%d", tx.id, tx.guid, reason, tx.request.attempts) end
    if retry and not tx.counted and Revalidation(tx.request) then
        Remove(tx.request)
    elseif retry and tx.request.attempts < MAX_ATTEMPTS then
        tx.request.notBefore = GetTime() + 0.5
    else
        Remove(tx.request)
        if retry then cooldown[tx.guid] = GetTime() + 15 end
    end
    -- Never start another request inside a ready-event callback: other
    -- listeners must read the buffer first. The next OnUpdate hands off.
    handoffPending = true
end

-- A newer NotifyInspect for another GUID (or a clear) suppresses this reply.
-- That is not the player's fault: re-queue with no attempt penalty.
local function Requeue(reason)
    local tx = active
    active = nil
    if not tx then return end
    local request = tx.request
    if tx.ready then
        -- this player's reply already arrived but could not be read (e.g.
        -- no talent points): the attempt counts and backs off, so a player who
        -- stays addressable (nameplate) is not re-asked forever.
        if not tx.counted then request.attempts = request.attempts + 1 end
        if request.attempts >= MAX_ATTEMPTS then
            Remove(request)
            cooldown[tx.guid] = GetTime() + 15
            if addon._debugEnabled then D("RESULT", "id=%d guid=%s state=%s attempts=%d requeued=false unreadable-reply",
                tx.id, tx.guid, reason, request.attempts) end
            return
        end
        request.notBefore = GetTime() + 0.5
    else
        if tx.counted then request.attempts = math.max(0, request.attempts - 1) end
        request.notBefore = 0
    end
    local drop = Revalidation(tx.request)
    if drop then Remove(tx.request) end
    if addon._debugEnabled then D("RESULT", "id=%d guid=%s state=%s attempts=%d requeued=%s", tx.id, tx.guid, reason,
        tx.request.attempts, tostring(not drop)) end
end

local function Begin(request, unit, own, mode)
    generation = generation + 1
    local now = GetTime()
    if own then request.attempts = request.attempts + 1 end
    local tx = { id = generation, guid = request.guid, name = request.name, class = request.class,
        unit = unit, sent = now, deadline = now + REQUEST_TIMEOUT, request = request,
        adopted = not own, counted = own }
    active = tx
    if addon._debugEnabled then D("INSPECT", "id=%d %s guid=%s name=%s unit=%s attempt=%d", tx.id, mode,
        tx.guid, tostring(tx.name), tostring(unit), request.attempts) end
    return tx
end

local function MarkReady(tx)
    if not tx.ready then
        tx.ready = true
        tx.readDeadline = GetTime() + READ_TIMEOUT
    end
    tx.nextRead = GetTime() + 0.03
end

local function HasTalent(group, tab, wanted)
    local count = GetNumTalents and GetNumTalents(tab, true, group) or 0
    for i = 1, count do
        local name, _, _, _, rank = GetTalentInfo(tab, i, true, nil, group)
        if wanted[name] and (tonumber(rank) or 0) > 0 then return true end
    end
end

local function FeralRole(group, tab)
    -- Preserve the previous talent-based classification (English talent names).
    if HasTalent(group, tab, { ["Thick Hide"] = true, ["Natural Reaction"] = true,
        ["Protector of the Pack"] = true }) then return "TANK" end
    if HasTalent(group, tab, { ["Feral Aggression"] = true, ["Primal Fury"] = true,
        ["Shredding Attacks"] = true, ["Primal Tenacity"] = true,
        ["Nurturing Instinct"] = true }) then return "DAMAGER" end
end

local function ReadSnapshot(tx)
    if active ~= tx or not tx.ready or lastNotifyGUID ~= tx.guid then return false end
    local map = addon.TALENT_TAB_SPECS[tx.class]
    if not map then return false end
    local group = GetActiveTalentGroup and GetActiveTalentGroup(true) or 1
    if type(group) ~= "number" or group < 1 or group > 2 then return false end
    local points, best, bestPoints, texture = {}, nil, -1, nil
    for tab = 1, 3 do
        local name, icon, spent = GetTalentTabInfo(tab, true, nil, group)
        if not name or type(spent) ~= "number" or spent < 0 then return false end
        points[tab] = spent
        if spent > bestPoints then best, bestPoints, texture = tab, spent, icon end
    end
    if bestPoints <= 0 or not texture or texture == "" or not map[best] then return false end
    local spec = map[best]
    local role = addon.SPEC_ROLES[tx.class] and addon.SPEC_ROLES[tx.class][spec]
    if tx.class == "DRUID" and spec == "FERAL" then role = FeralRole(group, best) end
    local feralKind
    if tx.class == "DRUID" and spec == "FERAL" and addon.ClassifyFeralRanks then
        feralKind = addon.ClassifyFeralRanks(function(index)
            if index > (GetNumTalents(2, true, nil, group) or 0) then return 0 end
            -- parentheses keep only the rank (maxRank was passed as tonumber's base).
            return tonumber((select(5, GetTalentInfo(2, index, true, nil, group)))) or 0
        end)
        role = nil -- assignment controls Tank icon; talents control Bear/Cat icon
        if feralKind == "CAT" then texture = "Interface\\Icons\\Ability_Druid_CatForm" end
    end
    -- Replace atomically: never combine a new spec with an old spec's texture.
    local data = { guid = tx.guid, name = tx.name, class = tx.class, spec = spec,
        specTexture = texture, specRole = role, points = points, group = group,
        source = "OPInspect", feralKind = feralKind, updatedAt = GetTime(), learnedAt = time() }
    addon._TalentCache[tx.guid] = data
    if saved then
        saved[tx.guid] = data
        local count, oldestGUID, oldestTime = 0, nil, math.huge
        for guid, record in pairs(saved) do
            count = count + 1
            if guid ~= tx.guid and (record.learnedAt or 0) < oldestTime then
                oldestGUID, oldestTime = guid, record.learnedAt or 0
            end
        end
        if count > MAX_RECORDS and oldestGUID then
            saved[oldestGUID] = nil
        end
    end
    if addon._debugEnabled then D("CACHE", "id=%d STORE guid=%s name=%s spec=%s points=%d/%d/%d icon=%s", tx.id,
        tx.guid, tostring(tx.name), spec, points[1], points[2], points[3], tostring(texture)) end
    Finish(tx.adopted and "ACCEPTED_SHARED" or "ACCEPTED", false)
    Refresh(tx.guid)
    return true
end

local function Send(request, unit)
    foreignGUID, foreignUntil = nil, 0 -- our request supersedes the foreign reply anyway
    local tx = Begin(request, unit, true, "START")
    sending = tx
    local ok, err = pcall(NotifyInspect, unit)
    sending = nil
    if not ok then
        if addon._debugEnabled then D("INSPECT", "id=%d API-error=%s", tx.id, tostring(err)) end
        Finish("API_ERROR", true)
    end
end

local function Pump()
    -- handoffPending: never send inside a ready-event dispatch; other
    -- listeners (TipTac etc.) are still reading the buffer.
    if not Scanner._initialized or active or handoffPending then return end
    local now = GetTime()
    local block = InspectFrame and InspectFrame:IsShown() and "InspectFrame-shown"
        or (Examiner and type(Examiner) == "table" and Examiner.IsShown and Examiner:IsShown() and "Examiner-shown")
    if block then
        if pumpBlock ~= block and #queue > 0 then if addon._debugEnabled then D("QUEUE", "BLOCK reason=%s", block) end end
        pumpBlock = block
        return
    end
    pumpBlock = nil
    -- An external request for a GUID we cannot use (e.g. MRT self-inspect) is
    -- given a short grace so its reply is not suppressed. A live hover token
    -- is fleeting and is exempt.
    local foreign = now < foreignUntil
    local chosen, chosenUnit, chosenRank = nil, nil, -1
    local i = 1
    while i <= #queue do
        local request = queue[i]
        if (not request.force and Fresh(addon._TalentCache[request.guid])) or now - request.seen > WAIT_AGE then
            if addon._debugEnabled then D("QUEUE", "retire guid=%s reason=%s", request.guid,
                Fresh(addon._TalentCache[request.guid]) and "cached" or "discovery-expired") end
            Remove(request)
        else
            local unit = Resolve(request.guid)
            local inspectable, reason = Inspectable(unit)
            local ok = now >= request.notBefore and inspectable and UnitGUID(unit) == request.guid
            if ok and foreign and unit ~= "mouseover" then ok, reason = false, "foreign-inspect-pending" end
            if ok then
                -- Unknown players before revalidations; background group work
                -- last; the fleeting mouseover token before other tokens.
                local rank = (request.groupOnly and 0 or 4)
                    + (Complete(addon._TalentCache[request.guid]) and 0 or 2)
                    + (unit == "mouseover" and 1 or 0)
                if rank > chosenRank then chosen, chosenUnit, chosenRank = request, unit, rank end
            else
                reason = not unit and "no-unit-token" or now < request.notBefore and "retry-backoff"
                    or reason or "guid-changed"
                if request.waitReason ~= reason then
                    request.waitReason = reason
                    if addon._debugEnabled then D("QUEUE", "WAIT guid=%s reason=%s", request.guid, reason) end
                end
            end
            i = i + 1 -- an unavailable stranger must not block addressable players
        end
    end
    if chosen then
        chosen.waitReason = nil
        Send(chosen, chosenUnit)
    end
end

function Scanner:Get(unitOrGUID)
    local guid = unitOrGUID
    if type(unitOrGUID) == "string" and UnitExists(unitOrGUID) then guid = UnitGUID(unitOrGUID) end
    return guid and addon._TalentCache[guid]
end

-- Returns the request for unit's GUID (creating it), true for "fresh, nothing
-- to do", or nil. adopt=true is used for observed external requests: their
-- reply costs nothing, so cooldown and freshness do not prevent harvesting it.
local function Enlist(unit, force, groupOnly, adopt)
    if not IsPlayer(unit) then return nil end
    local guid = UnitGUID(unit)
    local _, class = UnitClass(unit)
    if not guid or not addon.TALENT_TAB_SPECS[class] then return nil end
    local old = addon._TalentCache[guid]
    if old and old.class ~= class then
        addon._TalentCache[guid] = nil
        if saved then saved[guid] = nil end
        cooldown[guid] = nil
        if addon._debugEnabled then D("CACHE", "INVALIDATE guid=%s reason=class-changed old=%s new=%s", guid, tostring(old.class), class) end
        Refresh(guid)
    end
    if not adopt then
        if not force and cooldown[guid] and GetTime() < cooldown[guid] then return nil end
        if not force and Fresh(addon._TalentCache[guid]) then return true end
    end
    local request = queued[guid]
    if not request then
        request = { guid = guid, name = UnitName(unit), class = class,
            force = force, groupOnly = groupOnly == true, seen = GetTime(), notBefore = 0, attempts = 0 }
        queued[guid] = request
        queue[#queue + 1] = request
        if addon._debugEnabled then D("QUEUE", "ADD guid=%s name=%s depth=%d%s", guid, tostring(request.name), #queue,
            adopt and " source=observed" or "") end
    else
        request.seen = GetTime()
        request.force = request.force or force
        if not groupOnly and not adopt then request.groupOnly = false end
    end
    return request
end

function Scanner:Queue(unit, force, groupOnly)
    if not self._initialized then return false end
    local request = Enlist(unit, force, groupOnly, false)
    if request == nil then return false end
    if request == true then return true end
    -- An unknown player the user is pointing at outranks our own background
    -- revalidation of an already-known GUID (or a group-only refresh). The
    -- preempted request stays queued with no attempt penalty. Never preempt an
    -- observed external request or another unknown player (first one wins).
    local tx = active
    if tx and tx.guid ~= request.guid and not tx.adopted and not tx.ready and not handoffPending and not groupOnly
        and not Complete(addon._TalentCache[request.guid])
        and (Complete(addon._TalentCache[tx.guid]) or tx.request.groupOnly)
        and Inspectable(unit) and not (InspectFrame and InspectFrame:IsShown()) then
        if addon._debugEnabled then D("INSPECT", "id=%d PREEMPT guid=%s by=%s unit=%s", tx.id, tx.guid, request.guid, unit) end
        Requeue("PREEMPTED_BY_UNKNOWN")
        Send(request, unit)
        return true
    end
    Pump()
    return true
end

-- Explicit user discovery revalidates even fresh persistent/session records.
-- Calls for an already active/queued GUID coalesce into the same transaction.
function Scanner:Mouseover()
    return self:Queue("mouseover", true)
end

local function ScanGroup()
    local now = GetTime()
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    if raid == 0 and party == 0 then return end
    local prefix, count = raid > 0 and "raid" or "party", raid > 0 and raid or party
    -- hibernate when no friendly spec/role option nor Healer-in-CC needs it.
    if addon.SpecDetectionNeeded and not addon.SpecDetectionNeeded(prefix .. "1") then return end
    for i = 1, count do
        local unit = prefix .. i
        local guid = IsPlayer(unit) and UnitGUID(unit)
        local record = guid and addon._TalentCache[guid]
        local remoteFresh = record and record.source == "GroupComm" and now - record.updatedAt < 35
        if guid and not remoteFresh and Inspectable(unit) and not queued[guid]
            and (not lastGroupAttempt[guid] or now - lastGroupAttempt[guid] >= 30) then
            lastGroupAttempt[guid] = now
            -- Automatic revalidation is throttled separately from explicit hover.
            -- Do not force past a failed-request cooldown.
            if not cooldown[guid] or now >= cooldown[guid] then Scanner:Queue(unit, true, true) end
        end
    end
end

-- The communication decoder supplies roster-validated, GUID-specific data.
-- Never read the global inspect buffer in response to a communication callback.
function Scanner:ReceiveGroupTalents(unit, points, role, feralKind)
    if not self._initialized or not IsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    local _, class = UnitClass(unit)
    local map = addon.TALENT_TAB_SPECS[class]
    if not guid or not map then return end
    local best = 1
    for i = 2, 3 do if points[i] > points[best] then best = i end end
    if points[best] <= 0 then return end
    local spec = map[best]
    local texture = addon.SPEC_TREE_ICONS[class] and addon.SPEC_TREE_ICONS[class][spec]
    if not texture then return end
    if class ~= "DRUID" or spec ~= "FERAL" then role = addon.SPEC_ROLES[class] and addon.SPEC_ROLES[class][spec] end
    local data = { guid = guid, name = UnitName(unit), class = class, spec = spec,
        specTexture = texture, specRole = role, points = points, source = "GroupComm",
        feralKind = feralKind, updatedAt = GetTime(), learnedAt = time() }
    addon._TalentCache[guid] = data
    if saved then saved[guid] = data end
    -- Drain an outstanding same-player request before another GUID is inspected.
    if active and active.guid == guid then Finish("GROUP_COMM_ACCEPTED", false)
    elseif queued[guid] then Remove(queued[guid]) end
    if addon._debugEnabled then D("CACHE", "GROUP STORE guid=%s spec=%s points=%d/%d/%d", guid, spec, points[1], points[2], points[3]) end
    Refresh(guid)
end

-- Compatibility entry point: target/focus use the same worker, never a second path.
function Scanner:InspectNow(unit, force) return self:Queue(unit, force) end

local function Caller()
    if not addon._debugEnabled or not debugstack then return "unavailable" end
    return (debugstack(3, 5, 0):gsub("[\r\n]+", " <- "))
end

local intentUnits = { mouseover = true, target = true, focus = true }

-- Observe only. Every caller (OPlates included) moves the client's reply filter to
-- the newest GUID, so the newest GUID is the only reply that can be read.
if hooksecurefunc then
    hooksecurefunc("NotifyInspect", function(unit)
        local guid = unit and UnitGUID(unit)
        lastNotifyGUID, lastNotifyUnit, lastNotifyAt = guid, unit, GetTime()
        if sending and active == sending and guid == sending.guid then return end
        if addon._debugEnabled then D("HOOK", "EXTERNAL NotifyInspect unit=%s guid=%s active=%s caller=%s",
            tostring(unit), tostring(guid), tostring(active and active.id), Caller()) end
        if not Scanner._initialized then return end
        if active and guid and guid == active.guid then
            active.shared = true
            if addon._debugEnabled then D("HOOK", "SAME_GUID retained id=%d guid=%s", active.id, guid) end
            return
        end
        -- Our outstanding reply (if any) can no longer produce an event.
        if active then Requeue("EXTERNAL_NOTIFY_DIFFERENT_GUID") end
        -- spec detection hibernating for this unit: do not adopt the reply.
        if addon.SpecDetectionNeeded and unit and not addon.SpecDetectionNeeded(unit) then
            foreignGUID, foreignUntil = guid, GetTime() + FOREIGN_GRACE
            return
        end
        local request = guid and Enlist(unit, true, not intentUnits[unit], true)
        if type(request) == "table" then
            foreignGUID, foreignUntil = nil, 0
            Begin(request, unit, false, "ADOPT")
        else
            -- e.g. MRT self-inspect: do not stomp its reply, but never block long.
            foreignGUID, foreignUntil = guid, GetTime() + FOREIGN_GRACE
            if addon._debugEnabled then D("HOOK", "FOREIGN guid=%s grace=%.2f", tostring(guid), FOREIGN_GRACE) end
        end
    end)
    hooksecurefunc("ClearInspectPlayer", function()
        lastNotifyGUID, lastNotifyUnit = nil, nil
        if sending then return end
        if addon._debugEnabled then D("HOOK", "EXTERNAL ClearInspectPlayer active=%s caller=%s", tostring(active and active.id), Caller()) end
        if active then Requeue("EXTERNAL_CLEAR") end
    end)
end

frame:RegisterEvent("INSPECT_TALENT_READY")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "INSPECT_TALENT_READY" then
        nextGroupScan = 0
        if (GetNumRaidMembers and GetNumRaidMembers() or 0) == 0
            and (GetNumPartyMembers and GetNumPartyMembers() or 0) == 0 then
            if active and active.request.groupOnly then Finish("LEFT_GROUP", false) end
            for i = #queue, 1, -1 do if queue[i].groupOnly then Remove(queue[i]) end end
            lastGroupAttempt = {}
        end
        return
    end
    if addon._debugEnabled then
        local args = {}
        for i = 1, select("#", ...) do args[i] = tostring(select(i, ...)) end
        D("EVENT", "%s active=%s argc=%d args=%s buffer=%s unit=%s age=%.3f", event, tostring(active and active.id),
        select("#", ...), table.concat(args, ","), tostring(lastNotifyGUID), tostring(lastNotifyUnit),
        GetTime() - lastNotifyAt)
    end
    -- Stock 3.3.5 events are anonymous; the client only raises this event for
    -- the newest NotifyInspect GUID, so the buffer belongs to lastNotifyGUID.
    local guid = lastNotifyGUID
    -- Let every other listener read the buffer before anyone sends again.
    handoffPending = true
    if guid and guid == foreignGUID then foreignUntil = 0 end
    local tx = active
    if not guid then
        if addon._debugEnabled then D("INSPECT", "READY ignored reason=cleared") end
        return
    end
    if not tx then
        -- Late or unclaimed reply: harvest it only for a GUID we still want.
        local request = queued[guid]
        if not request then return end
        tx = Begin(request, lastNotifyUnit, false, "LATE")
    elseif tx.guid ~= guid then
        if addon._debugEnabled then D("INSPECT", "READY ignored id=%d reason=buffer-guid=%s", tx.id, guid) end
        return
    end
    MarkReady(tx)
    ReadSnapshot(tx)
end)

frame:SetScript("OnUpdate", function()
    local now = GetTime()
    -- Yield through event dispatch for other readers, then use the first update
    -- instead of losing a short hover to the normal 100ms queue timer.
    local handoff = handoffPending
    handoffPending = false
    if active then
        local tx = active
        if (not tx.ready and now >= tx.deadline) or (tx.ready and now >= tx.readDeadline) then
            Finish(tx.ready and "INCOMPLETE_TIMEOUT" or "NO_EVENT_TIMEOUT", true)
        elseif tx.ready and now >= tx.nextRead then
            tx.nextRead = now + 0.03
            ReadSnapshot(tx)
        end
    end
    if handoff or now >= nextTick then nextTick = now + 0.10; Pump() end
    if Scanner._initialized and now >= nextGroupScan then
        nextGroupScan = now + 2
        ScanGroup()
    end
end)

-- Only functions installed by the client itself count as proof: addon shims
-- (e.g. MRT Compat335 creating C_NamePlate) are tainted, so issecurevariable
-- rejects them. A live nameplateN unit is also proof (stock has no such token).
-- issecurevariable also reports a MISSING (nil) variable as secure, so a
-- function must exist before its security counts (prevents a false "detected" on a
-- stock client, then C_NamePlate nil-index errors).
local function Native(tbl, key, value)
    if type(issecurevariable) ~= "function" then return nil end
    -- 3.3.5a returns 1/nil, not true/false.
    if tbl ~= nil then
        if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then return nil end
        return issecurevariable(tbl, key) and tbl[key] or nil
    end
    if type(value) ~= "function" then return nil end
    return issecurevariable(key) and value or nil
end

-- Returns mode, proof, lookup (the native GUID->token function, if any).
function Scanner:DetectAwesomeWotlk()
    local lookup = Native(nil, "UnitTokenFromGUID", UnitTokenFromGUID)
    if lookup then return "UnitTokenFromGUID", "native UnitTokenFromGUID", lookup end
    local plates = C_NamePlate
    if type(plates) == "table" then
        lookup = Native(plates, "GetNamePlateTokenByGUID")
        if lookup then
            return "GetNamePlateTokenByGUID", "native C_NamePlate.GetNamePlateTokenByGUID", lookup
        end
        if Native(plates, "GetNamePlates") then return "events", "native C_NamePlate.GetNamePlates" end
    end
    for i = 1, 40 do
        if UnitExists("nameplate" .. i) then return "events", "live nameplate" .. i .. " unit" end
    end
    return nil, "not detected"
end

local function PlateEvent(_, event, unit)
    if not plateGUID or type(unit) ~= "string" then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        local index = tonumber(unit:match("^nameplate(%d+)$"))
        if index and index > plateMax then plateMax = math.min(index, 200) end
        local guid = UnitIsPlayer(unit) and UnitGUID(unit)
        if guid then
            plateGUID[guid], plateToken[unit] = unit, guid
            -- class (not spec) is readable from the plate unit at once.
            if addon.OnPlayerNamePlateAdded then addon.OnPlayerNamePlateAdded(unit) end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local guid = plateToken[unit]
        plateToken[unit] = nil
        if guid and plateGUID[guid] == unit then plateGUID[guid] = nil end
    end
end

-- Returns true when nameplate units are in use. With the option OFF and the
-- feature never enabled this returns at once: no frame, table or event exists.
function Scanner:SetPlateUnits(enabled)
    enabled = enabled == true
    if not enabled and not plateMode and not plateFrame then return false end
    local mode, proof, lookup = nil, "option off", nil
    if enabled then mode, proof, lookup = self:DetectAwesomeWotlk() end
    if mode and mode ~= "events" and type(lookup) ~= "function" then mode, proof = nil, "not detected" end
    if plateFrame then
        plateFrame:UnregisterAllEvents()
        plateFrame:SetScript("OnEvent", nil)
    end
    plateGUID, plateToken, plateMax = nil, nil, 0
    plateMode = mode
    plateLookup = mode ~= "events" and lookup or nil
    plateFrameGUID = mode and type(C_NamePlate) == "table" and Native(C_NamePlate, "GetGUIDForNamePlate") or nil
    if mode then
        -- Every detected mode needs the plate events, not just "events".
        --
        -- The lookup modes can turn a GUID into a unit token, but they never learn a CLASS: only
        -- NAME_PLATE_UNIT_ADDED hands us a live nameplateN unit, and UnitClass only answers for a real
        -- unit. A client that exposes UnitTokenFromGUID used to take the lookup branch and skip this
        -- block, so a stranger stayed "?" until he was hovered -- while a client that only exposed
        -- C_NamePlate.GetNamePlates fell through to "events" and worked. Wiring the events in every
        -- mode makes both behave identically, and the lookup stays available on top of it.
        plateFrame = plateFrame or CreateFrame("Frame")
        plateGUID, plateToken = {}, {}
        plateFrame:SetScript("OnEvent", PlateEvent)
        pcall(plateFrame.RegisterEvent, plateFrame, "NAME_PLATE_UNIT_ADDED")
        pcall(plateFrame.RegisterEvent, plateFrame, "NAME_PLATE_UNIT_REMOVED")
        for i = 1, 100 do
            local unit = "nameplate" .. i
            if UnitExists(unit) then PlateEvent(nil, "NAME_PLATE_UNIT_ADDED", unit) end
        end
    end
    self.plateMode = mode
    if addon._debugEnabled then D("SESSION", "awesome_wotlk nameplate units option=%s mode=%s proof=%s",
        tostring(enabled), tostring(mode), proof) end
    return mode ~= nil
end

function Scanner:Initialize()
    if self._initialized then return end
    self._initialized = true
    self.persistenceEnabled = OPlates and OPlates.db
        and OPlates.db.profile.nameplates.persistentTalentCache == true or false
    if addon._debugEnabled then D("SESSION", "OPlates newest-notify attribution / observe-adopt; persistent-cache=%s", tostring(self.persistenceEnabled)) end
    -- the in-world re-check and banner live in Options.lua (AwesomeWotlkLoginCheck).
    if OPlates and OPlates.db and OPlates.db.profile.nameplates.useAwesomeWotlkNameplateUnits == true then
        self:SetPlateUnits(true)
    end
    if not self.persistenceEnabled then
        OPlatesTalentDB = nil
        return -- no saved-record loading, creation, pruning or writes when disabled
    end
    if type(OPlatesTalentDB) ~= "table" or OPlatesTalentDB.schema ~= 1 then
        OPlatesTalentDB = { schema = 1, realms = {} }
    end
    local realm = GetRealmName() or "unknown"
    OPlatesTalentDB.realms = OPlatesTalentDB.realms or {}
    saved = OPlatesTalentDB.realms[realm] or {}
    OPlatesTalentDB.realms[realm] = saved
    local records = {}
    for guid, data in pairs(saved) do
        if type(data) == "table" and Complete(data) and data.guid == guid
            and type(data.learnedAt) == "number" and time() >= data.learnedAt
            and time() - data.learnedAt < RETAIN_AGE then
            records[#records + 1] = data
        else saved[guid] = nil end
    end
    table.sort(records, function(a, b) return a.learnedAt > b.learnedAt end)
    for i, data in ipairs(records) do
        if i <= MAX_RECORDS then addon._TalentCache[data.guid] = data
        else saved[data.guid] = nil end
    end
    if addon._debugEnabled then D("SESSION", "OPlates newest-notify attribution / observe-adopt; loaded=%d realm=%s", math.min(#records, MAX_RECORDS), realm) end
    if LibStub then
        for _, name in ipairs({ "LibNameplates-1.0", "LibTalentQuery-1.0", "LibGroupTalents-1.0" }) do
            local lib, minor = LibStub(name, true)
            if addon._debugEnabled then D("SESSION", "library=%s loaded=%s minor=%s", name, tostring(lib ~= nil), tostring(minor)) end
        end
    end
end
