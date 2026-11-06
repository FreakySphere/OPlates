# Installing OPlates

OPlates is built exclusively for **World of Warcraft: Wrath of the Lich King 3.3.5a** (`Interface 30300`).

## Fresh installation

1. Download the latest `OPlates-vX.XX.zip` file from [GitHub Releases](https://github.com/FreakySphere/OPlates/releases/latest).
2. Exit World of Warcraft completely.
3. Open your 3.3.5a game directory.
4. Open `Interface`, then `AddOns`.
5. Extract or copy the `OPlates` folder into `AddOns`.

The final layout must be:

```text
World of Warcraft\
└── Interface\
    └── AddOns\
        └── OPlates\
            ├── OPlates.toc
            ├── Core.lua
            ├── Art\
            ├── Common\
            ├── Libs\
            ├── Locales\
            ├── Misc\
            ├── Nameplates\
            ├── Profiles\
            └── UI\
```

6. Start the game.
7. On the character-selection screen, open **AddOns** and make sure **OPlates** is enabled.
8. Log in and type `/op`.

## Common folder mistake

This layout is wrong:

```text
Interface\AddOns\OPlates\OPlates\OPlates.toc
```

Move the inner `OPlates` folder up one level so `OPlates.toc` sits directly inside `Interface\AddOns\OPlates`.

## Updating

1. Exit the game.
2. Back up `WTF` if you want an extra safety copy of all addon settings.
3. Delete the old `Interface\AddOns\OPlates` folder.
4. Install the new `OPlates` folder from the release archive.
5. Start the game and check the version in `/op`.

Deleting the addon folder does **not** delete your settings. Do not delete the `WTF` folder unless you intentionally want to reset saved data.

## Uninstalling

1. Exit the game.
2. Delete `Interface\AddOns\OPlates`.
3. Optional: remove the `OPlatesDB` and `OPlatesTalentDB` entries from your account’s saved-variable files if you also want to erase settings and learned specialization data.

## Optional `awesome_wotlk` integration

OPlates works without a client patch. The optional [FreakySphere `awesome_wotlk` patch](https://github.com/FreakySphere/awesome_wotlk/releases/latest) exposes supported nameplate units sooner, allowing visible player information to appear without requiring mouseover in many situations. OPlates also recognizes supported legacy API shapes, including KhalGH-compatible nameplate units.

The client patch is a separate project and modifies the game client. Download it only from its official release page, review its documentation, keep backups, and follow its own installation instructions. OPlates does not install or remove the patch; it only detects compatible support and offers the option under **Advanced**.

## Troubleshooting installation

- **Not listed:** verify the folder layout and client version.
- **Marked out of date:** verify `OPlates.toc` says `## Interface: 30300` and that you are using a 3.3.5a client.
- **Settings do not open:** type `/op`, then try `/op classic`.
- **Corrupted update:** delete the addon folder and install a clean release instead of merging folders.

For runtime bugs, use the [bug-report form](https://github.com/FreakySphere/OPlates/issues/new?template=bug_report.yml).
