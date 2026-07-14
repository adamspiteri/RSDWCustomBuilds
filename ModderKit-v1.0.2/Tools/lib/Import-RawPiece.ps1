param(
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$PieceFolder
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$setup = & "$PSScriptRoot\Test-Setup.ps1" -ConfigPath $cfg.ConfigPath -Quiet
if (-not $setup.CanBuild) {
    throw "Build From Files is blocked. Run: Tools\rsdw-builds.ps1 check"
}

$pieceFolderFull = [IO.Path]::GetFullPath($PieceFolder)
$pieceJsonPath = Join-Path $pieceFolderFull "piece.json"
if (-not (Test-Path -LiteralPath $pieceJsonPath)) {
    throw "Missing piece.json in $pieceFolderFull"
}

$piece = Get-Content -LiteralPath $pieceJsonPath -Raw | ConvertFrom-Json
if (-not $piece.id -or $piece.id -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
    throw "piece.json id must be PascalCase letters/digits, e.g. MyStoneWall"
}
if (-not $piece.model) {
    throw "piece.json must include model"
}

$modelPath = Join-Path $pieceFolderFull $piece.model
if (-not (Test-Path -LiteralPath $modelPath)) {
    throw "Model file missing: $modelPath"
}

foreach ($prop in @("baseColor", "normal", "roughness", "icon")) {
    if ($piece.textures -and $piece.textures.$prop) {
        $tex = Join-Path $pieceFolderFull $piece.textures.$prop
        if (-not (Test-Path -LiteralPath $tex)) {
            throw "Texture '$prop' missing: $tex"
        }
    }
}

$pieceId = [string]$piece.id
$destDir = Join-Path $cfg.ContentRoot $pieceId
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -LiteralPath $pieceJsonPath -Destination (Join-Path $destDir "piece.json") -Force

$displayName = if ($piece.displayName) { [string]$piece.displayName } else { $pieceId }
$donor = if ($piece.donor) { [string]$piece.donor } else { "foundation_large" }
$menuCategory = if ($piece.menuCategory) { [string]$piece.menuCategory } else { "foundations" }
$catalogueIndex = if ($piece.catalogueIndex -ne $null) { [string]$piece.catalogueIndex } else { "auto" }
$persistenceId = if ($piece.persistenceId) { [string]$piece.persistenceId } else { "auto" }
$costWood = if ($piece.costWood -ne $null) { [int]$piece.costWood } else { 0 }

$ini = @"
[ piece ]
display_name = $displayName
donor = $donor
persistence_id = $persistenceId
cost_wood = $costWood
menu_category = $menuCategory
catalogue_index = $catalogueIndex

"@
Set-Content -LiteralPath (Join-Path $destDir "piece.ini") -Value $ini -Encoding UTF8

$importCfg = @{
    rawRoot = $pieceFolderFull
    piece = $piece
}
$importCfgPath = Join-Path $cfg.BuildDir "_raw_import_$pieceId.json"
New-Item -ItemType Directory -Force -Path $cfg.BuildDir | Out-Null
$importCfg | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $importCfgPath -Encoding UTF8

$ueCmd = Join-Path $cfg.UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$script = Join-Path $cfg.RepoRoot "Tools\unreal_import_raw_piece.py"
if (-not (Test-Path -LiteralPath $ueCmd)) { throw "UnrealEditor-Cmd missing: $ueCmd" }
if (-not (Test-Path -LiteralPath $script)) { throw "Import script missing: $script" }

Write-Host "Importing raw piece $pieceId via Unreal CLI..."
$env:RSDW_RAW_IMPORT_CONFIG = $importCfgPath
try {
    & $ueCmd $cfg.ProjectFile -run=pythonscript -script="$script" -unattended -nop4
    if ($LASTEXITCODE -ne 0) { throw "Unreal import failed: exit $LASTEXITCODE" }
} finally {
    Remove-Item Env:\RSDW_RAW_IMPORT_CONFIG -ErrorAction SilentlyContinue
}

$meshPath = Join-Path $destDir "SM_$pieceId.uasset"
if (-not (Test-Path -LiteralPath $meshPath)) {
    throw "Import completed but mesh is missing: $meshPath"
}

Write-Host "Imported $pieceId. Next: Tools\rsdw-builds.ps1 build $pieceId"
return [PSCustomObject]@{
    Id = $pieceId
    Folder = $destDir
    Mesh = $meshPath
}
