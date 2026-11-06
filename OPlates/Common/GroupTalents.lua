local _, addon = ...
-- Wire-compatible subset of LibGroupTalents-1.0 revision 65. No LibStub
-- registration, shared-library mutation, inspect worker, or tooltip dependency.
local PREFIX = "LibGroupTalents-1.0"
local frame = CreateFrame("Frame")
local roster, peers, outbox, sent = {}, {}, {}, {}
local nextRoster, nextSend, broadcastAt, nextHello = 0, 0, nil, 0
local channel

local function D(text, ...)
    if addon.DebugLog then addon:DebugLog("GROUP", text, ...) end
end
local function FullName(unit)
    local name, realm = UnitName(unit)
    if not name then return end
    return realm and realm ~= "" and name .. "-" .. realm or name
end
local function CRC(text)
    -- the extra parentheses keep only the build number. Without them the
    -- build date became tonumber's base and every TALENTS message errored.
    local value = tonumber((select(2, GetBuildInfo())))
    if not value then return end
    for i = 1, #text do value = (value * 2 + text:byte(i)) % 65536 end
    return value
end
local function Enqueue(message, target, key)
    if not channel or #message > 240 then return end
    key = key or (target or channel) .. ":" .. message:match("^%a+")
    if sent[key] and GetTime() - sent[key] < 5 then return end
    sent[key] = GetTime()
    outbox[#outbox + 1] = { message, target, target and roster[target] and roster[target].guid }
end
local function SelfTalents()
    local guid = UnitGUID("player")
    local _, class = UnitClass("player")
    local groups = GetNumTalentGroups and GetNumTalentGroups() or 1
    local active = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    if not guid or not guid:match("^0x%x+$") or not class or groups < 1 or groups > 2 then return end
    local payload = string.format("%X,%d,%s,%d,%d", tonumber(guid:sub(7), 16), UnitLevel("player"), class, active, groups)
    for group = 1, groups do
        local trees = {}
        for tab = 1, 3 do
            local ranks = {}
            -- 3rd argument is "pet"; passing the group read the (empty) pet tree.
            local count = GetNumTalents(tab, false, false)
            if not count or count < 1 then return end
            for i = 1, count do
                local _, _, _, _, rank = GetTalentInfo(tab, i, false, nil, group)
                if type(rank) ~= "number" or rank < 0 or rank > 5 then return end
                ranks[i] = tostring(rank)
            end
            trees[tab] = table.concat(ranks)
        end
        payload = payload .. ";" .. group .. "," .. table.concat(trees, "-")
    end
    return "TALENTS " .. payload .. ";" .. CRC(payload)
end
local function SendSelf(target)
    local message = SelfTalents()
    if not message then return end
    if target then Enqueue(message, target)
    else for name in pairs(peers) do if roster[name] then Enqueue(message, name) end end end
end
local function UpdateRoster()
    local raid = GetNumRaidMembers() or 0
    local party = GetNumPartyMembers() or 0
    if raid == 0 and party == 0 then
        roster, peers, outbox, sent = {}, {}, {}, {}
        channel, broadcastAt, nextHello = nil, nil, 0
        return
    end
    local _, instance = IsInInstance()
    channel = instance == "pvp" and "BATTLEGROUND" or raid > 0 and "RAID" or "PARTY"
    local current, changed = {}, false
    for i = 1, raid > 0 and raid or party do
        local unit = (raid > 0 and "raid" or "party") .. i
        local name, guid = FullName(unit), UnitGUID(unit)
        if name and guid and not UnitIsUnit(unit, "player") then
            current[name] = { unit = unit, guid = guid }
            if not roster[name] or roster[name].guid ~= guid then peers[name] = nil; changed = true end
        end
    end
    for name in pairs(roster) do if not current[name] then peers[name] = nil; changed = true end end
    roster = current
    if changed or GetTime() >= nextHello then
        Enqueue("HELLO 65")
        nextHello = GetTime() + 30
    end
    for name, peer in pairs(peers) do
        if roster[name] and GetTime() >= peer.nextRequest then
            Enqueue("REQUESTTALENTS", name)
            peer.nextRequest = GetTime() + 30
        end
    end
end
local function Decode(payload, entry)
    local body, checksum = payload:match("^(.*);(%d+)$")
    if not body or CRC(body) ~= tonumber(checksum) then return end
    local header = body:match("^([^;]+)")
    local id, level, class, active, groups = header:match("^(%x+),(%d+),([A-Z]+),([12]),([12])$")
    if not id then return end
    local guid
    if #id < 12 then guid = string.format("%s%012X", UnitGUID("player"):sub(1, 6), tonumber(id, 16))
    elseif #id <= 15 then guid = "0x0" .. string.rep("0", 15 - #id) .. id end
    local _, liveClass = UnitClass(entry.unit)
    if not guid or guid:lower() ~= entry.guid:lower() or UnitGUID(entry.unit) ~= entry.guid
        or class ~= liveClass or tonumber(active) > tonumber(groups) then return end
    local liveLevel = UnitLevel(entry.unit)
    if liveLevel and liveLevel > 0 and liveLevel ~= tonumber(level) then return end
    local selected, seen = nil, {}
    for segment in body:gmatch(";([^;]+)") do
        -- LibGroupTalents trims trailing zero ranks, so an unused tree is empty ("1,-5302..-0055").
        local group, a, b, c = segment:match("^([12]),([0-5]*)%-([0-5]*)%-([0-5]*)$")
        if not group or seen[group] or tonumber(group) > tonumber(groups) then return end
        seen[group] = true
        if #a > 40 or #b > 40 or #c > 40 then return end
        if group == active then selected = { a, b, c } end
    end
    if not selected then return end
    local points, total = {}, 0
    for tab = 1, 3 do
        local sum = 0
        for rank in selected[tab]:gmatch("%d") do sum = sum + tonumber(rank) end
        points[tab], total = sum, total + sum
    end
    if total > math.max(0, tonumber(level) - 9) then return end
    local feralKind
    if class == "DRUID" and addon.ClassifyFeralRanks then
        feralKind = addon.ClassifyFeralRanks(function(index) return tonumber(selected[2]:sub(index, index)) or 0 end)
    end
    addon.TalentScanner:ReceiveGroupTalents(entry.unit, points, nil, feralKind)
    if addon._debugEnabled then D("RECEIVED guid=%s class=%s active=%s", entry.guid, class, active) end
end
for _, event in ipairs({ "CHAT_MSG_ADDON", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE" }) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
    if event ~= "CHAT_MSG_ADDON" then
        nextRoster = 0
        UpdateRoster() -- clear queued sends synchronously on group departure
        if event == "PLAYER_TALENT_UPDATE" then broadcastAt = GetTime() + 5.1 end
        return
    end
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 255 then return end
    UpdateRoster()
    local entry = roster[sender]
    if not entry or not UnitIsConnected(entry.unit) then return end
    local command, payload = message:match("^(%a+)%s*(.*)$")
    if command == "HELLO" and tonumber(payload) then
        peers[sender] = peers[sender] or { nextRequest = 0 }
        if distribution ~= "WHISPER" then Enqueue("HELLO 65", sender) end
        Enqueue("REQUESTTALENTS", sender)
        peers[sender].nextRequest = GetTime() + 30
        SendSelf(sender)
    elseif command == "REQUESTTALENTS" then
        peers[sender] = peers[sender] or { nextRequest = 0 }
        SendSelf(sender)
    elseif command == "TALENTS" then
        Decode(payload, entry)
    end
end)
frame:SetScript("OnUpdate", function()
    if not addon.TalentScanner or not addon.TalentScanner._initialized then return end
    local now = GetTime()
    if now >= nextRoster then nextRoster = now + 2; UpdateRoster() end
    if channel and broadcastAt and now >= broadcastAt then broadcastAt = nil; SendSelf() end
    if now >= nextSend and #outbox > 0 then
        nextSend = now + 0.15
        local item = table.remove(outbox, 1)
        local entry = item[2] and roster[item[2]]
        if channel and (not item[2] or (entry and entry.guid == item[3] and UnitIsConnected(entry.unit))) then
            SendAddonMessage(PREFIX, item[1], item[2] and "WHISPER" or channel, item[2])
        end
    end
end)
