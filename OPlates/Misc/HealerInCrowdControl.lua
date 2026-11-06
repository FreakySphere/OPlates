local _, addon = ...

-- up to 5 alert frames. Out of combat each frame is bound to one healer
-- of the group; its breaker icon is a secure click spot that casts your
-- dispel on that healer (plain click out of combat, modifier-click in combat).
-- Detection runs only while grouped and only for healer specs:
--   healer: inspection / LibGroupTalents comm > the member's own OPlates message >
--           his talent spells in the combat log > LFD role > self-cast healer aura
--   CC:     his debuffs while he is visible to this client (~100 yd); farther
--           away (other zone/instance) only his own OPlates can report it ("OPlates").
local ICON_SIZE = 48
local PREFIX = "OPlates"
local MAX_FRAMES = 5
local frames = {}   -- [i] = visual alert frame (created on first use)
local clicks = {}   -- [i] = secure click button (created on first use, out of combat)
local slots = {}    -- [i] = { guid = , name = } healer bound to frame i
local isInTest = false
local omniCC = false
local pendingClicks, healersChanged = false, true

-- Player dispels/breakers by debuff type (single-rank spells in 3.3.5a).
local BREAKERS = {
    Magic = { 527, 988, 4987, 32375 },          -- Dispel Magic, Cleanse, Mass Dispel
    Curse = { 475, 2782, 51886 },               -- Remove Curse (Mage/Druid), Cleanse Spirit
    Poison = { 4987, 51886, 526, 2893, 8946 },  -- Cleanse, Cleanse Spirit, Cure Toxins, Abolish/Cure Poison
    Disease = { 4987, 51886, 526, 528, 552 },   -- Cleanse, Cleanse Spirit, Cure Toxins, Cure/Abolish Disease
}
local TREMOR_TOTEM = 8143
-- Tremor Totem removes Fear/Charm/Sleep; horror effects (Death Coil, Psychic
-- Horror) are not fear and are not removed by it.
local TREMOR_CATEGORIES = { fear = true }

-- Click spells per class: first known spell of each list. Classes without a
-- dispel get no click buttons.
local CLICK_SPELLS = {
    PRIEST = { left = { 988, 527 }, right = { 552, 528 } },   -- Dispel Magic / Abolish|Cure Disease
    PALADIN = { left = { 4987 } },                           -- Cleanse
    SHAMAN = { left = { 51886, 526 }, right = { TREMOR_TOTEM } }, -- Cleanse Spirit|Cure Toxins / Tremor Totem
    DRUID = { left = { 2782 }, right = { 2893, 8946 } },     -- Remove Curse / Abolish|Cure Poison
    MAGE = { left = { 475 } },                               -- Remove Curse
}

local healerUnits = {}   -- unit token -> guid, rebuilt every second while grouped
local localCC = {}       -- guid -> CC read from the unit's debuffs
local remoteCC = {}      -- guid -> CC reported by that member's own OPlates
local nameToUnit = {}    -- "Name" / "Name-Realm" -> group unit token
local rosterSeen = {}    -- reused every rebuild (no per-second garbage)
local channel
local selfHealer, selfSent, selfSentAt, selfPending = false, nil, 0, false

local function Cfg() return OPlates.db.profile.misc end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function MaxFrames()
    local n = tonumber(Cfg().healerInCrowdControlMaxFrames) or 3
    if n < 1 then n = 1 elseif n > MAX_FRAMES then n = MAX_FRAMES end
    return math.floor(n)
end

local function GroupSize()
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    return raid, party
end

local function InGroup()
    local raid, party = GroupSize()
    return raid > 0 or party > 0
end

local function KnownSpell(id) return IsSpellKnown and IsSpellKnown(id) end

local function FirstKnown(list)
    if not list then return end
    for _, id in ipairs(list) do if KnownSpell(id) then return id end end
end

local function IsRightSpell(id)
    local _, class = UnitClass("player")
    local def = CLICK_SPELLS[class]
    if not (def and def.right) then return false end
    for _, r in ipairs(def.right) do if r == id then return true end end
    return false
end

-- Frame 1 follows the X/Y sliders; frames 2-5 use their saved spot, else they
-- stack under frame 1.
local function FramePosition(i)
    local cfg = Cfg()
    local x, y = cfg.healerInCrowdControlOffsetX or 0, cfg.healerInCrowdControlOffsetY or 0
    if i == 1 then return x, y end
    local saved = cfg.healerInCrowdControlPositions and cfg.healerInCrowdControlPositions[i]
    if saved and saved.x and saved.y then return saved.x, saved.y end
    local size = cfg.healerInCrowdControlSize or ICON_SIZE
    return x, y - (i - 1) * (size + 50)
end

local function BreakerSize(size) return math.max(18, math.floor(size * 0.65 + 0.5)) end

local function UpdateGeometry(frame)
    local cfg = Cfg()
    local size = cfg.healerInCrowdControlSize or ICON_SIZE
    local outset = addon.CLASS_ICON_BORDER_OUTSET or 1.10
    frame:SetScale(1)
    frame:SetSize(size, size)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", FramePosition(frame._index))
    frame.border:ClearAllPoints()
    frame.border:SetSize(size * outset, size * outset)
    frame.border:SetPoint("CENTER", frame, "CENTER")
    frame.border:SetTexCoord(unpack(addon.CLASS_ICON_BORDER_TCOORDS))
    frame.centerText:SetFont("Fonts\\FRIZQT__.TTF", math.max(12, math.floor(size * 0.42 + 0.5)), "OUTLINE")
    local b = BreakerSize(size)
    local breaker = frame.breaker
    breaker:SetSize(b, b)
    breaker:ClearAllPoints()
    breaker:SetPoint("LEFT", frame, "RIGHT", 10, 0)
    -- Soft square glow around the breaker icon (Blizzard action-button border).
    local g = b * 0.4
    breaker.glow:ClearAllPoints()
    breaker.glow:SetPoint("TOPLEFT", breaker, "TOPLEFT", -g, g)
    breaker.glow:SetPoint("BOTTOMRIGHT", breaker, "BOTTOMRIGHT", g, -g)
    breaker.cdText:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, math.floor(b * 0.45 + 0.5)), "OUTLINE")
    breaker.rText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, math.floor(b * 0.28 + 0.5)), "OUTLINE")
end

local Update, ApplyClicks

-- The two number styles are mutually exclusive; with both off no number shows.
-- the coloured number sits in the icon centre, the white one under it.
local function SetTimerText(frame, cfg, remain)
    if cfg.healerInCrowdControlColoredTimer then
        local text, r, g, b = addon.FormatCountdown(remain)
        frame.centerText:SetText(text)
        frame.centerText:SetTextColor(r, g, b)
        frame.timerText:SetText("")
    elseif cfg.healerInCrowdControlUseCustomTimer then
        frame.timerText:SetText(string.format("%.1f", remain))
        frame.timerText:SetTextColor(1, 1, 1)
        frame.centerText:SetText("")
    else
        frame.timerText:SetText("")
        frame.centerText:SetText("")
    end
end

-- glowing yellow lines running around the square breaker icon. A line
-- that reaches a corner is split in two pieces (one per edge), so it bends
-- around the corner smoothly instead of jumping.
local SPARKS, SPARK_LAP = 8, 3.0
local function PlaceSegment(tex, breaker, side, edge, c0, c1)
    local len = c1 - c0
    if len < 0.5 then tex:Hide(); return end
    local mid = (c0 + c1) / 2
    local x, y
    if edge == 0 then x, y = mid, 0
    elseif edge == 1 then x, y = side, mid
    elseif edge == 2 then x, y = side - mid, side
    else x, y = 0, side - mid end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", breaker, "BOTTOMLEFT", x - 2, y - 2)
    if edge == 0 or edge == 2 then tex:SetSize(len, 2) else tex:SetSize(2, len) end
    tex:Show()
end

local function PlaceSparks(breaker, phase)
    local side = breaker:GetWidth() + 4
    local perimeter = side * 4
    local len = math.max(4, side / 4)
    for i = 1, SPARKS do
        local a = (((phase + (i - 1) / SPARKS) % 1) * perimeter - len / 2) % perimeter
        local edge = math.floor(a / side)
        if edge > 3 then edge, a = 0, 0 end
        local c = a - edge * side
        if c + len <= side then
            PlaceSegment(breaker.sparks[i], breaker, side, edge, c, c + len)
            breaker.sparks2[i]:Hide()
        else
            PlaceSegment(breaker.sparks[i], breaker, side, edge, c, side)
            PlaceSegment(breaker.sparks2[i], breaker, side, (edge + 1) % 4, 0, c + len - side)
        end
    end
end
addon.HealerCCPlaceSparks = PlaceSparks

local function HideSparks(breaker)
    for i = 1, SPARKS do breaker.sparks[i]:Hide(); breaker.sparks2[i]:Hide() end
end

-- Breaker readiness ---------------------------------------------------------
local function SpellOffCooldown(id)
    local start, duration = GetSpellCooldown(id)
    return not duration or duration <= 1.5 or not start or start + duration - GetTime() <= 0
end

local function SpellUsable(id)
    if not IsUsableSpell then return true end
    local name = GetSpellInfo(id)
    if not name then return true end
    return IsUsableSpell(name) and true or false -- false when out of mana or unusable
end

-- HasFullControl() stays true while silenced, so your own CC
-- debuffs (stun, silence, fear, ... never roots) are read too, once per moment.
local playerCCAt, playerCC = -1, false
local function PlayerFree()
    if HasFullControl and not HasFullControl() then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    local now = GetTime()
    if now ~= playerCCAt then
        playerCCAt = now
        playerCC = addon.GetUnitCrowdControl and addon.GetUnitCrowdControl("player", true) and true or false
    end
    return not playerCC
end

local function Pick(id, known)
    if not KnownSpell(id) then return nil, known end
    if SpellOffCooldown(id) and SpellUsable(id) then return id, known end
    return nil, known or id
end

local NONE = {}
-- Best KNOWN breaker for this CC, preferring one that is ready now.
local function FindBreaker(spellID, debuffType, category)
    if Cfg().healerInCrowdControlBreakerIcon == false then return end
    local hit, known
    if category and TREMOR_CATEGORIES[category] then
        hit, known = Pick(TREMOR_TOTEM, known)
        if hit then return hit, true end
    end
    for _, id in ipairs(debuffType and BREAKERS[debuffType] or NONE) do
        hit, known = Pick(id, known)
        if hit then return hit, true end
    end
    local legacy = spellID and addon.CrowdControlBreakers[spellID]
    if legacy then
        for id in pairs(legacy) do
            hit, known = Pick(id, known)
            if hit then return hit, true end
        end
    end
    if known then return known, false end
end

local function DetectOmniCC()
    omniCC = (IsAddOnLoaded and IsAddOnLoaded("OmniCC")) and true or (_G.OmniCC ~= nil)
end

-- the breaker turns grey only when it is not ready (cooldown, no mana /
-- unusable, or you are crowd-controlled or dead). On cooldown it shows the
-- Blizzard sweep and a number (OmniCC's number when OmniCC is installed).
local function RefreshBreaker(frame)
    local br = frame.breaker
    local cc = frame._cc
    local id = cc and FindBreaker(cc.spellID, cc.debuffType, cc.category)
    if not id then
        if br:IsShown() then br:Hide() end
        if br._cdSpell then br.cd:Hide(); br._cdSpell, br._cdStart, br._cdDur = nil, nil, nil end
        br.cdText:SetText("")
        br._spell = nil
        return
    end
    if br._spell ~= id then
        br.tex:SetTexture(addon.GetSpellTexture(id))
        br.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        br.rText:SetText(IsRightSpell(id) and "R" or "")
        -- A different spell: the old sweep belongs to the old spell.
        if br._cdSpell and br._cdSpell ~= id then
            br.cd:Hide(); br._cdSpell, br._cdStart, br._cdDur = nil, nil, nil
        end
        br._spell = id
    end
    local now = GetTime()
    local start, duration = GetSpellCooldown(id)
    local onCD = start and duration and duration > 1.5 and start > 0 and start + duration > now
    if onCD then
        if br._cdSpell ~= id or br._cdStart ~= start or br._cdDur ~= duration then
            br.cd:Show()
            br.cd:SetCooldown(start, duration)
            br._cdSpell, br._cdStart, br._cdDur = id, start, duration
        end
        if omniCC then
            br.cdText:SetText("")
        else
            local text, r, g, b = addon.FormatCountdown(start + duration - now)
            br.cdText:SetText(text)
            br.cdText:SetTextColor(r, g, b)
        end
    else
        if br._cdSpell then
            -- Early reset only; at its natural end the sweep (and OmniCC's
            -- finish effect) end by themselves.
            if br._cdStart + br._cdDur - now > 0.1 then br.cd:Hide() end
            br._cdSpell, br._cdStart, br._cdDur = nil, nil, nil
        end
        br.cdText:SetText("")
    end
    local ready = not onCD and SpellUsable(id) and PlayerFree()
    if ready ~= br._ready then
        br._ready = ready
        br.tex:SetDesaturated(not ready)
        if ready then
            br.glow:Show()
            PlaceSparks(br, ((frame._pulse or 0) / SPARK_LAP) % 1)
        else
            br.glow:Hide()
            HideSparks(br)
        end
    end
    if not br:IsShown() then br:Show() end
end

-- Alert frames ----------------------------------------------------------------
local function HideFrame(frame)
    if not frame then return end
    frame:Hide()
    frame:EnableMouse(false)
    frame.timerText:SetText("")
    frame.centerText:SetText("")
    frame.nameText:SetText("")
    frame.expires = nil
    frame._ccDuration = nil
    frame._spellID = nil
    frame._guid = nil
    frame._cc = nil
    -- OnUpdate is also cleared here, so after the first hide
    -- the pulse, timer and expiry never ran again.
end

local function OnDragStart(self)
    if not isInTest or InCombat() then return end
    self:StartMoving()
end

local function OnDragStop(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    local fx, fy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if fx and ux then
        local x, y = math.floor(fx - ux + 0.5), math.floor(fy - uy + 0.5)
        local cfg = Cfg()
        if self._index == 1 then
            cfg.healerInCrowdControlOffsetX, cfg.healerInCrowdControlOffsetY = x, y
        else
            cfg.healerInCrowdControlPositions = cfg.healerInCrowdControlPositions or {}
            cfg.healerInCrowdControlPositions[self._index] = { x = x, y = y }
        end
        cfg.lastModified = GetTime()
    end
    UpdateGeometry(self)
    if OPlates.NotifyOptions then OPlates:NotifyOptions() end
end

local function CreateAlertFrame(i)
    local frame = CreateFrame("Frame", i == 1 and "OPlatesHealerCCFrame" or ("OPlatesHealerCCFrame" .. i), UIParent)
    frame._index = i
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)
    frame:SetSize(ICON_SIZE, ICON_SIZE)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame)

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetTexture(addon.CLASS_ICON_BORDER)
    frame.border:SetVertexColor(1, 0.82, 0.25, 1)

    -- Square breaker icon (a spell of yours that can dispel/break this CC)
    -- with a glowing yellow border running around it while it is ready.
    local breaker = CreateFrame("Frame", nil, frame)
    frame.breaker = breaker
    breaker.tex = breaker:CreateTexture(nil, "ARTWORK")
    breaker.tex:SetAllPoints(breaker)
    breaker.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    breaker.icon = breaker.tex -- OmniCC's shine/pulse finish effects use .icon
    breaker.edge = breaker:CreateTexture(nil, "BACKGROUND")
    breaker.edge:SetPoint("TOPLEFT", breaker, "TOPLEFT", -2, 2)
    breaker.edge:SetPoint("BOTTOMRIGHT", breaker, "BOTTOMRIGHT", 2, -2)
    breaker.edge:SetTexture(0, 0, 0, 1)
    breaker.glow = breaker:CreateTexture(nil, "OVERLAY")
    breaker.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    breaker.glow:SetBlendMode("ADD")
    breaker.glow:SetVertexColor(1, 0.85, 0.1, 1)
    breaker.sparks, breaker.sparks2 = {}, {}
    for s = 1, SPARKS do
        for _, list in ipairs({ breaker.sparks, breaker.sparks2 }) do
            local t = breaker:CreateTexture(nil, "OVERLAY")
            t:SetTexture(1, 0.9, 0.2, 1)
            t:SetBlendMode("ADD")
            t:Hide()
            list[s] = t
        end
    end
    -- The only Cooldown frame OPlates creates (named, so OmniCC can draw on it).
    breaker.cd = CreateFrame("Cooldown", "OPlatesHealerCCBreakerCD" .. i, breaker)
    breaker.cd:SetAllPoints(breaker)
    breaker.cd:Hide()
    local over = CreateFrame("Frame", nil, breaker)
    over:SetAllPoints(breaker)
    over:SetFrameLevel((breaker:GetFrameLevel() or 1) + 3)
    breaker.over = over
    breaker.cdText = over:CreateFontString(nil, "OVERLAY")
    breaker.cdText:SetPoint("CENTER", breaker, "CENTER", 0, 0)
    breaker.cdText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    breaker.rText = over:CreateFontString(nil, "OVERLAY")
    breaker.rText:SetPoint("BOTTOMRIGHT", breaker, "BOTTOMRIGHT", -1, 2)
    breaker.rText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    breaker.rText:SetTextColor(1, 1, 1)
    breaker:Hide()

    frame.centerText = frame:CreateFontString(nil, "OVERLAY")
    frame.centerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.centerText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")

    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.timerText:SetPoint("TOP", frame, "BOTTOM", 0, -3)
    frame.timerText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    frame.timerText:SetTextColor(1, 1, 1)

    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.nameText:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    frame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")

    -- Pulse and sparks every frame; numbers and breaker state every 0.1 s.
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._pulse = (self._pulse or 0) + elapsed
        self.border:SetAlpha(0.72 + 0.28 * (0.5 + 0.5 * math.sin(self._pulse * 4.0)))
        local br = self.breaker
        if br._ready and br:IsShown() then
            br.glow:SetAlpha(0.55 + 0.45 * (0.5 + 0.5 * math.sin(self._pulse * 5.0)))
            PlaceSparks(br, (self._pulse / SPARK_LAP) % 1)
        end
        self._tick = (self._tick or 0) + elapsed
        if self._tick < 0.1 then return end
        self._tick = 0
        RefreshBreaker(self)
        if not self.expires then return end
        local remain = self.expires - GetTime()
        if remain <= 0 then
            if isInTest then
                -- Test mode loops the countdown until Hide.
                self.expires = GetTime() + (self._ccDuration or 8)
                remain = self._ccDuration or 8
            else
                self.expires = nil
                self.centerText:SetText("")
                self.timerText:SetText("")
                Update()
                return
            end
        end
        SetTimerText(self, Cfg(), remain)
    end)

    frame:Hide()
    DetectOmniCC()
    UpdateGeometry(frame)
    return frame
end

local function GetFrame(i)
    frames[i] = frames[i] or CreateAlertFrame(i)
    return frames[i]
end

local function ShowFrame(frame, cc, healerName, classFile, silent)
    local cfg = Cfg()
    local isNew = not frame:IsShown() or frame._spellID ~= cc.spellID or frame._guid ~= cc.guid
    if isNew then UpdateGeometry(frame) end

    addon.SetCircularTexture(frame.icon, cc.icon)
    frame.icon:Show()
    frame.border:Show()
    frame.expires, frame._ccDuration = nil, nil
    if cc.start and cc.duration and cc.duration > 0 then
        frame.expires = cc.start + cc.duration
        frame._ccDuration = cc.duration
        SetTimerText(frame, cfg, math.max(0, frame.expires - GetTime()))
    else
        frame.timerText:SetText("")
        frame.centerText:SetText("")
    end

    frame.nameText:SetText(healerName or "")
    frame.nameText:SetTextColor(addon.GetClassColor(classFile))

    frame._cc = cc
    RefreshBreaker(frame)

    if isNew and not silent and cfg.healerInCrowdControlSound then
        PlaySoundFile("Sound\\Interface\\iQuestUpdate.wav", "Master")
    end
    frame._spellID, frame._guid = cc.spellID, cc.guid
    if isNew then frame._pulse = 0 end
    frame:Show()
end

local function HideAll()
    for i = 1, MAX_FRAMES do HideFrame(frames[i]) end
end

-- Context and roster ------------------------------------------------------------
local function ContextAllowed()
    local cfg = Cfg()
    if not cfg.healerInCrowdControl or not InGroup() then return false end
    local inInstance, instanceType = IsInInstance()
    if instanceType == "arena" or (IsActiveBattlefieldArena and IsActiveBattlefieldArena()) then
        return cfg.healerInCrowdControlInArena ~= false
    end
    if inInstance and instanceType == "pvp" then return cfg.healerInCrowdControlInBG ~= false end
    if inInstance and (instanceType == "party" or instanceType == "raid") then return cfg.healerInCrowdControlInPVE ~= false end
    return cfg.healerInCrowdControlInWorld ~= false -- open world, Wintergrasp, cities
end

local function FullName(unit)
    local name, realm = UnitName(unit)
    if not name then return end
    return realm and realm ~= "" and name .. "-" .. realm or name, name
end

local function IsHealerUnit(unit, guid)
    local talent = addon.TalentScanner and addon.TalentScanner:Get(guid)
    local _, classFile = UnitClass(unit)
    if talent and talent.spec and talent.class == classFile then return talent.specRole == "HEALER" end
    if remoteCC[guid] then return true end -- only healers send OPlates
    local sig = addon.GetGroupSpecSignature and addon.GetGroupSpecSignature(guid)
    if sig and sig.class == classFile then return sig.role == "HEALER" end
    local role = addon.GetAssignedGroupRole and addon.GetAssignedGroupRole(unit)
    if role then return role == "HEALER" end
    local cached = addon.GetCachedUnitData and addon.GetCachedUnitData(unit)
    return cached and cached.isHealer == true or false
end

local function ScanUnit(unit, guid)
    local icon, spellID, start, duration, category, debuffType
    if addon.GetUnitCrowdControl then
        icon, spellID, start, duration, category, debuffType = addon.GetUnitCrowdControl(unit, true)
    end
    if icon then
        local cc = localCC[guid] or {}
        cc.guid, cc.icon, cc.spellID, cc.start, cc.duration, cc.category, cc.debuffType =
            guid, icon, spellID, start, duration, category, debuffType
        localCC[guid] = cc
    else
        localCC[guid] = nil
    end
end

local function RebuildRoster()
    wipe(nameToUnit)
    local raid, party = GroupSize()
    local prefix, count = raid > 0 and "raid" or "party", raid > 0 and raid or party
    local _, instanceType = IsInInstance()
    channel = (raid > 0 or party > 0) and (instanceType == "pvp" and "BATTLEGROUND" or raid > 0 and "RAID" or "PARTY") or nil
    local seen = wipe(rosterSeen)
    for i = 1, count do
        local unit = prefix .. i
        local guid = UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitGUID(unit)
        if guid then
            local full, short = FullName(unit)
            if full then nameToUnit[full] = unit; nameToUnit[short] = nameToUnit[short] or unit end
            seen[guid] = true
            if IsHealerUnit(unit, guid) then
                if healerUnits[unit] ~= guid then healerUnits[unit] = guid; ScanUnit(unit, guid); healersChanged = true end
            elseif healerUnits[unit] then
                healerUnits[unit] = nil; healersChanged = true
            end
        end
    end
    for unit, guid in pairs(healerUnits) do
        if not seen[guid] or not UnitExists(unit) or UnitGUID(unit) ~= guid then healerUnits[unit] = nil; healersChanged = true end
    end
    for guid in pairs(localCC) do if not seen[guid] then localCC[guid] = nil end end
    for guid in pairs(remoteCC) do if not seen[guid] then remoteCC[guid] = nil end end
end

-- Slot binding (out of combat only) ---------------------------------------------
local healerByGuid, healerNames, unbound = {}, {}, {}
local function ByName(a, b) return healerNames[a] < healerNames[b] end

local function AssignSlots()
    if InCombat() then return false end
    if not healersChanged then return false end
    healersChanged = false
    local n = MaxFrames()
    local changed = false
    wipe(healerByGuid); wipe(healerNames)
    for unit, guid in pairs(healerUnits) do
        local full = FullName(unit)
        if full then healerByGuid[guid], healerNames[guid] = unit, full end
    end
    for i = 1, MAX_FRAMES do
        local s = slots[i]
        if s and (n == 1 or i > n or not healerByGuid[s.guid]) then slots[i] = nil; changed = true
        elseif s and s.name ~= healerNames[s.guid] then s.name = healerNames[s.guid]; changed = true end
    end
    if n == 1 then return changed end -- max 1: one dynamic alert, no binding
    -- Re-pack: bound frames stay in their order without gaps.
    local w = 1
    for i = 1, n do
        if slots[i] then
            if w ~= i then slots[w], slots[i] = slots[i], nil; changed = true end
            w = w + 1
        end
    end
    wipe(unbound)
    for guid in pairs(healerByGuid) do
        local bound = false
        for i = 1, n do if slots[i] and slots[i].guid == guid then bound = true; break end end
        if not bound then unbound[#unbound + 1] = guid end
    end
    table.sort(unbound, ByName)
    for _, guid in ipairs(unbound) do
        if w > n then break end
        slots[w] = { guid = guid, name = healerNames[guid] }
        w, changed = w + 1, true
    end
    return changed
end

-- Secure click buttons -------------------------------------------------------------
-- Parented to UIParent (a protected child would make the alert frame protected)
-- at the breaker's absolute position. Shown out of combat while their healer is
-- crowd-controlled; in combat only while the modifier is held (state driver).
local SNIPPET = [[
    if newstate == "armed" then
        if self:GetAttribute("bound") then self:Show() else self:Hide() end
    elseif newstate == "off" then
        self:Hide()
    elseif self:GetAttribute("bound") and self:GetAttribute("active") then
        self:Show()
    else
        self:Hide()
    end
]]

local function CreateClick(i)
    local b = CreateFrame("Button", "OPlatesHealerClick" .. i, UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    b:SetFrameStrata("DIALOG")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetAttribute("_onstate-dispel", SNIPPET)
    b:Hide()
    clicks[i] = b
    return b
end

local function ClickSpells()
    local _, class = UnitClass("player")
    local def = CLICK_SPELLS[class]
    if not def then return end
    return FirstKnown(def.left), FirstKnown(def.right)
end

local function MacroFor(id, name)
    local spell = id and GetSpellInfo(id)
    if not spell then return nil end
    if id == TREMOR_TOTEM then return "/cast " .. spell end
    return "/cast [target=" .. name .. "] " .. spell
end

local function SetMacro(b, button, text)
    b:SetAttribute("type" .. button, text and "macro" or nil)
    b:SetAttribute("*type" .. button, text and "macro" or nil)
    b:SetAttribute("macrotext" .. button, text)
    b:SetAttribute("*macrotext" .. button, text)
end

local function Unbind(b)
    if b._bound then
        b:SetAttribute("bound", nil)
        b:SetAttribute("active", nil)
        b._bound, b._active, b._name, b._left, b._right = nil, nil, nil, nil, nil
    end
    if b:IsShown() then b:Hide() end
end

ApplyClicks = function()
    if InCombat() then pendingClicks = true; return end
    pendingClicks = false
    local cfg = Cfg()
    local n = MaxFrames()
    local left, right = ClickSpells()
    local enabled = cfg.healerInCrowdControl and not cfg.healerInCrowdControlNoClick and n > 1
        and (left or right) and not isInTest and ContextAllowed()
    local mod = string.lower(cfg.healerInCrowdControlClickModifier or "ALT")
    if mod ~= "alt" and mod ~= "shift" and mod ~= "ctrl" then mod = "alt" end
    local driver = "[combat,mod:" .. mod .. "] armed; [combat] off; ooc"
    local size = cfg.healerInCrowdControlSize or ICON_SIZE
    local bs = BreakerSize(size)
    for i = 1, MAX_FRAMES do
        local slot = enabled and i <= n and slots[i]
        local b = clicks[i]
        if slot and slot.name then
            b = b or CreateClick(i)
            if b._name ~= slot.name or b._left ~= left or b._right ~= right then
                SetMacro(b, 1, MacroFor(left, slot.name))
                SetMacro(b, 2, MacroFor(right, slot.name))
                b._name, b._left, b._right = slot.name, left, right
            end
            local x, y = FramePosition(i)
            x = x + size / 2 + 10 + bs / 2
            if b._x ~= x or b._y ~= y or b._size ~= bs then
                b:ClearAllPoints()
                b:SetSize(bs, bs)
                b:SetPoint("CENTER", UIParent, "CENTER", x, y)
                b._x, b._y, b._size = x, y, bs
            end
            local f = frames[i]
            local active = f and f:IsShown() and f._guid == slot.guid and f.breaker:IsShown() and true or false
            if not b._bound then b:SetAttribute("bound", true); b._bound = true end
            if b._active ~= active then b:SetAttribute("active", active or nil); b._active = active end
            if b._driver ~= driver then
                RegisterStateDriver(b, "dispel", driver)
                b._driver = driver
            end
            if active then
                if not b:IsShown() then b:Show() end
            elseif b:IsShown() then
                b:Hide()
            end
        elseif b then
            Unbind(b)
        end
    end
end

-- Display ---------------------------------------------------------------------------
local ccList, numCC, used = {}, 0, {}

local function ShowEntry(i, e)
    ShowFrame(GetFrame(i), e.cc, (UnitName(e.unit)), select(2, UnitClass(e.unit)))
    used[i] = true
end

Update = function()
    if isInTest then return end
    if not ContextAllowed() then
        HideAll()
        if not InCombat() then AssignSlots(); ApplyClicks() end
        return
    end
    if AssignSlots() then pendingClicks = true end
    local now = GetTime()
    local n = MaxFrames()
    numCC = 0
    for unit, guid in pairs(healerUnits) do
        local cc
        local remote = remoteCC[guid]
        if remote and remote.expires and remote.expires <= now then remoteCC[guid] = { guid = guid }; remote = nil end
        -- His own debuffs are authoritative while he is visible; beyond that
        -- only his own OPlates message can tell.
        if UnitIsVisible(unit) then cc = localCC[guid]
        elseif remote and remote.spellID then cc = remote end
        if cc and cc.start and cc.duration and cc.duration > 0 and cc.start + cc.duration <= now then cc = nil end
        if cc then
            numCC = numCC + 1
            local e = ccList[numCC] or {}
            ccList[numCC] = e
            e.cc, e.unit, e.guid, e.pri, e.done = cc, unit, guid, addon.CrowdControlPriority(cc.category, cc.spellID), false
        end
    end
    wipe(used)
    -- 1) every CC'd healer on his own bound frame.
    if n > 1 then
        for i = 1, n do
            local s = slots[i]
            if s then
                for k = 1, numCC do
                    local e = ccList[k]
                    if not e.done and e.guid == s.guid then e.done = true; ShowEntry(i, e); break end
                end
            end
        end
    end
    -- 2) the rest by priority: a free frame first, then a frame whose bound
    -- healer is not CC'd (visual only, its click stays with its own healer).
    while true do
        local best
        for k = 1, numCC do
            local e = ccList[k]
            if not e.done and (not best or e.pri > best.pri) then best = e end
        end
        if not best then break end
        best.done = true
        local target
        for i = 1, n do if not used[i] and not slots[i] then target = i; break end end
        if not target then for i = 1, n do if not used[i] then target = i; break end end end
        if not target then break end
        ShowEntry(target, best)
    end
    for i = 1, MAX_FRAMES do if not used[i] then HideFrame(frames[i]) end end
    if not InCombat() then ApplyClicks() end
end

-- Test mode -------------------------------------------------------------------------
-- the test shows a CC that your own spells can break (so the breaker
-- icon appears whenever you know a fitting spell), else Polymorph.
local TEST_AURAS = {
    { spellID = 118, debuffType = "Magic", category = "incapacitate", fallbackIcon = "Spell_Nature_Polymorph" },
    { spellID = 5782, debuffType = "Magic", category = "fear", fallbackIcon = "Spell_Shadow_Possession" },
    { spellID = 51514, debuffType = "Curse", category = "incapacitate", fallbackIcon = "Spell_Shaman_Hex" },
    { spellID = 49012, debuffType = "Poison", category = "incapacitate", fallbackIcon = "INV_Spear_02" },
}
addon.HealerCCTestAura = function()
    for _, a in ipairs(TEST_AURAS) do
        if FindBreaker(a.spellID, a.debuffType, a.category) then
            return { spellID = a.spellID, debuffType = a.debuffType, category = a.category, fallbackIcon = a.fallbackIcon }
        end
    end
    local a = TEST_AURAS[1]
    return { spellID = a.spellID, debuffType = a.debuffType, category = a.category, fallbackIcon = a.fallbackIcon }
end

function OPlates:TestHealerInCrowdControl()
    if InCombat() then
        addon.PRINT("Cannot run test mode in combat")
        return
    end
    if IsInInstance() then
        addon.PRINT("Cannot run test mode inside an instance")
        return
    end
    isInTest = true
    ApplyClicks() -- the secure click spots are unbound while testing
    local _, classFile = UnitClass("player")
    for i = 1, MAX_FRAMES do
        if i <= MaxFrames() then
            local cc = addon.HealerCCTestAura()
            cc.guid, cc.start, cc.duration = "test" .. i, GetTime(), 8 + (i - 1) * 2
            cc.icon = addon.GetSpellTexture(cc.spellID) or addon.ICON_PATH(cc.fallbackIcon)
            local frame = GetFrame(i)
            ShowFrame(frame, cc, i == 1 and UnitName("player") or ("Healer " .. i), classFile, i > 1)
            frame:EnableMouse(true) -- drag to move (test mode, out of combat)
        else
            HideFrame(frames[i])
        end
    end
    addon.PRINT("Healer CC test: drag the icons to move them, then press Hide.")
end

function OPlates:HideTestHealerInCrowdControl()
    local was = isInTest
    isInTest = false
    HideAll()
    if was then Update() end
    if not InCombat() then ApplyClicks() end
end

function OPlates:UpdateHealerInCrowdControl()
    for i = 1, MAX_FRAMES do if frames[i] then UpdateGeometry(frames[i]) end end
    if not InCombat() then ApplyClicks() end
end

function OPlates:ResetHealerInCrowdControlPositions()
    local cfg = Cfg()
    cfg.healerInCrowdControlOffsetX, cfg.healerInCrowdControlOffsetY = 0, 250
    cfg.healerInCrowdControlPositions = nil
    cfg.lastModified = GetTime()
    self:UpdateHealerInCrowdControl()
    if self.NotifyOptions then self:NotifyOptions() end
end

-- Own healer status and group messages ------------------------------------------------
-- The player's own spec, from his own talents (never an inspection).
local function RefreshSelfHealer()
    local _, class = UnitClass("player")
    local map = addon.TALENT_TAB_SPECS and addon.TALENT_TAB_SPECS[class]
    local wasHealer = selfHealer
    selfHealer = false
    if not map then return end
    local group = GetActiveTalentGroup and GetActiveTalentGroup(false, false) or 1
    local best, bestPoints = nil, 0
    for tab = 1, 3 do
        local _, _, spent = GetTalentTabInfo(tab, false, false, group)
        if type(spent) == "number" and spent > bestPoints then best, bestPoints = tab, spent end
    end
    local spec = best and map[best]
    selfHealer = spec ~= nil and addon.SPEC_ROLES[class] and addon.SPEC_ROLES[class][spec] == "HEALER" or false
    -- A respec away from healing tells the group to forget him as a healer.
    if wasHealer and not selfHealer and channel then SendAddonMessage(PREFIX, "N", channel) end
    if not selfHealer then selfSent = nil end
end

-- A healer's own OPlates reports his CC to the group, so members at any distance
-- (other zone, other instance) are alerted. One short message per change.
local function SendSelf(force)
    if not channel or not selfHealer or not Cfg().healerInCrowdControl then return end
    local icon, spellID, start, duration, _, debuffType
    if addon.GetUnitCrowdControl then icon, spellID, start, duration, _, debuffType = addon.GetUnitCrowdControl("player", true) end
    local message, key
    if icon and spellID then
        local expires = start and duration and duration > 0 and start + duration or 0
        local remain = expires > 0 and math.max(0, expires - GetTime()) or 0
        message = string.format("C %d %d %d %s", spellID, math.floor(remain * 10 + 0.5),
            math.floor((duration or 0) * 10 + 0.5), debuffType or "-")
        key = spellID .. ":" .. math.floor(expires * 2 + 0.5) -- same aura = same key
    elseif selfSent and selfSent ~= "E" then
        message, key = "E", "E"
    end
    if not message then return end
    if not force and key == selfSent then return end
    if GetTime() - selfSentAt < 0.2 then selfPending = true; return end
    selfSent, selfSentAt, selfPending = key, GetTime(), false
    SendAddonMessage(PREFIX, message, channel)
end

local function Receive(message, sender)
    if type(message) ~= "string" or #message > 60 then return end
    local unit = nameToUnit[sender]
    local guid = unit and UnitGUID(unit)
    if not guid then return end
    if message == "N" then
        remoteCC[guid], localCC[guid] = nil, nil
        if not IsHealerUnit(unit, guid) and healerUnits[unit] then healerUnits[unit] = nil; healersChanged = true end
        Update()
        return
    elseif message == "E" then
        remoteCC[guid] = { guid = guid }
    else
        local id, remain, duration, debuffType = message:match("^C (%d+) (%d+) (%d+) (%a+)$")
        local spellID = tonumber(id)
        local name, _, icon = GetSpellInfo(spellID or 0)
        local category = name and addon.GetCrowdControlCategory(spellID, name)
        if not icon or not category or category == "root" or category == "disarm" then return end
        remain, duration = tonumber(remain) / 10, tonumber(duration) / 10
        local now = GetTime()
        local start = duration > 0 and remain > 0 and now + remain - duration or nil
        remoteCC[guid] = { guid = guid, icon = icon, spellID = spellID, category = category,
            debuffType = debuffType ~= "-" and debuffType or nil, start = start,
            duration = start and duration or nil, expires = now + (remain > 0 and remain or 10) }
    end
    if not healerUnits[unit] then
        healerUnits[unit] = guid
        healersChanged = true
        if UnitIsVisible(unit) then ScanUnit(unit, guid) end
    end
    Update()
end

local tick = 0
local function OnUpdate(_, elapsed)
    tick = tick + elapsed
    if tick < 1 then return end
    tick = 0
    RebuildRoster()
    -- A healer coming into visibility fires no UNIT_AURA; rescan the few healers.
    for unit, guid in pairs(healerUnits) do
        if UnitIsVisible(unit) then ScanUnit(unit, guid) else localCC[guid] = nil end
    end
    if selfPending then SendSelf() end
    Update()
end

local function OnEvent(_, event, a1, a2, a3, a4)
    if event == "UNIT_AURA" then
        if a1 == "player" then SendSelf(); return end
        local guid = healerUnits[a1]
        if guid then ScanUnit(a1, guid); Update() end
        return
    end
    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then Receive(a2, a4) end
        return
    end
    if event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        RefreshSelfHealer()
        if not InCombat() then ApplyClicks() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if isInTest then OPlates:HideTestHealerInCrowdControl() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        healersChanged = true -- re-pack healers who left or joined during combat
        Update()
        if pendingClicks then ApplyClicks() end
        return
    end
    if event == "LEARNED_SPELL_IN_TAB" then
        if not InCombat() then ApplyClicks() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        isInTest = false
        HideAll(); wipe(localCC); wipe(remoteCC); wipe(healerUnits)
        healersChanged = true
        RefreshSelfHealer()
    end
    RebuildRoster()
    SendSelf(true)
    Update()
end

function OPlates:SetupHealerInCrowdControl()
    if not self._healerCCFrame then
        local frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
        self._healerCCFrame = frame
        -- One timer per second, only while grouped and enabled.
        local driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", OnUpdate)
        self._healerCCDriver = driver
    end
    local frame, driver = self._healerCCFrame, self._healerCCDriver
    frame:UnregisterAllEvents()
    healersChanged = true
    if self.db.profile.misc.healerInCrowdControl then
        for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
            "UNIT_AURA", "CHAT_MSG_ADDON", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LEARNED_SPELL_IN_TAB" }) do
            frame:RegisterEvent(event)
        end
        frame:SetScript("OnEvent", function(f, event, ...)
            OnEvent(f, event, ...)
            if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
                if InGroup() then driver:Show() else driver:Hide() end
            end
        end)
        RefreshSelfHealer()
        RebuildRoster()
        if InGroup() then driver:Show() else driver:Hide() end
        Update()
    else
        driver:Hide()
        wipe(healerUnits); wipe(localCC); wipe(remoteCC)
        HideAll()
        if not InCombat() then
            for i = 1, MAX_FRAMES do slots[i] = nil end
            ApplyClicks()
        else
            pendingClicks = true
            frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- unbind the click spots after combat
        end
    end
end
