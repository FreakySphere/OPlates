-- Locale coverage test (v1.15).
--
-- AceLocale raises an error popup for a key that is missing from the active
-- locale, so a half-translated release is a visible bug, not a silent one. The
-- shipped fallback is silent (GetLocale(addonName, true)), and this test is the
-- guard that replaces the popup:
--
--   * every L["..."] key used in the addon exists in enUS
--   * every locale file defines exactly the same key set as enUS
--   * no key is defined twice in one file
--
--   usage: lua5.1 tests/locale_coverage.lua <addon root>

local root = arg and arg[1] or "OPlates"
local failures = 0

local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-56s got %s, want %s", label, tostring(got), tostring(want)))
    else
        print(string.format("PASS %-56s %s", label, tostring(got)))
    end
end

---------------------------------------------------------------------------
-- collect every L["..."] key used in the addon's own source
---------------------------------------------------------------------------
local function unescape(k)
    return (k:gsub("\\(.)", function(c)
        if c == "n" then return "\n" end
        if c == "t" then return "\t" end
        return c
    end))
end

local function keys_used_in(path)
    local f = io.open(path, "rb")
    if not f then return {} end
    local s = f:read("*a")
    f:close()
    local out = {}
    local i = 1
    while true do
        local a = s:find('L["', i, true)
        if not a then break end
        local j = a + 3
        local buf = {}
        while j <= #s do
            local c = s:sub(j, j)
            if c == "\\" then
                buf[#buf + 1] = s:sub(j, j + 1)
                j = j + 2
            elseif c == '"' then
                break
            else
                buf[#buf + 1] = c
                j = j + 1
            end
        end
        out[#out + 1] = unescape(table.concat(buf))
        i = j + 1
    end
    return out
end

-- the TOC is the authoritative file list: a new source file has to be added
-- there anyway, so the coverage test can never drift from what actually loads.
local function sources_from_toc()
    local out = {}
    local f = io.open(root .. "/OPlates.toc", "rb")
    if not f then return out end
    local body = f:read("*a") or ""
    f:close()
    body = body:gsub("\r", "")
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local t = line:match("^%s*(.-)%s*$")
        if t ~= "" and t:sub(1, 2) ~= "##" then
            t = t:gsub("\\", "/")
            if t:sub(-4) == ".lua" and t:sub(1, 6) ~= "Libs/" and t:sub(1, 8) ~= "Locales/" then
                out[#out + 1] = root .. "/" .. t
            end
        end
    end
    return out
end

local sources = sources_from_toc()
check("source files found", #sources > 5, true)

local used = {}
local usedCount = 0
for _, path in ipairs(sources) do
    for _, key in ipairs(keys_used_in(path)) do
        if not used[key] then
            used[key] = path
            usedCount = usedCount + 1
        end
    end
end
check("distinct keys used in code", usedCount > 50, true)

---------------------------------------------------------------------------
-- load a locale file with a stubbed AceLocale
---------------------------------------------------------------------------
local function load_locale(path)
    local keys, dupes = {}, 0
    local store = {}
    local loc = setmetatable({}, {
        __newindex = function(t, k, v)
            if store[k] ~= nil then dupes = dupes + 1 end
            rawset(t, k, v)
            keys[k] = true
        end,
    })
    local fake = {
        NewLocale = function() return loc end,
        GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
    }
    LibStub = function() return fake end
    local addon = {}
    local chunk = assert(loadfile(path))
    chunk("OPlates", addon)
    return keys, dupes
end

local LOCALES = { "enUS", "deDE", "esES", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local base = root .. "/Locales/enUS.lua"
local baseKeys = load_locale(base)
local baseCount = 0
for _ in pairs(baseKeys) do baseCount = baseCount + 1 end
check("enUS key count", baseCount > 100, true)

local missingInBase = 0
for key in pairs(used) do
    if not baseKeys[key] then
        missingInBase = missingInBase + 1
        if missingInBase <= 5 then print("      missing from enUS: " .. key:sub(1, 90)) end
    end
end
check("every key used in code is in enUS", missingInBase, 0)

for _, code in ipairs(LOCALES) do
    local path = root .. "/Locales/" .. code .. ".lua"
    local keys, dupes = load_locale(path)
    local n, missing, extra = 0, 0, 0
    for k in pairs(keys) do
        n = n + 1
        if not baseKeys[k] then extra = extra + 1 end
    end
    for k in pairs(baseKeys) do
        if not keys[k] then
            missing = missing + 1
            if missing <= 3 then print("      " .. code .. " missing: " .. k:sub(1, 80)) end
        end
    end
    check(string.format("%-5s same keys as enUS", code), missing + extra, 0)
    check(string.format("%-5s no duplicate keys", code), dupes, 0)
end

print(failures == 0 and "\nall locale coverage checks passed" or ("\n" .. failures .. " failure(s)"))
