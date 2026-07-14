param(
    [string]$ConfigPath,
    [string]$BackupDir
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $root = Join-Path $cfg.BuildDir "_install_backups"
    $latest = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw "No install backups found under $root" }
    $BackupDir = $latest.FullName
}

if (-not (Test-Path -LiteralPath $BackupDir)) {
    throw "Backup folder not found: $BackupDir"
}

Write-Host "Rolling back install from: $BackupDir"

Get-ChildItem -Path $cfg.GamePaksDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like "$($cfg.PakBasename).*" -or $_.Name -like "pakchunk*-Windows_P.*"
} | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force
}

$pakBackup = Join-Path $BackupDir "Paks"
if (Test-Path -LiteralPath $pakBackup) {
    Get-ChildItem -Path $pakBackup -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cfg.GamePaksDir $_.Name) -Force
        Write-Host "Restored pak: $($_.Name)"
    }
}

$modBackup = Join-Path $BackupDir "Mod"
if (Test-Path -LiteralPath $modBackup) {
    if (Test-Path -LiteralPath $cfg.LoaderRoot) {
        Remove-Item -LiteralPath $cfg.LoaderRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $cfg.LoaderRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $modBackup "*") -Destination $cfg.LoaderRoot -Recurse -Force
    Write-Host "Restored mod folder: $($cfg.LoaderRoot)"
}

Write-Host "Rollback complete. Restart the game."
