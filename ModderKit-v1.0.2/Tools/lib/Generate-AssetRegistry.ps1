# Export the mod's FILTERED premade AssetRegistry.bin (UE backend only).
#
# Why: the game's AssetManager registers building pieces NATIVELY by scanning the
# asset registry for /Script/Dominion.BuildingPieceData under /Game/Gameplay
# (recursive, bIsEditorOnly=False - verified in the shipped Engine ini blob).
# Mod paks carry no registry rows, so pak DAs used to be invisible to that scan;
# the engine merges <EnabledContentPlugin>/AssetRegistry.bin from every enabled
# content plugin at boot (LoadPremadeAssetRegistry_Plugins), so deploying this
# file to a plugin folder makes the game register the pieces itself - no Lua.
#
# Proven in-game 2026-07-12: 774 pieces loaded (772 vanilla + 2 custom), game
# assigned BuildingPieceDataIndex 577/578, placement + save/reload all native.
#
# The export is FILTERED to the mod's own roots. Never widen it: AppendState
# overwrites duplicate rows, so stub rows at vanilla paths would corrupt the
# game's own registry entries.
param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$outFile = Join-Path $cfg.BuildDir "AssetRegistry.bin"
New-Item -ItemType Directory -Force -Path $cfg.BuildDir | Out-Null

& "$PSScriptRoot\Invoke-UnrealPython.ps1" -ConfigPath $cfg.ConfigPath `
    -ScriptPath (Join-Path $cfg.ToolsDir "unreal_export_registry.py") `
    -TaskConfig @{
        package_paths = @(
            "/Game/$($cfg.CookFolder)",
            "/Game/Gameplay/BaseBuilding_New/BuildingPieces/$($cfg.CookFolder)")
        output_file   = ($outFile -replace '\\', '/')
    }

if (-not (Test-Path -LiteralPath $outFile)) {
    throw "UE python reported OK but registry not found: $outFile"
}
$size = (Get-Item -LiteralPath $outFile).Length
if ($size -lt 100) { throw "AssetRegistry.bin suspiciously small ($size bytes)" }
Write-Host "AssetRegistry.bin exported ($size bytes): $outFile"
