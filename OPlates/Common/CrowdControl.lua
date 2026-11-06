local _, addon = ...;

-- WotLK crowd-control spell IDs (for circular icon replacement + Healer-in-CC).
-- every 3.3.5a rank (cross-checked with DRData-1.0 1049), so a
-- max-rank Fear/Psychic Scream/Hammer of Justice/Sap is recognised. Concussive
-- Shot (a slow) was removed. Unknown IDs fall back to the localized spell name.
local definitions = {
    stun = {
        853, 5588, 5589, 10308,                 -- Hammer of Justice
        408, 8643,                              -- Kidney Shot
        1833,                                   -- Cheap Shot
        5211, 6798, 8983,                       -- Bash
        9005, 9823, 9827, 27006, 49803,         -- Pounce
        22570, 49802,                           -- Maim
        24394, 19577,                           -- Intimidation
        44572,                                  -- Deep Freeze
        47481,                                  -- Gnaw (Ghoul)
        30283, 30413, 30414, 47846, 47847,      -- Shadowfury
        12809,                                  -- Concussion Blow
        46968,                                  -- Shockwave
        20549,                                  -- War Stomp
        7922,                                   -- Charge Stun
        20252, 20253,                           -- Intercept
        30153, 30195, 30197, 47995,             -- Intercept (Felguard)
        50518, 53558, 53559, 53560, 53561, 53562, -- Ravage (pet)
        50519, 53564, 53565, 53566, 53567, 53568, -- Sonic Blast (pet)
        2812, 10318, 27139, 48816, 48817,       -- Holy Wrath
        22703,                                  -- Inferno Effect
        60995,                                  -- Demon Charge
        12355,                                  -- Impact
        39796,                                  -- Stoneclaw Stun
        20170,                                  -- Seal of Justice stun
        12798,                                  -- Revenge Stun
        16544,                                  -- Improved Fire Nova Totem
        58861,                                  -- Bash (Spirit Wolf)
        20276,                                  -- Knockdown
    },
    silence = {
        15487,                                  -- Silence
        1330,                                   -- Garrote - Silence
        34490,                                  -- Silencing Shot
        47476, 49913, 49914, 49915, 49916,      -- Strangulate
        24259, 19244, 19647,                    -- Spell Lock
        18469, 55021,                           -- Improved Counterspell
        18425,                                  -- Improved Kick
        18498,                                  -- Gag Order
        25046, 28730, 50613,                    -- Arcane Torrent
        53588, 53589, 62347,                    -- Nether Shock (pet)
        63529,                                  -- Shield of the Templar
        31117,                                  -- Unstable Affliction (silence on dispel)
    },
    fear = {
        5782, 6213, 6215,                       -- Fear
        6358,                                   -- Seduction
        5484, 17928,                            -- Howl of Terror
        8122, 8124, 10888, 10890,               -- Psychic Scream
        1513, 14326, 14327,                     -- Scare Beast
        10326,                                  -- Turn Evil
        5246, 20511,                            -- Intimidating Shout
    },
    horror = {
        6789, 17925, 17926, 27223, 47859, 47860, -- Death Coil (Warlock)
        64044,                                  -- Psychic Horror
    },
    disorient = {
        2094,                                   -- Blind
        19503, 37506,                           -- Scatter Shot
        31661, 33041, 33042, 33043, 42949, 42950, -- Dragon's Breath
        49203,                                  -- Hungering Cold
    },
    incapacitate = {
        118, 12824, 12825, 12826, 28271, 28272, 61305, 61025, 61721, 61780, -- Polymorph
        3355, 14308, 14309,                     -- Freezing Trap Effect
        60210,                                  -- Freezing Arrow Effect
        19386, 24132, 24133, 27068, 49011, 49012, -- Wyvern Sting
        20066,                                  -- Repentance
        6770, 2070, 11297, 51724,               -- Sap
        1776,                                   -- Gouge
        2637, 18657, 18658,                     -- Hibernate
        9484, 9485, 10955,                      -- Shackle Undead
        51514,                                  -- Hex
        605,                                    -- Mind Control
        710, 18647,                             -- Banish
    },
    cyclone = {
        33786,                                  -- Cyclone
    },
    root = {
        339, 1062, 5195, 5196, 9852, 9853, 26989, 53308, -- Entangling Roots
        19970, 19971, 19972, 19973, 19974, 19975, 27010, 53313, -- Nature's Grasp
        122, 865, 6131, 10230, 27088, 42917,    -- Frost Nova
        33395,                                  -- Freeze (Water Elemental)
        63685,                                  -- Freeze (Frozen Power)
        8377, 31983, 64695,                     -- Earthgrab
        19185, 64803, 64804,                    -- Entrapment
        12494,                                  -- Frostbite
        55080,                                  -- Shattered Barrier
        23694,                                  -- Improved Hamstring
        19306, 20909, 20910, 27067, 48998, 48999, -- Counterattack
        45334,                                  -- Feral Charge Effect (Bear)
        4167,                                   -- Web (pet)
        50245, 53544, 53545, 53546, 53547, 53548, -- Pin (pet)
        54706, 55505, 55506, 55507, 55508, 55509, -- Venom Web Spray (pet)
        13099, 13119, 13120, 13138, 13139, 16566, -- Net-o-Matic
        55536,                                  -- Frostweave Net
        39965,                                  -- Frost Grenade
    },
    -- disarms (DRData-1.0 1049 "disarm").
    disarm = {
        676,                                    -- Disarm
        51722,                                  -- Dismantle
        53359,                                  -- Chimera Shot - Scorpid
        64058,                                  -- Psychic Horror (disarm)
        53542, 53543,                           -- Snatch (pet)
    },
}

-- A non-CC aura shares the name of these spells (Wyvern Sting DoT, Psychic
-- Horror disarm, the Seal of Justice buff), so they are matched by ID only.
-- also the Psychic Horror disarm, the Unstable Affliction DoT and the
-- Feral Charge interrupt (same names as a CC above).
local NAME_UNSAFE = {
    [19386] = true, [24132] = true, [24133] = true, [27068] = true, [49011] = true, [49012] = true,
    [64044] = true, [20170] = true, [19577] = true,
    [64058] = true, [31117] = true, [45334] = true,
}

addon.CrowdControlDefinitions = {};
for category, ids in pairs(definitions) do
    for _, spellId in ipairs(ids) do
        addon.CrowdControlDefinitions[spellId] = category;
    end
end

addon.CrowdControlAuras = {};
for spellId, drType in pairs(addon.CrowdControlDefinitions) do
    if drType ~= "taunt" and drType ~= "knockback" then
        addon.CrowdControlAuras[spellId] = drType;
    end
end

-- estimated PvP durations (10 s PvP cap) for nameplates without a unit
-- token (stock client), which only see the combat-log event. A real aura read
-- (unit token) always replaces the estimate. Unlisted spells use the longest
-- duration OPlates has read from a real aura, else they show no number.
local baseDurations = {
    { 6, 10308 }, { 5, 5589 }, { 4, 5588 }, { 3, 853 },              -- Hammer of Justice
    { 4, 1833 },                                                    -- Cheap Shot
    { 4, 8983 }, { 3, 6798 }, { 2, 5211 },                          -- Bash
    { 3, 9005, 9823, 9827, 27006, 49803 },                          -- Pounce
    { 3, 24394 },                                                   -- Intimidation
    { 5, 44572 },                                                   -- Deep Freeze
    { 3, 47481 },                                                   -- Gnaw
    { 3, 30283, 30413, 30414, 47846, 47847 },                       -- Shadowfury
    { 5, 12809 },                                                   -- Concussion Blow
    { 4, 46968 },                                                   -- Shockwave
    { 2, 20549 },                                                   -- War Stomp
    { 1.5, 7922 },                                                  -- Charge Stun
    { 3, 20253 },                                                   -- Intercept
    { 3, 2812 },                                                    -- Holy Wrath
    { 2, 22703 },                                                   -- Inferno Effect
    { 2, 12355 },                                                   -- Impact
    { 3, 39796 },                                                   -- Stoneclaw Stun
    { 3, 12798 },                                                   -- Revenge Stun
    { 5, 15487 },                                                   -- Silence
    { 3, 1330 },                                                    -- Garrote - Silence
    { 3, 34490 },                                                   -- Silencing Shot
    { 5, 47476, 49913, 49914, 49915, 49916 },                       -- Strangulate
    { 3, 24259 },                                                   -- Spell Lock
    { 2, 18469 },                                                   -- Improved Counterspell
    { 2, 18425 },                                                   -- Improved Kick
    { 3, 18498 },                                                   -- Gag Order
    { 2, 25046, 28730, 50613 },                                     -- Arcane Torrent
    { 3, 63529 },                                                   -- Shield of the Templar
    { 10, 5782, 6213, 6215 },                                       -- Fear
    { 10, 6358 },                                                   -- Seduction
    { 8, 8122, 8124, 10888, 10890 },                                -- Psychic Scream
    { 8, 5246, 20511 },                                             -- Intimidating Shout
    { 3, 6789, 17925, 17926, 27223, 47859, 47860 },                 -- Death Coil
    { 3, 64044 },                                                   -- Psychic Horror
    { 10, 2094 },                                                   -- Blind
    { 4, 19503 },                                                   -- Scatter Shot
    { 5, 31661, 33041, 33042, 33043, 42949, 42950 },                -- Dragon's Breath
    { 10, 49203 },                                                  -- Hungering Cold
    { 10, 118, 12824, 12825, 12826, 28271, 28272, 61305, 61025, 61721, 61780 }, -- Polymorph
    { 10, 3355, 14308, 14309, 60210 },                              -- Freezing Trap / Arrow
    { 6, 19386, 24132, 24133, 27068, 49011, 49012 },                -- Wyvern Sting
    { 6, 20066 },                                                   -- Repentance
    { 10, 6770, 2070, 11297, 51724 },                               -- Sap
    { 4, 1776 },                                                    -- Gouge
    { 10, 2637, 18657, 18658 },                                     -- Hibernate
    { 10, 51514 },                                                  -- Hex
    { 6, 33786 },                                                   -- Cyclone
    { 10, 339, 1062, 5195, 5196, 9852, 9853, 26989, 53308 },        -- Entangling Roots
    { 8, 122, 865, 6131, 10230, 27088, 42917 },                     -- Frost Nova
    { 5, 12494 },                                                   -- Frostbite
    { 8, 55080 },                                                   -- Shattered Barrier
    { 5, 23694 },                                                   -- Improved Hamstring
    -- (LibAuraInfo-1.0 / DRData-1.0 1049; combo-point spells assume 5 points)
    { 5, 408 }, { 6, 8643 },                                        -- Kidney Shot
    { 5, 22570, 49802 },                                            -- Maim
    { 2, 20170 },                                                   -- Seal of Justice stun
    { 3, 10318, 27139, 48816, 48817 },                              -- Holy Wrath
    { 2, 16544 },                                                   -- Improved Fire Nova Totem
    { 2, 58861 },                                                   -- Bash (Spirit Wolf)
    { 4, 55021 },                                                   -- Improved Counterspell (rank 2)
    { 2, 62347 },                                                   -- Nether Shock
    { 5, 31117 },                                                   -- Unstable Affliction silence
    { 6, 5484 }, { 8, 17928 },                                      -- Howl of Terror
    { 10, 1513, 14326, 14327 },                                     -- Scare Beast
    { 10, 10326 },                                                  -- Turn Evil
    { 10, 605 },                                                    -- Mind Control
    { 6, 710, 18647 },                                              -- Banish
    { 10, 9484, 9485, 10955 },                                      -- Shackle Undead
    { 4, 37506 },                                                   -- Scatter Shot
    { 5, 33395, 63685 },                                            -- Freeze
    { 4, 8377, 31983 }, { 5, 64695 },                               -- Earthgrab
    { 4, 19185, 64803, 64804 },                                     -- Entrapment
    { 5, 19306, 20909, 20910, 27067, 48998, 48999 },                -- Counterattack
    { 4, 45334 },                                                   -- Feral Charge Effect
    { 4, 4167 },                                                    -- Web
    { 10, 676, 51722, 64058, 53359 },                               -- Disarm, Dismantle, Psychic Horror, Chimera
    { 10, 53542, 53543 },                                           -- Snatch
    { 10, 19970, 19971, 19972, 19973, 19974, 19975, 27010, 53313 }, -- Nature's Grasp
    { 3, 20252 },                                                   -- Intercept
}
addon.CrowdControlBaseDuration = {};
for _, row in ipairs(baseDurations) do
    for i = 2, #row do addon.CrowdControlBaseDuration[row[i]] = row[1] end
end

-- diminishing-returns categories (DRData-1.0 layout). Spells of one
-- category share DR: full, then half, then a quarter duration, then immune;
-- reset 20 s (DRData RESET_TIME) after the last one was applied.
local DR_BY_CATEGORY = { stun = "ctrlstun", silence = "silence", fear = "fear", horror = "horror",
    disorient = "disorient", incapacitate = "disorient", cyclone = "cyclone", root = "ctrlroot", disarm = "disarm" }
-- spells DRData-1.0 1049 does not list get no DR ("none").
local drExceptions = {
    rndstun = { 12355, 39796, 20170, 12798, 16544 },
    cheapshot = { 1833, 9005, 9823, 9827, 27006, 49803 },
    charge = { 7922 },
    fear = { 2094 },
    scatters = { 19503, 37506 },
    sleep = { 2637, 18657, 18658 },
    mc = { 605 },
    banish = { 710, 18647 },
    rndroot = { 23694, 12494, 55080 },
    entrapment = { 19185, 64803, 64804 },
    none = { 20276, 31117, 63685, 64695, 19306, 20909, 20910, 27067, 48998, 48999, 45334,
        13099, 13119, 13120, 13138, 13139, 16566, 55536, 39965 },
}
addon.CrowdControlDR = {};
for spellId, category in pairs(addon.CrowdControlDefinitions) do
    addon.CrowdControlDR[spellId] = DR_BY_CATEGORY[category]
end
for drCategory, ids in pairs(drExceptions) do
    for _, spellId in ipairs(ids) do
        addon.CrowdControlDR[spellId] = drCategory ~= "none" and drCategory or false
    end
end
addon.CROWD_CONTROL_DR_RESET = 20
addon.CrowdControlDRByCategory = DR_BY_CATEGORY

-- which CC is drawn when a player has several (highest wins, a tie goes
-- to the newest). Display order (separate from DR): A stuns > B incapacitate/
-- disorient/Cyclone (Mind Control included) > C fears/horrors (Seduction
-- included) > D silences > E roots > F disarms.
local CC_CATEGORY_PRIORITY = { stun = 100, incapacitate = 90, disorient = 90, cyclone = 90,
    fear = 80, horror = 80, silence = 70, root = 60, disarm = 50 }
addon.CrowdControlPriority = function(category, spellId)
    return CC_CATEGORY_PRIORITY[category] or 40
end

-- Built on first use (spell names are client-localized). A name shared by two
-- categories maps to false and is never used.
local byName;
addon.GetCrowdControlCategory = function(spellId, spellName)
    local category = spellId and addon.CrowdControlAuras[spellId];
    if category or type(spellName) ~= "string" then return category end
    if not byName then
        byName = {};
        for id, cat in pairs(addon.CrowdControlAuras) do
            local name = not NAME_UNSAFE[id] and GetSpellInfo(id);
            if name then
                local old = byName[name];
                if old == nil then byName[name] = cat elseif old ~= cat then byName[name] = false end
            end
        end
    end
    return byName[spellName] or nil
end

-- Breaker spell ID -> set of CC spell IDs it can remove (WotLK). Kept for
-- compatibility; Healer-in-CC chooses breakers by the aura's dispel type.
local breakers = {
    [2782] = { [51514] = true },  -- Remove Curse (Druid): Hex
    [51886] = { [51514] = true }, -- Cleanse Spirit (Shaman): Hex
    [475] = { [51514] = true },   -- Remove Curse (Mage): Hex
};

addon.CrowdControlBreakers = {};
for breaker, ccs in pairs(breakers) do
    for spellID in pairs(ccs) do
        addon.CrowdControlBreakers[spellID] = addon.CrowdControlBreakers[spellID] or {};
        addon.CrowdControlBreakers[spellID][breaker] = true;
    end
end

-- Self-cast healer-talent auras (Overlay counts them only when the unit cast
-- them on itself; a tank wearing a healer's Earth Shield is not a healer).
-- Lifebloom is baseline for every druid and therefore proves nothing.
addon.HealerBuffAuras = {
    [53563] = true,                                                       -- Beacon of Light
    [974] = true, [32593] = true, [32594] = true, [49283] = true, [49284] = true, -- Earth Shield
    [47788] = true,                                                       -- Guardian Spirit
};

-- coloured countdown (shared with the nameplate centre timer):
-- grey/white "Xh"/"Xm" at 1 minute or more, yellow whole seconds 59..6, red
-- whole seconds 5 and 4, then red tenths 3.9 .. 0.0.
addon.FormatCountdown = function(remain)
    if remain >= 3600 then
        return string.format("%dh", math.floor(remain / 3600 + 0.5)), 0.8, 0.8, 0.8
    elseif remain >= 60 then
        return string.format("%dm", math.floor(remain / 60 + 0.5)), 0.9, 0.9, 0.9
    elseif remain >= 6 then
        return string.format("%d", math.floor(remain)), 1, 0.85, 0.1
    elseif remain >= 4 then
        return string.format("%d", math.floor(remain)), 1, 0.15, 0.15
    end
    return string.format("%.1f", math.floor(math.max(0, remain) * 10) / 10), 1, 0.15, 0.15
end
