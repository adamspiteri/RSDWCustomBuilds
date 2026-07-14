# GPL-free catalogue patch: retoc extract + binary patch (no UAssetGUI).
# Falls back to Generate-Catalogue012.ps1 until patch_legacy_catalogue.py passes validation.
param(
    [string]$ConfigPath,
    [string]$PieceName,
    [switch]$ForceLegacy
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

function Get-CollectionLabel {
    param([string]$MenuCategory)
    switch ($MenuCategory) {
        "foundations" { return "CollectionBasicBuilding" }
        "walls"       { return "CollectionBasicBuilding" }
        "floors"      { return "CollectionBasicBuilding" }
        "roofs"       { return "CollectionBasicBuilding" }
        "props"       { return "CollectionBasicBuilding" }
        default       { return "CollectionBasicBuilding" }
    }
}

$useLegacy = $ForceLegacy -or ($cfg.BuildBackend -eq "ue")
if ($useLegacy) {
    $validator = Join-Path $cfg.ToolsDir "validate_legacy_catalogue.py"
    if (-not (Test-Path -LiteralPath $validator)) {
        if ($cfg.BuildBackend -eq "ue") {
            throw "[cat-retoc] validate_legacy_catalogue.py missing (UE backend requires retoc catalogue patch)"
        }
        Write-Host "[cat-retoc] validate_legacy_catalogue.py missing; using Generate-Catalogue012.ps1"
        $useLegacy = $false
    }
}

if (-not $useLegacy) {
    & "$PSScriptRoot\Generate-Catalogue012.ps1" -ConfigPath $cfg.ConfigPath -PieceName $PieceName
    return
}

$all = & "$PSScriptRoot\Scan-Pieces.ps1" -ConfigPath $cfg.ConfigPath
$daRoot = Join-Path $cfg.PakRawRoot "Gameplay\BaseBuilding_New\BuildingPieces\$($cfg.CookFolder)"
$daContentRoot = Join-Path $cfg.ProjectRoot "Content\Gameplay\BaseBuilding_New\BuildingPieces\$($cfg.CookFolder)"
$targets = @()
foreach ($p in ($all | Sort-Object Id)) {
    $daPakRaw = Join-Path $daRoot "$($p.Id)\DA_$($p.Id).uasset"
    $daContent = Join-Path $daContentRoot "$($p.Id)\DA_$($p.Id).uasset"
    if ((Test-Path -LiteralPath $daPakRaw) -or (Test-Path -LiteralPath $daContent)) {
        $targets += $p
    } elseif ($PieceName -and $p.Id -eq $PieceName) {
        throw "[cat-retoc] $PieceName has no generated DA - run generate-da first."
    }
}
if ($targets.Count -eq 0) { throw "[cat-retoc] No pieces with generated DAs found." }
Write-Host "[cat-retoc] Cataloguing $($targets.Count) piece(s): $(($targets | ForEach-Object Id) -join ', ')"

$relCat = "RSDragonwilds\Content\Gameplay\BaseBuilding_New\BuildingPieces\DA_BuildPieceCatalogue_Default.uasset"
$work = Join-Path $env:TEMP "rsdw-cat-retoc-$(Get-Date -Format 'yyyyMMddHHmmss')"
$basePaks = Join-Path $work "basepaks"
$legacy = Join-Path $work "legacy"
$vanillaUasset = Join-Path $legacy $relCat
$vanillaUexp = $vanillaUasset -replace '\.uasset$', '.uexp'
New-Item -ItemType Directory -Force -Path $basePaks, $legacy | Out-Null

$outDir = [IO.Path]::GetFullPath((Join-Path $cfg.PakRawRoot "Gameplay\BaseBuilding_New\BuildingPieces"))
$outUasset = Join-Path $outDir "DA_BuildPieceCatalogue_Default.uasset"
$outUexp = $outUasset -replace '\.uasset$', '.uexp'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "[cat-retoc] Extracting PRISTINE vanilla catalogue..."
Get-ChildItem $cfg.GamePaksDir -File |
    Where-Object { $_.Name -like 'RSDragonwilds-Windows.*' -or $_.Name -like 'global.*' } |
    Copy-Item -Destination $basePaks -Force
& $cfg.Retoc to-legacy -f DA_BuildPieceCatalogue_Default --version UE5_6 --no-shaders $basePaks $legacy 2>&1 | Out-Null
if (-not (Test-Path -LiteralPath $vanillaUasset)) { throw "[cat-retoc] retoc to-legacy failed" }

$PyPatch = Join-Path $cfg.ToolsDir "patch_legacy_catalogue.py"
$curU = $vanillaUasset
$curE = $vanillaUexp
$assigned = @{}
$step = 0
foreach ($piece in $targets) {
    $step++
    $nextU = Join-Path $work "cat_$step.uasset"
    $nextE = Join-Path $work "cat_$step.uexp"
    $label = Get-CollectionLabel $piece.MenuCategory
    $pieceAsset = "DA_$($piece.Id)"
    $piecePkg = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/$($cfg.CookFolder)/$($piece.Id)/$pieceAsset"
    Write-Host "[cat-retoc] Patching $pieceAsset ($($piece.PersistenceId))..."
    $lines = & $cfg.PythonExe $PyPatch $curU $curE $nextU $nextE $piecePkg $pieceAsset $label $piece.PersistenceId 2>&1
    $lines | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "[cat-retoc] patch_legacy_catalogue.py failed for $($piece.Id)" }
    $curU = $nextU
    $curE = $nextE
    foreach ($line in $lines) {
        if ([string]$line -match 'CATALOGUE_INDEX\|([^|]+)\|(\d+)') {
            $assigned[$Matches[1]] = [int]$Matches[2]
        }
    }
}

Write-Host "[cat-retoc] Validating patched catalogue..."
$persistIds = @($targets | ForEach-Object { [string]$_.PersistenceId })
& $cfg.PythonExe $validator $curU $curE $targets.Count @persistIds
if ($LASTEXITCODE -ne 0) {
    if ($cfg.BuildBackend -eq "ue") {
        throw "[cat-retoc] Legacy patch validation failed (UE backend has no UAssetGUI fallback)"
    }
    Write-Warning "[cat-retoc] Legacy patch validation failed; falling back to Generate-Catalogue012.ps1 (RSDWAssetCli)"
    & "$PSScriptRoot\Generate-Catalogue012.ps1" -ConfigPath $cfg.ConfigPath -PieceName $PieceName
    return
}

Copy-Item -LiteralPath $curU -Destination $outUasset -Force
Copy-Item -LiteralPath $curE -Destination $outUexp -Force
foreach ($piece in $targets) {
    if (-not $assigned.ContainsKey($piece.Id)) { continue }
    $catalogueIndex = [int]$assigned[$piece.Id]
    Write-Host "[cat-retoc] $($piece.Id): AllPiecesInCatalogue index = $catalogueIndex"
    $metaPath = Join-Path $cfg.PakRawRoot "$($cfg.CookFolder)\$($piece.Id)\piece.meta.json"
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        $meta | Add-Member -NotePropertyName catalogue_index -NotePropertyValue $catalogueIndex -Force
        $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    }
}
$uexpSize = (Get-Item -LiteralPath $outUexp).Length
Write-Host "[cat-retoc] OK: $outUasset ($((Get-Item -LiteralPath $outUasset).Length) bytes, uexp=$uexpSize) [no UAssetGUI]"
