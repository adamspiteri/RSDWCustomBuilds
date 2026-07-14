param(
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$PackFolder
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$setup = & "$PSScriptRoot\Test-Setup.ps1" -ConfigPath $cfg.ConfigPath -Quiet
if (-not $setup.CanInstall) {
    throw "Install Pack is blocked. Run: Tools\rsdw-builds.ps1 check"
}

$pack = [IO.Path]::GetFullPath($PackFolder)
if (-not (Test-Path -LiteralPath $pack)) { throw "Pack folder not found: $pack" }

$required = @(".pak", ".utoc", ".ucas") | ForEach-Object { Join-Path $pack "$($cfg.PakBasename)$_" }
foreach ($f in $required) {
    if (-not (Test-Path -LiteralPath $f)) {
        throw "Missing required pack file: $f"
    }
}

& "$PSScriptRoot\Backup-Install.ps1" -ConfigPath $cfg.ConfigPath -Reason "install-pack" | Out-Null

foreach ($f in $required) {
    Copy-Item -LiteralPath $f -Destination (Join-Path $cfg.GamePaksDir (Split-Path -Leaf $f)) -Force
    Write-Host "Installed pak: $(Split-Path -Leaf $f)"
}

Get-ChildItem -Path $pack -File -Filter "pakchunk*-Windows_P.*" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cfg.GamePaksDir $_.Name) -Force
    Write-Host "Installed shader chunk: $($_.Name)"
}

$modDir = Join-Path $pack "Mod"
if (Test-Path -LiteralPath $modDir) {
    if (Test-Path -LiteralPath $cfg.LoaderRoot) {
        Remove-Item -LiteralPath $cfg.LoaderRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $cfg.LoaderRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $modDir "*") -Destination $cfg.LoaderRoot -Recurse -Force
    Write-Host "Installed UE4SS mod folder: $($cfg.LoaderRoot)"
}

Write-Host "Install complete. Full game restart required."
