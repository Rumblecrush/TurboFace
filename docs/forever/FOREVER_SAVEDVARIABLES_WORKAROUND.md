# Forever SavedVariables workaround

Forever beta build 69913 can write TurboFace's SavedVariables correctly while
failing to load them on the next login or `/reload`. TurboFace Prep67 includes a
manual snapshot bridge for that client bug.

## Normal use

1. Configure TurboFace in game.
2. Log out to the **character-selection screen** so WoW writes the current
   `TurboFace.lua` files.
3. Save the snapshot from the installed `Interface\AddOns\TurboFaceForever`
   folder:
   - Windows: open PowerShell in the addon folder and run
     `& ".\Tools\Save-ForeverVariables.ps1"`.
   - Linux/Proton: open a terminal there and run
     `./Save-TurboFaceForever.sh`.
4. Review the account and character paths printed by the script. Numeric realm
   folders are supported automatically.
5. Type `SAVE` only when the listed snapshot is known-good.

The script combines the most recently written account-wide and character-level
TurboFace files (`TurboFace.lua`, `TurboFaceForever.lua`, or the installed addon
folder name) into `Core\ForeverRestoreData.lua`. That file loads before any
TurboFace runtime code. On the next login or `/reload`, TurboFace uses the
restored tables and does not apply the hardcoded development preset.

Each successful run backs up the previous restore file under
`ForeverRestoreBackups`. Do not save after TurboFace has already loaded an empty
or unwanted state; doing so would make that state the next restore snapshot.

The distributed addon deliberately contains an inert placeholder instead of
personal SavedVariables. Installing a newer TurboFaceForever package can replace
your generated restore file, so rerun the saver from the freshly installed addon
folder **before the next login or `/reload`**. The known-good data in `WTF` is
still the source; ordinary in-place extraction does not remove the timestamped
backup directory.

## What is preserved

Account-wide variables:

- `TurboFaceDB`
- `TurboFaceCacheDB`
- `TurboFaceProfilesDB`
- `TurboFaceTrainerDB`
- `TurboFaceSpeedrunDB`
- `TurboFaceCompatDB`

Character variables:

- `TurboFaceCharDB`
- `TurboFaceTrainerCharDB`
- `TurboFaceCVarExportCharDB`
- `TurboFaceSpeedrunCharDB`

This includes Options checkboxes, layouts, profiles, Trainer observations and
queues, Grocery state, learned flight/Hearthstone timing, and Speedrun data.

## Manual paths / discovery problems

When the script is run from the installed addon folder, it infers the adjacent
`_classic_beta_\WTF` directory. If TurboFace exists in a staging folder or the
wrong account/character was selected, launch PowerShell and provide explicit
paths:

```powershell
& ".\Tools\Save-ForeverVariables.ps1" `
  -WtfRoot "C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF" `
  -AccountFile "C:\...\Account\123456#1\SavedVariables\TurboFace.lua" `
  -CharacterFile "C:\...\Account\123456#1\987654\Character\SavedVariables\TurboFace.lua"
```

Back up the full `WTF` folder before first use. The workaround does not repair
Blizzard's loader; it supplies a known-good input before TurboFace initializes.

### Linux/Proton explicit path

The Linux script normally infers `WTF` from its location under the Proton/Wine
prefix. If the addon is a symlink or is being run from a staging directory, pass
the native Linux path explicitly:

```bash
./Save-TurboFaceForever.sh \
  --wtf-root "/path/to/prefix/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/WTF"
```

The script reads the prefix as ordinary Linux files; it does not need to run
inside Proton, Wine, or a Windows PowerShell process.

The source repository retains `Save-TurboFaceForever.bat` as a development
convenience, but public release archives omit batch launchers because
CurseForge does not accept them inside addon packages.
