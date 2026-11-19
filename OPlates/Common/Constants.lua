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

-- The role a spec implies, or nil. Every render path uses this, so a spec read
-- from the combat log (a player nobody inspected) still gets the healer or tank
-- icon its spec deserves. The assigned group role and an inspection stay
-- stronger: callers OR this with what they already know.
function addon.RoleForSpec(classFile, spec)
    local roles = classFile and addon.SPEC_ROLES[classFile]
    return roles and spec and roles[spec] or nil
end

-- "Unknown player (?)" is the fallback for a player we know nothing about. It
-- only makes sense while at least one identity icon is allowed on that side:
-- with class, spec, healer AND tank all off, a question mark is the only thing
-- the plate could ever show, and it could never turn into anything - pure
-- noise. The rule is per side and deliberately ignores the flag-carrier, pet
-- and CC/aura icons: those are separate layers with their own switches.
function addon.UnknownIconLocked(cfg, enemy)
    if not cfg then return false end
    if enemy then
        return cfg.enemyShowClass == false and cfg.enemyShowSpec == false
            and cfg.enemyHealerIcon == false and cfg.enemyTankIcon == false
    end
    return cfg.showClassIcon == false and cfg.showSpec == false
        and cfg.useHealerIcon == false and cfg.useTankIcon == false
end

-- Keep the stored value honest. Entering the locked state unchecks it, and it
-- stays unchecked when an identity icon comes back - the user has to turn it
-- on again himself. Called at login/profile change and after every option
-- write, so the checkbox and the render can never disagree.
function addon.SanitizeUnknownIcons(cfg)
    if not cfg then return end
    if addon.UnknownIconLocked(cfg, true) then cfg.enemyShowUnknown = false end
    if addon.UnknownIconLocked(cfg, false) then cfg.showUnknownFriendly = false end
end

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
        -- Deliberately NOT Ability_Racial_BearForm: that is the Bear Form icon,
        -- and a Feral spec icon must never look like a bear tank. A proven bear
        -- shows the TANK icon (or the Bear Form icon when tank icons are off,
        -- set by ApplyFeralIdentity); an unproven Feral shows the cat form, the
        -- neutral half of the Feral tree.
        FERAL = "Interface\\Icons\\Ability_Druid_CatForm",
        RESTORATION = "Interface\\Icons\\Spell_Nature_HealingTouch",
    },
}

-- enemy spec signatures: spellID = { class, spec, strength[, feralKind] }.
-- Matched by spell NAME (every rank, any client language) from the combat log
-- of hostile players only. Strength 2 = 51-point talent: the owner has more
-- points in that tree than in both others together, so it is always right.
-- Strength 1 = deep (31+ point) talent: right for practically every real
-- build; it never overrides a strength-2 result. Shallow talents are excluded.
-- An AURA event never identifies anybody (see SIGNATURE_EVENTS in Overlay.lua):
-- the client logs an aura with the unit that OWNS the effect as its source, and
-- for a party-wide buff that owner is the RECIPIENT, not the caster. So no
-- entry here needs a "this one is a party aura" flag - the whole event class is
-- ignored for identity and only a cast, a hit or a summon counts.
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
-- The third value is the talent's DEPTH: required points / 5, which is the
-- talent row minus one (row 11 = 50 points = 10, row 9 = 40 points = 8, row 6
-- = 25 points = 5). It doubles as confidence: a deeper talent outranks a
-- shallower one when two signals disagree (see NoteEnemySpec).
--
-- 8 is the number that matters. A row-9 talent needs 40 points, and a build
-- with 41+ points in another tree cannot also have 40 here (40 + 41 > 71), so
-- strength 8+ can only belong to the spec it names: it is proof on its own and
-- always wins, even over a build we read earlier (see DeeperSpec).
--
-- Anything below 8 is a talent a hybrid build can pick up off-tree. It fills an
-- UNKNOWN spec, and it may replace a known one only when it is DEEPER than
-- anything that spec has shown - because a talent's row is a lower bound on the
-- points spent in its tree, so the deepest talent names the main tree. That is
-- what keeps the real hybrids right (Preg 0/28/43 reads Retribution, never
-- Protection) while a 25-point dip never flips a 46-point build.
-- Verified against this client's own talent trees (Talented/Data.lua and
-- Talent.dbc): every row-9+ talent of all 30 specs is listed here.
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
    [19506] = { "HUNTER", "MARKSMANSHIP", 6 },            -- Trueshot Aura
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
    [30706] = { "SHAMAN", "ELEMENTAL", 8 },               -- Totem of Wrath
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
    [16190] = { "SHAMAN", "RESTORATION", 6 },             -- Mana Tide Totem
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
    -- Not a talent row of its own: Moonkin Form grants this aura, and only a
    -- druid in Moonkin Form can wear it. A capture showed a moonkin buffing a
    -- party member and staying a class-only druid because the aura was missing
    -- here, then being guessed FERAL on a Cat Form shift until he shifted back.
    [24907] = { "DRUID", "BALANCE", 6 },      -- Moonkin Aura
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
    [34297] = { "DRUID", "FERAL", 6 },                    -- Improved Leader of the Pack
    [17007] = { "DRUID", "FERAL", 6 },                    -- Leader of the Pack
    [33851] = { "DRUID", "FERAL", 6 },        -- Primal Tenacity
    [17003] = { "DRUID", "FERAL", 5 },        -- Heart of the Wild
    [57878] = { "DRUID", "FERAL", 5 },        -- Natural Reaction
    [33853] = { "DRUID", "FERAL", 5 },        -- Survival of the Fittest
    [16979] = { "DRUID", "FERAL", 4 },        -- Feral Charge (Bear)
    [49377] = { "DRUID", "FERAL", 4 },        -- Feral Charge (Cat)
    [61336] = { "DRUID", "FERAL", 2 },        -- Survival Instincts
    -- RESTORATION
    [48438] = { "DRUID", "RESTORATION", 10 },             -- Wild Growth
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
-- A few talents share their localized NAME with another class's spell on this
-- server, so matching them by name flipped the wrong class (Berserk was reported
-- as a paladin/warrior cast name). These are matched by exact spell ID instead:
-- the ID stays unique even when the name does not. Looked up after the name map,
-- so a name match still wins.
addon.SPEC_SIGNATURES_BY_ID = {
    [50334] = { "DRUID", "FERAL", 10 },   -- Berserk (51-point Feral)
}

-- Weak signals (v1.15).
--
-- Spells every spec of a class can train, which lean towards one spec without
-- proving it: any mage can cast Frostbolt, so Frostbolt does not prove Frost.
-- They are used ONLY when no real signature is known, and they never replace
-- one - see NoteWeakSpec in Nameplates/Overlay.lua. Off by default.
--
-- Generated from this client's SkillLineAbility.dbc (trainable, not talent
-- granted) and cross-checked against SPEC_SIGNATURES above: no entry here is
-- a strong signature, and every entry is trainable by the whole class.
-- An optional third field names a FORM ("BEAR"/"CAT") for the spells that can
-- only be used in one druid form; it never changes the class or the spec, only
-- which half of Feral the icon shows.
--
-- One deliberate exception to "every spec can train it": Mind Flay. It is a
-- 10-point Shadow talent, so a Discipline or Holy priest with 10 Shadow points
-- can cast it. It is kept here, not in SPEC_SIGNATURES, so it stays a soft
-- guess that cannot lock a healer into Shadow; a real Shadow talent overrides
-- it and an inspection ignores it.
addon.WEAK_SIGNATURES = {
    -- MAGE
    [116] = { "MAGE", "FROST" },  -- Frostbolt
    [205] = { "MAGE", "FROST" },  -- Frostbolt
    [837] = { "MAGE", "FROST" },  -- Frostbolt
    [7322] = { "MAGE", "FROST" },  -- Frostbolt
    [8406] = { "MAGE", "FROST" },  -- Frostbolt
    [8407] = { "MAGE", "FROST" },  -- Frostbolt
    [8408] = { "MAGE", "FROST" },  -- Frostbolt
    [10179] = { "MAGE", "FROST" },  -- Frostbolt
    [10180] = { "MAGE", "FROST" },  -- Frostbolt
    [10181] = { "MAGE", "FROST" },  -- Frostbolt
    [25304] = { "MAGE", "FROST" },  -- Frostbolt
    [27071] = { "MAGE", "FROST" },  -- Frostbolt
    [27072] = { "MAGE", "FROST" },  -- Frostbolt
    [38697] = { "MAGE", "FROST" },  -- Frostbolt
    [42841] = { "MAGE", "FROST" },  -- Frostbolt
    [42842] = { "MAGE", "FROST" },  -- Frostbolt
    [30455] = { "MAGE", "FROST" },  -- Ice Lance
    [42913] = { "MAGE", "FROST" },  -- Ice Lance
    [42914] = { "MAGE", "FROST" },  -- Ice Lance
    [120] = { "MAGE", "FROST" },  -- Cone of Cold
    [8492] = { "MAGE", "FROST" },  -- Cone of Cold
    [10159] = { "MAGE", "FROST" },  -- Cone of Cold
    [10160] = { "MAGE", "FROST" },  -- Cone of Cold
    [10161] = { "MAGE", "FROST" },  -- Cone of Cold
    [27087] = { "MAGE", "FROST" },  -- Cone of Cold
    [42930] = { "MAGE", "FROST" },  -- Cone of Cold
    [42931] = { "MAGE", "FROST" },  -- Cone of Cold
    -- MAGE
    [133] = { "MAGE", "FIRE" },  -- Fireball
    [143] = { "MAGE", "FIRE" },  -- Fireball
    [145] = { "MAGE", "FIRE" },  -- Fireball
    [3140] = { "MAGE", "FIRE" },  -- Fireball
    [8400] = { "MAGE", "FIRE" },  -- Fireball
    [8401] = { "MAGE", "FIRE" },  -- Fireball
    [8402] = { "MAGE", "FIRE" },  -- Fireball
    [10148] = { "MAGE", "FIRE" },  -- Fireball
    [10149] = { "MAGE", "FIRE" },  -- Fireball
    [10150] = { "MAGE", "FIRE" },  -- Fireball
    [10151] = { "MAGE", "FIRE" },  -- Fireball
    [25306] = { "MAGE", "FIRE" },  -- Fireball
    [27070] = { "MAGE", "FIRE" },  -- Fireball
    [38692] = { "MAGE", "FIRE" },  -- Fireball
    [42832] = { "MAGE", "FIRE" },  -- Fireball
    [42833] = { "MAGE", "FIRE" },  -- Fireball
    [2136] = { "MAGE", "FIRE" },  -- Fire Blast
    [2137] = { "MAGE", "FIRE" },  -- Fire Blast
    [2138] = { "MAGE", "FIRE" },  -- Fire Blast
    [8412] = { "MAGE", "FIRE" },  -- Fire Blast
    [8413] = { "MAGE", "FIRE" },  -- Fire Blast
    [10197] = { "MAGE", "FIRE" },  -- Fire Blast
    [10199] = { "MAGE", "FIRE" },  -- Fire Blast
    [27078] = { "MAGE", "FIRE" },  -- Fire Blast
    [27079] = { "MAGE", "FIRE" },  -- Fire Blast
    [42872] = { "MAGE", "FIRE" },  -- Fire Blast
    [42873] = { "MAGE", "FIRE" },  -- Fire Blast
    [2948] = { "MAGE", "FIRE" },  -- Scorch
    [8444] = { "MAGE", "FIRE" },  -- Scorch
    [8445] = { "MAGE", "FIRE" },  -- Scorch
    [8446] = { "MAGE", "FIRE" },  -- Scorch
    [10205] = { "MAGE", "FIRE" },  -- Scorch
    [10206] = { "MAGE", "FIRE" },  -- Scorch
    [10207] = { "MAGE", "FIRE" },  -- Scorch
    [27073] = { "MAGE", "FIRE" },  -- Scorch
    [27074] = { "MAGE", "FIRE" },  -- Scorch
    [42858] = { "MAGE", "FIRE" },  -- Scorch
    [42859] = { "MAGE", "FIRE" },  -- Scorch
    -- MAGE
    [30451] = { "MAGE", "ARCANE" },  -- Arcane Blast
    [42894] = { "MAGE", "ARCANE" },  -- Arcane Blast
    [42896] = { "MAGE", "ARCANE" },  -- Arcane Blast
    [42897] = { "MAGE", "ARCANE" },  -- Arcane Blast
    [5143] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [5144] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [5145] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [8416] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [8417] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [10211] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [10212] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [25345] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [27075] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [38699] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [38704] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [42843] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    [42846] = { "MAGE", "ARCANE" },  -- Arcane Missiles
    -- WARLOCK
    [686] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [695] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [705] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [1088] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [1106] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [7641] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [11659] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [11660] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [11661] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [25307] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [27209] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [47808] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [47809] = { "WARLOCK", "AFFLICTION" },  -- Shadow Bolt
    [172] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [6222] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [6223] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [7648] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [11671] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [11672] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [25311] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [27216] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [47812] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [47813] = { "WARLOCK", "AFFLICTION" },  -- Corruption
    [689] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [699] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [709] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [7651] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [11699] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [11700] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [27219] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [27220] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    [47857] = { "WARLOCK", "AFFLICTION" },  -- Drain Life
    -- WARLOCK
    [348] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [707] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [1094] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [2941] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [11665] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [11667] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [11668] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [25309] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [27215] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [47810] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [47811] = { "WARLOCK", "DESTRUCTION" },  -- Immolate
    [5676] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [17919] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [17920] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [17921] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [17922] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [17923] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [27210] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [30459] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [47814] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [47815] = { "WARLOCK", "DESTRUCTION" },  -- Searing Pain
    [6353] = { "WARLOCK", "DESTRUCTION" },  -- Soul Fire
    [17924] = { "WARLOCK", "DESTRUCTION" },  -- Soul Fire
    [27211] = { "WARLOCK", "DESTRUCTION" },  -- Soul Fire
    [30545] = { "WARLOCK", "DESTRUCTION" },  -- Soul Fire
    [47824] = { "WARLOCK", "DESTRUCTION" },  -- Soul Fire
    [47825] = { "WARLOCK", "DESTRUCTION" },  -- Soul Fire
    -- PRIEST
    [8092] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [8102] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [8103] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [8104] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [8105] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [8106] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [10945] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [10946] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [10947] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [25372] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [25375] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [48126] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [48127] = { "PRIEST", "SHADOW" },  -- Mind Blast
    [15407] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [17311] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [17312] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [17313] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [17314] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [18807] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [25387] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [48155] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [48156] = { "PRIEST", "SHADOW" },  -- Mind Flay
    [589] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [594] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [970] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [992] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [2767] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [10892] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [10893] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [10894] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [25367] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [25368] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [48124] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    [48125] = { "PRIEST", "SHADOW" },  -- Shadow Word: Pain
    -- PRIEST
    [14914] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15261] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15262] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15263] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15264] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15265] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15266] = { "PRIEST", "HOLY" },  -- Holy Fire
    [15267] = { "PRIEST", "HOLY" },  -- Holy Fire
    [25384] = { "PRIEST", "HOLY" },  -- Holy Fire
    [48134] = { "PRIEST", "HOLY" },  -- Holy Fire
    [48135] = { "PRIEST", "HOLY" },  -- Holy Fire
    -- DRUID
    [5176] = { "DRUID", "BALANCE" },  -- Wrath
    [5177] = { "DRUID", "BALANCE" },  -- Wrath
    [5178] = { "DRUID", "BALANCE" },  -- Wrath
    [5179] = { "DRUID", "BALANCE" },  -- Wrath
    [5180] = { "DRUID", "BALANCE" },  -- Wrath
    [6780] = { "DRUID", "BALANCE" },  -- Wrath
    [8905] = { "DRUID", "BALANCE" },  -- Wrath
    [9912] = { "DRUID", "BALANCE" },  -- Wrath
    [26984] = { "DRUID", "BALANCE" },  -- Wrath
    [26985] = { "DRUID", "BALANCE" },  -- Wrath
    [48459] = { "DRUID", "BALANCE" },  -- Wrath
    [48461] = { "DRUID", "BALANCE" },  -- Wrath
    [2912] = { "DRUID", "BALANCE" },  -- Starfire
    [8949] = { "DRUID", "BALANCE" },  -- Starfire
    [8950] = { "DRUID", "BALANCE" },  -- Starfire
    [8951] = { "DRUID", "BALANCE" },  -- Starfire
    [9875] = { "DRUID", "BALANCE" },  -- Starfire
    [9876] = { "DRUID", "BALANCE" },  -- Starfire
    [25298] = { "DRUID", "BALANCE" },  -- Starfire
    [26986] = { "DRUID", "BALANCE" },  -- Starfire
    [48464] = { "DRUID", "BALANCE" },  -- Starfire
    [48465] = { "DRUID", "BALANCE" },  -- Starfire
    [8921] = { "DRUID", "BALANCE" },  -- Moonfire
    [8924] = { "DRUID", "BALANCE" },  -- Moonfire
    [8925] = { "DRUID", "BALANCE" },  -- Moonfire
    [8926] = { "DRUID", "BALANCE" },  -- Moonfire
    [8927] = { "DRUID", "BALANCE" },  -- Moonfire
    [8928] = { "DRUID", "BALANCE" },  -- Moonfire
    [8929] = { "DRUID", "BALANCE" },  -- Moonfire
    [9833] = { "DRUID", "BALANCE" },  -- Moonfire
    [9834] = { "DRUID", "BALANCE" },  -- Moonfire
    [9835] = { "DRUID", "BALANCE" },  -- Moonfire
    [26987] = { "DRUID", "BALANCE" },  -- Moonfire
    [26988] = { "DRUID", "BALANCE" },  -- Moonfire
    [48462] = { "DRUID", "BALANCE" },  -- Moonfire
    [48463] = { "DRUID", "BALANCE" },  -- Moonfire
    -- DRUID
    [5185] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [5186] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [5187] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [5188] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [5189] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [6778] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [8903] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [9758] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [9888] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [9889] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [25297] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [26978] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [26979] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [48377] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [48378] = { "DRUID", "RESTORATION" },  -- Healing Touch
    [8936] = { "DRUID", "RESTORATION" },  -- Regrowth
    [8938] = { "DRUID", "RESTORATION" },  -- Regrowth
    [8939] = { "DRUID", "RESTORATION" },  -- Regrowth
    [8940] = { "DRUID", "RESTORATION" },  -- Regrowth
    [8941] = { "DRUID", "RESTORATION" },  -- Regrowth
    [9750] = { "DRUID", "RESTORATION" },  -- Regrowth
    [9856] = { "DRUID", "RESTORATION" },  -- Regrowth
    [9857] = { "DRUID", "RESTORATION" },  -- Regrowth
    [9858] = { "DRUID", "RESTORATION" },  -- Regrowth
    [26980] = { "DRUID", "RESTORATION" },  -- Regrowth
    [48442] = { "DRUID", "RESTORATION" },  -- Regrowth
    [48443] = { "DRUID", "RESTORATION" },  -- Regrowth
    -- DRUID: the form decides the Feral half. A form or a form-locked ability
    -- is a weak signal (any druid can train it) but it names the FORM exactly,
    -- which is what turns "Feral" into the tank icon or the cat icon.
    [768] = { "DRUID", "FERAL", "CAT" },    -- Cat Form
    [5487] = { "DRUID", "FERAL", "BEAR" },  -- Bear Form
    [9634] = { "DRUID", "FERAL", "BEAR" },  -- Dire Bear Form
    [6807] = { "DRUID", "FERAL", "BEAR" },  -- Maul
    [779] = { "DRUID", "FERAL", "BEAR" },   -- Swipe (Bear)
    [33745] = { "DRUID", "FERAL", "BEAR" }, -- Lacerate
    [99] = { "DRUID", "FERAL", "BEAR" },    -- Demoralizing Roar
    [5209] = { "DRUID", "FERAL", "BEAR" },  -- Challenging Roar
    [22842] = { "DRUID", "FERAL", "BEAR" }, -- Frenzied Regeneration
    [5221] = { "DRUID", "FERAL", "CAT" },   -- Shred
    [1822] = { "DRUID", "FERAL", "CAT" },   -- Rake
    [1079] = { "DRUID", "FERAL", "CAT" },   -- Rip
    [1082] = { "DRUID", "FERAL", "CAT" },   -- Claw
    [9005] = { "DRUID", "FERAL", "CAT" },   -- Pounce
    [5217] = { "DRUID", "FERAL", "CAT" },   -- Tiger's Fury
    -- SHAMAN
    [403] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [529] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [548] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [915] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [943] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [6041] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [10391] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [10392] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [15207] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [15208] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [25448] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [25449] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [49237] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [49238] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [49239] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [49240] = { "SHAMAN", "ELEMENTAL" },  -- Lightning Bolt
    [421] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [930] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [2860] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [10605] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [25439] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [25442] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [49268] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [49269] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [49270] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [49271] = { "SHAMAN", "ELEMENTAL" },  -- Chain Lightning
    [8050] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [8052] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [8053] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [10447] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [10448] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [25457] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [29228] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [49232] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    [49233] = { "SHAMAN", "ELEMENTAL" },  -- Flame Shock
    -- SHAMAN
    [331] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [332] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [547] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [913] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [939] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [959] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [8005] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [10395] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [10396] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [25357] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [25391] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [25396] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [49272] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [49273] = { "SHAMAN", "RESTORATION" },  -- Healing Wave
    [8004] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [8008] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [8010] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [10466] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [10467] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [10468] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [25420] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [49275] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    [49276] = { "SHAMAN", "RESTORATION" },  -- Lesser Healing Wave
    -- ROGUE
    [1752] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [1757] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [1758] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [1759] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [1760] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [8621] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [11293] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [11294] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [26861] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [26862] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [48637] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    [48638] = { "ROGUE", "COMBAT" },  -- Sinister Strike
    -- ROGUE
    [53] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [2589] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [2590] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [2591] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [8721] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [11279] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [11280] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [11281] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [25300] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [26863] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [48656] = { "ROGUE", "SUBTLETY" },  -- Backstab
    [48657] = { "ROGUE", "SUBTLETY" },  -- Backstab
    -- HUNTER
    [3044] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14281] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14282] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14283] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14284] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14285] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14286] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [14287] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [27019] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [49044] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [49045] = { "HUNTER", "MARKSMANSHIP" },  -- Arcane Shot
    [2643] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [14288] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [14289] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [14290] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [25294] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [27021] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [49047] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    [49048] = { "HUNTER", "MARKSMANSHIP" },  -- Multi-Shot
    -- WARRIOR
    [2565] = { "WARRIOR", "PROTECTION" },  -- Shield Block
}
-- Class spells (v1.15).
--
-- Every spell exactly one class can train, so casting it proves the
-- class with no guessing and no inspection. Compact on purpose: the id
-- lists are parsed once, on first use, into addon.SPELL_CLASS.
--
-- Generated from this client's SkillLineAbility.dbc, excluding talent-
-- granted spells (those prove a spec and already live in
-- SPEC_SIGNATURES) and any spell more than one class can train.
addon.CLASS_SPELL_IDS = {
    DEATHKNIGHT = "42650,42651,43265,45462,45463,45477,45524,45529,45902,46584,47476,47528,47541,47568,47632,47633,48263,48265,48266,48707,48721,48743,48778,48792,49020,49194,49575,49576,49796,49892,49893,49894,49895,49896,49903,49904,49909,49917,49918,49919,49920,49921,49923,49924,49936,49937,49938,49939,49940,49941,49998,49999,50447,50448,50449,50842,51052,53323,53331,53341,53342,53343,53344,53428,54446,54447,59921,61455,62158,70164",
    DRUID = "99,339,467,740,768,769,770,774,779,780,782,783,1058,1062,1066,1075,1079,1082,1126,1178,1430,1735,1822,1823,1824,1850,2090,2091,2637,2782,2893,2908,2912,3025,3029,3137,3627,5176,5177,5178,5179,5180,5185,5186,5187,5188,5189,5195,5196,5201,5209,5211,5215,5217,5221,5225,5229,5232,5234,5421,5487,5570,6756,6778,6780,6785,6787,6793,6795,6798,6800,6807,6808,6809,8903,8905,8907,8910,8914,8918,8921,8924,8925,8926,8927,8928,8929,8936,8938,8939,8940,8941,8946,8949,8950,8951,8955,8972,8983,8992,8998,9000,9005,9007,9490,9492,9493,9634,9635,9745,9747,9750,9752,9754,9756,9758,9821,9823,9824,9826,9827,9829,9830,9833,9834,9835,9839,9840,9841,9845,9846,9849,9850,9852,9853,9856,9857,9858,9862,9863,9866,9867,9875,9876,9880,9881,9884,9885,9888,9889,9892,9894,9896,9898,9901,9904,9908,9910,9912,16689,16810,16811,16812,16813,16833,16834,16835,16857,16864,16914,16958,16961,17007,17104,17329,17401,17402,18657,18658,18960,20484,20719,20739,20742,20747,20748,21178,21849,21850,22568,22570,22812,22827,22828,22829,22842,22845,24248,24858,24905,24907,24943,24944,24945,24946,24968,24969,24970,24971,24972,24974,24975,24976,24977,25297,25298,25299,26978,26979,26980,26981,26982,26983,26984,26985,26986,26987,26988,26989,26990,26991,26992,26994,26995,26996,26997,26998,27000,27001,27002,27003,27004,27005,27006,27007,27008,27009,27012,27013,29166,31018,31709,33357,33589,33590,33591,33592,33596,33597,33599,33600,33601,33602,33603,33604,33605,33606,33607,33745,33763,33786,33831,33851,33852,33853,33855,33856,33859,33866,33867,33872,33873,33876,33878,33879,33880,33881,33882,33883,33886,33887,33888,33889,33890,33891,33917,33943,33956,33957,33982,33983,33986,33987,34151,34152,34153,34297,34299,34300,35363,35364,37116,37117,40120,42230,42231,42232,42233,48377,48378,48438,48440,48441,48442,48443,48446,48447,48450,48451,48459,48461,48462,48463,48464,48465,48466,48468,48469,48470,48477,48479,48480,48559,48560,48561,48562,48563,48564,48565,48566,48567,48568,48569,48570,48571,48572,48573,48575,48576,48577,48578,48579,49799,49800,49802,49803,49804,50334,50464,50516,52610,53223,53225,53226,53227,53248,53249,53251,53307,53308,53312,61336,61384,61387,61388,61390,61391,62078,62600,63503,65139,66530",
    HUNTER = "75,136,781,883,982,1002,1130,1462,1494,1495,1499,1510,1513,1515,1543,1978,2641,2643,2973,2974,3034,3043,3044,3045,3111,3661,3662,3674,5116,5118,5384,6197,6991,13159,13161,13163,13165,13481,13542,13543,13544,13549,13550,13551,13552,13553,13554,13555,13795,13797,13809,13812,13813,14260,14261,14262,14263,14264,14265,14266,14269,14270,14271,14281,14282,14283,14284,14285,14286,14287,14288,14289,14290,14294,14295,14298,14299,14300,14301,14302,14303,14304,14305,14310,14311,14314,14315,14316,14317,14318,14319,14320,14321,14322,14323,14324,14325,14326,14327,19168,19180,19181,19258,19259,19290,19294,19306,19376,19386,19498,19499,19500,19503,19549,19550,19551,19575,19578,19801,19878,19879,19880,19882,19883,19884,19885,20043,20190,20736,20895,20909,20910,24131,24132,24133,24134,24135,24283,24296,24297,24443,25294,25295,25296,27014,27016,27019,27021,27022,27023,27024,27025,27026,27044,27045,27046,27065,27067,27068,27069,34026,34074,34453,34454,34455,34459,34460,34462,34464,34465,34466,34467,34468,34469,34470,34471,34475,34476,34477,34482,34483,34484,34485,34486,34487,34488,34489,34490,34491,34492,34493,34494,34496,34497,34498,34499,34500,34501,34502,34503,34506,34507,34508,34600,34692,34833,34834,34835,34836,34837,34838,34839,34948,34949,34950,34954,35029,35030,35098,35099,35100,35101,35102,35104,35110,35111,36916,42234,42243,42244,42245,48989,48990,48995,48996,48998,48999,49000,49001,49009,49010,49011,49012,49044,49045,49047,49048,49049,49050,49051,49052,49053,49054,49055,49056,49064,49065,49066,49067,49071,53338,53339,56641,60192,61005,61006,61846,61847,62757,63668,63669,63670,63671,63672",
    MAGE = "10,116,118,120,122,130,133,143,145,168,205,475,543,587,597,604,759,837,865,990,1008,1449,1459,1460,1461,1463,1953,2120,2121,2136,2137,2138,2139,2948,3140,3552,3561,3562,3563,3565,3566,3567,5143,5144,5145,5504,5505,5506,6117,6127,6129,6131,6141,6143,7300,7301,7302,7320,7322,8400,8401,8402,8406,8407,8408,8412,8413,8416,8417,8422,8423,8427,8437,8438,8439,8444,8445,8446,8450,8451,8455,8457,8458,8461,8462,8492,8494,8495,10053,10054,10059,10138,10139,10140,10144,10145,10148,10149,10150,10151,10156,10157,10159,10160,10161,10169,10170,10173,10174,10177,10179,10180,10181,10185,10186,10187,10191,10192,10193,10197,10199,10201,10202,10205,10206,10207,10211,10212,10215,10216,10219,10220,10223,10225,10230,11069,11070,11071,11078,11080,11083,11095,11100,11103,11108,11113,11115,11124,11129,11151,11160,11170,11175,11180,11185,11189,11190,11207,11210,11366,11367,11368,11416,11417,11418,11419,11420,11426,11958,12338,12339,12340,12341,12349,12350,12351,12353,12355,12357,12358,12378,12398,12399,12400,12472,12473,12484,12485,12486,12487,12488,12489,12490,12494,12496,12497,12505,12518,12519,12522,12523,12524,12525,12526,12569,12571,12592,12672,12824,12825,12826,12872,12873,12952,12953,12982,12983,13018,13019,13020,13021,13031,13032,13033,18809,22782,22783,22959,23028,25304,25306,25345,27070,27071,27072,27073,27074,27075,27078,27079,27080,27082,27085,27086,27087,27088,27090,27101,27124,27125,27126,27127,27128,27130,27131,27132,27133,27134,28271,28272,28332,28574,28592,28593,28609,28612,29074,29075,29076,29077,29438,29439,29440,29441,29442,29444,29447,30451,30455,30482,31569,31570,31571,31572,31574,31575,31579,31582,31583,31584,31585,31586,31587,31588,31589,31638,31639,31640,31641,31642,31643,31656,31657,31658,31661,31667,31668,31669,31670,31672,31674,31675,31676,31677,31678,31679,31680,31682,31683,31687,32266,32267,32271,32272,32796,33041,33042,33043,33405,33690,33691,33717,33933,33938,33944,33946,34293,34295,34296,34913,35578,35581,35715,35717,37420,38692,38697,38699,38704,42198,42208,42209,42210,42211,42212,42213,42832,42833,42841,42842,42843,42846,42858,42859,42872,42873,42890,42891,42894,42896,42897,42913,42914,42917,42920,42921,42925,42926,42930,42931,42937,42938,42939,42940,42944,42945,42949,42950,42955,42956,42985,42995,43002,43008,43010,43012,43015,43017,43019,43020,43023,43024,43038,43039,43043,43044,43045,43046,43987,44378,44379,44394,44395,44396,44397,44398,44399,44400,44401,44402,44403,44404,44413,44425,44440,44441,44442,44443,44445,44446,44448,44449,44450,44457,44461,44469,44470,44471,44472,44543,44544,44545,44546,44548,44549,44557,44560,44561,44566,44567,44568,44570,44571,44572,44614,44745,44780,44781,45438,47610,49358,49359,49360,49361,53140,53142,54354,54486,54488,54489,54490,54646,54648,54658,54659,54734,54741,54747,54748,54749,54787,55091,55092,55094,55339,55340,55342,55359,55360,55361,55362,58659,61721,64349,64350,64353,64357,71761",
    PALADIN = "67,465,498,633,635,639,642,643,647,853,879,1022,1026,1032,1038,1044,1152,2800,2812,3472,4987,5502,5588,5589,5599,5614,5615,5923,5924,5925,5926,6940,7294,7328,9452,9453,9799,10278,10290,10291,10292,10293,10298,10299,10300,10301,10308,10310,10312,10313,10314,10318,10322,10324,10326,10328,10329,13819,19740,19742,19746,19750,19752,19834,19835,19836,19837,19838,19850,19852,19853,19854,19876,19888,19891,19895,19896,19897,19898,19899,19900,19939,19940,19941,19942,19943,20050,20052,20053,20066,20096,20097,20098,20099,20100,20116,20154,20164,20165,20166,20184,20185,20186,20187,20217,20254,20255,20256,20262,20263,20264,20265,20266,20271,20359,20360,20361,20473,20772,20773,20911,20922,20923,20924,20929,20930,21084,23214,24239,24274,24275,25290,25291,25292,25780,25781,25782,25829,25836,25894,25898,25899,25902,25903,25911,25912,25913,25914,25916,25918,25956,25957,25988,25997,26016,26017,26022,26023,26573,27135,27136,27137,27138,27139,27140,27141,27142,27143,27149,27150,27151,27152,27153,27154,27173,27174,27175,27176,27179,27180,31785,31789,31801,31803,31804,31821,31822,31823,31825,31826,31828,31829,31830,31833,31834,31835,31836,31837,31838,31839,31840,31841,31842,31844,31845,31848,31849,31850,31851,31852,31858,31859,31860,31866,31867,31868,31869,31871,31872,31876,31877,31878,31879,31880,31881,31884,31898,31935,32043,32223,32699,32700,33072,33073,33074,33776,34767,34769,35395,35396,35397,48781,48782,48784,48785,48788,48800,48801,48805,48806,48816,48817,48818,48819,48820,48821,48822,48823,48824,48825,48826,48827,48931,48932,48933,48934,48935,48936,48937,48938,48941,48942,48943,48945,48947,48949,48950,48951,48952,53375,53376,53379,53380,53381,53382,53385,53407,53408,53484,53486,53488,53489,53501,53502,53503,53519,53527,53530,53551,53552,53553,53556,53557,53563,53569,53576,53583,53585,53590,53591,53592,53595,53600,53601,53648,53651,53652,53653,53654,53655,53656,53657,53659,53660,53661,53671,53672,53673,53695,53696,53709,53710,53711,53726,53733,53736,53742,54043,54149,54151,54152,54153,54154,54155,54428,59578,60091,61411,62124,63646,63647,63648,63649,63650,64205",
    PRIEST = "17,139,453,527,528,552,585,586,588,589,591,592,594,596,598,600,602,605,724,970,976,984,988,992,996,1004,1006,1243,1244,1245,1706,2006,2010,2050,2052,2053,2054,2055,2060,2061,2096,2767,2791,2944,3747,6060,6063,6064,6065,6066,6074,6075,6076,6077,6078,6346,7001,7128,8092,8102,8103,8104,8105,8106,8122,8124,8129,9472,9473,9474,9484,9485,10060,10880,10881,10888,10890,10892,10893,10894,10898,10899,10900,10901,10909,10915,10916,10917,10927,10928,10929,10933,10934,10937,10938,10945,10946,10947,10951,10952,10955,10957,10958,10960,10961,10963,10964,10965,14531,14743,14752,14774,14818,14819,14910,14914,15237,15257,15259,15260,15261,15262,15263,15264,15265,15266,15267,15270,15272,15273,15274,15275,15286,15307,15308,15309,15310,15311,15312,15313,15314,15316,15317,15318,15320,15327,15328,15331,15332,15335,15336,15337,15338,15392,15407,15430,15431,15448,15487,17311,17312,17313,17314,17322,17323,18807,19236,19238,19240,19241,19242,19243,19276,19277,19278,19279,19280,20770,21562,21564,23455,23458,23459,25210,25213,25217,25218,25221,25222,25233,25235,25308,25312,25314,25315,25316,25329,25331,25363,25364,25367,25368,25372,25375,25384,25387,25389,25392,25431,25433,25435,25437,25467,27681,27683,27789,27790,27799,27800,27801,27803,27804,27805,27811,27813,27815,27816,27817,27818,27828,27839,27840,27841,27870,27871,27873,27874,27900,27901,27902,27903,27904,28275,28276,32375,32379,32546,32996,32999,33076,33142,33143,33145,33146,33150,33151,33154,33158,33159,33160,33161,33162,33167,33171,33172,33186,33190,33191,33192,33193,33196,33197,33198,33206,33213,33214,33215,33221,33222,33223,33224,33225,33371,34433,34753,34754,34859,34860,34861,34863,34864,34865,34866,34908,34909,34910,34914,34916,34917,34919,39374,44416,45234,45237,45241,45242,45243,45244,48040,48045,48062,48063,48065,48066,48067,48068,48070,48071,48072,48073,48074,48075,48076,48077,48078,48084,48085,48086,48087,48088,48089,48112,48113,48119,48120,48122,48123,48124,48125,48126,48127,48134,48135,48155,48156,48157,48158,48159,48160,48161,48162,48168,48169,48170,48171,48172,48173,48299,48300,64843,64844",
    ROGUE = "53,408,703,921,1329,1725,1752,1757,1758,1759,1760,1766,1776,1784,1833,1842,1856,1857,1860,1943,1966,2070,2094,2098,2589,2590,2591,2836,2983,5171,5277,5938,5952,6760,6761,6762,6768,6770,6774,8621,8623,8624,8631,8632,8633,8637,8639,8640,8643,8647,8676,8696,8721,8724,8725,11267,11268,11269,11273,11274,11275,11279,11280,11281,11289,11290,11293,11294,11297,11299,11300,11303,11305,14165,14166,14179,14181,14278,16511,17347,17348,21184,25300,25302,26669,26679,26839,26861,26862,26863,26864,26865,26867,26884,26889,27441,27448,31016,31122,31123,31124,31125,31126,31130,31131,31208,31209,31211,31212,31213,31216,31217,31218,31219,31220,31221,31222,31223,31224,31226,31227,31228,31229,31230,31234,31235,31236,31244,31245,31380,31382,31383,32601,32645,32684,34411,34412,34413,35541,35550,35551,35552,35553,36554,48637,48638,48656,48657,48658,48659,48660,48663,48666,48667,48668,48671,48672,48673,48674,48675,48676,48689,48690,48691,51625,51626,51627,51628,51629,51632,51633,51634,51635,51636,51637,51662,51664,51665,51667,51668,51669,51672,51674,51675,51677,51679,51680,51682,51685,51686,51687,51688,51689,51690,51692,51693,51696,51698,51699,51700,51701,51708,51709,51710,51711,51712,51713,51722,51723,51724,57933,57934,57992,57993,58410,58413,58414,58415,58422,58423,58424,58425,58426,58427,61329",
    SHAMAN = "131,324,325,331,332,370,379,403,421,529,546,547,548,556,905,913,915,930,939,943,945,959,974,1064,1535,2008,2062,2484,2645,2825,2860,3599,3738,5394,5675,5730,6041,6196,6363,6364,6365,6375,6377,6390,6391,6392,6495,8004,8005,8008,8010,8012,8017,8018,8019,8024,8027,8030,8033,8038,8042,8044,8045,8046,8050,8052,8053,8056,8058,8071,8075,8134,8143,8154,8155,8160,8161,8170,8177,8181,8184,8190,8227,8232,8235,8249,8498,8499,8512,10391,10392,10395,10396,10399,10406,10407,10408,10412,10413,10414,10427,10428,10431,10432,10437,10438,10442,10447,10448,10456,10462,10463,10466,10467,10468,10472,10473,10478,10479,10486,10495,10496,10497,10526,10537,10538,10585,10586,10587,10595,10600,10601,10605,10622,10623,11314,11315,15207,15208,16176,16177,16190,16235,16236,16237,16240,16266,16268,16339,16341,16342,16355,16356,16362,16387,17364,20608,20609,20610,20776,20777,21169,24398,25357,25361,25391,25396,25420,25422,25423,25439,25442,25448,25449,25454,25457,25464,25469,25472,25489,25500,25505,25508,25509,25525,25528,25533,25546,25547,25552,25557,25560,25563,25567,25570,25574,25590,26372,28996,28997,28998,28999,29000,29062,29064,29065,29079,29080,29082,29084,29086,29177,29178,29179,29180,29187,29189,29191,29192,29193,29202,29205,29206,29228,30160,30664,30665,30666,30669,30670,30671,30672,30673,30674,30675,30678,30679,30706,30708,30798,30802,30808,30809,30812,30813,30814,30816,30818,30819,30823,30824,30864,30865,30866,30867,30868,30869,30872,30873,30874,30881,30883,30884,30885,30886,32175,32176,32182,32593,32594,33736,36591,36936,43338,43339,49230,49231,49232,49233,49235,49236,49237,49238,49239,49240,49268,49269,49270,49271,49272,49273,49275,49276,49277,49278,49279,49280,49281,49283,49284,51466,51470,51886,55458,55459,57622,57720,57721,57722,57960,57994,58580,58581,58582,58643,58649,58652,58656,58699,58703,58704,58731,58734,58737,58739,58741,58745,58751,58755,58756,58757,58771,58773,58774,58785,58790,58794,58795,58796,58801,58803,58804,59156,59158,59159,60043,60103,60348,61649,61657,63370,63372,75461",
    WARLOCK = "126,132,172,348,603,686,687,688,689,691,693,695,696,697,698,699,702,705,706,707,709,710,712,755,980,1010,1086,1088,1094,1098,1106,1108,1120,1122,1454,1455,1456,1490,1714,1949,2362,2941,3698,3699,3700,5138,5484,5500,5676,5697,5699,5740,5782,5784,5857,6201,6202,6205,6213,6215,6217,6219,6222,6223,6229,6353,6366,6789,7641,7646,7648,7651,8288,8289,11659,11660,11661,11665,11667,11668,11671,11672,11675,11677,11678,11681,11682,11683,11684,11687,11688,11689,11693,11694,11695,11699,11700,11707,11708,11711,11712,11713,11719,11721,11722,11725,11726,11729,11730,11733,11734,11735,11739,11740,17727,17728,17877,17919,17920,17921,17922,17923,17924,17925,17926,17928,17951,17952,17953,17962,18220,18540,18541,18647,18662,18822,18867,18868,18869,18870,18871,18937,18938,20752,20755,20756,20757,23161,23759,23760,23761,23762,23785,23822,23823,23824,23825,23826,23827,23828,23829,23833,23834,23835,23836,23837,23838,23839,23840,23841,23842,23843,23844,25307,25309,25311,27209,27210,27211,27212,27213,27214,27215,27216,27217,27218,27219,27220,27222,27223,27224,27228,27230,27238,27243,27250,27259,27260,27263,27265,27285,28172,28176,28189,28610,29722,29858,29886,29893,30054,30057,30060,30061,30062,30063,30064,30108,30143,30144,30145,30146,30242,30245,30246,30247,30248,30283,30288,30289,30290,30291,30292,30293,30295,30296,30299,30301,30302,30319,30320,30321,30326,30404,30405,30413,30414,30459,30545,30546,30909,30910,31117,32231,32381,32382,32383,32385,32386,32387,32388,32389,32390,32391,32392,32393,32394,32477,32483,32484,34935,34936,34938,34939,35691,35692,35693,35702,35703,35704,35705,35706,42218,42223,42224,42225,42226,47206,47793,47808,47809,47810,47811,47812,47813,47814,47815,47817,47818,47819,47820,47822,47823,47824,47825,47826,47827,47833,47834,47835,47836,47837,47838,47841,47843,47846,47847,47855,47856,47857,47859,47860,47863,47864,47865,47867,47871,47878,47884,47886,47888,47889,47890,47891,47892,47893,47897,48018,48020,48181,50511,50796,57946,58284,58435,58887,58889,59092,59161,59163,59164,59170,59171,59172,61191,61290,61610,63108,63156,63158,75445",
    WARRIOR = "71,72,78,100,284,285,355,469,676,694,772,845,871,1160,1161,1464,1608,1680,1715,1719,2048,2457,2458,2565,2687,3411,5242,5246,5308,6178,6190,6192,6343,6546,6547,6548,6552,6572,6574,6673,7369,7376,7379,7381,7384,7386,8198,8204,8205,8820,11549,11550,11551,11554,11555,11556,11564,11565,11566,11567,11572,11573,11574,11578,11580,11581,11600,11601,11604,11605,11608,11609,12287,12292,12294,12295,12300,12308,12328,12665,12666,12676,12677,12678,12723,12810,12811,12959,12960,18499,20230,20243,20252,20504,20505,20569,20647,20658,20660,20661,20662,21156,21551,21552,21553,23584,23585,23586,23587,23588,23880,23881,23885,23920,23922,23923,23924,23925,25202,25203,25208,25231,25234,25236,25241,25242,25248,25258,25264,25269,25286,25288,25289,26654,29140,29143,29144,29590,29591,29592,29593,29594,29598,29599,29623,29707,29721,29723,29724,29725,29759,29760,29761,29762,29763,29776,29787,29790,29792,29801,29834,29836,29838,29841,29842,29859,29888,29889,30016,30022,30324,30330,30356,30357,34428,35446,35448,35449,45471,46845,46854,46855,46856,46857,46859,46860,46865,46866,46867,46908,46909,46910,46911,46913,46914,46915,46916,46917,46924,46945,46946,46947,46949,46951,46952,46953,46968,47294,47295,47296,47436,47437,47439,47440,47449,47450,47465,47470,47471,47474,47475,47485,47486,47487,47488,47497,47498,47501,47502,47519,47520,50685,50686,50687,50720,55694,56112,56611,56612,56613,56614,56636,56637,56638,56924,56927,56929,56930,56931,56932,57499,57755,57823,58872,58874,59088,59089,60970,61216,61221,61222,64380,64382,64976",
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
