# UAssetGUI-free donor-BP clone: retoc extract the donor Blueprint from the GAME paks,
# then binary-clone it (clone_legacy_bp.py) with the identity + mesh renamed to the piece.
# The clone lands in PakRaw\RSDWBuilds\<Id>\BP_<Id>.uasset(+uexp); Pack-IoStore stages it
# in place of the small cooked editor BP (which lacks donor snap/collider/stability config
# - a child of the generic base piece can neither snap nor pass placement validation).
param(
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$PieceName
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

# donor key -> game BP package folder + asset name (0.12.0.0; floor folder is singular)
$DonorBp = @{
    wall_large       = @{ Dir = "Walls";       Name = "BP_T1_Wall_Large" }
    foundation_large = @{ Dir = "Foundations"; Name = "BP_T1_Foundation_Large" }
    foundation_med   = @{ Dir = "Foundations"; Name = "BP_T1_Foundation_Medium" }
    floor_large      = @{ Dir = "Floor";       Name = "BP_T1_Floor_Large" }
    roof_large       = @{ Dir = "Roofs";       Name = "BP_T1_Roof_Large_Shallow" }
}

$all = & "$PSScriptRoot\Scan-Pieces.ps1" -ConfigPath $cfg.ConfigPath
$piece = $all | Where-Object { $_.Id -eq $PieceName } | Select-Object -First 1
if (-not $piece) { throw "Piece not found: $PieceName" }

$donorKey = if ($piece.Donor) { $piece.Donor } else { "wall_large" }
$donor = $DonorBp[$donorKey]
if (-not $donor) { throw "No donor BP mapping for '$donorKey' (add to Generate-PieceBlueprint-Retoc.ps1)" }

$donorPkg = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/$($donor.Dir)/$($donor.Name)"
$prefix = "/Game/$($cfg.CookFolder)/$PieceName"
$newPkg = "$prefix/BP_$PieceName"
$newMeshPkg = "$prefix/SM_$PieceName"

$work = Join-Path $env:TEMP "rsdw-bpclone-$PieceName"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Host "[bp-clone] Extracting donor $($donor.Name) from game paks..."
# Read the game Paks dir directly (no multi-GB copies). -f is a substring filter, so
# variants (e.g. _Diagonal) extract too - we pick the exact file below.
& $cfg.Retoc to-legacy -f $donor.Name --version $cfg.UERetocVersion --no-shaders $cfg.GamePaksDir $work 2>&1 | Out-Null
$donorUasset = Join-Path $work ("RSDragonwilds\Content\Gameplay\BaseBuilding_New\BuildingPieces\Tier1_Brynmoor\$($donor.Dir)\$($donor.Name).uasset")
$donorUexp = $donorUasset -replace '\.uasset$', '.uexp'
if (-not (Test-Path -LiteralPath $donorUasset)) { throw "[bp-clone] retoc did not produce $donorUasset" }
if (-not (Test-Path -LiteralPath $donorUexp)) { throw "[bp-clone] donor uexp missing: $donorUexp" }

$outDir = Join-Path $cfg.PakRawRoot "$($cfg.CookFolder)\$PieceName"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outUasset = Join-Path $outDir "BP_$PieceName.uasset"
$outUexp = Join-Path $outDir "BP_$PieceName.uexp"

$py = Join-Path $cfg.ToolsDir "clone_legacy_bp.py"
Push-Location $cfg.ToolsDir
try {
    $lines = & $cfg.PythonExe $py $donorUasset $donorUexp $outUasset $outUexp `
        $donorPkg $donor.Name $newPkg "BP_$PieceName" `
        "auto" "auto" $newMeshPkg "SM_$PieceName" 2>&1
    $lines | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0 -or -not (($lines | Out-String) -match 'RSDW_CLONE_OK')) {
        throw "[bp-clone] clone_legacy_bp.py failed for $PieceName"
    }
} finally {
    Pop-Location
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[bp-clone] OK: $outUasset ($((Get-Item -LiteralPath $outUasset).Length) bytes) - donor behavior ($donorKey) with SM_$PieceName"
