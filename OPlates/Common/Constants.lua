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
addon.SPEC_SIGNATURES = {
    [46924] = { "WARRIOR", "ARMS", 2 },          -- Bladestorm
    [12294] = { "WARRIOR", "ARMS", 1 },          -- Mortal Strike
    [23881] = { "WARRIOR", "FURY", 1 },          -- Bloodthirst
    [46968] = { "WARRIOR", "PROTECTION", 2 },    -- Shockwave
    [20243] = { "WARRIOR", "PROTECTION", 1 },    -- Devastate
    [50720] = { "WARRIOR", "PROTECTION", 1 },    -- Vigilance
    [53563] = { "PALADIN", "HOLY", 2 },          -- Beacon of Light
    [31842] = { "PALADIN", "HOLY", 1 },          -- Divine Illumination
    [20473] = { "PALADIN", "HOLY", 1 },          -- Holy Shock
    [53595] = { "PALADIN", "PROTECTION", 2 },    -- Hammer of the Righteous
    [31935] = { "PALADIN", "PROTECTION", 1 },    -- Avenger's Shield
    [53385] = { "PALADIN", "RETRIBUTION", 2 },   -- Divine Storm
    [35395] = { "PALADIN", "RETRIBUTION", 1 },   -- Crusader Strike
    [20066] = { "PALADIN", "RETRIBUTION", 1 },   -- Repentance
    [53301] = { "HUNTER", "SURVIVAL", 2 },       -- Explosive Shot
    [3674]  = { "HUNTER", "SURVIVAL", 1 },       -- Black Arrow
    [19386] = { "HUNTER", "SURVIVAL", 1 },       -- Wyvern Sting
    [53209] = { "HUNTER", "MARKSMANSHIP", 2 },   -- Chimera Shot
    [34490] = { "HUNTER", "MARKSMANSHIP", 1 },   -- Silencing Shot
    [19506] = { "HUNTER", "MARKSMANSHIP", 1 },   -- Trueshot Aura
    [34471] = { "HUNTER", "BEAST_MASTERY", 1 },  -- The Beast Within
    [19574] = { "HUNTER", "BEAST_MASTERY", 1 },  -- Bestial Wrath
    [51662] = { "ROGUE", "ASSASSINATION", 2 },   -- Hunger for Blood
    [1329]  = { "ROGUE", "ASSASSINATION", 1 },   -- Mutilate
    [51690] = { "ROGUE", "COMBAT", 2 },          -- Killing Spree
    [13750] = { "ROGUE", "COMBAT", 1 },          -- Adrenaline Rush
    [51713] = { "ROGUE", "SUBTLETY", 2 },        -- Shadow Dance
    [36554] = { "ROGUE", "SUBTLETY", 1 },        -- Shadowstep
    [47540] = { "PRIEST", "DISCIPLINE", 2 },     -- Penance
    [33206] = { "PRIEST", "DISCIPLINE", 1 },     -- Pain Suppression
    [10060] = { "PRIEST", "DISCIPLINE", 1 },     -- Power Infusion
    [47788] = { "PRIEST", "HOLY", 2 },           -- Guardian Spirit
    [34861] = { "PRIEST", "HOLY", 1 },           -- Circle of Healing
    [47585] = { "PRIEST", "SHADOW", 2 },         -- Dispersion
    [34914] = { "PRIEST", "SHADOW", 1 },         -- Vampiric Touch
    [15473] = { "PRIEST", "SHADOW", 1 },         -- Shadowform
    [49028] = { "DEATHKNIGHT", "BLOOD", 2 },     -- Dancing Rune Weapon
    [55050] = { "DEATHKNIGHT", "BLOOD", 1 },     -- Heart Strike
    [49184] = { "DEATHKNIGHT", "FROST", 2 },     -- Howling Blast
    [49143] = { "DEATHKNIGHT", "FROST", 1 },     -- Frost Strike
    [49206] = { "DEATHKNIGHT", "UNHOLY", 2 },    -- Summon Gargoyle
    [55090] = { "DEATHKNIGHT", "UNHOLY", 1 },    -- Scourge Strike
    [51490] = { "SHAMAN", "ELEMENTAL", 2 },      -- Thunderstorm
    [30706] = { "SHAMAN", "ELEMENTAL", 1 },      -- Totem of Wrath
    [16166] = { "SHAMAN", "ELEMENTAL", 1 },      -- Elemental Mastery
    [51533] = { "SHAMAN", "ENHANCEMENT", 2 },    -- Feral Spirit
    [30823] = { "SHAMAN", "ENHANCEMENT", 1 },    -- Shamanistic Rage
    [17364] = { "SHAMAN", "ENHANCEMENT", 1 },    -- Stormstrike
    [61295] = { "SHAMAN", "RESTORATION", 2 },    -- Riptide
    [974]   = { "SHAMAN", "RESTORATION", 1 },    -- Earth Shield
    [16190] = { "SHAMAN", "RESTORATION", 1 },    -- Mana Tide Totem
    [44425] = { "MAGE", "ARCANE", 2 },           -- Arcane Barrage
    [31589] = { "MAGE", "ARCANE", 1 },           -- Slow
    [12042] = { "MAGE", "ARCANE", 1 },           -- Arcane Power
    [44457] = { "MAGE", "FIRE", 2 },             -- Living Bomb
    [31661] = { "MAGE", "FIRE", 1 },             -- Dragon's Breath
    [44572] = { "MAGE", "FROST", 2 },            -- Deep Freeze
    [31687] = { "MAGE", "FROST", 1 },            -- Summon Water Elemental
    [48181] = { "WARLOCK", "AFFLICTION", 2 },    -- Haunt
    [30108] = { "WARLOCK", "AFFLICTION", 1 },    -- Unstable Affliction
    [47241] = { "WARLOCK", "DEMONOLOGY", 2 },    -- Metamorphosis
    [30146] = { "WARLOCK", "DEMONOLOGY", 1 },    -- Summon Felguard
    [50796] = { "WARLOCK", "DESTRUCTION", 2 },   -- Chaos Bolt
    [30283] = { "WARLOCK", "DESTRUCTION", 1 },   -- Shadowfury
    [48505] = { "DRUID", "BALANCE", 2 },         -- Starfall
    [33831] = { "DRUID", "BALANCE", 1 },         -- Force of Nature
    [50516] = { "DRUID", "BALANCE", 1 },         -- Typhoon
    -- "Berserk" (50334) removed. On this server the client localizes other
    -- classes' casts to the same name, so a name-matched signature flipped paladins
    -- and warriors to DRUID FERAL. Mangle (Cat/Bear) already proves Feral and its kind.
    [33876] = { "DRUID", "FERAL", 1, "CAT" },    -- Mangle (Cat)
    [33878] = { "DRUID", "FERAL", 1, "BEAR" },   -- Mangle (Bear)
    [48438] = { "DRUID", "RESTORATION", 2 },     -- Wild Growth
    [33891] = { "DRUID", "RESTORATION", 1 },     -- Tree of Life
    [18562] = { "DRUID", "RESTORATION", 1 },     -- Swiftmend
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
