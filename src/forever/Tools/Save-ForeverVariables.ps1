[CmdletBinding()]
param(
    [string]$WtfRoot,
    [string]$AccountFile,
    [string]$CharacterFile,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Stop-WithMessage([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Read-TextWithoutBom([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) {
        return $text.Substring(1)
    }
    return $text
}

function Resolve-SourceFile([string]$ExplicitPath, [object[]]$Candidates, [string]$Kind) {
    if ($ExplicitPath) {
        $resolved = Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop
        return Get-Item -LiteralPath $resolved.Path
    }
    if (-not $Candidates -or $Candidates.Count -eq 0) {
        Stop-WithMessage "No $Kind TurboFace SavedVariables file was found. Pass -${Kind}File with its full path."
    }
    return $Candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$addonDir = Split-Path -Parent $PSScriptRoot
$restoreFile = Join-Path $addonDir "Core\ForeverRestoreData.lua"

if (-not $WtfRoot) {
    # Installed layout:
    # <client>\Interface\AddOns\TurboFaceForever\Tools\this-script.ps1
    $addOnsDir = Split-Path -Parent $addonDir
    $interfaceDir = Split-Path -Parent $addOnsDir
    $clientDir = Split-Path -Parent $interfaceDir
    $autoWtf = Join-Path $clientDir "WTF"
    if (Test-Path -LiteralPath $autoWtf -PathType Container) {
        $WtfRoot = $autoWtf
    }
}

if (-not $WtfRoot) {
    Stop-WithMessage "Could not infer the WTF folder. Pass -WtfRoot with the full _classic_beta_\WTF path."
}
$resolvedWtf = Resolve-Path -LiteralPath $WtfRoot -ErrorAction Stop
$WtfRoot = $resolvedWtf.Path
$accountRoot = Join-Path $WtfRoot "Account"
if (-not (Test-Path -LiteralPath $accountRoot -PathType Container)) {
    Stop-WithMessage "No Account folder exists under '$WtfRoot'."
}

$addonFolderName = Split-Path -Leaf $addonDir
$candidateNames = @("TurboFace.lua", "TurboFaceForever.lua", "$addonFolderName.lua") |
    Select-Object -Unique
$allFiles = @(Get-ChildItem -LiteralPath $accountRoot -File -Recurse -ErrorAction Stop |
    Where-Object { $candidateNames -contains $_.Name })
$accountCandidates = @()
$characterCandidates = @()
foreach ($file in $allFiles) {
    $relative = $file.FullName.Substring($accountRoot.Length) -replace '^[\\/]+', ''
    $parts = @($relative -split '[\\/]')
    # Account\<ACCOUNT>\SavedVariables\TurboFace.lua
    if ($parts.Count -eq 3 -and $parts[1] -eq "SavedVariables") {
        $accountCandidates += $file
    }
    # Account\<ACCOUNT>\<REALM OR NUMERIC ID>\<CHARACTER>\SavedVariables\TurboFace.lua
    elseif ($parts.Count -eq 5 -and $parts[3] -eq "SavedVariables") {
        $characterCandidates += $file
    }
}

$accountSource = Resolve-SourceFile $AccountFile $accountCandidates "Account"
$characterSource = Resolve-SourceFile $CharacterFile $characterCandidates "Character"

function Get-AccountKey([string]$Path) {
    $relative = $Path.Substring($accountRoot.Length) -replace '^[\\/]+', ''
    return @($relative -split '[\\/]')[0]
}
$accountKey = Get-AccountKey $accountSource.FullName
$characterAccountKey = Get-AccountKey $characterSource.FullName
if ($accountKey -ne $characterAccountKey) {
    Stop-WithMessage "The newest account and character files belong to different accounts ('$accountKey' and '$characterAccountKey'). Pass explicit -AccountFile and -CharacterFile paths."
}

$accountText = Read-TextWithoutBom $accountSource.FullName
$characterText = Read-TextWithoutBom $characterSource.FullName
if ($accountText -notmatch '(?m)^\s*TurboFaceDB\s*=') {
    Stop-WithMessage "The account-wide source does not assign TurboFaceDB: '$($accountSource.FullName)'."
}
if ($characterText -notmatch '(?m)^\s*TurboFaceCharDB\s*=') {
    Stop-WithMessage "The character source does not assign TurboFaceCharDB: '$($characterSource.FullName)'."
}

Write-Host "TurboFace Forever restore snapshot" -ForegroundColor Cyan
Write-Host "Account source  : $($accountSource.FullName)"
Write-Host "  Modified/bytes: $($accountSource.LastWriteTime) / $($accountSource.Length)"
Write-Host "Character source: $($characterSource.FullName)"
Write-Host "  Modified/bytes: $($characterSource.LastWriteTime) / $($characterSource.Length)"
Write-Host "Restore target  : $restoreFile"
Write-Host ""
Write-Host "Only continue if TurboFace was in a good state when you logged out." -ForegroundColor Yellow

if (-not $Yes) {
    $confirmation = Read-Host "Type SAVE to update the restore snapshot"
    if ($confirmation -cne "SAVE") {
        Write-Host "Cancelled; no files were changed."
        exit 2
    }
}

$backupDir = Join-Path $addonDir "ForeverRestoreBackups"
[System.IO.Directory]::CreateDirectory($backupDir) | Out-Null
if (Test-Path -LiteralPath $restoreFile -PathType Leaf) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = Join-Path $backupDir "ForeverRestoreData-$stamp.lua"
    Copy-Item -LiteralPath $restoreFile -Destination $backupFile -Force
    Write-Host "Previous snapshot: $backupFile"
}

$generatedAt = (Get-Date).ToString("o")
$header = @"
-- GENERATED FILE -- DO NOT HAND EDIT
-- Generated by Tools\Save-ForeverVariables.ps1 after a deliberate logout.
-- Account source: $($accountSource.FullName)
-- Character source: $($characterSource.FullName)

"@
$marker = @"

TurboFaceForeverRestoreMeta = {
    enabled = true,
    format = 1,
    generatedAt = [==[$generatedAt]==],
    accountSource = [==[$($accountSource.FullName)]==],
    characterSource = [==[$($characterSource.FullName)]==],
    accountBytes = $($accountSource.Length),
    characterBytes = $($characterSource.Length),
}
"@
$output = $header + $accountText.TrimEnd() + "`r`n`r`n" + $characterText.TrimEnd() + "`r`n" + $marker
$tempFile = "$restoreFile.tmp"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempFile, $output, $utf8NoBom)
Move-Item -LiteralPath $tempFile -Destination $restoreFile -Force

Write-Host ""
Write-Host "Saved TurboFace's restore snapshot successfully." -ForegroundColor Green
Write-Host "The next login or /reload will preload these settings and character data."
