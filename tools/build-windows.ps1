<#
.SYNOPSIS
  Build the Windows desktop version of the game locally.

.DESCRIPTION
  Runs the Godot 4.5 headless import and exports the "Windows Desktop" preset
  from game/export_presets.cfg to build\windows\CombatPrototype.exe (a single
  exe with the .pck embedded, plus a console wrapper for seeing script output).

  Needs the Godot 4.5-stable editor and its export templates installed:
    - editor:    https://godotengine.org/download/windows/  (4.5-stable)
    - templates: in the editor, Editor > Manage Export Templates > Download,
                 or unzip Godot_v4.5-stable_export_templates.tpz to
                 %APPDATA%\Godot\export_templates\4.5.stable\

  Point the script at the editor with -Godot, the GODOT environment variable,
  or by having godot.exe on PATH.

.EXAMPLE
  .\tools\build-windows.ps1
  .\tools\build-windows.ps1 -Godot "C:\Godot\Godot_v4.5-stable_win64.exe" -Debug -Run
#>
[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT,
    [switch]$Debug,      # export the debug template (script errors shown in the console)
    [switch]$Run         # launch the exe when the export finishes
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "game"
$out = Join-Path $root "build\windows"
$exe = Join-Path $out "CombatPrototype.exe"

if (-not $Godot) {
    $found = Get-Command godot, godot.exe, Godot_v4.5-stable_win64.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $Godot = $found.Source }
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "Godot editor not found. Pass -Godot <path to Godot_v4.5-stable_win64.exe>, set `$env:GODOT, or put it on PATH."
}

New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "Importing project (first run takes a while)..."
& $Godot --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Import failed (exit $LASTEXITCODE)" }

$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
Write-Host "Exporting Windows Desktop ($mode)..."
& $Godot --headless --path $project $mode "Windows Desktop" $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw "Export failed (exit $LASTEXITCODE)" }

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "Built $exe ($size MB)"

if ($Run) { Start-Process $exe }
