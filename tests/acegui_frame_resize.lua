-- Regression test for the Warmane crash:
--   ..\AddOns\OPlates\Profiles\Helpers.lua:154: attempt to call method 'EnableResize' (a nil value)
--
-- Two things are asserted:
--   1. the bundled AceGUI Frame widget now provides EnableResize (backport of upstream v30)
--   2. Profiles/Helpers.lua guards the call, so an older AceGUI supplied by another addon
--      cannot take the whole addon down again
--
--   usage: lua5.1 tests/acegui_frame_resize.lua <addon root>

local root = arg and arg[1] or "OPlates"

-------------------------------------------------------------------- stub client
local function newObj()
    local o = { __calls = {} }
    setmetatable(o, {
        __index = function(t, k)
            local f = function(self)
                local c = rawget(self, "__calls")
                if c then c[k] = (c[k] or 0) + 1 end
                return self
            end
            rawset(t, k, f)
            return f
        end,
    })
    return o
end

CreateFrame = function() return newObj() end
UIParent = newObj()
CLOSE = "Close"
GetLocale = function() return "enUS" end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

-- 3.3.5a string aliases that LibStub and AceGUI expect
strmatch, strfind, strsub = string.match, string.find, string.sub
strlower, strupper, strrep = string.lower, string.upper, string.rep
gsub, gmatch, format = string.gsub, string.gmatch, string.format
tinsert, tremove = table.insert, table.remove
floor, ceil, abs = math.floor, math.ceil, math.abs
max, min = math.max, math.min

local function load(rel)
    local chunk = assert(loadfile(root .. "/" .. rel))
    chunk()
end

load("Libs/LibStub/LibStub.lua")
load("Libs/AceGUI-3.0/AceGUI-3.0.lua")
load("Libs/AceGUI-3.0/widgets/AceGUIContainer-Frame.lua")

local AceGUI = assert(LibStub("AceGUI-3.0", true), "AceGUI did not register")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-42s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-42s %s", label, tostring(got)))
    end
end

-------------------------------------------------------------------- 1. the widget
check("Frame widget registered", AceGUI:GetWidgetVersion("Frame") ~= nil, true)

local w = AceGUI:Create("Frame")
assert(w, "could not create a Frame widget")

check("widget has EnableResize", type(w.EnableResize), "function")
check("widget exposes sizers", type(w.sizer_se) == "table" and type(w.sizer_s) == "table" and type(w.sizer_e) == "table", true)

-- calling it must not raise, and must actually hide the three sizers
local ok, err = pcall(function() w:EnableResize(false) end)
check("EnableResize(false) does not raise", ok, true)
if not ok then print("   " .. tostring(err)) end

check("sizer_se hidden", (w.sizer_se.__calls or {}).Hide, 1)
check("sizer_s hidden", (w.sizer_s.__calls or {}).Hide, 1)
check("sizer_e hidden", (w.sizer_e.__calls or {}).Hide, 1)

local ok2 = pcall(function() w:EnableResize(true) end)
check("EnableResize(true) does not raise", ok2, true)
check("sizer_se shown again", (w.sizer_se.__calls or {}).Show, 1)

-------------------------------------------------------------------- 2. the guard
local src = io.open(root .. "/Profiles/Helpers.lua"):read("*a")

local function guarded(name)
    -- `if ( name.EnableResize ) then` must appear before the call
    local pat = "if%s*%(%s*" .. name .. "%.EnableResize%s*%)%s*then"
    return src:find(pat) ~= nil
end

check("Helpers guards export dialog", guarded("export"), true)
check("Helpers guards import dialog", guarded("import"), true)

-- every call must sit inside a guard, so the two counts have to match
local function count(pat)
    local n, pos = 0, 1
    while true do
        local s, e = src:find(pat, pos)
        if not s then return n end
        n = n + 1
        pos = e + 1
    end
end

local function audit(method, expected)
    local calls  = count(":" .. method .. "%(")
    local guards = count("if%s*%(%s*[%w_%.]+%." .. method .. "%s*%)%s*then")
    check(method .. " call sites", calls, expected)
    check(method .. " guards", guards, expected)
    check(method .. " fully guarded", calls, guards)
end

audit("EnableResize", 2)
audit("SetClipsChildren", 2)

if failures > 0 then
    error(failures .. " check(s) failed")
end
print("\nall AceGUI resize checks passed")
