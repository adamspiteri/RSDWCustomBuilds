param(
    [string]$ConfigPath,
    [string]$ContentRoot,
    [switch]$Strict,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

function Get-ExpectedMenuCategory {
    param([string]$DonorKey)
    switch ($DonorKey) {
        "foundation_large" { return "foundations" }
        "foundation_med" { return "foundations" }
        "wall_large" { return "walls" }
        "floor_large" { return "floors" }
        "roof_large" { return "roofs" }
        default { return $null }
    }
}

function Read-PieceIni {
    param([string]$Path)
    $data = @{ display_name = ""; donor = "foundation_large"; persistence_id = "auto"; cost_wood = "0"; cost = ""; menu_category = "foundations"; catalogue_index = "auto"; native_placement = "false"; auto_fit = "true"; auto_material = "true"; source_mesh = ""; restore_mesh = "false"; fit_thickness_scale = "1" }
    if (-not (Test-Path $Path)) { return $data }
    $section = ""
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith(";")) { return }
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLower(); return }
        if ($line -match '^([^=]+)=(.*)$' -and $section -eq "piece") {
            $data[$Matches[1].Trim().ToLower()] = $Matches[2].Trim()
        }
    }
    return $data
}

function Merge-PieceJson {
    param($Data, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Data }
    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($json.displayName) { $Data.display_name = [string]$json.displayName }
    if ($json.donor) { $Data.donor = [string]$json.donor }
    if ($json.persistenceId) { $Data.persistence_id = [string]$json.persistenceId }
    if ($json.costWood -ne $null) { $Data.cost_wood = [string]$json.costWood }
    if ($json.menuCategory) { $Data.menu_category = [string]$json.menuCategory }
    if ($json.catalogueIndex -ne $null) { $Data.catalogue_index = [string]$json.catalogueIndex }
    if ($json.catalogueIndex -eq $null -and $json.autoCatalogueIndex -eq $true) { $Data.catalogue_index = "auto" }
    if ($json.materialMode) { $Data.material_mode = [string]$json.materialMode }
    return $Data
}

function Test-PieceId {
    param([string]$Id)
    return $Id -match '^[A-Za-z][A-Za-z0-9]*$'
}

function Test-PieceIniHasPieceSection {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line.Trim() -match '^\[piece\]$') { return $true }
    }
    return $false
}

$pieces = @()
$errors = @()
$warnings = @()

$scanRoot = if (-not [string]::IsNullOrWhiteSpace($ContentRoot)) {
    [IO.Path]::GetFullPath($ContentRoot)
} else {
    $cfg.ContentRoot
}

if (-not (Test-Path $scanRoot)) {
    Write-Host "No content root yet: $scanRoot"
    return @()
}

$knownDonors = @()
if ($cfg.DonorMap) {
    $knownDonors = @($cfg.DonorMap.Keys | Sort-Object)
}

foreach ($dir in (Get-ChildItem -Path $scanRoot -Directory)) {
    $id = $dir.Name
    if ($id.StartsWith("_")) { continue }
    if (-not (Test-PieceId $id)) {
        $errors += "Invalid piece folder name: $id (use PascalCase)"
        continue
    }

    $iniPath = Join-Path $dir.FullName "piece.ini"
    if (-not (Test-Path $iniPath)) {
        # Non-piece asset folders (e.g. BlankMenu menu icons) - skip silently.
        continue
    }
    if (-not (Test-PieceIniHasPieceSection $iniPath)) {
        $errors += "$id : piece.ini must contain a [piece] section (no spaces inside brackets)"
    }

    $ini = Read-PieceIni $iniPath
    $ini = Merge-PieceJson -Data $ini -Path (Join-Path $dir.FullName "piece.json")
    $sm = Join-Path $dir.FullName "SM_$id.uasset"
    $bpContent = Join-Path $dir.FullName "BP_$id.uasset"
    $bpPakRaw = Join-Path $cfg.PakRawRoot "$($cfg.CookFolder)\$id\BP_$id.uasset"
    $hasSm = Test-Path $sm
    $hasBp = (Test-Path $bpContent) -or (Test-Path $bpPakRaw)
    if (-not $hasSm) {
        $errors += "$id : missing SM_$id.uasset"
    }
    if (-not $hasBp) {
        $warnings += "$id : missing PakRaw BP_$id.uasset (Build All will generate from donor BP)"
    }

    $persist = $ini.persistence_id
    if ($persist -eq "auto" -or [string]::IsNullOrWhiteSpace($persist)) {
        $persist = "RSDWBuilds_${id}_v1"
    }
    $display = $ini.display_name
    if ([string]::IsNullOrWhiteSpace($display)) { $display = $id }

    $donor = "foundation_large"
    if ($ini.donor) { $donor = $ini.donor }

    if ($knownDonors.Count -eq 0) {
        $errors += "$id : no [donors] configured in mod.config.ini"
    } elseif ($knownDonors -notcontains $donor) {
        $errors += "$id : unknown donor '$donor' in piece.ini (valid: $($knownDonors -join ', '))"
    }

    $costWood = 0
    if ($ini.cost_wood) { $costWood = [int]$ini.cost_wood }

    # cost = wood:4, plank:2  (friendly material names; see Generate-PieceData-UE registry).
    # Legacy cost_wood folds into wood when no explicit wood entry exists.
    $costs = [ordered]@{}
    if ($ini.cost) {
        foreach ($part in ($ini.cost -split ',')) {
            $kv = $part.Trim() -split '[:=]'
            if ($kv.Count -eq 2 -and $kv[1].Trim() -match '^\d+$') {
                $costs[$kv[0].Trim().ToLower()] = [int]$kv[1].Trim()
            } elseif ($part.Trim() -ne '') {
                $errors += "$id : bad cost entry '$($part.Trim())' (use material:amount)"
            }
        }
    }
    if ($costWood -gt 0 -and -not $costs.Contains('wood')) { $costs['wood'] = $costWood }

    $menuCategory = "foundations"
    if ($ini.menu_category) { $menuCategory = $ini.menu_category }
    $expectedMenu = Get-ExpectedMenuCategory $donor
    if ($expectedMenu -and $menuCategory -ne $expectedMenu) {
        $errors += "$id : menu_category=$menuCategory but donor=$donor expects '$expectedMenu' - fix piece.ini"
    }

    $catalogueIndex = $null
    if ($ini.catalogue_index -and $ini.catalogue_index -ne "auto") { $catalogueIndex = [int]$ini.catalogue_index }

    $metaPath = Join-Path $cfg.PakRawRoot "$($cfg.CookFolder)\$id\piece.meta.json"
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        if ($null -ne $meta.catalogue_index) {
            $catalogueIndex = [int]$meta.catalogue_index
        }
    }

    $nativePlacement = $false
    if ($ini.native_placement) {
        $nativePlacement = @("1", "true", "yes") -contains $ini.native_placement.ToLower()
    }

    $pieces += [PSCustomObject]@{
        Id               = $id
        Folder           = $dir.FullName
        DisplayName      = $display
        Donor            = $donor
        PersistenceId    = $persist
        CostWood         = $costWood
        Costs            = $costs
        AutoFit          = (@("1","true","yes") -contains $ini.auto_fit.ToLower())
        AutoMaterial     = (@("1","true","yes") -contains $ini.auto_material.ToLower())
        SourceMesh       = $ini.source_mesh
        RestoreMesh      = (@("1","true","yes") -contains $ini.restore_mesh.ToLower())
        FitThicknessScale = if ($ini.fit_thickness_scale) { [double]$ini.fit_thickness_scale } else { 1.0 }
        MenuCategory     = $menuCategory
        CatalogueIndex   = $catalogueIndex
        MaterialMode     = if ($ini.material_mode) { $ini.material_mode } else { "custom" }
        NativePlacement  = $nativePlacement
        HasStaticMesh    = $hasSm
        HasBlueprint     = $hasBp
        GamePathPrefix   = "/Game/$($cfg.CookFolder)/$id"
    }
}

if (-not $Quiet) {
    foreach ($w in $warnings) { Write-Warning $w }
    foreach ($e in $errors) { Write-Warning $e }
}

if ($Strict -and $errors.Count -gt 0) {
    throw ("Piece scan failed:`n" + ($errors -join "`n"))
}

return $pieces
