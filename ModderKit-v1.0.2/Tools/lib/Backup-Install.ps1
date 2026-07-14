param(
    [string]$ConfigPath,
    [string]$Reason = "install"
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeReason = ($Reason -replace '[^A-Za-z0-9_-]', '_')
$backupRoot = Join-Path $cfg.BuildDir "_install_backups"
$backupDir = Join-Path $backupRoot "$stamp-$safeReason"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$pakBackup = Join-Path $backupDir "Paks"
$modBackup = Join-Path $backupDir "Mod"
New-Item -ItemType Directory -Force -Path $pakBackup | Out-Null

Get-ChildItem -Path $cfg.GamePaksDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like "$($cfg.PakBasename).*" -or $_.Name -like "pakchunk*-Windows_P.*"
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $pakBackup $_.Name) -Force
}

if (Test-Path -LiteralPath $cfg.LoaderRoot) {
    Copy-Item -LiteralPath $cfg.LoaderRoot -Destination $modBackup -Recurse -Force
}

$meta = @{
    created = (Get-Date).ToUniversalTime().ToString("o")
    reason = $Reason
    gamePaksDir = $cfg.GamePaksDir
    loaderRoot = $cfg.LoaderRoot
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupDir "backup.json") -Encoding UTF8

Write-Host "Install backup: $backupDir"
return $backupDir
