# Release Guide

This guide is for the OPlates maintainer.

## 1. Prepare the source

- Update `## Version` in `OPlates/OPlates.toc`.
- Move completed entries from **Unreleased** into a dated section in `CHANGELOG.md`.
- Confirm all official links use `https://github.com/FreakySphere/OPlates`.
- Confirm the Support link uses `https://reymit.ir/FreakySphere`.
- Review branding and designated asset changes against `BRANDING.md`.

## 2. Validate

- Load the addon on a clean WoW 3.3.5a client.
- Test `/op`, `/oplates` and `/op classic`.
- Test friendly and enemy icons, Class/Spec Filters, Healer CC, profiles and the minimap button.
- Test stock-client behavior.
- Test the FreakySphere `awesome_wotlk` integration separately; when relevant, also test supported legacy lookup modes.
- Run `lua5.1 tests/awesome_wotlk_compat.lua` from the repository root.
- Confirm there are no Lua errors and no unexpected saved-variable reset.
- Review repository links and Markdown files.

## 3. Check the package layout

The release ZIP must contain exactly one top-level addon folder:

```text
OPlates-v1.00.zip
└── OPlates\
    ├── OPlates.toc
    └── ...
```

Do not include repository documents, `.github`, development scripts, saved variables, logs or test artifacts inside the installable `OPlates` folder.

Optional local PowerShell example from the repository root:

```powershell
Compress-Archive -Path .\OPlates -DestinationPath .\OPlates-v1.00.zip
```

Inspect any local archive before publishing. The GitHub release workflow independently builds and verifies the public archive from the tagged source.

## 4. Publish on GitHub

1. Commit and push the release source and documents to `main`.
2. Wait for the **Validate** workflow to pass.
3. Create an annotated tag such as `v1.00` on the validated commit.
4. Push the tag.
5. The **Release** workflow verifies that the tag matches the TOC, checks Lua syntax, builds `OPlates-v1.00.zip`, creates a SHA-256 checksum, and publishes both files to a GitHub release.
6. Review the generated release notes and edit them to match the corresponding `CHANGELOG.md` section if needed.

If GitHub Actions are unavailable, create the release manually using the locally verified ZIP and checksum.

## 5. Verify the public release

- Download the published ZIP as a user would.
- Verify its folder layout.
- Install it on a clean client.
- Confirm the version shown in `/op`.
- Confirm README badges and release links resolve.
- Keep the release ZIP unchanged after publication; publish a new version for corrections.
