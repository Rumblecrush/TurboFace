-- TurboFace Forever SavedVariables restore snapshot
--
-- This placeholder is intentionally inert.  On Forever beta builds where the
-- client writes SavedVariables but fails to load them, run
-- Tools\Save-ForeverVariables.ps1 after logging out to the character-selection
-- screen.  The PowerShell script replaces this file with the latest
-- account-wide and per-character TurboFace.lua contents plus an enabled marker.
--
-- Keep this file before Core/Compatibility.lua in TurboFace.toc: several
-- feature databases are consumed while addon files load, before PLAYER_LOGIN.

TurboFaceForeverRestoreMeta = nil
