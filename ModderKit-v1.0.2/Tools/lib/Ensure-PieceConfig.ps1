param(
    [string]$ConfigPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

function Get-MenuCategoryForDonor {
    param([string]$DonorKey)
    switch ($DonorKey) {
        "foundation_large" { return "foundations" }
        "foundation_med" { return "foundations" }
        "wall_large" { return "walls" }
        "floor_large" { return "floors" }
        "roof_large" { return "roofs" }
        default { return "foundations" }
    }
}

function Get-DisplayNameFromId {
    param([string]$Id)
    return ($Id -creplace '([a-z])([A-Z])', '$1 $2')
}

function Test-PieceId {
    param([string]$Id)
    return $Id -match '^[A-Za-z][A-Za-z0-9]*$'
}

function Write-DefaultPieceIni {
    param(
        [string]$Path,
        [string]$PieceId,
        [string]$Donor = "foundation_large"
    )
    $displayName = Get-DisplayNameFromId $PieceId
    $menuCategory = Get-MenuCategoryForDonor $Donor
    $ini = @"
[piece]
display_name = $displayName
donor = $Donor
persistence_id = auto
cost_wood = 0
menu_category = $menuCategory
catalogue_index = auto
native_placement = true
auto_fit = true
auto_material = true

"@
    Set-Content -LiteralPath $Path -Value $ini -Encoding UTF8
}

$contentRoot = $cfg.ContentRoot
if (-not (Test-Path -LiteralPath $contentRoot)) {
    return @()
}

$created = @()
foreach ($dir in Get-ChildItem -Path $contentRoot -Directory -ErrorAction SilentlyContinue) {
    $id = $dir.Name
    if ($id.StartsWith("_")) { continue }
    if (-not (Test-PieceId $id)) { continue }

    $iniPath = Join-Path $dir.FullName "piece.ini"
    if (Test-Path -LiteralPath $iniPath) { continue }

    $smPath = Join-Path $dir.FullName "SM_$id.uasset"
    if (-not (Test-Path -LiteralPath $smPath)) { continue }

    Write-DefaultPieceIni -Path $iniPath -PieceId $id
    $created += $id

    if ($cfg.BuildsFolder -and -not [string]::IsNullOrWhiteSpace($cfg.BuildsFolder)) {
        $buildsDir = Join-Path $cfg.BuildsFolder $id
        New-Item -ItemType Directory -Force -Path $buildsDir | Out-Null
        Copy-Item -LiteralPath $iniPath -Destination (Join-Path $buildsDir "piece.ini") -Force
    }

    if (-not $Quiet) {
        Write-Host "Auto-created piece.ini for $id (default donor=foundation_large; edit if wall/floor/roof)"
    }
}

return $created
