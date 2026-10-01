<#
.SYNOPSIS
  Play the game as a desktop app, straight from the project (no export needed).

.DESCRIPTION
  Launches the Godot editor binary in game mode on game/, so it opens the boot
  menu (combat prototype / campaign) in its own window. Runs the working tree
  as-is, uncommitted changes included. Needs no export templates.

  Uses -Godot, else $env:GODOT, else the local 4.7.1 install.

.EXAMPLE
  .\tools\play-desktop.ps1
  .\tools\play-desktop.ps1 -Console      # keep a console window with script output
#>
[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT,
    [switch]$Console
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "game"

if (-not $Godot) { $Godot = "K:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe" }
if ($Console) { $Godot = $Godot -replace '(_console)?\.exe$', '_console.exe' }
if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot. Pass -Godot <path> or set `$env:GODOT." }

# A cold checkout has no .godot/ import cache; the game needs it to load.
if (-not (Test-Path (Join-Path $project ".godot\imported"))) {
    Write-Host "Importing project (first run only)..."
    $imp = $Godot -replace '(_console)?\.exe$', '_console.exe'
    & $imp --headless --path $project --import
    if ($LASTEXITCODE -ne 0) { throw "Import failed (exit $LASTEXITCODE)" }
}

if ($Console) { & $Godot --path $project } else { Start-Process $Godot -ArgumentList "--path", "`"$project`"" }
