local _, addon = ...

addon.TEST_MODE = false
addon.PROJECT_WOTLK = true
addon.PROFILE_VERSION = 1.0

addon.ADDON_ICON = "Interface\\Icons\\Ability_DualWield"
-- OPlates' own role icons (64x64 BLP2, ARGB8888, full mip chain), drawn
-- round by the portrait renderer like every other square icon.
addon.HEALER_ICON = "Interface\\AddOns\\OPlates\\Art\\Healer_Icon"
addon.TANK_ICON = "Interface\\AddOns\\OPlates\\Art\\Tank_Icon"
addon.ROLE_ICONS = { HEALER = addon.HEALER_ICON, TANK = addon.TANK_ICON }
addon.PET_ICON = "Interface\\Icons\\Ability_Hunter_MendPet"
addon.UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
addon.FLAG_ICON_HORDE = "Interface\\Icons\\INV_BannerPVP_01"
addon.FLAG_ICON_ALLIANCE = "Interface\\Icons\\INV_BannerPVP_02"
addon.FLAG_ICON_NEUTRAL = "Interface\\Icons\\INV_BannerPVP_03"
addon.CLASS_ICON_ATLAS = "Interface\\TargetingFrame\\UI-Classes-Circles"
addon.CLASS_ICON_BORDER = "Interface\\AddOns\\OPlates\\Art\\ClassIconBorder"
-- The original 512x512 border has transparent padding. These texcoords crop to its
-- actual visible ring while keeping the texture power-of-two for WotLK stability.
addon.CLASS_ICON_BORDER_TCOORDS = { 89/512, 423/512, 89/512, 423/512 }
-- The visible ring is intentionally allowed to extend just beyond the icon frame so
-- the border hugs the icon from the outside instead of disappearing inside its edge.
addon.CLASS_ICON_BORDER_OUTSET = 1.08
-- OPlates' own pre-rounded art (64x64 and 128x128 icons, 256x256 QR code).
addon.HEALER_CC_ART = "Interface\\AddOns\\OPlates\\Art\\HealerCC"
addon.SUPPORT_ART = "Interface\\AddOns\\OPlates\\Art\\Support"
addon.LOGO_ART = "Interface\\AddOns\\OPlates\\Art\\Logo"
addon.SUPPORT_QR_ART = "Interface\\AddOns\\OPlates\\Art\\SupportQR"

-- WotLK flag-carrying auras: 23333 is the Horde Flag (carried by an
-- Alliance player) and 23335 the Alliance Flag.
addon.FLAG_AURAS = {
    [23333] = "Horde",
    [23335] = "Alliance",
    [34976] = "Neutral",
}

addon.FLAG_ICON_BY_FACTION = {
    Alliance = addon.FLAG_ICON_ALLIANCE,
    Horde = addon.FLAG_ICON_HORDE,
    Neutral = addon.FLAG_ICON_NEUTRAL,
}

-- Spell signatures used only to improve WotLK spec inference from observed casts.
-- The client has no Retail specialization API, so this is deliberately a confidence/cache system.
-- Spec classification for role overlays. Feral is treated as tank only when a tank signature is seen.
addon.TALENT_TAB_SPECS = {
    WARRIOR = { [1] = "ARMS", [2] = "FURY", [3] = "PROTECTION" },
    PALADIN = { [1] = "HOLY", [2] = "PROTECTION", [3] = "RETRIBUTION" },
    HUNTER = { [1] = "BEAST_MASTERY", [2] = "MARKSMANSHIP", [3] = "SURVIVAL" },
    ROGUE = { [1] = "ASSASSINATION", [2] = "COMBAT", [3] = "SUBTLETY" },
    PRIEST = { [1] = "DISCIPLINE", [2] = "HOLY", [3] = "SHADOW" },
    DEATHKNIGHT = { [1] = "BLOOD", [2] = "FROST", [3] = "UNHOLY" },
    SHAMAN = { [1] = "ELEMENTAL", [2] = "ENHANCEMENT", [3] = "RESTORATION" },
    MAGE = { [1] = "ARCANE", [2] = "FIRE", [3] = "FROST" },
    WARLOCK = { [1] = "AFFLICTION", [2] = "DEMONOLOGY", [3] = "DESTRUCTION" },
    DRUID = { [1] = "BALANCE", [2] = "FERAL", [3] = "RESTORATION" },
}

addon.SPEC_ROLES = {
    WARRIOR = { ARMS = "DAMAGER", FURY = "DAMAGER", PROTECTION = "TANK" },
    PALADIN = { HOLY = "HEALER", PROTECTION = "TANK", RETRIBUTION = "DAMAGER" },
    HUNTER = { BEAST_MASTERY = "DAMAGER", MARKSMANSHIP = "DAMAGER", SURVIVAL = "DAMAGER" },
    ROGUE = { ASSASSINATION = "DAMAGER", COMBAT = "DAMAGER", SUBTLETY = "DAMAGER" },
    PRIEST = { DISCIPLINE = "HEALER", HOLY = "HEALER", SHADOW = "DAMAGER" },
    DEATHKNIGHT = { BLOOD = "TANK", FROST = "DAMAGER", UNHOLY = "DAMAGER" },
    SHAMAN = { ELEMENTAL = "DAMAGER", ENHANCEMENT = "DAMAGER", RESTORATION = "HEALER" },
    MAGE = { ARCANE = "DAMAGER", FIRE = "DAMAGER", FROST = "DAMAGER" },
    WARLOCK = { AFFLICTION = "DAMAGER", DEMONOLOGY = "DAMAGER", DESTRUCTION = "DAMAGER" },
    DRUID = { BALANCE = "DAMAGER", FERAL = "DAMAGER", RESTORATION = "HEALER" },
}

-- Stable WotLK talent-tree icons for GUID-validated group communication.
-- Never read the shared inspect buffer to choose a communicated spec's texture.
addon.SPEC_TREE_ICONS = {
    WARRIOR = {
        ARMS = "Interface\\Icons\\Ability_Rogue_Eviscerate",
        FURY = "Interface\\Icons\\Ability_Warrior_InnerRage",
        PROTECTION = "Interface\\Icons\\INV_Shield_06",
    },
    PALADIN = {
        HOLY = "Interface\\Icons\\Spell_Holy_HolyBolt",
        PROTECTION = "Interface\\Icons\\Spell_Holy_DevotionAura",
        RETRIBUTION = "Interface\\Icons\\Spell_Holy_AuraOfLight",
    },
    HUNTER = {
        BEAST_MASTERY = "Interface\\Icons\\Ability_Hunter_BeastTaming",
        MARKSMANSHIP = "Interface\\Icons\\Ability_Marksmanship",
        SURVIVAL = "Interface\\Icons\\Ability_Hunter_SwiftStrike",
    },
    ROGUE = {
        ASSASSINATION = "Interface\\Icons\\Ability_Rogue_Eviscerate",
        COMBAT = "Interface\\Icons\\Ability_BackStab",
        SUBTLETY = "Interface\\Icons\\Ability_Stealth",
    },
    PRIEST = {
        DISCIPLINE = "Interface\\Icons\\Spell_Holy_WordFortitude",
        HOLY = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
        SHADOW = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    },
    DEATHKNIGHT = {
        BLOOD = "Interface\\Icons\\Spell_Deathknight_BloodPresence",
        FROST = "Interface\\Icons\\Spell_Deathknight_FrostPresence",
        UNHOLY = "Interface\\Icons\\Spell_Deathknight_UnholyPresence",
    },
    SHAMAN = {
        ELEMENTAL = "Interface\\Icons\\Spell_Nature_Lightning",
        ENHANCEMENT = "Interface\\Icons\\Spell_Nature_LightningShield",
        RESTORATION = "Interface\\Icons\\Spell_Nature_MagicImmunity",
    },
    MAGE = {
        ARCANE = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        FIRE = "Interface\\Icons\\Spell_Fire_FireBolt02",
        FROST = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    },
    WARLOCK = {
        AFFLICTION = "Interface\\Icons\\Spell_Shadow_DeathCoil",
        DEMONOLOGY = "Interface\\Icons\\Spell_Shadow_Metamorphosis",
        DESTRUCTION = "Interface\\Icons\\Spell_Shadow_RainOfFire",
    },
    DRUID = {
        BALANCE = "Interface\\Icons\\Spell_Nature_StarFall",
        FERAL = "Interface\\Icons\\Ability_Racial_BearForm",
        RESTORATION = "Interface\\Icons\\Spell_Nature_HealingTouch",
    },
}

-- enemy spec signatures: spellID = { class, spec, strength[, feralKind] }.
-- Matched by spell NAME (every rank, any client language) from the combat log
-- of hostile players only. Strength 2 = 51-point talent: the owner has more
-- points in that tree than in both others together, so it is always right.
-- Strength 1 = deep (31+ point) talent: right for practically every real
-- build; it never overrides a strength-2 result. Shallow talents are excluded.
-- Signature spells, one entry per spell NAME (not per rank).
-- The map is keyed by GetSpellInfo() name in Signatures(), so a single id
-- covers every rank of that spell: a downranked Frostbolt still reports
-- "Frostbolt" in the combat log. The id below is only the seed that
-- resolves the name, so it does not matter which rank it points at.
--
-- Every entry is a TALENT at row 5 or deeper (25+ points in that tree),
-- taken from this client's own Talent.dbc / TalentTab.dbc / Spell.dbc,
-- so it is unobtainable by the other two specs of the class. Base class
-- abilities are deliberately absent: Frostbolt, Fireball, Starfire,
-- Holy Light and Death Coil are trainable by every spec of their class
-- and would tag the wrong spec. Names shared by two specs, or shared
-- with another class's spell list, were dropped in the same pass.
--
-- The third value is the talent row, i.e. how deep the talent sits, and
-- doubles as confidence: a deeper talent always outranks a shallower one
-- when two signals disagree (see NoteEnemySpec).
--
-- One deliberate exclusion: "Berserk" (50334). On this server the client
-- localizes other classes' casts to that same name, so a name-matched
-- signature flipped paladins and warriors to DRUID FERAL. Feral is already
-- proven by Mangle (Cat) / Mangle (Bear) and twelve other Feral talents.
addon.SPEC_SIGNATURES = {
    -- WARRIOR
    -- ARMS
    [46924] = { "WARRIOR", "ARMS", 10 },      -- Bladestorm
    [46867] = { "WARRIOR", "ARMS", 9 },       -- Wrecking Crew
    [29836] = { "WARRIOR", "ARMS", 8 },       -- Blood Frenzy
    [29623] = { "WARRIOR", "ARMS", 8 },       -- Endless Rage
    [29723] = { "WARRIOR", "ARMS", 8 },       -- Sudden Death
    [35446] = { "WARRIOR", "ARMS", 7 },       -- Improved Mortal Strike
    [64976] = { "WARRIOR", "ARMS", 7 },       -- Juggernaut
    [46859] = { "WARRIOR", "ARMS", 7 },       -- Unrelenting Assault
    [12862] = { "WARRIOR", "ARMS", 6 },       -- Improved Slam
    [12294] = { "WARRIOR", "ARMS", 6 },       -- Mortal Strike
    [29834] = { "WARRIOR", "ARMS", 6 },       -- Second Wind
    [46865] = { "WARRIOR", "ARMS", 6 },       -- Strength of Arms
    [12289] = { "WARRIOR", "ARMS", 5 },       -- Improved Hamstring
    [46854] = { "WARRIOR", "ARMS", 5 },       -- Trauma
    -- FURY
    [46917] = { "WARRIOR", "FURY", 10 },      -- Titan's Grip
    [56927] = { "WARRIOR", "FURY", 9 },       -- Unending Fury
    [46913] = { "WARRIOR", "FURY", 8 },       -- Bloodsurge
    [60970] = { "WARRIOR", "FURY", 8 },       -- Heroic Fury
    [29801] = { "WARRIOR", "FURY", 8 },       -- Rampage
    [46910] = { "WARRIOR", "FURY", 7 },       -- Furious Attacks
    [29759] = { "WARRIOR", "FURY", 7 },       -- Improved Berserker Stance
    [23881] = { "WARRIOR", "FURY", 6 },       -- Bloodthirst
    [29721] = { "WARRIOR", "FURY", 6 },       -- Improved Whirlwind
    [46908] = { "WARRIOR", "FURY", 6 },       -- Intensify Rage
    [20500] = { "WARRIOR", "FURY", 5 },       -- Improved Berserker Rage
    -- PROTECTION
    [46968] = { "WARRIOR", "PROTECTION", 10 },-- Shockwave
    [58872] = { "WARRIOR", "PROTECTION", 9 }, -- Damage Shield
    [46951] = { "WARRIOR", "PROTECTION", 9 }, -- Sword and Board
    [47294] = { "WARRIOR", "PROTECTION", 8 }, -- Critical Block
    [20243] = { "WARRIOR", "PROTECTION", 8 }, -- Devastate
    [57499] = { "WARRIOR", "PROTECTION", 8 }, -- Warbringer
    [46945] = { "WARRIOR", "PROTECTION", 7 }, -- Safeguard
    [29787] = { "WARRIOR", "PROTECTION", 6 }, -- Focused Rage
    [29593] = { "WARRIOR", "PROTECTION", 6 }, -- Improved Defensive Stance
    [50720] = { "WARRIOR", "PROTECTION", 6 }, -- Vigilance
    -- PALADIN
    -- HOLY
    [53563] = { "PALADIN", "HOLY", 10 },      -- Beacon of Light
    [53556] = { "PALADIN", "HOLY", 9 },       -- Enlightened Judgements
    [53569] = { "PALADIN", "HOLY", 9 },       -- Infusion of Light
    [31842] = { "PALADIN", "HOLY", 8 },       -- Divine Illumination
    [53671] = { "PALADIN", "HOLY", 8 },       -- Judgements of the Pure
    [31837] = { "PALADIN", "HOLY", 7 },       -- Holy Guidance
    [53551] = { "PALADIN", "HOLY", 7 },       -- Sacred Cleansing
    [31828] = { "PALADIN", "HOLY", 6 },       -- Blessed Life
    [20473] = { "PALADIN", "HOLY", 6 },       -- Holy Shock
    [31833] = { "PALADIN", "HOLY", 6 },       -- Light's Grace
    [5923] = { "PALADIN", "HOLY", 5 },        -- Holy Power
    [31825] = { "PALADIN", "HOLY", 5 },       -- Purifying Power
    -- PROTECTION
    [53595] = { "PALADIN", "PROTECTION", 10 },-- Hammer of the Righteous
    [53695] = { "PALADIN", "PROTECTION", 9 }, -- Judgements of the Just
    [53709] = { "PALADIN", "PROTECTION", 9 }, -- Shield of the Templar
    [31935] = { "PALADIN", "PROTECTION", 8 }, -- Avenger's Shield
    [53583] = { "PALADIN", "PROTECTION", 8 }, -- Guarded by the Light
    [53590] = { "PALADIN", "PROTECTION", 8 }, -- Touched by the Light
    [31858] = { "PALADIN", "PROTECTION", 7 }, -- Combat Expertise
    [20127] = { "PALADIN", "PROTECTION", 7 }, -- Redoubt
    [31850] = { "PALADIN", "PROTECTION", 6 }, -- Ardent Defender
    [20925] = { "PALADIN", "PROTECTION", 6 }, -- Holy Shield
    [31785] = { "PALADIN", "PROTECTION", 6 }, -- Spiritual Attunement
    [31848] = { "PALADIN", "PROTECTION", 5 }, -- Sacred Duty
    -- RETRIBUTION
    [53385] = { "PALADIN", "RETRIBUTION", 10 },-- Divine Storm
    [53380] = { "PALADIN", "RETRIBUTION", 9 },-- Righteous Vengeance
    [35395] = { "PALADIN", "RETRIBUTION", 8 },-- Crusader Strike
    [53501] = { "PALADIN", "RETRIBUTION", 8 },-- Sheath of Light
    [53379] = { "PALADIN", "RETRIBUTION", 8 },-- Swift Retribution
    [31879] = { "PALADIN", "RETRIBUTION", 7 },-- Fanaticism
    [53375] = { "PALADIN", "RETRIBUTION", 7 },-- Sanctified Wrath
    [31876] = { "PALADIN", "RETRIBUTION", 6 },-- Judgements of the Wise
    [20066] = { "PALADIN", "RETRIBUTION", 6 },-- Repentance
    [53486] = { "PALADIN", "RETRIBUTION", 6 },-- The Art of War
    [31871] = { "PALADIN", "RETRIBUTION", 5 },-- Divine Purpose
    -- HUNTER
    -- BEAST_MASTERY
    [53270] = { "HUNTER", "BEAST_MASTERY", 10 },-- Beast Mastery
    [56314] = { "HUNTER", "BEAST_MASTERY", 9 },-- Kindred Spirits
    [53256] = { "HUNTER", "BEAST_MASTERY", 8 },-- Cobra Strikes
    [53262] = { "HUNTER", "BEAST_MASTERY", 8 },-- Longevity
    [34471] = { "HUNTER", "BEAST_MASTERY", 8 },-- The Beast Within
    [53252] = { "HUNTER", "BEAST_MASTERY", 7 },-- Invigoration
    [34466] = { "HUNTER", "BEAST_MASTERY", 7 },-- Serpent's Swiftness
    [19574] = { "HUNTER", "BEAST_MASTERY", 6 },-- Bestial Wrath
    [34462] = { "HUNTER", "BEAST_MASTERY", 6 },-- Catlike Reflexes
    [34455] = { "HUNTER", "BEAST_MASTERY", 6 },-- Ferocious Inspiration
    [34453] = { "HUNTER", "BEAST_MASTERY", 5 },-- Animal Handler
    [19621] = { "HUNTER", "BEAST_MASTERY", 5 },-- Frenzy
    -- MARKSMANSHIP
    [53209] = { "HUNTER", "MARKSMANSHIP", 10 },-- Chimera Shot
    [53241] = { "HUNTER", "MARKSMANSHIP", 9 },-- Marked for Death
    [53221] = { "HUNTER", "MARKSMANSHIP", 8 },-- Improved Steady Shot
    [34490] = { "HUNTER", "MARKSMANSHIP", 8 },-- Silencing Shot
    [53215] = { "HUNTER", "MARKSMANSHIP", 8 },-- Wild Quiver
    [34485] = { "HUNTER", "MARKSMANSHIP", 7 },-- Master Marksman
    [53228] = { "HUNTER", "MARKSMANSHIP", 7 },-- Rapid Recuperation
    [35104] = { "HUNTER", "MARKSMANSHIP", 6 },-- Improved Barrage
    [53234] = { "HUNTER", "MARKSMANSHIP", 6 },-- Piercing Shots
    [19506] = { "HUNTER", "MARKSMANSHIP", 6 },-- Trueshot Aura
    [34475] = { "HUNTER", "MARKSMANSHIP", 5 },-- Combat Experience
    [19507] = { "HUNTER", "MARKSMANSHIP", 5 },-- Ranged Weapon Specialization
    -- SURVIVAL
    [53301] = { "HUNTER", "SURVIVAL", 10 },   -- Explosive Shot
    [53290] = { "HUNTER", "SURVIVAL", 9 },    -- Hunting Party
    [3674] = { "HUNTER", "SURVIVAL", 8 },     -- Black Arrow
    [53298] = { "HUNTER", "SURVIVAL", 8 },    -- Point of No Escape
    [53302] = { "HUNTER", "SURVIVAL", 8 },    -- Sniper Training
    [34506] = { "HUNTER", "SURVIVAL", 7 },    -- Master Tactician
    [53295] = { "HUNTER", "SURVIVAL", 7 },    -- Noxious Stings
    [34500] = { "HUNTER", "SURVIVAL", 6 },    -- Expose Weakness
    [34497] = { "HUNTER", "SURVIVAL", 6 },    -- Thrill of the Hunt
    [19386] = { "HUNTER", "SURVIVAL", 6 },    -- Wyvern Sting
    [34491] = { "HUNTER", "SURVIVAL", 5 },    -- Resourcefulness
    -- ROGUE
    -- ASSASSINATION
    [51662] = { "ROGUE", "ASSASSINATION", 10 },-- Hunger For Blood
    [51664] = { "ROGUE", "ASSASSINATION", 9 },-- Cut to the Chase
    [31226] = { "ROGUE", "ASSASSINATION", 8 },-- Master Poisoner
    [1329] = { "ROGUE", "ASSASSINATION", 8 }, -- Mutilate
    [51627] = { "ROGUE", "ASSASSINATION", 8 },-- Turn the Tables
    [31234] = { "ROGUE", "ASSASSINATION", 7 },-- Find Weakness
    [51634] = { "ROGUE", "ASSASSINATION", 7 },-- Focused Attacks
    [31380] = { "ROGUE", "ASSASSINATION", 6 },-- Deadened Nerves
    [51625] = { "ROGUE", "ASSASSINATION", 6 },-- Deadly Brew
    [58426] = { "ROGUE", "ASSASSINATION", 6 },-- Overkill
    [14158] = { "ROGUE", "ASSASSINATION", 5 },-- Murder
    [14186] = { "ROGUE", "ASSASSINATION", 5 },-- Seal Fate
    -- COMBAT
    [51690] = { "ROGUE", "COMBAT", 10 },      -- Killing Spree
    [51685] = { "ROGUE", "COMBAT", 9 },       -- Prey on the Weak
    [51682] = { "ROGUE", "COMBAT", 8 },       -- Savage Combat
    [32601] = { "ROGUE", "COMBAT", 8 },       -- Surprise Attacks
    [51672] = { "ROGUE", "COMBAT", 8 },       -- Unfair Advantage
    [35541] = { "ROGUE", "COMBAT", 7 },       -- Combat Potency
    [5952] = { "ROGUE", "COMBAT", 7 },        -- Throwing Specialization
    [13750] = { "ROGUE", "COMBAT", 6 },       -- Adrenaline Rush
    [31130] = { "ROGUE", "COMBAT", 6 },       -- Nerves of Steel
    [31124] = { "ROGUE", "COMBAT", 5 },       -- Blade Twisting
    [30919] = { "ROGUE", "COMBAT", 5 },       -- Weapon Expertise
    -- SUBTLETY
    [51713] = { "ROGUE", "SUBTLETY", 10 },    -- Shadow Dance
    [51708] = { "ROGUE", "SUBTLETY", 9 },     -- Slaughter from the Shadows
    [58414] = { "ROGUE", "SUBTLETY", 8 },     -- Filthy Tricks
    [51698] = { "ROGUE", "SUBTLETY", 8 },     -- Honor Among Thieves
    [36554] = { "ROGUE", "SUBTLETY", 8 },     -- Shadowstep
    [31216] = { "ROGUE", "SUBTLETY", 7 },     -- Sinister Calling
    [51692] = { "ROGUE", "SUBTLETY", 7 },     -- Waylay
    [31228] = { "ROGUE", "SUBTLETY", 6 },     -- Cheat Death
    [31211] = { "ROGUE", "SUBTLETY", 6 },     -- Enveloping Shadows
    [14183] = { "ROGUE", "SUBTLETY", 6 },     -- Premeditation
    [30902] = { "ROGUE", "SUBTLETY", 5 },     -- Deadliness
    [31221] = { "ROGUE", "SUBTLETY", 5 },     -- Master of Subtlety
    -- PRIEST
    -- DISCIPLINE
    [47540] = { "PRIEST", "DISCIPLINE", 10 }, -- Penance
    [52795] = { "PRIEST", "DISCIPLINE", 9 },  -- Borrowed Time
    [47509] = { "PRIEST", "DISCIPLINE", 8 },  -- Divine Aegis
    [47516] = { "PRIEST", "DISCIPLINE", 8 },  -- Grace
    [33206] = { "PRIEST", "DISCIPLINE", 8 },  -- Pain Suppression
    [47507] = { "PRIEST", "DISCIPLINE", 7 },  -- Aspiration
    [47535] = { "PRIEST", "DISCIPLINE", 7 },  -- Rapture
    [57470] = { "PRIEST", "DISCIPLINE", 7 },  -- Renewed Hope
    [45234] = { "PRIEST", "DISCIPLINE", 6 },  -- Focused Will
    [63504] = { "PRIEST", "DISCIPLINE", 6 },  -- Improved Flash Heal
    [10060] = { "PRIEST", "DISCIPLINE", 6 },  -- Power Infusion
    [34908] = { "PRIEST", "DISCIPLINE", 5 },  -- Enlightenment
    [33186] = { "PRIEST", "DISCIPLINE", 5 },  -- Focused Power
    -- HOLY
    [47788] = { "PRIEST", "HOLY", 10 },       -- Guardian Spirit
    [47562] = { "PRIEST", "HOLY", 9 },        -- Divine Providence
    [34861] = { "PRIEST", "HOLY", 8 },        -- Circle of Healing
    [63534] = { "PRIEST", "HOLY", 8 },        -- Empowered Renew
    [47558] = { "PRIEST", "HOLY", 8 },        -- Test of Faith
    [64127] = { "PRIEST", "HOLY", 7 },        -- Body and Soul
    [33158] = { "PRIEST", "HOLY", 7 },        -- Empowered Healing
    [63730] = { "PRIEST", "HOLY", 7 },        -- Serendipity
    [33142] = { "PRIEST", "HOLY", 6 },        -- Blessed Resilience
    [34753] = { "PRIEST", "HOLY", 6 },        -- Holy Concentration
    [724] = { "PRIEST", "HOLY", 6 },          -- Lightwell
    [14898] = { "PRIEST", "HOLY", 5 },        -- Spiritual Healing
    [33150] = { "PRIEST", "HOLY", 5 },        -- Surge of Light
    -- SHADOW
    [47585] = { "PRIEST", "SHADOW", 10 },     -- Dispersion
    [47573] = { "PRIEST", "SHADOW", 9 },      -- Twisted Faith
    [47580] = { "PRIEST", "SHADOW", 8 },      -- Pain and Suffering
    [64044] = { "PRIEST", "SHADOW", 8 },      -- Psychic Horror
    [34914] = { "PRIEST", "SHADOW", 8 },      -- Vampiric Touch
    [47569] = { "PRIEST", "SHADOW", 7 },      -- Improved Shadowform
    [33191] = { "PRIEST", "SHADOW", 7 },      -- Misery
    [33221] = { "PRIEST", "SHADOW", 6 },      -- Shadow Power
    [15473] = { "PRIEST", "SHADOW", 6 },      -- Shadowform
    [63625] = { "PRIEST", "SHADOW", 5 },      -- Improved Devouring Plague
    [14910] = { "PRIEST", "SHADOW", 5 },      -- Mind Melt
    -- DEATHKNIGHT
    -- BLOOD
    [49028] = { "DEATHKNIGHT", "BLOOD", 10 }, -- Dancing Rune Weapon
    [61154] = { "DEATHKNIGHT", "BLOOD", 9 },  -- Blood Gorged
    [55050] = { "DEATHKNIGHT", "BLOOD", 8 },  -- Heart Strike
    [49023] = { "DEATHKNIGHT", "BLOOD", 8 },  -- Might of Mograine
    [49189] = { "DEATHKNIGHT", "BLOOD", 8 },  -- Will of the Necropolis
    [62905] = { "DEATHKNIGHT", "BLOOD", 7 },  -- Improved Death Strike
    [49018] = { "DEATHKNIGHT", "BLOOD", 7 },  -- Sudden Doom
    [55233] = { "DEATHKNIGHT", "BLOOD", 7 },  -- Vampiric Blood
    [49027] = { "DEATHKNIGHT", "BLOOD", 6 },  -- Bloodworms
    [49016] = { "DEATHKNIGHT", "BLOOD", 6 },  -- Hysteria
    [50365] = { "DEATHKNIGHT", "BLOOD", 6 },  -- Improved Blood Presence
    [53137] = { "DEATHKNIGHT", "BLOOD", 5 },  -- Abomination's Might
    [48988] = { "DEATHKNIGHT", "BLOOD", 5 },  -- Bloody Vengeance
    -- FROST
    [49184] = { "DEATHKNIGHT", "FROST", 10 }, -- Howling Blast
    [49202] = { "DEATHKNIGHT", "FROST", 9 },  -- Tundra Stalker
    [49200] = { "DEATHKNIGHT", "FROST", 8 },  -- Acclimation
    [49143] = { "DEATHKNIGHT", "FROST", 8 },  -- Frost Strike
    [50187] = { "DEATHKNIGHT", "FROST", 8 },  -- Guile of Gorefiend
    [54639] = { "DEATHKNIGHT", "FROST", 7 },  -- Blood of the North
    [65661] = { "DEATHKNIGHT", "FROST", 7 },  -- Threat of Thassarian
    [51271] = { "DEATHKNIGHT", "FROST", 7 },  -- Unbreakable Armor
    [50040] = { "DEATHKNIGHT", "FROST", 6 },  -- Chilblains
    [49203] = { "DEATHKNIGHT", "FROST", 6 },  -- Hungering Cold
    [50384] = { "DEATHKNIGHT", "FROST", 6 },  -- Improved Frost Presence
    [55610] = { "DEATHKNIGHT", "FROST", 5 },  -- Improved Icy Talons
    [49024] = { "DEATHKNIGHT", "FROST", 5 },  -- Merciless Combat
    [49188] = { "DEATHKNIGHT", "FROST", 5 },  -- Rime
    -- UNHOLY
    [49206] = { "DEATHKNIGHT", "UNHOLY", 10 },-- Summon Gargoyle
    [50117] = { "DEATHKNIGHT", "UNHOLY", 9 }, -- Rage of Rivendare
    [51099] = { "DEATHKNIGHT", "UNHOLY", 8 }, -- Ebon Plaguebringer
    [55090] = { "DEATHKNIGHT", "UNHOLY", 8 }, -- Scourge Strike
    [49217] = { "DEATHKNIGHT", "UNHOLY", 8 }, -- Wandering Plague
    [49222] = { "DEATHKNIGHT", "UNHOLY", 7 }, -- Bone Shield
    [49032] = { "DEATHKNIGHT", "UNHOLY", 7 }, -- Crypt Fever
    [51052] = { "DEATHKNIGHT", "UNHOLY", 6 }, -- Anti-Magic Zone
    [66799] = { "DEATHKNIGHT", "UNHOLY", 6 }, -- Desolation
    [63560] = { "DEATHKNIGHT", "UNHOLY", 6 }, -- Ghoul Frenzy
    [50391] = { "DEATHKNIGHT", "UNHOLY", 6 }, -- Improved Unholy Presence
    [55666] = { "DEATHKNIGHT", "UNHOLY", 5 }, -- Desecration
    [49224] = { "DEATHKNIGHT", "UNHOLY", 5 }, -- Magic Suppression
    [52143] = { "DEATHKNIGHT", "UNHOLY", 5 }, -- Master of Ghouls
    [49208] = { "DEATHKNIGHT", "UNHOLY", 5 }, -- Reaping
    -- SHAMAN
    -- ELEMENTAL
    [51490] = { "SHAMAN", "ELEMENTAL", 10 },  -- Thunderstorm
    [62097] = { "SHAMAN", "ELEMENTAL", 9 },   -- Shamanism
    [51474] = { "SHAMAN", "ELEMENTAL", 8 },   -- Astral Shift
    [51480] = { "SHAMAN", "ELEMENTAL", 8 },   -- Lava Flows
    [30706] = { "SHAMAN", "ELEMENTAL", 8 },   -- Totem of Wrath
    [63370] = { "SHAMAN", "ELEMENTAL", 7 },   -- Booming Echoes
    [51466] = { "SHAMAN", "ELEMENTAL", 7 },   -- Elemental Oath
    [30675] = { "SHAMAN", "ELEMENTAL", 7 },   -- Lightning Overload
    [16166] = { "SHAMAN", "ELEMENTAL", 6 },   -- Elemental Mastery
    [51483] = { "SHAMAN", "ELEMENTAL", 6 },   -- Storm, Earth and Fire
    [30672] = { "SHAMAN", "ELEMENTAL", 5 },   -- Elemental Precision
    [16578] = { "SHAMAN", "ELEMENTAL", 5 },   -- Lightning Mastery
    -- ENHANCEMENT
    [51533] = { "SHAMAN", "ENHANCEMENT", 10 },-- Feral Spirit
    [51528] = { "SHAMAN", "ENHANCEMENT", 9 }, -- Maelstrom Weapon
    [51523] = { "SHAMAN", "ENHANCEMENT", 8 }, -- Earthen Power
    [30812] = { "SHAMAN", "ENHANCEMENT", 8 }, -- Mental Quickness
    [30823] = { "SHAMAN", "ENHANCEMENT", 8 }, -- Shamanistic Rage
    [51521] = { "SHAMAN", "ENHANCEMENT", 7 }, -- Improved Stormstrike
    [60103] = { "SHAMAN", "ENHANCEMENT", 7 }, -- Lava Lash
    [51525] = { "SHAMAN", "ENHANCEMENT", 7 }, -- Static Shock
    [17364] = { "SHAMAN", "ENHANCEMENT", 6 }, -- Stormstrike
    [63373] = { "SHAMAN", "ENHANCEMENT", 5 }, -- Frozen Power
    [30802] = { "SHAMAN", "ENHANCEMENT", 5 }, -- Unleashed Rage
    -- RESTORATION
    [61295] = { "SHAMAN", "RESTORATION", 10 },-- Riptide
    [51562] = { "SHAMAN", "RESTORATION", 9 }, -- Tidal Waves
    [51556] = { "SHAMAN", "RESTORATION", 8 }, -- Ancestral Awakening
    [974] = { "SHAMAN", "RESTORATION", 8 },   -- Earth Shield
    [51560] = { "SHAMAN", "RESTORATION", 8 }, -- Improved Earth Shield
    [51554] = { "SHAMAN", "RESTORATION", 7 }, -- Blessing of the Eternals
    [30872] = { "SHAMAN", "RESTORATION", 7 }, -- Improved Chain Heal
    [30867] = { "SHAMAN", "RESTORATION", 7 }, -- Nature's Blessing
    [51886] = { "SHAMAN", "RESTORATION", 6 }, -- Cleanse Spirit
    [16190] = { "SHAMAN", "RESTORATION", 6 }, -- Mana Tide Totem
    [30881] = { "SHAMAN", "RESTORATION", 6 }, -- Nature's Guardian
    [16178] = { "SHAMAN", "RESTORATION", 5 }, -- Purification
    -- MAGE
    -- ARCANE
    [44425] = { "MAGE", "ARCANE", 10 },       -- Arcane Barrage
    [44400] = { "MAGE", "ARCANE", 9 },        -- Netherwind Presence
    [35578] = { "MAGE", "ARCANE", 9 },        -- Spell Power
    [44404] = { "MAGE", "ARCANE", 8 },        -- Missile Barrage
    [31589] = { "MAGE", "ARCANE", 8 },        -- Slow
    [44378] = { "MAGE", "ARCANE", 7 },        -- Arcane Flows
    [31584] = { "MAGE", "ARCANE", 7 },        -- Mind Mastery
    [31579] = { "MAGE", "ARCANE", 6 },        -- Arcane Empowerment
    [12042] = { "MAGE", "ARCANE", 6 },        -- Arcane Power
    [44394] = { "MAGE", "ARCANE", 6 },        -- Incanter's Absorption
    [15058] = { "MAGE", "ARCANE", 5 },        -- Arcane Instability
    [31571] = { "MAGE", "ARCANE", 5 },        -- Arcane Potency
    [31574] = { "MAGE", "ARCANE", 5 },        -- Prismatic Cloak
    -- FIRE
    [44457] = { "MAGE", "FIRE", 10 },         -- Living Bomb
    [44449] = { "MAGE", "FIRE", 9 },          -- Burnout
    [31661] = { "MAGE", "FIRE", 8 },          -- Dragon's Breath
    [44442] = { "MAGE", "FIRE", 8 },          -- Firestarter
    [44445] = { "MAGE", "FIRE", 8 },          -- Hot Streak
    [31656] = { "MAGE", "FIRE", 7 },          -- Empowered Fire
    [64353] = { "MAGE", "FIRE", 7 },          -- Fiery Payback
    [11129] = { "MAGE", "FIRE", 6 },          -- Combustion
    [31679] = { "MAGE", "FIRE", 6 },          -- Molten Fury
    [34293] = { "MAGE", "FIRE", 6 },          -- Pyromaniac
    [31641] = { "MAGE", "FIRE", 5 },          -- Blazing Speed
    [11124] = { "MAGE", "FIRE", 5 },          -- Fire Power
    -- FROST
    [44572] = { "MAGE", "FROST", 10 },        -- Deep Freeze
    [44566] = { "MAGE", "FROST", 9 },         -- Chilled to the Bone
    [44546] = { "MAGE", "FROST", 8 },         -- Brain Freeze
    [44557] = { "MAGE", "FROST", 8 },         -- Enduring Winter
    [31687] = { "MAGE", "FROST", 8 },         -- Summon Water Elemental
    [31682] = { "MAGE", "FROST", 7 },         -- Empowered Frostbolt
    [44543] = { "MAGE", "FROST", 7 },         -- Fingers of Frost
    [31674] = { "MAGE", "FROST", 6 },         -- Arctic Winds
    [11426] = { "MAGE", "FROST", 6 },         -- Ice Barrier
    [44745] = { "MAGE", "FROST", 6 },         -- Shattered Barrier
    [55091] = { "MAGE", "FROST", 5 },         -- Cold as Ice
    [11180] = { "MAGE", "FROST", 5 },         -- Winter's Chill
    -- WARLOCK
    -- AFFLICTION
    [48181] = { "WARLOCK", "AFFLICTION", 10 },-- Haunt
    [47201] = { "WARLOCK", "AFFLICTION", 9 }, -- Everlasting Affliction
    [47198] = { "WARLOCK", "AFFLICTION", 8 }, -- Death's Embrace
    [58435] = { "WARLOCK", "AFFLICTION", 8 }, -- Pandemic
    [30108] = { "WARLOCK", "AFFLICTION", 8 }, -- Unstable Affliction
    [30054] = { "WARLOCK", "AFFLICTION", 7 }, -- Improved Howl of Terror
    [32477] = { "WARLOCK", "AFFLICTION", 7 }, -- Malediction
    [30060] = { "WARLOCK", "AFFLICTION", 6 }, -- Contagion
    [18220] = { "WARLOCK", "AFFLICTION", 6 }, -- Dark Pact
    [47195] = { "WARLOCK", "AFFLICTION", 6 }, -- Eradication
    [54037] = { "WARLOCK", "AFFLICTION", 5 }, -- Improved Felhunter
    [18271] = { "WARLOCK", "AFFLICTION", 5 }, -- Shadow Mastery
    -- DEMONOLOGY
    [47241] = { "WARLOCK", "DEMONOLOGY", 10 },-- Metamorphosis
    [47236] = { "WARLOCK", "DEMONOLOGY", 9 }, -- Demonic Pact
    [54347] = { "WARLOCK", "DEMONOLOGY", 8 }, -- Improved Demonic Tactics
    [63117] = { "WARLOCK", "DEMONOLOGY", 8 }, -- Nemesis
    [30146] = { "WARLOCK", "DEMONOLOGY", 8 }, -- Summon Felguard
    [63156] = { "WARLOCK", "DEMONOLOGY", 7 }, -- Decimation
    [30242] = { "WARLOCK", "DEMONOLOGY", 7 }, -- Demonic Tactics
    [47193] = { "WARLOCK", "DEMONOLOGY", 6 }, -- Demonic Empowerment
    [35691] = { "WARLOCK", "DEMONOLOGY", 6 }, -- Demonic Knowledge
    [30319] = { "WARLOCK", "DEMONOLOGY", 6 }, -- Demonic Resilience
    [23785] = { "WARLOCK", "DEMONOLOGY", 5 }, -- Master Demonologist
    [47245] = { "WARLOCK", "DEMONOLOGY", 5 }, -- Molten Core
    -- DESTRUCTION
    [50796] = { "WARLOCK", "DESTRUCTION", 10 },-- Chaos Bolt
    [47266] = { "WARLOCK", "DESTRUCTION", 9 },-- Fire and Brimstone
    [47258] = { "WARLOCK", "DESTRUCTION", 8 },-- Backdraft
    [47220] = { "WARLOCK", "DESTRUCTION", 8 },-- Empowered Imp
    [30283] = { "WARLOCK", "DESTRUCTION", 8 },-- Shadowfury
    [54117] = { "WARLOCK", "DESTRUCTION", 7 },-- Improved Soul Leech
    [30288] = { "WARLOCK", "DESTRUCTION", 7 },-- Shadow and Flame
    [17962] = { "WARLOCK", "DESTRUCTION", 6 },-- Conflagrate
    [18096] = { "WARLOCK", "DESTRUCTION", 6 },-- Pyroclasm
    [30293] = { "WARLOCK", "DESTRUCTION", 6 },-- Soul Leech
    [17954] = { "WARLOCK", "DESTRUCTION", 5 },-- Emberstorm
    [30299] = { "WARLOCK", "DESTRUCTION", 5 },-- Nether Protection
    -- DRUID
    -- BALANCE
    [48505] = { "DRUID", "BALANCE", 10 },     -- Starfall
    [48506] = { "DRUID", "BALANCE", 9 },      -- Earth and Moon
    [48516] = { "DRUID", "BALANCE", 8 },      -- Eclipse
    [33831] = { "DRUID", "BALANCE", 8 },      -- Force of Nature
    [48488] = { "DRUID", "BALANCE", 8 },      -- Gale Winds
    [50516] = { "DRUID", "BALANCE", 8 },      -- Typhoon
    [48389] = { "DRUID", "BALANCE", 7 },      -- Owlkin Frenzy
    [33603] = { "DRUID", "BALANCE", 7 },      -- Wrath of Cenarius
    [33600] = { "DRUID", "BALANCE", 6 },      -- Improved Faerie Fire
    [48384] = { "DRUID", "BALANCE", 6 },      -- Improved Moonkin Form
    [24858] = { "DRUID", "BALANCE", 6 },      -- Moonkin Form
    [33592] = { "DRUID", "BALANCE", 5 },      -- Balance of Power
    [33597] = { "DRUID", "BALANCE", 5 },      -- Dreamstate
    [16896] = { "DRUID", "BALANCE", 5 },      -- Moonfury
    -- FERAL
    [63503] = { "DRUID", "FERAL", 9 },        -- Primal Gore
    [48432] = { "DRUID", "FERAL", 9 },        -- Rend and Tear
    [48532] = { "DRUID", "FERAL", 8 },        -- Improved Mangle
    [48492] = { "DRUID", "FERAL", 8 },        -- King of the Jungle
    [33878] = { "DRUID", "FERAL", 8, "BEAR" },-- Mangle (Bear)
    [33876] = { "DRUID", "FERAL", 8, "CAT" }, -- Mangle (Cat)
    [48483] = { "DRUID", "FERAL", 7 },        -- Infected Wounds
    [33859] = { "DRUID", "FERAL", 7 },        -- Predatory Instincts
    [57873] = { "DRUID", "FERAL", 7 },        -- Protector of the Pack
    [34297] = { "DRUID", "FERAL", 6 },        -- Improved Leader of the Pack
    [17007] = { "DRUID", "FERAL", 6 },        -- Leader of the Pack
    [33851] = { "DRUID", "FERAL", 6 },        -- Primal Tenacity
    [17003] = { "DRUID", "FERAL", 5 },        -- Heart of the Wild
    [57878] = { "DRUID", "FERAL", 5 },        -- Natural Reaction
    [33853] = { "DRUID", "FERAL", 5 },        -- Survival of the Fittest
    -- RESTORATION
    [48438] = { "DRUID", "RESTORATION", 10 }, -- Wild Growth
    [51179] = { "DRUID", "RESTORATION", 9 },  -- Gift of the Earthmother
    [63410] = { "DRUID", "RESTORATION", 9 },  -- Improved Barkskin
    [48535] = { "DRUID", "RESTORATION", 8 },  -- Improved Tree of Life
    [48539] = { "DRUID", "RESTORATION", 8 },  -- Revitalize
    [33891] = { "DRUID", "RESTORATION", 8 },  -- Tree of Life
    [33886] = { "DRUID", "RESTORATION", 7 },  -- Empowered Rejuvenation
    [48496] = { "DRUID", "RESTORATION", 7 },  -- Living Seed
    [34151] = { "DRUID", "RESTORATION", 6 },  -- Living Spirit
    [33881] = { "DRUID", "RESTORATION", 6 },  -- Natural Perfection
    [18562] = { "DRUID", "RESTORATION", 6 },  -- Swiftmend
    [33879] = { "DRUID", "RESTORATION", 5 },  -- Empowered Touch
    [17074] = { "DRUID", "RESTORATION", 5 },  -- Nature's Bounty
}

addon.GetSpecIcon = function(classFile, specName, fallback)
    local treeIcons = addon.SPEC_TREE_ICONS[classFile]
    if treeIcons and treeIcons[specName] then return treeIcons[specName] end
    return fallback
end


addon.FORMAT_TEXTURE = function(texture, customSize)
    local size = customSize or 20
    return format("|T%s:" .. size .. "|t", texture)
end

addon.ICON_PATH = function(iconName)
    return "Interface\\Icons\\" .. iconName
end

addon.PRINT = function(message)
    DEFAULT_CHAT_FRAME:AddMessage("|TInterface\\AddOns\\OPlates\\Art\\Logo:16|t |cff00c0ffOPlates:|r " .. message)
end

addon.IsAddOnLoadedSafe = function(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return IsAddOnLoaded(name)
end

addon.GetSpellTexture = function(spellId)
    if not spellId then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then return tex end
    end
    local _, _, icon = GetSpellInfo(spellId)
    return icon
end

addon.IsInPvPInstance = function()
    if IsActiveBattlefieldArena and IsActiveBattlefieldArena() then return true end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "pvp" or instanceType == "arena")
end

-- Combat-log flag test without the `bit` library.
--
-- 3.3.5a ships `bit`, but servers and addon packs do replace or omit it, and
-- three call sites used it unguarded - a nil `bit` there was an error inside the
-- combat-log handler, which silently costs every CC and every enemy spec. Doing
-- the arithmetic directly removes the dependency: exact for the single-bit masks
-- the combat log uses, and no library to be missing.
addon.HasFlag = function(value, mask)
    if type(value) ~= "number" or type(mask) ~= "number" or value <= 0 or mask <= 0 then return false end
    return math.floor(value / mask) % 2 == 1
end

addon.GetClassColor = function(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

addon.SetClassIconTexture = function(texture, classFile)
    if not texture or not classFile then return false end
    texture:SetTexture(addon.CLASS_ICON_ATLAS)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if coords then
        texture:SetTexCoord(unpack(coords))
        return true
    end
    texture:SetTexCoord(0, 1, 0, 1)
    return false
end

-- a healer / tank icon (the art is square, so it goes through the same
-- round renderer as spec icons; it also resets the texcoords).
addon.SetRoleTexture = function(texture, role)
    if not texture then return false end
    local path = addon.ROLE_ICONS[role]
    if not path then return false end
    addon.SetCircularTexture(texture, path)
    return true
end

-- WotLK's old portrait API is the renderer used by the working C+C foundation.
addon.SetCircularTexture = function(texture, path)
    if not texture then return end
    texture:SetTexCoord(0, 1, 0, 1)
    if path and SetPortraitToTexture then
        SetPortraitToTexture(texture, path)
    elseif path then
        texture:SetTexture(path)
    else
        texture:SetTexture(nil)
    end
end
