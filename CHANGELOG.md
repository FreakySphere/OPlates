# Changelog

All notable public changes to OPlates are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). OPlates uses public release numbers beginning with `1.00`.

## [Unreleased]

No public changes yet.

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
