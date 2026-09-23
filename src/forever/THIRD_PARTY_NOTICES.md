# TurboFace Third-Party Notices

TurboFace contains or adapts the third-party material listed below.
The corresponding license texts or attribution notices ship in `Licenses/` and
remain part of every release package.

## Flight Timer Classic

- Project: Flight Timer Classic by Nomana (Timo Hausmann / timohausmann)
- Source: https://github.com/timohausmann/FlightTimerClassic
- Source revision: `5c9982c28af97da25baa3e7df39db62911a45840`
- License: Creative Commons Attribution 2.0 Generic (CC BY 2.0)
- Attribution notice: `Licenses/FlightTimerClassic-CC-BY-2.0-NOTICE.txt`
- Scope: the directional Classic Era baseline durations adapted into
  `Plus/FlightData.lua`. TurboFace changed the global/namespace representation
  and uses these values only until its own full-route observation is available.

## What's Training?

- Project: What's Training? by Fusionpit
- Source: https://github.com/fusionpit/WhatsTraining
- License: MIT
- License text: `Licenses/WhatsTraining-MIT.txt`
- Scope: the bundled Classic Era class and pet trainer seed catalogs, the
  faction-specific weapon-master NPC/capital catalog, plus the filtering
  lineage used by the Training feature. TurboFace modified and integrated this
  material.

Profession trainer offerings remain runtime observations stored in
`TurboFaceTrainerDB`; they do not come from the recipe catalog below.

## LibProfessionDB

- Project: LibProfessionDB by Pimptasty
- Project page: https://www.curseforge.com/wow/addons/libprofessiondb
- Upstream release: ProfessionDB-v1.7.0 (2026-08-21)
- Upstream archive SHA-256: `07ff36a7858a50f098d5a40e90f4b8b0f4c73bf06b25fb583778aedba5363573`
- License: MIT
- License text: `Licenses/LibProfessionDB-MIT.txt`
- Scope: `Libs/LibProfessionDB/`. TurboFace ships only the Classic Era core,
  English names, recipe-item/rank-book classification, hidden/acquisition
  metadata, and recipe-source data. Generated data files were wrapped in
  deferred loader closures so they materialize only when the Recipes tab is
  first opened. The standalone addon's Ace3/version-check host is not included.

LibProfessionDB's core recipe catalog is generated from Blizzard client data.
Its source metadata is generated from community server databases, and its
never-implemented classification credits AllTheThings; see the upstream project
page for the complete data-provenance description.

## EasyFrames

- Project: EasyFrames by Mirmidonis
- Source: https://repos.curseforge.com/wow/easy-frames
- License: BSD 3-Clause
- License text: `Licenses/EasyFrames-BSD-3-Clause.txt`
- Scope: design and implementation lineage in TurboFace's UnitFrames system.
  The Ace3 framework dependency was removed and the functionality was
  substantially reorganized and rewritten for TurboFace.

## TurboPlates

- Project: TurboPlates by Miko
- Source: https://github.com/esurm/TurboPlates
- License: MIT
- License text: `Licenses/TurboPlates-MIT.txt`
- Scope: nameplate aura/rendering lineage and the following byte-identical
  media assets: `Circle_White.tga`, `GlowTex.tga`, `Smooth.tga`, `Statusbar_Clean.blp`,
  `Statusbar_Stripes.blp`, `bar_hyanda.tga`, `bar_serenity.tga`, and
  `bar_skyline.tga`.

TurboFace's copies of LibStub, CallbackHandler-1.0, and LibSharedMedia-3.0
were also acquired through the TurboPlates bundle. Those libraries retain
their own upstream licenses and notices below.

## LibClassicDurations

- Project: LibClassicDurations by d87
- Source: https://github.com/rgd87/LibClassicDurations
- Project page: https://www.curseforge.com/wow/addons/libclassicdurations
- License: MIT, as declared by the official CurseForge project metadata
- License text: `Licenses/LibClassicDurations-MIT.txt`
- Scope: `Libs/LibClassicDurations/`. The ability data files are upstream
  copies. TurboFace modified `core.lua` to make NPC-data processing, its purge
  ticker, and its set watcher demand-driven and dormant without consumers.

## LibSharedMedia-3.0

- Project: LibSharedMedia-3.0 by Elkano
- Source: https://www.wowace.com/projects/libsharedmedia-3-0
- License: GNU Lesser General Public License 2.1
- License text: `Licenses/LibSharedMedia-LGPL-2.1.txt`
- Scope: `Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua`.

## CallbackHandler-1.0

- Project: CallbackHandler-1.0, Ace3 Development Team
- Source: https://www.wowace.com/projects/callbackhandler
- License: BSD-style Ace3 license; embedded redistribution is permitted and
  standalone redistribution is restricted
- License text: `Licenses/CallbackHandler-Ace3-BSD.txt`
- Scope: `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`, embedded only as
  a TurboFace support library.

## LibStub

- Project: LibStub; credited authors are Kaelten, Cladhaire, ckknight, Mikk,
  Ammo, Nevcairiel, and joshborke
- Source: https://www.wowace.com/projects/libstub
- License: public domain
- Notice: `Licenses/LibStub-Public-Domain.txt`
- Scope: `Libs/LibStub/LibStub.lua`.

Blizzard API names, runtime texture paths, spell identifiers, and game data
referenced by TurboFace are not bundled third-party source or media.
