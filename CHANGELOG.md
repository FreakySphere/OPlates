# Changelog

All notable public changes to OPlates are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). OPlates uses public release numbers beginning with `1.00`.

## [1.20] - 2026-11-20

**This is the biggest update OPlates has had.** It remembers players, reads hybrid builds properly, follows druid forms, and the crowd-control layer was audited spell by spell.

### Added

- **Class/Spec Memory.** Class, spec and role are stored per player, per side, and come back after `/reload`, logout and login. Separate SavedVariables, its own Delete button, and turning the option off never wipes anything.
- **Spec Guessing.** Shared spells — Fireball, Shadow Word: Pain, Sinister Strike — fill in a spec the combat log cannot prove. Switchable per side; a real read locks it.
- **Hybrid builds.** The deepest talent tree names the spec: Preg 0/28/43 is Retribution, rogue 38/33 is Assassination, DK 43/26/2 is Blood. Builds nobody plays no longer weaken the model.
- **Druid forms.** Moonkin Form is Balance, Tree of Life is Restoration, and a feral talent build keeps cat or bear through every shapeshift.
- **`?` is off by default.** A fresh install draws no question mark. It locks itself when no class/spec/healer/tank icon is enabled, and never appears on pets.

### Fixed

- A buff that shares a CC name (Mage Impact) no longer draws a stun on the mage or advances his stun DR.
- The DR window now runs from the CC's removal, and a refresh keeps its step.
- Slider fillers draw at the right width the first time an options page opens.
- Removed a duplicate refresh on target change.

### Changed

- New defaults: pet 0.5, flag 2.0, healer 1.5 on both sides; enemy offset 11; enemy name off; Healer CC 65 / 400 / 115.
- `OPlatesSpecMemory` is now a SavedVariable.

## [1.14] - 2026-11-15

### Fixed

- **Battlegrounds going quiet partway through a match.** The 3.3.5a combat log stops delivering `COMBAT_LOG_EVENT_UNFILTERED` once it fills, and only recovers on a loading screen — so everything that reads it goes blind. 1.13 tried to prevent that by clearing the log above 400 entries, but the counter it relied on cannot be trusted: in a capture it reported **32, 23 and 202 entries while the log had already stopped delivering**, so the threshold never fired and a match sat at 0.2 events per second for 304 seconds. OPlates now watches for *silence* instead. No combat-log event for 8 seconds inside a battleground means the log has stalled, whatever the counter claims, and it is cleared. The check runs every 2 seconds, so a stall is caught in 8–10 seconds rather than never. Measured across three battlegrounds since: 99–126 clears per match, **zero stalls**.
- **Two players with the same name.** A plate with no GUID can only be matched by short name, and `Bob-Icecrown` and `Bob-Blackrock` are both `Bob`. The old map held one GUID per name and marked the name unusable on a collision, which broke the lookup for **both** players; the fallback then took whichever match it happened to iterate first, which could put one player's stun on the other. The map is now a set of candidates, narrowed by class, and used only when exactly one survives. A name that stays ambiguous draws nothing — a missing icon is a nuisance, an icon on the wrong player is a lie.

### Changed

- **No external library in the detection path.** Seven call sites used the `bit` library for combat-log flags, three of them unguarded — a client without `bit` would have thrown inside the combat-log handler, silently costing every crowd-control icon and every enemy spec. The flag tests are now plain arithmetic, so OPlates no longer depends on `bit`, `!!!ClassicAPI` or any other library to detect players, crowd control or specs.
- Every crowd-control entry now carries the class it landed on, so the by-name fallback can narrow by class too.

### Debug

- The lookup line only reports real decisions now. It used to log the "nothing to draw" case as well, which was 3684 of 3826 lines in one capture and pushed the useful ones out of the chat scrollback.
- `AURAPICK` reports the candidates it saw, the player it chose and why, so a wrong icon can be traced to a specific rule.
- The stall line records what the entry counter claimed at that moment, which is how the counter's unreliability was confirmed in the first place.
- The plate retry line is throttled to two per second per player; it was 1557 lines in a single Alterac Valley.

### Compatibility

- Verified against a stock 3.3.5a client with no patches and no `!!!ClassicAPI`.
- The signature table is unchanged at 369 spells, and the single-candidate name path is untouched, so everything 1.13 achieved for enemy specs and crowd control is preserved.

## [1.13] - 2026-11-15

### Added

- **Enemy spec detection from 369 signature spells, up from 72.** Every entry is a talent at row 5 or deeper, so no other spec of that class can reach it, and every one was checked against the client's own `Talent.dbc`, `TalentTab.dbc`, `Spell.dbc` and `SkillLineAbility.dbc`. Coverage went from 1–3 spells per spec to 10–15, which is the difference between recognising a player only when he presses a long cooldown and recognising him from ordinary casts. Names shared by two specs, and names learnable by another class, were dropped rather than guessed at.
- **A respec is now visible while you watch.** An enemy who changes spec in the open world or in Wintergrasp switches icon on the first signature spell of his new spec. Battlegrounds were never affected: the spec cache is wiped on every loading screen.
- **`Warmane: patch not allowed`** in the top-right corner of the settings window, in the **Advanced** tab, and in every login banner. Servers that forbid client modifications are not compatible with `awesome_wotlk` or any client patch, and the addon now says so instead of quietly recommending one.

### Changed

- **The unpatched warning is a first-run notice.** It used to appear on every login and every reload, which is noise for anyone on a server where client patches are forbidden — and an unpatched client is a fully supported setup. It now shows once per account and never again. The green "patch detected" banner is likewise once ever. The `DISABLED` prompt still asks every login, because it only reaches players who installed the patch and then switched the option off.
- **The chat line is separate from the banner.** One short line per login reports the patch state and the Warmane note, whatever the banner decided to do.
- **Signature strength is now the talent row (5–10)** instead of a hand-assigned 1 or 2, so the value is mechanical and auditable. Depth still decides between hints that agree on a spec: Devastate can no longer downgrade Shockwave.
- **A different spec of the same class replaces the stored one immediately**, but only from row 8 or deeper. A player cannot use another tree's talent without having the points in it, so a cross-spec signature means he respecced just now — but a 25-point hybrid talent was being read as a respec and could flip a warlock between Demonology and Affliction mid-fight. Row 8 is 40 points, which a hybrid build does not reach.
- Status text in the settings window no longer prints the detection proof: `awesome_wotlk patch: detected`, not `detected (native UnitTokenFromGUID)`.

### Fixed

- **Enemy crowd control and specs going quiet in long battlegrounds.** The 3.3.5a combat log stops delivering `COMBAT_LOG_EVENT_UNFILTERED` once it fills, and only recovers on a loading screen, so everything that reads it goes blind partway through a match. OPlates now clears the log when it holds 400 or more entries, checked every 5 seconds. In testing this recovered a 304-second stall in Arathi Basin where delivery had fallen to 0.2 events per second, and held 40–100 events per second for the rest of the match. The threshold is deliberate: a blind 2-second clear, which other addons use, would throw away the scrollback of anyone who actually reads the combat log.

### Debug

- A throughput line every 10 seconds, `[CLEU] rate N events/s`, and a line whenever the log is cleared, so a silent capture can be told apart from a delivery problem.
- `AURAKEY` now reports both lookup paths and both sides. It previously only logged plates with no GUID, which is why hostile lookups never appeared in a capture.

## [1.12] - 2026-11-11

### Fixed

- **Enemy crowd control and specs on Warmane.** The combat log's player flag (`0x400`) is now the authority for "is this a player", instead of assuming every player GUID starts with `0x0000`. Warmane hands out `0x06`, `0x07` and `0x0A`, so every combat-log gate rejected its players: no CC icons, no enemy specs from casts, and no group spec hints for Healer-in-CC. Five separate gates had the same assumption.
- **Enemy CC on plates that have never been hovered.** A plate without a GUID could not find its CC when the name map had not caught up yet. Every CC now carries the short name it was applied to, and the plate falls back to the CC store when the map misses.
- **Empty vehicles drawn as pets.** A player riding a cannon or demolisher occupies his pet token, so the vehicle's name entered the pet-name set — and from then on every empty vehicle on the field was painted with a pet icon. Vehicles (`0xF15`) are now excluded from that set, from the pet test, and from rendering entirely.

### Added

- Debug output for crowd control, the combat log, the name map and the plate lookup, all behind the existing debug toggle.

## [1.11] - 2026-11-10

### Fixed

- **Startup error on a clean client.** `Profiles/Helpers.lua` called `EnableResize` on an AceGUI frame that does not provide it, and `SetClipsChildren`, which is not a 3.3.5a frame method at all. Either one aborted initialisation, so the settings table was never registered (`/op` did nothing) and an empty Import window was left on screen. Both calls are now guarded, and the bundled AceGUI Frame widget gained the missing `EnableResize` method so the dialogs stay fixed-size.
- **Enemy icons disappearing after hover or target.** On servers whose player GUIDs do not begin with `0x0000`, the NPC guard treated those plates as creatures and hid them as soon as a GUID was bound — which is exactly when you hovered or targeted. Playerhood is now proven by any of: a player-shaped GUID, a class-coloured bar, a cached identity, or a plate already drawn as a player.

## [1.10] - 2026-11-09

### Added

- **Reset window** slider under **Advanced**, 15–20 seconds. The diminishing-returns window is decided by the server and drifts between roughly 15 and 20 seconds, so the crowd-control estimate is now tunable instead of fixed. Lower it if icons keep showing a reduced duration after the effect should have reset; raise it if they snap back to full too early.

### Changed

- Diminishing-returns reset window now defaults to 18.1 seconds instead of 20, which is closer to what the window actually measures on a live server.

## [1.00] - 2026-11-05

### Added

- First public release of OPlates for World of Warcraft: Wrath of the Lich King 3.3.5a.
- Circular class, specialization, healer, tank, pet and flag-carrier icons for friendly and enemy nameplates.
- Independent icon modes and visibility rules for friendly and enemy plates.
- Live crowd-control icon replacement with colored countdowns and diminishing-return-aware estimates.
- Custom buff and debuff spell-ID lists for each side.
- Friendly and enemy Class Filters and Spec Filters.
- Optional player names below icons and names for players whose icons are hidden.
- Arena numbers for enemy players.
- Healer crowd-control alerts with sounds, movable positions, multiple alert slots and secure dispel/breaker buttons.
- Persistent specialization memory option and profile support.
- Optional integration with FreakySphere’s `awesome_wotlk` patch, supported legacy API shapes and stock-client fallback behavior.
- Compatible nameplate event handling for global and table-based GUID-to-unit lookup modes.
- Ownerless zero-GUID rejection so recycled nameplate slots are never treated as players.
- Themed settings window, classic settings fallback and minimap button.
- Built-in troubleshooting commands and session-only debug logging.
- Complete localized addon summaries for supported client locales.

[Unreleased]: https://github.com/FreakySphere/OPlates/compare/v1.00...HEAD
[1.00]: https://github.com/FreakySphere/OPlates/releases/tag/v1.00
