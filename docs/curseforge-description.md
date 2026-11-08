# OPlates

### One circle. Every answer.

**The nameplate overlay that tells you who you are fighting — before you finish the thought.**

Built for **World of Warcraft: Wrath of the Lich King 3.3.5a**.

[![Latest release](https://img.shields.io/github/v/release/FreakySphere/OPlates?display_name=tag&sort=semver&style=flat-square&color=d4af37)](https://github.com/FreakySphere/OPlates/releases/latest) [![WotLK 3.3.5a](https://img.shields.io/badge/World%20of%20Warcraft-WotLK%203.3.5a-33aaff?style=flat-square)](https://github.com/FreakySphere/OPlates#-compatibility) [![License](https://img.shields.io/badge/license-GPL--3.0--or--later-d4af37?style=flat-square)](https://github.com/FreakySphere/OPlates/blob/main/LICENSE) [![Issues](https://img.shields.io/github/issues/FreakySphere/OPlates?style=flat-square&color=8f6ed5)](https://github.com/FreakySphere/OPlates/issues)

***

## ✨ The idea

Nameplate addons are very good at showing you **bars**. Health, resources, cast bars — all of it, beautifully.

None of them tell you **who** is behind the bar.

OPlates adds exactly one thing: a single **circular icon above every friendly and enemy player**, carrying the one piece of information you actually need in that half-second — their class, their spec, their role, the crowd control that just landed on them, or the buff you have been waiting for. The border is their class colour. Target them and it pulses yellow. That is the whole addon, and that is why it works.

> **It does not replace your nameplates.** TidyPlates, ThreatPlates, Kui Nameplates, NotPlater, ElvUI, etc — keep every bar, every font, every pixel of your setup. OPlates draws on top of it.

This entire idea was put forward and kept running by a project calling **[SweepyBoop's PvP Helper](https://www.curseforge.com/wow/addons/sweepyboops-pvp-helper)**, and since there was no compatible version for 3.3.5a, I decided to create a similar AddOn by myself.

***

## 📸 See it

**🟡 The plates** — one circle above every friendly and enemy player. Class, spec or role, your choice per side, inside a ring that is always their class colour.

![Friendly plates in Dalaran](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/friendly-icons.jpg)

_Friendly plates · Dalaran — warrior, shaman and two healers, each with their own circle_

**⚔️ In combat** — the same rule at full speed. The flag carrier is marked, the healers are crosses, everyone else is their class. You read the fight in one glance instead of hovering names.

![Enemy plates in Warsong Gulch](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/nameplates-combat-flag-2.jpg)

_Enemy plates · Warsong Gulch — flag carrier, healer and class icons at the same time_

**🎯 Target highlight** — target a player and their ring turns yellow and pulses. Switch away and it snaps straight back to their class colour, with no fade and no delay.

![Target highlight on an enemy healer](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/targeted-enemy-healer.jpg)

_Targeted enemy healer — the yellow ring follows your target_

**🌀 Crowd control, the instant it lands** — a stun lands and the class icon is gone, replaced by the CC icon with its remaining duration ticking down. The moment the effect ends, the class icon is back. Smart diminishing returns keep the timer honest, and priority decides what you see when effects overlap.

![Crowd control icon with a countdown](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/enemy-cc.jpg)

_Stun on an enemy — CC icon with a live countdown, back to class the instant it ends_

**🚨 Healer CC alerts** — a second layer, for your own group. When a healer gets controlled, an alert appears wherever you put it, with the countdown and an optional one-click dispel or breaker.

![Healer CC alert](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/healer-cc-alert.gif)

_Healer CC alert — countdown, plus a breaker your character actually knows_

**🎛️ Filters for every class and every spec** — configured separately for friends and enemies. Click an icon to hide it. The change applies instantly, and hiding an icon never hides the player.

![Friendly Class Filters](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/friendly-class-filters.png)

_Friendly Class Filters_

![Enemy Spec Filters](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/enemy-spec-filters.png)

_Enemy Spec Filters — all 30 specs, per side_

**⚙️ One window for all of it** — friendly and enemy plates side by side, healer alerts, tools, profiles, and the roadmap features already sitting in the rail, marked **soon**.

![The OPlates settings window](https://cdn.jsdelivr.net/gh/FreakySphere/OPlates@main/docs/screenshots/settings-overview.png)

_The settings window — type /op and everything is here_

***

## ⚡ Install in 30 seconds

1.  Grab **`OPlates-v1.00.zip`** from [**Releases**](https://github.com/FreakySphere/OPlates/releases/latest).
2.  Close World of Warcraft completely.
3.  Extract the **`OPlates`** folder into your addons folder:

```
   World of Warcraft\Interface\AddOns\OPlates\OPlates.toc
```

4.  Start the game, tick **OPlates** on the AddOns screen, log in, type **`/op`**.

> ⚠️ One folder deep, not two. If you end up with `AddOns\OPlates\OPlates\`, the addon will not load. Upgrading and more help: [INSTALL.md](https://github.com/FreakySphere/OPlates/blob/main/INSTALL.md).

## 🎮 Quick start

1.  Type **`/op`** — the settings window opens (or use the minimap button under **Tools**).
2.  Pick **Friendly Plates** or **Enemy Plates**.
3.  Choose an **Icon mode**, then tick what you want: class, spec, healer, tank, pets, flag carrier.
4.  Fine-tune with **Class Filters** and **Spec Filters** — filtering an icon never hides the player or their other information.
5.  Want auras? Paste spell IDs into that side's **Buffs** / **Debuffs** box.
6.  Nudge **icon size** and **position** until it sits right on your plates.
7.  Open **Healer CC** and hit **Test** — drag the alert where you want it, outside combat.

## ⌨️ Commands

*   **`/op`** or **`/oplates`** — open the themed settings window
*   **`/op classic`** — open the classic settings window
*   **`/op debug on`** — start detailed logging for this session
*   **`/op debug off`** — stop logging
*   **`/op debug reset`** — start a fresh debug session
*   **`/op talent reset`** — forget learned specializations and reload the UI

***

## 🧩 Compatibility

*   **Game** — World of Warcraft: Wrath of the Lich King **3.3.5a** (`Interface 30300`)
*   **Stock client** — ✅ fully supported. Identity may take a moment on some plates.
*   **Patched client** — ✅✅ instant identity, no hover needed, with a supported patch below
*   **Dependencies** — none. Libraries are bundled.

### Supported `awesome_wotlk` patches

OPlates is built for two specific patches — **not** every fork that carries the name:

*   🟢 **[FreakySphere's awesome\_wotlk](https://github.com/FreakySphere/awesome_wotlk/releases/latest)** — the superset build this addon was developed against. _Recommended._
*   🟢 **[KhalGH's awesome\_wotlk 0.1.4-f3](https://github.com/KhalGH/awesome_wotlk/releases/download/0.1.4-f3/AwesomeWotlk.7z)** — the fork OPlates originally grew up on.

The patch is entirely optional. OPlates detects what the client can do and switches its nameplate-unit integration on by itself the first time it finds a supported one; you can turn it off again under **Advanced**. A patch modifies your game client — use only the linked releases and read their instructions.

> Not Retail. Not Classic Era. Not Wrath Classic. **3.3.5a only.**

***

## 🗺️ Roadmap

Three things are planned. **No dates, no promises** — they ship when they are good enough.

**🧱 Plate Filters** Hide individual nameplate elements — names, health bars, power bars, cast bars, icons — from whichever nameplate addon you run. TidyPlates, ThreatPlates, Kui Nameplates, NotPlater, ElvUI: OPlates will be able to strip the pieces you do not want, whatever is drawing them.

**🎨 Aura Filters** A dedicated window with the full set of class, spec and racial buffs and debuffs as circular icons. Tick what you care about, drag to set which aura outranks which — instead of typing spell IDs by hand.

**⚔️ Raid & Dungeon** A PvE layer in the spirit of BigWigs and DBM: when a boss puts something on a raid member, that player's circle becomes that debuff, that mechanic, that thing you must react to — visible on the nameplate itself, where your eyes already are.

***

## 🩺 If something looks off

**OPlates is not in the AddOns list** — check `Interface\AddOns\OPlates\OPlates.toc` exists, and that you are not one folder too deep.

**A class or spec stays unknown** — normal on a stock client. Target or mouse over the player once, or install a supported patch for instant identity.

**The healer alert button will not click in combat** — that is Blizzard, not OPlates. Set an in-combat modifier, make sure **Display only** is off, and configure the alert before the pull.

**Anything else** — type `/op debug on`, reproduce it, then open a [bug report](https://github.com/FreakySphere/OPlates/issues/new?template=bug_report.yml) with your OPlates version and whether your client is stock or patched. Never paste passwords, server credentials or tokens.

***

## 💛 Support OPlates

I built OPlates to give back to the lovely WotLK 3.3.5a community, and especially to support Warmane players and keep the spirit of this server alive. It took many long hours of work to make every plate and mechanism fixed and stable.

OPlates is completely free, and it always will be. But if it has made your games a little easier or a little more fun, a small donation is deeply appreciated to help keep this project growing and fuel my passion to create even more insane addons like this.

Whether you donate or just share OPlates with a friend, your support means the world to me. Thank you for being part of this community.

With love, **FreakySphere**

[![Support on ReyMit](https://img.shields.io/badge/Support%20on-ReyMit-7B3FE4?style=for-the-badge&logo=heart&logoColor=white)](https://reymit.ir/FreakySphere)

**USDT (TRC20)** Only send USDT on the **TRON (TRC20) network**. Using a different asset or network may result in lost funds.

**Three addresses, three networks.** Each one accepts a single network — anything else sent to it is lost permanently.

**USDT** · TRC20 — TRON network

```
TFoVYvxDwCvyxWmsQXxEVwLgZhPkJFwzyk
```

**BNB** · BEP-20 — BNB Smart Chain

```
0xfAcc945FB11975B17eAF82131558913574856133
```

**BTC** · native — Bitcoin

```
bc1qqvl3edwwna38gh2xg9jhu9tz675g000x47mnwz
```

***

## 📄 Project & license

*   **Download** — [latest release](https://github.com/FreakySphere/OPlates/releases/latest)
*   **Source & issues** — [FreakySphere/OPlates](https://github.com/FreakySphere/OPlates)
*   **License** — [GNU GPL-3.0-or-later](https://github.com/FreakySphere/OPlates/blob/main/LICENSE)
*   **Credits & asset terms** — [Copyright](https://github.com/FreakySphere/OPlates/blob/main/COPYRIGHT.md) · [Branding](https://github.com/FreakySphere/OPlates/blob/main/BRANDING.md) · [Third-party notices](https://github.com/FreakySphere/OPlates/blob/main/THIRD_PARTY_NOTICES.md)

OPlates is an independent community project. It is not affiliated with or endorsed by Blizzard Entertainment.

_Made with care for the WotLK 3.3.5a community by FreakySphere._
