# Contributing to OPlates

Thank you for helping improve OPlates. Focused bug fixes, 3.3.5a-compatible features, performance improvements, documentation fixes and artwork improvements are welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md) and the project’s [license](LICENSE).

## Before you begin

1. Search [existing issues](https://github.com/FreakySphere/OPlates/issues).
2. Open a feature request before investing in a large change.
3. Keep one pull request focused on one problem.
4. Test on a World of Warcraft 3.3.5a client.

## Project identity and assets

All source-code contributions are distributed under GPL-3.0-or-later. Preserve truthful copyright, authorship, license and third-party notices.

The official project identity and designated Logo/Support assets are governed by [`BRANDING.md`](BRANDING.md). A fork may exercise all GPL rights in the code, but must not impersonate an official OPlates release or falsely attribute its changes to FreakySphere.

## Technical boundaries

- Target Lua 5.1 and the WoW 3.3.5a API (`Interface 30300`).
- Do not introduce Retail-only or modern Classic APIs.
- Keep the addon compatible with a stock client.
- Treat FreakySphere and compatible legacy `awesome_wotlk` integration as optional; preserve stock-client behavior.
- Do not replace or globally override inspection functions.
- Avoid reading private caches owned by unrelated addons.
- Preserve Blizzard secure-action rules for in-combat click buttons.
- Keep Feral role behavior consistent: an assigned Tank role wins; otherwise talents decide Bear or Cat behavior.
- Do not modify bundled libraries unless the change specifically requires it and their upstream license is followed.

## Style

- Match the surrounding Lua style and naming.
- Prefer small, reviewable changes.
- Explain non-obvious 3.3.5a compatibility work in comments.
- Keep user-facing text concise and clear.
- Do not add generated build output, saved variables, logs or editor files.

## Testing

Before opening a pull request:

1. Start with a clean OPlates folder.
2. Verify `/op` and `/op classic` open without Lua errors.
3. Test both friendly and enemy plates.
4. Test stock, FreakySphere, and relevant compatible legacy `awesome_wotlk` modes when your change affects unit discovery.
5. Test relevant behavior in combat and out of combat.
6. Reload the UI and relog to check saved settings.
7. Confirm the minimap icon and profile operations still work.
8. Include exact reproduction steps and results in the pull request.

## Pull requests

Use the pull-request template. Describe:

- the problem;
- the cause;
- what changed;
- how you tested it;
- any performance or compatibility impact;
- screenshots for visible UI changes.

Submitting a contribution means you have the right to provide it and agree that it may be distributed under GPL-3.0-or-later.
