param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$source = $cfg.BuildsFolder
$dest = $cfg.ContentRoot

if ([string]::IsNullOrWhiteSpace($source)) {
    Write-Host "No builds_folder configured - using Content/RSDWBuilds in the modder kit."
    return @()
}

if (-not (Test-Path -LiteralPath $source)) {
    throw "Builds folder not found: $source"
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null

$synced = @()
foreach ($dir in Get-ChildItem -Path $source -Directory -ErrorAction SilentlyContinue) {
    if ($dir.Name.StartsWith("_")) { continue }
    $ini = Join-Path $dir.FullName "piece.ini"
    if (-not (Test-Path -LiteralPath $ini)) { continue }

    $target = Join-Path $dest $dir.Name
    Write-Host "Sync $($dir.Name) -> $target"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path $dir.FullName "*") -Destination $target -Recurse -Force
    $synced += $dir.Name
}

if ($synced.Count -eq 0) {
    Write-Warning "No piece folders found in builds folder (each needs piece.ini): $source"
}

return $synced
