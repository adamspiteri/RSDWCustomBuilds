# Deploy the RSDWBlankMenu UE4SS mod (vanilla menu runtime bind only; no F7 overlay) to the game and
# make sure the LEGACY RSDWCustomBuilds Lua mod cannot start (UE4SS starts any mod folder
# containing enabled.txt even when mods.txt says 0 - running both mods crashes on world load).
param(
    [string]$ConfigPath,
    [string]$BlankMenuRoot
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

if (-not $BlankMenuRoot) {
    $kitBlank = Join-Path $cfg.ProjectRoot "RSDWBlankMenu"
    $siblingBlank = Join-Path (Split-Path $cfg.ProjectRoot -Parent) "RSDWBlankMenu"
    if (Test-Path -LiteralPath $kitBlank) {
        $BlankMenuRoot = $kitBlank
    } else {
        $BlankMenuRoot = $siblingBlank
    }
}
if (-not (Test-Path -LiteralPath $BlankMenuRoot)) {
    Write-Warning "Deploy-BlankMenu: RSDWBlankMenu not found at $BlankMenuRoot - skipped."
    return
}

$modsRoot = Join-Path $cfg.GameRoot "Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path -LiteralPath $modsRoot)) {
    Write-Warning "Deploy-BlankMenu: UE4SS Mods folder not found: $modsRoot - install UE4SS first."
    return
}

$dest = Join-Path $modsRoot "RSDWBlankMenu"
New-Item -ItemType Directory -Force -Path (Join-Path $dest "Scripts") | Out-Null

$scriptsDest = Join-Path $dest "Scripts"
if (Test-Path $scriptsDest) { Remove-Item $scriptsDest -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $BlankMenuRoot "Scripts") -Destination $scriptsDest -Recurse -Force
Copy-Item -LiteralPath (Join-Path $BlankMenuRoot "enabled.txt") -Destination (Join-Path $dest "enabled.txt") -Force
$iconsSrc = Join-Path $BlankMenuRoot "Icons"
if (Test-Path -LiteralPath $iconsSrc) {
    $iconsDest = Join-Path $dest "Icons"
    New-Item -ItemType Directory -Force -Path $iconsDest | Out-Null
    Copy-Item -LiteralPath (Join-Path $iconsSrc "*") -Destination $iconsDest -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Deployed RSDWBlankMenu Scripts/ -> $dest"

# Kill switches for the legacy mod: no enabled.txt, and 0 in mods.txt.
foreach ($legacy in @("RSDWCustomBuilds", "RSDWStonewallMenu")) {
    $legacyEnabled = Join-Path $modsRoot "$legacy\enabled.txt"
    if (Test-Path -LiteralPath $legacyEnabled) {
        Remove-Item -LiteralPath $legacyEnabled -Force
        Write-Host "Removed legacy $legacy\enabled.txt (would double-load and crash)"
    }
}

$modsTxt = Join-Path $modsRoot "mods.txt"
if (Test-Path -LiteralPath $modsTxt) {
    $lines = @(Get-Content -LiteralPath $modsTxt)
    $want = [ordered]@{ "RSDWBlankMenu" = "1"; "RSDWCustomBuilds" = "0"; "RSDWStonewallMenu" = "0" }
    $out = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*(\w+)\s*:\s*\d+' -and $want.Contains($Matches[1])) {
            $name = $Matches[1]
            $out += "$name : $($want[$name])"
            $want.Remove($name)
        } else {
            $out += $line
        }
    }
    foreach ($k in @($want.Keys)) { $out = @("$k : $($want[$k])") + $out }
    Set-Content -LiteralPath $modsTxt -Value $out
    Write-Host "mods.txt: RSDWBlankMenu=1, legacy mods=0"
}
