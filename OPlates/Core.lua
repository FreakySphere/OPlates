local addonName, addon = ...
addon.L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local L = addon.L

local GetAddOnMetadata = GetAddOnMetadata
OPlates = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceSerializer-3.0")

local function Metadata(key)
    if GetAddOnMetadata then return GetAddOnMetadata(addonName, key) end
    return nil
end

-- The TOC Title is coloured for the AddOns list; every in-game title uses the plain text.
local function PlainText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:match("^%s*(.-)%s*$")
    return s ~= "" and s or nil
end

addon.addonTitle = PlainText(Metadata("Title")) or "OPlates"
addon.UIVersionText = "Version " .. (Metadata("Version") or "?")

local addonIcon = addon.LOGO_ART or "Interface\\AddOns\\OPlates\\Art\\Logo"
local OPlatesLDB = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
    type = "data source",
    text = addonName,
    icon = addonIcon,
    OnTooltipShow = function(tooltip)
        tooltip:SetText(addon.addonTitle, 1, 1, 1)
        tooltip:AddLine(L["Click to open the settings"])
    end,
    OnClick = function()
        addon.OpenOptionsWindow()
    end,
})
local icon = LibStub("LibDBIcon-1.0")

-- LibDBIcon crops every button icon by 5% and resets that crop on mouse-up and
-- drag-stop. The OPlates logo has its own ring, so the full image is restored
-- after each of those handlers. The button is made lazily, so this runs at each
-- show; the hooks are added once.
function addon.MinimapFullIcon()
    local b = _G["LibDBIcon10_" .. addonName]
    if not b or not b.icon then return end
    if not b._opFullIcon then
        b._opFullIcon = true
        local function full(self) if self.icon then self.icon:SetTexCoord(0, 1, 0, 1) end end
        b:HookScript("OnMouseDown", full)
        b:HookScript("OnMouseUp", full)
        b:HookScript("OnDragStop", full)
    end
    b.icon:SetTexCoord(0, 1, 0, 1)
end

local defaults = {
    profile = {
        nameplates = {
            classIconsEnabled = true,
            friendlyDisplayMode = "ALL",
            enemyDisplayMode = "ALL",
            classIconSize = 1.0,
            healerIconSize = 1.35,
            flagCarrierIconSize = 1.5,
            petIconSize = 0.8,
            classIconHorizontalOffset = 0,
            classIconOffset = -3,
            useHealerIcon = true,
            useTankIcon = true,
            showSpec = true,
            persistentTalentCache = false,
            useAwesomeWotlkNameplateUnits = false,
            showClassIcon = true,
            showUnknownFriendly = true,
            classToSpecDelay = 1.0,
            classToSpecDelayEnabled = true,
            drResetSeconds = 18.1,
            petIconsEnabled = true,
            useFlagCarrierIcon = true,
            enemyFlagCarrierIcon = true,
            enemyPetIcon = true,
            enemyHealerIcon = true,
            enemyTankIcon = true,
            enemyShowSpec = true,
            enemyShowClass = true,
            enemyShowUnknown = true,
            showPlayerName = true,
            enemyShowPlayerName = true,
            showNameWithoutIcon = false,
            enemyShowNameWithoutIcon = false,
            showCrowdControl = true,
            crowdControlTimer = true,
            enemyCrowdControlTimer = true,
            auraEnabled = true,
            showBuffs = false,
            showDebuffs = false,
            buffWhitelist = "",
            debuffWhitelist = "",
            -- enemy icons master switch and an independent enemy
            -- "Circular aura replacement" set (same layout as Friendly).
            enemyIconsEnabled = true,
            enemyShowCrowdControl = true,
            enemyAuraEnabled = true,
            enemyShowBuffs = false,
            enemyShowDebuffs = false,
            enemyBuffWhitelist = "",
            enemyDebuffWhitelist = "",
            hideOutsidePvP = false,
            hideEnemyOutsidePvP = false,
            arenaNumbersEnabled = true,
            enemyIconScale = 100,
            enemyIconOffsetX = 0,
            enemyIconOffsetY = 0,
            enemyHealerIconSize = 1.35,
            enemyPetIconSize = 0.8,
            enemyFlagCarrierIconSize = 1.5,
            -- per-side class/spec filters. Only DISABLED entries are stored
            -- (an empty table means every class/spec is shown). Class keys are the
            -- class file ("ROGUE"); spec keys are "CLASS:SPEC" ("ROGUE:COMBAT").
            classFilter = {},
            enemyClassFilter = {},
            specFilter = {},
            enemySpecFilter = {},
        },
        misc = {
            healerInCrowdControl = true,
            healerInCrowdControlSound = true,
            healerInCrowdControlSize = 48,
            healerInCrowdControlOffsetX = 0,
            healerInCrowdControlOffsetY = 250,
            healerInCrowdControlInArena = true,
            healerInCrowdControlInBG = true,
            healerInCrowdControlInPVE = true,
            healerInCrowdControlInWorld = true,
            healerInCrowdControlUseCustomTimer = false,
            healerInCrowdControlColoredTimer = true,
            healerInCrowdControlBreakerIcon = true,
            healerInCrowdControlMaxFrames = 3,
            healerInCrowdControlClickModifier = "ALT",
            healerInCrowdControlNoClick = false,
        },
        minimap = { hide = true },
    },
}

local options = {
    name = addon.addonTitle,
    type = "group",
    args = {
        description = {
            order = 1,
            type = "description",
            fontSize = "medium",
            name = L["Circular class, spec and role icons on every nameplate, live crowd-control icons and instant Healer CC alerts."]
                .. "\n\n|cffaaaaaa" .. L["OPlates only adds icons. Your nameplate addon keeps its own bars and style."] .. "|r",
        },
    },
}

function OPlates:SetupBlizzardOptions()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = addon.addonTitle
    panel:Hide()
    panel:SetScript("OnShow", function(self)
        local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(addon.addonTitle)
        local context = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        context:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        context:SetText(string.format(L["Type %s or click the minimap button to open the settings."], "|cff00ff00/op|r"))
        local open = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
        open:SetText(L["Open settings"])
        open:SetWidth(177)
        open:SetHeight(24)
        open:SetPoint("TOPLEFT", context, "BOTTOMLEFT", 0, -30)
        open:SetScript("OnClick", function()
            addon.OpenOptionsWindow()
        end)
        self:SetScript("OnShow", nil)
    end)
    if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel) end
    SLASH_OPlates1 = "/op"
    SLASH_OPlates2 = "/oplates"
    SlashCmdList.OPlates = function(msg)
        msg = string.lower(msg or "")
        if msg == "debug" or msg == "debug on" then
            if addon._debugEnabled then
                addon:DebugReset("/op debug on")
            else
                addon:SetDebug(true, "/op debug on")
            end
            return
        elseif msg == "debug off" then
            addon:SetDebug(false)
            return
        elseif msg == "debug reset" then
            addon:DebugReset("/op debug reset")
            return
        elseif msg == "talent reset" then
            -- Explicit cold-cache test command. Reload also clears render snapshots
            -- and cancels every outstanding request/timer from the old session.
            OPlatesTalentDB = nil
            ReloadUI()
            return
        elseif msg == "classic" then
            addon.OpenClassicOptions()
            return
        end
        addon.OpenOptionsWindow()
    end
end

-- every way of opening the options goes through Filters.lua's
-- addon.OpenOptions (it also shows the awesome_wotlk note in the corner).
-- opens the new themed settings window; addon.OpenOptions (Filters.lua)
-- also hides an open filter window first. "/op classic" keeps the old window.
addon.OpenOptionsWindow = function()
    if addon.OpenOptions then
        addon.OpenOptions()
    elseif addon.UISettings then
        addon.UISettings.Open()
    else
        LibStub("AceConfigDialog-3.0"):Open(addonName)
    end
end

addon.OpenClassicOptions = function()
    if addon.UISettings then addon.UISettings.Hide() end
    LibStub("AceConfigDialog-3.0"):Open(addonName)
    local filters = addon.NameplateFilters
    if filters and filters.UpdateStatusNote then filters.UpdateStatusNote() end
end

function OPlates:NotifyOptions()
    if LibStub and LibStub("AceConfigRegistry-3.0", true) then
        LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
    end
    -- keep the corner note and an open filter window in step.
    local filters = addon.NameplateFilters
    if filters then
        if filters.UpdateStatusNote then filters.UpdateStatusNote() end
        if filters.Refresh then filters.Refresh() end
    end
    if addon.UISettings and addon.UISettings.RefreshOpen then addon.UISettings.RefreshOpen() end
end

-- options removed in this version are dropped from the saved profile, and
-- the two Healer CC number styles are mutually exclusive (coloured wins).
addon.MigrateProfile = function(profile)
    local np, misc = profile and profile.nameplates, profile and profile.misc
    if np then np.ccUseCustomCooldown, np.ccNumericText = nil, nil end
    if np then
        -- the "Healer-only shortcut" toggle is gone; a saved ON becomes
        -- the equivalent Display mode, so the plates look exactly the same.
        if rawget(np, "showHealerOnly") == true then np.friendlyDisplayMode = "HEALER" end
        np.showHealerOnly = nil
        -- the legacy "Show CC icons" toggles are replaced by the CC only mode.
        np.showCCIcons, np.enemyShowCCIcons = nil, nil
        -- enemy plates used the Friendly aura settings until now. Copy
        -- them once into the new independent enemy keys (no visible change).
        if not np.enemyAuraSplit then
            np.enemyAuraSplit = true
            np.enemyShowCrowdControl = np.showCrowdControl
            np.enemyAuraEnabled = np.auraEnabled
            np.enemyShowBuffs = np.showBuffs
            np.enemyShowDebuffs = np.showDebuffs
            np.enemyBuffWhitelist = np.buffWhitelist
            np.enemyDebuffWhitelist = np.debuffWhitelist
        end
    end
    if misc then
        misc.healerInCrowdControlUseRotatingRing = nil
        if misc.healerInCrowdControlColoredTimer and misc.healerInCrowdControlUseCustomTimer then
            misc.healerInCrowdControlUseCustomTimer = false
        end
    end
end

function OPlates:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("OPlatesDB", defaults, true)
    addon.MigrateProfile(self.db.profile)

    options.args.nameplates = addon.GetWotLKNameplateOptions(2)
    options.args.healercc = addon.GetWotLKHealerOptions(3)
    options.args.misc = addon.GetWotLKMiscOptions(4, icon, OPlatesLDB)

    addon.importDialogs = addon.importDialogs or {}
    addon.importDialogs[""] = addon.CreateImportDialog("")
    addon.exportDialog = addon.exportDialog or addon.CreateExportDialog()
    options.args.profileSharing = {
        order = 8,
        type = "group",
        name = "Share",
        desc = "Send your setup to a friend, or load theirs.",
        args = {
            share = { order = 1, type = "group", inline = true, name = "Import & Export", args = {
                import = { order = 1, type = "execute", name = "Import", desc = "Paste a setup string from another player.", func = function() OPlates:ShowImport("") end },
                export = { order = 2, type = "execute", name = "Export", desc = "Copy your setup as a string to share.", func = function() OPlates:ShowExport() end },
            } },
        },
    }
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    options.args.profiles.desc = "Save, switch, copy or reset whole setups."

    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options)
    LibStub("AceConfigDialog-3.0"):SetDefaultSize(addonName, 680, 560)

    self:SetupBlizzardOptions()
    icon:Register(addonName, OPlatesLDB, self.db.profile.minimap)
    if self.db.profile.minimap.hide then icon:Hide(addonName) else icon:Show(addonName) end
    addon.MinimapFullIcon()

    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    if addon.TalentScanner then addon.TalentScanner:Initialize() end
    self:SetupNameplateOverlays()
    self:SetupHealerInCrowdControl()
end

function OPlates:RefreshConfig()
    if addon.TalentScanner and addon.TalentScanner._initialized
        and addon.TalentScanner.persistenceEnabled ~= (self.db.profile.nameplates.persistentTalentCache == true) then
        ReloadUI()
        return
    end
    addon.MigrateProfile(self.db.profile)
    if addon.TalentScanner and addon.TalentScanner._initialized then
        addon.TalentScanner:SetPlateUnits(self.db.profile.nameplates.useAwesomeWotlkNameplateUnits == true)
    end
    self:RefreshNameplateOverlays()
    self:SetupHealerInCrowdControl()
    if self.db.profile.minimap.hide then icon:Hide(addonName) else icon:Show(addonName); addon.MinimapFullIcon() end
    self:NotifyOptions()
end
