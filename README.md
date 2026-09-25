# TurboFace

**An all-in-one speedrunning and interface addon for WoW Classic Era and WoW Forever.**

[![Latest release](https://img.shields.io/github/v/release/Rumblecrush/TurboFace?label=release)](https://github.com/Rumblecrush/TurboFace/releases/latest)
[![Verify and build](https://github.com/Rumblecrush/TurboFace/actions/workflows/ci.yml/badge.svg)](https://github.com/Rumblecrush/TurboFace/actions/workflows/ci.yml)

[Download on CurseForge](https://www.curseforge.com/wow/addons/turboface) ·
[Download from GitHub](https://github.com/Rumblecrush/TurboFace/releases/latest) ·
[Join Discord](https://discord.gg/apZzz38M9)

TurboFace combines combat information, leveling and speedrun tools, inventory
automation, training helpers, movers, and profiles in one configurable addon.
It enhances the native UI while keeping the information needed for fast,
repeatable leveling close at hand.

## Supported clients

| Client | Status | Interface | Package |
|---|---|---:|---|
| WoW Classic Era | Stable | 11509 | `TurboFace-Classic-0.18.1.zip` |
| WoW Forever | Supported beta client | 16001 | `TurboFace-Forever-0.18.1.zip` |

Use only the package matching your client. GitHub Releases provides both ZIPs
for direct installation. CurseForge availability can follow its normal file
review process.

## Feature highlights

### Nameplates and unit frames

- Enhanced native nameplates with optional threat numbers, aggro audio,
  important auras, combo points, quest indicators, power overlays, and swing
  information.
- Configurable Player, Target, Target-of-Target, Pet, and Party frames with
  Classic-style artwork.
- DoT and incoming-heal prediction, absorb bars, aura styling, health and power
  text, cast bars, and raid/classification indicators.

### Combat tools

- Main-hand, off-hand, ranged, and target swing timers.
- Player and target cast bars as standalone widgets or integrated unit-frame
  elements.
- Lightweight current/overall damage and healing meter with an optional
  PlayerFrame DPS/HPS badge.
- Enemy leash countdowns, class resources, important-buff reminders, and
  class-specific combat indicators.

### Leveling, training, and speedrunning

- XP bar with XP/hour, rested and quest XP, session time, and level-time data.
- Cumulative `/played` speedrun splits with personal-best and segment
  comparisons.
- Level-one Quick Setup for selected macros, bindings, action placement, CVars,
  and supported UI settings.
- Training and Skills pages integrated with the Spellbook, profession Training
  and Recipes views, per-character training queues, and skill tracking.

### Inventory and utility

- Custom loot notifications with quality, quantity, and vendor value.
- Junk/useful/bank item marking, merchant selling, bank routing, free-slot
  tracking, and a Net Worth display.
- Grocery List planning for repeat purchases such as food, water, reagents,
  ammunition, poisons, potions, and other supplies.
- Hearthstone location/cooldown tools and an optional Classic batching
  assistant.
- Hybrid Flight Bar with immediate route estimates and account-wide learning
  from completed flights.
- Minimap, map, chat, social, automation, and general quality-of-life options.
- Optional integration with UnstuckSkips and Baganator.

## Installation

### CurseForge app

Install TurboFace from the
[CurseForge project page](https://www.curseforge.com/wow/addons/turboface),
selecting the file for your client when available.

### Manual installation

1. Download the matching ZIP from
   [GitHub Releases](https://github.com/Rumblecrush/TurboFace/releases/latest).
2. Exit World of Warcraft.
3. Extract the archive into the selected client's `Interface/AddOns` folder.
4. Confirm the resulting path is `Interface/AddOns/TurboFace/TurboFace.toc`.
5. Start the game and enable **TurboFace** on the AddOns screen.

## Getting started

- `/tf` or `/turboface` — open TurboFace Options.
- `/tf move` or `/tfmove` — show mover handles and the alignment grid.
- `/tf lock` — finish positioning and lock mover handles.
- `/tfsplits` — manage or inspect speedrun splits.
- `/tfgrocery` or `/tfshop` — open Grocery List commands.

Profiles can be saved, switched, imported, and exported from the **Profile**
tab. Options that alter Blizzard-owned or protected frames may require
`/reload`; the relevant option sections identify those cases.

## Classic Era and WoW Forever

Both packages are built from the same shared feature source. Classic Era uses
the official Classic UI architecture. WoW Forever uses a modernized UI with
different protected-frame and secret-value rules, so its package includes
dedicated compatibility and native-UI adapters.

Forever is currently a beta game client. TurboFace supports its targeted
Interface `16001` build, but client-side beta changes can require compatibility
updates. Include the exact game build when reporting a Forever issue.

## Bug reports and support

- [Report a bug or request a feature](https://github.com/Rumblecrush/TurboFace/issues/new/choose)
- [Join the TurboFace Discord](https://discord.gg/apZzz38M9)
- [View the CurseForge project](https://www.curseforge.com/wow/addons/turboface)

For bugs, include the client, TurboFace version, exact game build, reproduction
steps, and the full Lua error if one appears.

## Credits and third-party software

TurboFace is developed and maintained by **Rumblecrush**. It includes or adapts
third-party software and data under their respective licenses. See
[Third-Party Notices](THIRD_PARTY_NOTICES.md) for sources, scope, attribution,
and license locations.

## License

TurboFace's original material is All Rights Reserved. Official releases may be
downloaded for personal use with World of Warcraft; redistribution and modified
distribution require prior written permission. See the [license](LICENSE) for
the complete terms.

## Developer documentation

Development and release material is intentionally kept out of the player-facing
sections above:

- [Contributing](CONTRIBUTING.md)
- [Development guide](docs/DEVELOPMENT.md)
- [Release guide](docs/RELEASING.md)
- [Multi-client strategy](docs/MULTICLIENT_STRATEGY.md)
- [Source map](docs/SOURCE_MAP.md)
- [Classic architecture](docs/classic/ARCHITECTURE.md)
- [Forever architecture](docs/forever/ARCHITECTURE.md)
- [Classic changelog](docs/classic/CHANGELOG.md)
- [Forever changelog](docs/forever/CHANGELOG.md)
