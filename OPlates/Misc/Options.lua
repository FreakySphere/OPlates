local _, addon = ...
local L = addon.L

addon.GetWotLKMiscOptions = function(order, icon)
    return {
        order = order,
        type = "group",
        name = "Tools",
        desc = "Minimap button and troubleshooting.",
        args = {
            general = { order = 1, type = "group", inline = true, name = "Minimap", args = {
                showMinimapIcon = {
                    order = 1,
                    type = "toggle",
                    width = "full",
                    name = "Minimap button",
                    desc = "A minimap button that opens this window.",
                    get = function() return not OPlates.db.profile.minimap.hide end,
                    set = function(_, value)
                        OPlates.db.profile.minimap.hide = not value
                        if value then icon:Show("OPlates"); if addon.MinimapFullIcon then addon.MinimapFullIcon() end else icon:Hide("OPlates") end
                        OPlates:NotifyOptions()
                    end,
                },
            } },
            -- runtime only, never saved; OFF again at every login.
            debug = { order = 2, type = "group", inline = true, name = "Troubleshooting", args = {
                debugEnabled = {
                    order = 1,
                    type = "toggle",
                    width = "full",
                    name = "Debug log in chat",
                    desc = "Prints detailed debug lines to chat for this session only. Off again at every login.",
                    get = function() return addon._debugEnabled == true end,
                    set = function(_, value) addon:SetDebug(value, "Misc option") end,
                },
                debugCommands = {
                    order = 2,
                    type = "description",
                    name = "|cffaaaaaa/op debug on  -  start logging\n/op debug off  -  stop logging\n/op debug reset  -  start a new log session\n/op talent reset  -  forget learned specs and reload\n/op classic  -  open the classic settings window|r",
                },
            } },
        },
    }
end

addon.GetWotLKHealerOptions = function(order)
    local function card(name, order, args)
        return { order = order, type = "group", inline = true, name = name, args = args }
    end
    return {
        order = order,
        type = "group",
        name = "Healer CC",
        desc = "A big alert the moment a healer in your group is crowd controlled, with a one-click dispel.",
        get = function(info) return OPlates.db.profile.misc[info[#info]] end,
        set = function(info, value)
            OPlates.db.profile.misc[info[#info]] = value
            OPlates.db.profile.misc.lastModified = GetTime()
            OPlates:UpdateHealerInCrowdControl()
            OPlates:SetupHealerInCrowdControl()
            OPlates:NotifyOptions()
        end,
        args = {
            alert = card("Alert", 1, {
                healerInCrowdControl = { order = 1, type = "toggle", width = "full", name = "Healer CC alert",
                    desc = "Only in a group, for healer-spec members. Within about 100 yards it reads their debuffs directly; farther away it works when the healer also runs this addon." },
                healerInCrowdControlSound = { order = 2, type = "toggle", width = "full", name = "Play a sound" },
            }),
            where = card("Where", 2, {
                healerInCrowdControlInArena = { order = 1, type = "toggle", name = "Arenas" },
                healerInCrowdControlInBG = { order = 2, type = "toggle", name = "Battlegrounds" },
                healerInCrowdControlInPVE = { order = 3, type = "toggle", name = "Dungeons & raids" },
                healerInCrowdControlInWorld = { order = 4, type = "toggle", name = "Open world",
                    desc = "Includes Wintergrasp." },
            }),
            look = card("Size & Position", 3, {
                healerInCrowdControlTest = { order = 1, type = "execute", name = L["Test"],
                    desc = "Shows sample alerts so you can see and move them.",
                    func = "TestHealerInCrowdControl", handler = OPlates },
                healerInCrowdControlHide = { order = 2, type = "execute", name = L["Hide"],
                    desc = "Hides the sample alerts.",
                    func = "HideTestHealerInCrowdControl", handler = OPlates },
                healerInCrowdControlResetPositions = { order = 3, type = "execute", name = "Reset positions",
                    desc = "Puts every alert back in its default place (the first at the offsets below, the others stacked under it).",
                    func = "ResetHealerInCrowdControlPositions", handler = OPlates },
                healerInCrowdControlSize = {
                    order = 4, type = "range", width = "full", name = "Alert size", min = 30, max = 120, step = 1,
                    set = function(info, value)
                        OPlates.db.profile.misc[info[#info]] = value
                        OPlates.db.profile.misc.lastModified = GetTime()
                        OPlates:UpdateHealerInCrowdControl()
                        -- no NotifyOptions here; rebuilding the dialog mid-drag
                        -- made the slider jump like a button instead of dragging.
                    end,
                },
                healerInCrowdControlOffsetX = {
                    order = 5, type = "range", name = "Move left / right", min = -800, max = 800, step = 1,
                    set = function(info, value)
                        OPlates.db.profile.misc[info[#info]] = value
                        OPlates.db.profile.misc.lastModified = GetTime()
                        OPlates:UpdateHealerInCrowdControl()
                    end,
                },
                healerInCrowdControlOffsetY = {
                    order = 6, type = "range", name = "Move up / down", min = -500, max = 500, step = 1,
                    set = function(info, value)
                        OPlates.db.profile.misc[info[#info]] = value
                        OPlates.db.profile.misc.lastModified = GetTime()
                        OPlates:UpdateHealerInCrowdControl()
                    end,
                },
                healerInCrowdControlMoveInfo = { order = 7, type = "description",
                    name = "|cffaaaaaaTip: press Test, then drag the alerts (out of combat). Dragging the first one also moves the sliders.|r" },
            }),
            -- the two number styles are mutually exclusive.
            timer = card("Countdown", 4, {
                timerInfo = { order = 1, type = "description",
                    name = "|cffaaaaaaPick one style, or neither for no number.|r" },
                healerInCrowdControlColoredTimer = { order = 2, type = "toggle", width = "full", name = "Colored, in the center",
                    desc = "White from 1 minute, yellow under 1 minute, red from 5 seconds (then tenths). Turns the white number off.",
                    set = function(info, value)
                        local misc = OPlates.db.profile.misc
                        misc.healerInCrowdControlColoredTimer = value
                        if value then misc.healerInCrowdControlUseCustomTimer = false end
                        misc.lastModified = GetTime()
                        OPlates:NotifyOptions()
                    end },
                healerInCrowdControlUseCustomTimer = { order = 3, type = "toggle", width = "full", name = "White, under the icon",
                    desc = "A simple white number with tenths. Turns the colored number off.",
                    set = function(info, value)
                        local misc = OPlates.db.profile.misc
                        misc.healerInCrowdControlUseCustomTimer = value
                        if value then misc.healerInCrowdControlColoredTimer = false end
                        misc.lastModified = GetTime()
                        OPlates:NotifyOptions()
                    end },
            }),
            dispel = card("Click to Dispel", 5, {
                healerInCrowdControlBreakerIcon = { order = 1, type = "toggle", width = "full", name = "Dispel button",
                    desc = "A square button beside the alert with your spell that can break this CC (Dispel Magic, Cleanse, Remove Curse, Cleanse Spirit, Cure Toxins, Tremor Totem for fears). Glowing: ready. Grey: on cooldown, out of mana, or you are crowd controlled. Hidden if you know no such spell." },
                healerInCrowdControlMaxFrames = {
                    order = 2, type = "range", name = "Max alerts", min = 1, max = 5, step = 1,
                    desc = "How many alerts can show at once. Out of combat each one is bound to one healer of your group, so a healer keeps the same spot. 1 = a single alert for the most important healer, without click.",
                    -- like the other sliders, no NotifyOptions while dragging
                    -- (the dialog rebuild destroyed the thumb, so it only worked by clicks).
                    set = function(info, value)
                        local misc = OPlates.db.profile.misc
                        if misc.healerInCrowdControlMaxFrames == value then return end
                        misc.healerInCrowdControlMaxFrames = value
                        misc.lastModified = GetTime()
                        OPlates:UpdateHealerInCrowdControl()
                        OPlates:SetupHealerInCrowdControl()
                    end,
                },
                healerInCrowdControlClickModifier = {
                    order = 3, type = "select", name = "In-combat key",
                    desc = "Out of combat a plain click dispels. In combat (Blizzard rules) hold this key while clicking.",
                    values = { ALT = "Alt", SHIFT = "Shift", CTRL = "Ctrl" },
                    disabled = function() return OPlates.db.profile.misc.healerInCrowdControlNoClick end,
                },
                healerInCrowdControlNoClick = { order = 4, type = "toggle", width = "full", name = "Display only (no clicks)",
                    desc = "The dispel button only shows; no click buttons are created." },
                clickInfo = { order = 5, type = "description",
                    name = "|cffaaaaaaLeft click: Dispel Magic, Cleanse, Cleanse Spirit, Cure Toxins or Remove Curse. Right click (small R): Abolish or Cure Disease, Tremor Totem, Abolish or Cure Poison. A healer who joins during combat gets a display-only alert until combat ends.|r" },
            }),
        },
    }
end
