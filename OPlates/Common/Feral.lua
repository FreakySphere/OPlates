local _, addon = ...
-- 3.3.5 Feral tree indices, cross-checked against Talented's DRUID tree
-- (Data.lua) and its GetTalentInfo(tab,index) template representation.
-- Shared talents such as Thick Hide/Primal Fury do not establish Cat identity.
function addon.ClassifyFeralRanks(rank)
    if rank(16) > 0 or rank(22) > 0 then return "BEAR" end -- Natural Reaction / Protector of the Pack
    if rank(9) > 0 or rank(18) > 0 or rank(21) > 0 then return "CAT" end -- Shredding Attacks / Primal Tenacity / Nurturing Instinct
end

-- One place for the two form textures. The FERAL *spec* icon is the cat form
-- (see SPEC_TREE_ICONS): a spec icon must never be a bear, or a cat druid
-- looks like a tank while "Show tank icons" is on. Only a proven BEAR gets the
-- bear form texture; while the tank icon is on, both render paths replace it
-- with the TANK icon.
addon.FERAL_TEXTURES = {
    BEAR = "Interface\\Icons\\Ability_Racial_BearForm",
    CAT = "Interface\\Icons\\Ability_Druid_CatForm",
}

function addon.FeralTexture(kind)
    return kind and addon.FERAL_TEXTURES[kind] or nil
end

-- The shapeshift auras. A druid we can see but who is not casting (a level 12
-- bear standing still) never produces a combat-log line, so the only way to
-- know his FORM is to read his buffs from the unit token.
addon.FERAL_FORM_SPELLS = {
    [5487] = "BEAR",   -- Bear Form
    [9634] = "BEAR",   -- Dire Bear Form
    [768] = "CAT",     -- Cat Form
}

-- A shapeshift that only one spec would ever have is proof of that spec, not a
-- hint.
--
-- Tree of Life needs 40 points in Restoration, and 40 there plus the 41 a
-- Balance or Feral build needs is more than the 71 points a character has, so
-- no other build can wear it at all.
--
-- Moonkin Form sits at Balance row 6 (30 points), so a 30/0/41 Restoration
-- druid could technically wear it. That build is a leftover of the TBC
-- "Dreamstate" idea: it spends 30 of its 71 points on a form it cannot heal in,
-- which buys a healer nothing, and nobody plays it in 3.3.5a.
-- A druid who spends 30 points in Balance and then shifts into the Balance form
-- is a Balance druid, and OPlates is built for the builds people actually play,
-- not for the 0.01% that spends points on a form it cannot use. Treating
-- Moonkin as a hint instead meant a real Moonkin who shifted before we saw him
-- kept a guessed Restoration or Feral icon for the whole fight.
--
-- Cat Form and Bear Form are absent: every druid can train both.
addon.SPEC_FORM_SPELLS = {
    [33891] = "RESTORATION", -- Tree of Life (40-point Restoration)
    [24858] = "BALANCE",     -- Moonkin Form (30-point Balance)
}

-- "BEAR"/"CAT" for a unit currently shapeshifted, nil otherwise. Reads both the
-- 10th and 11th return so it works whether the client returns spellId in the
-- WotLK position or the later one.
function addon.UnitFormKind(unit)
    if not unit or not UnitBuff then return nil end
    local i = 1
    while i <= 40 do
        local name, _, _, _, _, _, _, _, _, a10, a11 = UnitBuff(unit, i)
        if not name then break end
        local kind = (type(a11) == "number" and addon.FERAL_FORM_SPELLS[a11])
            or (type(a10) == "number" and addon.FERAL_FORM_SPELLS[a10])
        if kind then return kind end
        i = i + 1
    end
end

function addon.ApplyFeralIdentity(data, assignedTank)
    if data.class ~= "DRUID" or data.spec ~= "FERAL" then return end
    data.isTank = assignedTank == true
    data.isHealer = false
    -- Always normalise the texture: a record saved by an older build (or the
    -- client's own Feral tab icon) can carry the Bear Form texture for a druid
    -- whose form we do not know. Unknown form means the cat, never the bear.
    data.specTexture = addon.FeralTexture(data.feralKind) or addon.FeralTexture("CAT") or data.specTexture
end

function addon.IsAssignedGroupTank(unit)
    if not unit then return false end
    -- UnitInParty/UnitInRaid always exist on a real client; the guards keep a
    -- stripped UI or a test harness from erroring inside a render.
    local inGroup = (UnitInParty and UnitInParty(unit)) or (UnitInRaid and UnitInRaid(unit))
    if not inGroup then return false end
    if UnitGroupRolesAssigned then
        local tank = UnitGroupRolesAssigned(unit)
        if tank == true or tank == "TANK" then return true end
    end
    -- 3.3.5a returns 1/nil here, so the old "== true" never matched.
    return GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) and true or false
end
