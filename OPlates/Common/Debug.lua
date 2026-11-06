local _, addon = ...

-- OFF at every login. Runtime flag only (never saved); /op debug on or
-- Misc > "Enable debug logging" turns it on for this session.
addon._debugEnabled = false
addon._debugSeq = 0
addon._debugSession = addon._debugSession or 0
addon._debugCompact = true

local function Safe(v)
    if v == nil then return "nil" end
    if type(v) == "boolean" then return v and "true" or "false" end
    return tostring(v)
end

function addon:DebugLog(tag, msg, ...)
    if not self._debugEnabled then return end
    self._debugSeq = (self._debugSeq or 0) + 1
    local ok, text = pcall(string.format, msg or "", ...)
    if not ok then text = tostring(msg) end
    local stamp = GetTime and string.format("%.3f", GetTime()) or "?"
    local line = string.format("[OPDBG #%04d t=%s %s] %s", self._debugSeq, stamp, Safe(tag), text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    elseif self.Print then
        self:Print(line)
    end
end

function addon:DebugReset(reason)
    self._debugSession = (self._debugSession or 0) + 1
    self._debugSeq = 0
    self:DebugLog("SESSION", "reset session=%d reason=%s", self._debugSession, tostring(reason or "manual"))
end

function addon:SetDebug(on, reason)
    on = on and true or false
    if on == (self._debugEnabled == true) then return end
    if on then
        self._debugEnabled = true
        self:DebugReset(reason or "enabled")
        self:DebugLog("CMD", "Detailed OPlates debug logging ENABLED (%s)", tostring(addon.addonTitle))
    else
        self:DebugLog("CMD", "Detailed OPlates debug logging DISABLED")
        self._debugEnabled = false
    end
    if OPlates and OPlates.NotifyOptions then OPlates:NotifyOptions() end
end
