# UE-only backend: generate BP_<PieceId> inside Unreal (no UAssetGUI / RSDWAssetCli).
# Child of the editor-only BP_T1_BasePiece stub with an owned SCS mesh component;
# at runtime the parent path resolves to the game's real base piece class.
param(
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$PieceName,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$prefix = "/Game/$($cfg.CookFolder)/$PieceName"
$meshUasset = Join-Path $cfg.ContentRoot "$PieceName\SM_$PieceName.uasset"
if (-not (Test-Path -LiteralPath $meshUasset)) {
    throw "SM_$PieceName.uasset missing in $($cfg.ContentRoot)\$PieceName - author/sync the mesh first."
}

& "$PSScriptRoot\Invoke-UnrealPython.ps1" -ConfigPath $cfg.ConfigPath `
    -ScriptPath (Join-Path $cfg.ToolsDir "unreal_generate_bp.py") `
    -TaskConfig @{
        piece_id  = $PieceName
        mesh_path = "$prefix/SM_$PieceName"
        bp_pkg    = $prefix
        bp_name   = "BP_$PieceName"
        force     = [bool]$Force
    }

$bpUasset = Join-Path $cfg.ContentRoot "$PieceName\BP_$PieceName.uasset"
if (-not (Test-Path -LiteralPath $bpUasset)) {
    throw "UE python reported OK but BP not found on disk: $bpUasset"
}
Write-Host "Generated (UE backend): $bpUasset ($((Get-Item -LiteralPath $bpUasset).Length) bytes)"
