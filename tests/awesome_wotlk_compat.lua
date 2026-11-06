-- Focused Lua 5.1 regression coverage for optional awesome_wotlk discovery.
-- This loads the real Common/Talents.lua in isolated mocked 3.3.5a clients.

local passed = 0

local function check(value, message)
    assert(value, message)
end

local function fixture(shape)
    local frames, units, added = {}, {}, 0
    local addon = {
        TALENT_TAB_SPECS = { MAGE = { "ARCANE", "FIRE", "FROST" } },
        SPEC_ROLES = { MAGE = { ARCANE = "DAMAGER", FIRE = "DAMAGER", FROST = "DAMAGER" } },
    }

    local env = setmetatable({}, { __index = _G })
    env.OPlates = { db = { profile = { nameplates = {} } } }
    env.GetTime = function() return 1 end
    env.time = function() return 1 end
    env.GetRealmName = function() return "Test Realm" end
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end end
    env.hooksecurefunc = function() end
    env.UnitExists = function(unit) return units[unit] ~= nil end
    env.UnitIsPlayer = function(unit) return units[unit] and units[unit].player or false end
    env.UnitIsUnit = function(a, b) return a == b end
    env.UnitGUID = function(unit) return units[unit] and units[unit].guid end
    env.UnitClass = function(unit)
        local data = units[unit]
        return data and data.class, data and data.class
    end
    env.UnitName = function(unit) return units[unit] and units[unit].name end

    env.CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(kind, fn) self.scripts[kind] = fn end
        frames[#frames + 1] = frame
        return frame
    end

    if shape.lookup == "global" then
        env.UnitTokenFromGUID = function(guid)
            for unit, data in pairs(units) do if data.guid == guid then return unit end end
        end
    elseif shape.lookup == "table" then
        env.C_NamePlate = {
            GetNamePlateTokenByGUID = function(guid)
                for unit, data in pairs(units) do if data.guid == guid then return unit end end
            end,
        }
    elseif shape.lookup == "events" then
        env.C_NamePlate = { GetNamePlates = function() return {} end }
    end

    if shape.frameGUID then
        env.C_NamePlate = env.C_NamePlate or {}
        env.C_NamePlate.GetGUIDForNamePlate = function(plate) return plate.guid end
    end

    env.issecurevariable = function(a, b)
        if b ~= nil then return env.C_NamePlate and env.C_NamePlate[b] ~= nil and 1 or nil end
        return env[a] ~= nil and 1 or nil
    end

    addon.OnPlayerNamePlateAdded = function(unit)
        added = added + 1
        check(unit == "nameplate1", "unexpected unit passed to plate callback")
    end

    local chunk = assert(loadfile("OPlates/Common/Talents.lua"))
    setfenv(chunk, env)
    chunk("OPlates", addon)

    return {
        addon = addon,
        frames = frames,
        units = units,
        added = function() return added end,
    }
end

local function test(name, fn)
    fn()
    passed = passed + 1
    print("PASS " .. name)
end

test("stock client remains inactive", function()
    local f = fixture({})
    check(f.addon.TalentScanner:DetectAwesomeWotlk() == nil, "stock client was falsely detected")
    check(f.addon.TalentScanner:SetPlateUnits(true) == false, "stock client enabled patched units")
    check(#f.frames == 1, "stock client allocated a nameplate event frame")
end)

local supported = {
    { name = "event-only KhalGH-compatible API", shape = { lookup = "events", frameGUID = true }, mode = "events" },
    { name = "FreakySphere API 40 global lookup", shape = { lookup = "global", frameGUID = true }, mode = "UnitTokenFromGUID" },
    { name = "compatible table lookup API", shape = { lookup = "table", frameGUID = true }, mode = "GetNamePlateTokenByGUID" },
    { name = "older DLL without frame GUID", shape = { lookup = "global" }, mode = "UnitTokenFromGUID" },
}

for _, case in ipairs(supported) do
    test(case.name .. " registers and consumes plate events", function()
        local f = fixture(case.shape)
        local scanner = f.addon.TalentScanner
        local mode = scanner:DetectAwesomeWotlk()
        check(mode == case.mode, "wrong lookup mode: " .. tostring(mode))
        check(scanner:SetPlateUnits(true), "supported client mode was not enabled")
        check(scanner.plateMode == case.mode, "published plate mode differs")
        check(#f.frames == 2, "nameplate event frame was not allocated")

        local plateFrame = f.frames[2]
        check(plateFrame.events.NAME_PLATE_UNIT_ADDED, "NAME_PLATE_UNIT_ADDED not registered")
        check(plateFrame.events.NAME_PLATE_UNIT_REMOVED, "NAME_PLATE_UNIT_REMOVED not registered")
        check(type(plateFrame.scripts.OnEvent) == "function", "nameplate event handler missing")

        local guid = "0x00000000000000AB"
        f.units.nameplate1 = { player = true, guid = guid, class = "MAGE", name = "Visible Mage" }
        plateFrame.scripts.OnEvent(plateFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
        check(f.added() == 1, "plate event did not publish the visible player's class")
        check(scanner:PlateUnitForGUID(guid) == "nameplate1", "GUID did not resolve to the exact live plate token")

        if case.mode == "events" then
            plateFrame.scripts.OnEvent(plateFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
            f.units.nameplate1 = nil
            check(scanner:PlateUnitForGUID(guid) == nil, "removed plate retained a stale GUID mapping")
        end
    end)
end

test("ownerless zero GUIDs are rejected", function()
    local f = fixture({ lookup = "global", frameGUID = true })
    local scanner = f.addon.TalentScanner
    check(scanner:SetPlateUnits(true), "API 40 fixture was not enabled")
    check(scanner:PlateGUID({ guid = "0x0000000000000000" }) == nil, "full zero GUID was accepted")
    check(scanner:PlateGUID({ guid = "0x0" }) == nil, "short zero GUID was accepted")
    check(scanner:PlateGUID({ guid = "" }) == nil, "empty GUID was accepted")
    check(scanner:PlateGUID({ guid = "0x00000000000000AB" }) == "0x00000000000000AB", "valid GUID was rejected")
end)

print(string.format("%d awesome_wotlk compatibility tests passed", passed))
