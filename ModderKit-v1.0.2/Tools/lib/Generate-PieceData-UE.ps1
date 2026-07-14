# UE-only backend: generate DA_<PieceId> inside Unreal (no UAssetGUI / archive JSON).
# Per-donor constants below were read ONCE from the 0.12 vanilla donors and baked in;
# re-verify them after a major game update (see Docs/UE_ONLY_BACKEND.md).
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

# donor -> piece tag, stability row, xp row, safe vanilla icon (verified 0.12.0.0)
$DonorConstants = @{
    wall_large       = @{ Tag = "BaseBuilding.PieceType.Base";       Stab = "Tier1_Base";       Xp = "Build_Wall_Tier1";       Icon = "/Game/Art/UI/Icons/07_T1_Building_Icons/Walls/T_Icon_T1_Wall.T_Icon_T1_Wall" }
    floor_large      = @{ Tag = "BaseBuilding.PieceType.Foundation"; Stab = "Tier1_Base";       Xp = "Build_Foundation_Tier1"; Icon = "/Game/Art/UI/Icons/07_T1_Building_Icons/Floors/T_Icon_T1_Square_Floor.T_Icon_T1_Square_Floor" }
    foundation_large = @{ Tag = "BaseBuilding.PieceType.Foundation"; Stab = "Tier1_Foundation"; Xp = "Build_Foundation_Tier1"; Icon = "/Game/Art/UI/Icons/07_T1_Building_Icons/Floors/T_Icon_T1_Square_Floor.T_Icon_T1_Square_Floor" }
    foundation_med   = @{ Tag = "BaseBuilding.PieceType.Foundation"; Stab = "Tier1_Foundation"; Xp = "Build_Beam_Tier1_Med";   Icon = "/Game/Art/UI/Icons/07_T1_Building_Icons/Floors/T_Icon_T1_Medium_Square_Floor.T_Icon_T1_Medium_Square_Floor" }
    roof_large       = @{ Tag = "BaseBuilding.PieceType.Base";       Stab = "Tier1_Base";       Xp = "Build_Roof_Tier1";       Icon = "/Game/Art/UI/Icons/07_T1_Building_Icons/Roofs/T_Icon_T1_45_Roof.T_Icon_T1_45_Roof" }
}

# Friendly material names -> game item assets (0.12.0.0; used by `cost = wood:4, plank:2`).
$MaterialRegistry = @{
    wood        = @{ Pkg = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Wood_Ash";       Name = "ITEM_Resources_Wood_Ash";       Class = "FuelItemData" }
    wood_oak    = @{ Pkg = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Wood_Oak";       Name = "ITEM_Resources_Wood_Oak";       Class = "FuelItemData" }
    plank       = @{ Pkg = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Plank_Ash";      Name = "ITEM_Resources_Plank_Ash";      Class = "FuelItemData" }
    plank_oak   = @{ Pkg = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Plank_Oak";      Name = "ITEM_Resources_Plank_Oak";      Class = "FuelItemData" }
    stone       = @{ Pkg = "/Game/Gameplay/Items/Resources/Mineral/ITEM_Resources_Stone";       Name = "ITEM_Resources_Stone";          Class = "ItemData" }
    stone_block = @{ Pkg = "/Game/Gameplay/Items/Resources/Mineral/ITEM_Resources_Stone_Block"; Name = "ITEM_Resources_Stone_Block";    Class = "ItemData" }
    clay        = @{ Pkg = "/Game/Gameplay/Items/Resources/Mineral/ITEM_Resources_Clay";        Name = "ITEM_Resources_Clay";           Class = "ItemData" }
}


# Donor mesh bounding boxes (from archive ExtendedBounds, 0.12.0.0) - auto_fit targets.
$DonorFitBox = @{
    wall_large       = @{ min = @(-150.0, -36.0, -8.0);    max = @(150.0, 32.0, 314.0) }
    foundation_large = @{ min = @(-169.0, -169.0, -300.0); max = @(169.0, 169.0, 4.0) }
    foundation_med   = @{ min = @(-94.0, -94.0, -300.0);   max = @(94.0, 94.0, 4.0) }
    floor_large      = @{ min = @(-180.0, -171.0, -46.0);  max = @(188.0, 167.0, 12.0) }
    roof_large       = @{ min = @(-165.0, -170.0, -95.0);  max = @(203.0, 166.0, 103.0) }
}


function Get-FitBoxWithThicknessScale {
    param([hashtable]$FitBox, [double]$ThicknessScale)
    if ($ThicknessScale -le 0 -or [math]::Abs($ThicknessScale - 1.0) -lt 0.001) {
        return $FitBox
    }
    $min = @([double]$FitBox.min[0], [double]$FitBox.min[1], [double]$FitBox.min[2])
    $max = @([double]$FitBox.max[0], [double]$FitBox.max[1], [double]$FitBox.max[2])
    $centerY = ($min[1] + $max[1]) / 2.0
    $halfY = (($max[1] - $min[1]) / 2.0) * $ThicknessScale
    $min[1] = $centerY - $halfY
    $max[1] = $centerY + $halfY
    return @{ min = $min; max = $max }
}

$all = & "$PSScriptRoot\Scan-Pieces.ps1" -ConfigPath $cfg.ConfigPath
$piece = $all | Where-Object { $_.Id -eq $PieceName } | Select-Object -First 1
if (-not $piece) { throw "Piece not found: $PieceName" }
if (-not $piece.HasStaticMesh) { throw "$PieceName missing SM_$PieceName.uasset" }

$donorKey = if ($piece.Donor) { $piece.Donor } else { "wall_large" }
$const = $DonorConstants[$donorKey]
if (-not $const) { throw "No UE-backend constants for donor '$donorKey' (add to Generate-PieceData-UE.ps1)" }

# Build costs -> Requirements (hard refs to game items via editor-only placeholders).
$requirements = @()
if ($piece.Costs) {
    foreach ($mat in $piece.Costs.Keys) {
        $entry = $MaterialRegistry[$mat]
        if (-not $entry) {
            throw "$PieceName : unknown cost material '$mat'. Valid: $(($MaterialRegistry.Keys | Sort-Object) -join ', ')"
        }
        $requirements += @{
            amount     = [int]$piece.Costs[$mat]
            item_pkg   = $entry.Pkg
            item_name  = $entry.Name
            item_class = $entry.Class
        }
        Write-Host "  cost: $($piece.Costs[$mat])x $mat -> $($entry.Name)"
    }
}

$prefix = "/Game/$($cfg.CookFolder)/$PieceName"
$daScanRoot = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/$($cfg.CookFolder)/$PieceName"
$daName = "DA_$PieceName"

# Icon: the piece's own T_Icon_<Id> if authored; otherwise the UE task imports the
# kit's default placeholder PNG as T_Icon_<Id>. (Referencing a vanilla GAME icon path
# does not survive DA generation - unloadable soft refs serialize empty.)
$iconUasset = Join-Path $cfg.ContentRoot "$PieceName\T_Icon_$PieceName.uasset"
$iconPath = "$prefix/T_Icon_$PieceName.T_Icon_$PieceName"
$defaultIconPng = Join-Path $cfg.ToolsDir "assets\T_Icon_Default.png"
$iconImportPng = ""
if (-not (Test-Path -LiteralPath $iconUasset)) {
    if (Test-Path -LiteralPath $defaultIconPng) {
        $iconImportPng = $defaultIconPng
    } else {
        Write-Warning "No T_Icon_$PieceName and no default icon PNG - menu tile will have no image."
    }
}

& "$PSScriptRoot\Invoke-UnrealPython.ps1" -ConfigPath $cfg.ConfigPath `
    -ScriptPath (Join-Path $cfg.ToolsDir "unreal_generate_da.py") `
    -TaskConfig @{
        piece_id       = $PieceName
        display_name   = $piece.DisplayName
        description    = "Custom building piece ($PieceName)."
        persistence_id = $piece.PersistenceId
        da_pkg         = $daScanRoot
        da_name        = $daName
        mesh_path      = "$prefix/SM_$PieceName.SM_$PieceName"
        bp_class_path  = "$prefix/BP_$PieceName.BP_${PieceName}_C"
        icon_path      = $iconPath
        icon_import_png = $iconImportPng
        icon_dest_pkg  = $prefix
        icon_dest_name = "T_Icon_$PieceName"
        piece_tag      = $const.Tag
        stability_row  = $const.Stab
        xp_row         = $const.Xp
        requirements   = $requirements
        auto_fit       = [bool]$piece.AutoFit
        auto_material  = [bool]$piece.AutoMaterial
        source_mesh    = [string]$piece.SourceMesh
        restore_mesh   = [bool]$piece.RestoreMesh
        fit_box             = (Get-FitBoxWithThicknessScale $DonorFitBox[$donorKey] $piece.FitThicknessScale)
        fit_thickness_scale = [double]$piece.FitThicknessScale
        force          = $true
    }

$daOnDisk = Join-Path $cfg.ProjectRoot "Content\Gameplay\BaseBuilding_New\BuildingPieces\$($cfg.CookFolder)\$PieceName\$daName.uasset"
if (-not (Test-Path -LiteralPath $daOnDisk)) {
    throw "UE python reported OK but DA not found on disk: $daOnDisk"
}

# Retire any stale UAssetGUI-generated PakRaw DA for this piece so staging can't
# resurrect it over the cooked UE DA.
$stalePakRawDa = Join-Path $cfg.PakRawRoot "Gameplay\BaseBuilding_New\BuildingPieces\$($cfg.CookFolder)\$PieceName"
if (Test-Path -LiteralPath $stalePakRawDa) {
    Remove-Item -LiteralPath $stalePakRawDa -Recurse -Force
    Write-Host "Removed stale PakRaw DA folder (CLI backend leftover): $stalePakRawDa"
}

# piece.meta.json (catalogue index recorder + manifest input) stays in PakRaw/RSDWBuilds.
$metaDir = Join-Path $cfg.PakRawRoot "$($cfg.CookFolder)\$PieceName"
New-Item -ItemType Directory -Force -Path $metaDir | Out-Null
$metaOut = Join-Path $metaDir "piece.meta.json"
$meta = @{
    piece_id       = $PieceName
    display_name   = $piece.DisplayName
    persistence_id = $piece.PersistenceId
    mesh_soft      = "$prefix/SM_$PieceName.SM_$PieceName"
    icon_soft      = $iconPath
    da_soft        = "$daScanRoot/$daName.$daName"
    buildable_bp   = "$prefix/BP_$PieceName.BP_${PieceName}_C"
    donor          = $donorKey
    backend        = "ue"
    status         = "generated"
    generated_at   = (Get-Date).ToUniversalTime().ToString("o")
}
if (Test-Path -LiteralPath $metaOut) {
    # keep an existing catalogue_index across rebuilds (catalogue step refreshes it anyway)
    $old = Get-Content -LiteralPath $metaOut -Raw | ConvertFrom-Json
    if ($null -ne $old.catalogue_index) { $meta.catalogue_index = $old.catalogue_index }
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metaOut -Encoding UTF8

Write-Host "Generated (UE backend): $daOnDisk ($((Get-Item -LiteralPath $daOnDisk).Length) bytes)"
Write-Host "  PersistenceID = $($piece.PersistenceId)"
Write-Host "  BuildableActor = $prefix/BP_$PieceName.BP_${PieceName}_C"
Write-Host "  Icon = $iconPath"
