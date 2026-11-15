local _, addon = ...

---------------------------------------------------------------------------
-- Combat log keep-alive (3.3.5a)
--
-- This client stops delivering COMBAT_LOG_EVENT_UNFILTERED once its combat log
-- fills up, and it only recovers on a loading screen. Everything that reads the
-- log then goes blind: our crowd control, enemy specs and flag carriers, and
-- other addons' parsers too. That is why a long Arathi Basin goes quiet while a
-- freshly entered instance works again.
--
-- Clearing the log periodically is the long-standing workaround; Skada ships it
-- as "Combat Log Fix" ("Keeps the combat log from breaking"), and DBM and
-- PlateBuffs call it as well. We only clear once the log is close to full, so a
-- player who actually reads the combat log keeps their scrollback.
--
-- Measured in Eye of the Storm: ~60 log entries per second, so a 15 s check let
-- the log reach 1147 entries before it was cleared. Checking every 5 s and
-- clearing above 400 caps the peak near 600 instead, and in quiet play the log
-- never reaches 400 at all, so it is left alone.
local COMBATLOG_SOFT_CAP = 400
-- How often the watchdog looks. This is what decides how long a stall stays
-- unnoticed: the clear happens on the first tick after the threshold, so the
-- real delay is the threshold rounded UP to this step. At 5 s the delay ranged
-- 10-15 s for a 10 s threshold; at 2 s it ranges 8-10 s for an 8 s threshold,
-- and the near-full peaks drop too because the cap is checked more often.
local COMBATLOG_CHECK_EVERY = 2
-- Silence watchdog. The entry counter cannot be trusted to notice a stall: a
-- capture recorded it reporting 32, 23 and 202 entries while the log had already
-- stopped delivering, so the 400 threshold could never fire and events sat at
-- 0.2 per second for 304 seconds. A live battleground always has combat traffic,
-- so silence itself is the signal.
--
-- 8 s rather than 10: a false clear costs almost nothing (the combat log's
-- scrollback, which nobody reads mid-fight), while a missed second can swallow a
-- whole 6 s stun. The cooldown still caps it at two clears a minute.
local COMBATLOG_SILENT_AFTER = 8
local COMBATLOG_SILENT_COOLDOWN = 30

-- Pure decision, so the rule can be tested without a client.
--   "cap"     the log is close to full
--   "silence" nothing has arrived for a while inside a battleground
--   nil       leave it alone
--
-- lastSilence is the time of the previous SILENCE clear, not of any clear. A
-- near-full clear means the log was healthy a moment ago, so it must not delay
-- the watchdog: a capture showed a stall beginning right after one, and the
-- shared timestamp kept it blind for the whole 30 s cooldown.
addon.CombatLogWatch = function(now, lastEvent, lastSilence, entries, inPvP)
    if entries and entries >= COMBATLOG_SOFT_CAP then return "cap" end
    if not inPvP then return nil end
    if not lastEvent then return "silence" end        -- nothing has ever arrived
    if now - lastEvent < COMBATLOG_SILENT_AFTER then return nil end
    if lastSilence and lastSilence > 0 and now - lastSilence < COMBATLOG_SILENT_COOLDOWN then return nil end
    return "silence"
end

do
    local clear = CombatLogClearEntries
    local count = CombatLogGetNumEntries
    if type(clear) == "function" and type(count) == "function" then
        local frame = CreateFrame("Frame")
        local startedAt = GetTime()
        local elapsed, lastSilence = 0, 0
        frame:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < COMBATLOG_CHECK_EVERY then return end
            elapsed = 0
            local now = GetTime()
            local ok, entries = pcall(count, true)
            if not ok or type(entries) ~= "number" then entries = nil end
            local inPvP = addon.IsInPvPInstance and addon.IsInPvPInstance() or false
            local why = addon.CombatLogWatch(now, addon._cleuLastAt or startedAt, lastSilence, entries, inPvP)
            if not why then return end
            if addon._debugEnabled then
                if why == "cap" then
                    addon:DebugLog("CLEU", "combat log near full (%d entries) - cleared so events keep flowing", entries)
                else
                    addon:DebugLog("CLEU", "no events for %.0fs in a PvP instance (counter says %s) - cleared, the log had stalled",
                        now - (addon._cleuLastAt or startedAt), entries and tostring(entries) or "unreadable")
                end
            end
            pcall(clear)
            if why == "silence" then lastSilence = now end
        end)
    end
end
