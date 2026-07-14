param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$manifestPath = Join-Path $cfg.ModSource "pieces.json"
if (-not (Test-Path $manifestPath)) {
    throw "Missing $manifestPath - run build first (Write-Manifest step)."
}

$destRoot = $cfg.LoaderRoot
if (-not (Test-Path $destRoot)) {
    New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
}

# Copy manifest + scripts (preserve enabled.txt if user added)
$items = @("pieces.json", "enabled.txt")
foreach ($item in $items) {
    $src = Join-Path $cfg.ModSource $item
    if (Test-Path $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $destRoot $item) -Force
        Write-Host "Deployed $item"
    }
}

$scriptsSrc = Join-Path $cfg.ModSource "Scripts"
$scriptsDest = Join-Path $destRoot "Scripts"
if (Test-Path $scriptsSrc) {
    if (Test-Path $scriptsDest) { Remove-Item $scriptsDest -Recurse -Force }
    Copy-Item -LiteralPath $scriptsSrc -Destination $scriptsDest -Recurse -Force
    Write-Host "Deployed Scripts/"
}

# Custom menu icons: merge-copy (never delete) so user-supplied PNGs survive redeploys.
$iconsSrc = Join-Path $cfg.ModSource "Icons"
$iconsDest = Join-Path $destRoot "Icons"
if (-not (Test-Path $iconsDest)) { New-Item -ItemType Directory -Force -Path $iconsDest | Out-Null }
if (Test-Path $iconsSrc) {
    Copy-Item -LiteralPath (Join-Path $iconsSrc "*") -Destination $iconsDest -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Deployed Icons/ (merge)"
}

# Ensure mods.txt hint
$modsTxt = Join-Path (Split-Path $destRoot -Parent) "mods.txt"
if (Test-Path $modsTxt) {
    $raw = Get-Content $modsTxt -Raw
    if ($raw -notmatch [regex]::Escape($cfg.ModFolder)) {
        Write-Host "Add '$($cfg.ModFolder)' to $modsTxt if not loading."
    }
} else {
    Write-Host "UE4SS mods.txt not found - install UE4SS first."
}

Write-Host "Mod folder: $destRoot"
