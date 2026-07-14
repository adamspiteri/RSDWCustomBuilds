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

function Resolve-UAssetGuiExe {
    $resolver = Join-Path $PSScriptRoot "Resolve-RSDWAssetCli.ps1"
    if (-not (Test-Path -LiteralPath $resolver)) { return $null }
    return & $resolver -Config $cfg
}

function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return Test-Path -LiteralPath $Path
}

function Resolve-MappingsPath {
    if ($cfg.MappingsPath -and (Test-Path -LiteralPath $cfg.MappingsPath)) { return $cfg.MappingsPath }
    if ($env:RSDW_MAPPINGS_PATH -and (Test-Path -LiteralPath $env:RSDW_MAPPINGS_PATH)) { return $env:RSDW_MAPPINGS_PATH }
    $candidate = "$env:LOCALAPPDATA\UAssetGUI\Mappings\RSDragonwilds.usmap"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

$runUat = Join-Path $cfg.UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$ueCmd = Join-Path $cfg.UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$ue4ssRoot = Join-Path $cfg.GameRoot "Binaries\Win64\ue4ss"
$ueBackend = ($cfg.BuildBackend -eq "ue")
$uassetGui = if ($ueBackend) { $null } else { Resolve-UAssetGuiExe }
$mappings = if ($ueBackend) { $null } else { Resolve-MappingsPath }

$checks = @(
    [PSCustomObject]@{ Area = "Kit"; Name = "Modder kit"; RequiredFor = "Build"; Path = $cfg.RepoRoot; Ok = (Test-PathSafe $cfg.RepoRoot) },
    [PSCustomObject]@{ Area = "Kit"; Name = "Content/RSDWBuilds"; RequiredFor = "Build"; Path = $cfg.ContentRoot; Ok = (Test-PathSafe $cfg.ContentRoot) },
    [PSCustomObject]@{ Area = "Game"; Name = "Dragonwilds root"; RequiredFor = "Install"; Path = $cfg.GameRoot; Ok = (Test-PathSafe $cfg.GameRoot) },
    [PSCustomObject]@{ Area = "Game"; Name = "Content/Paks"; RequiredFor = "Install"; Path = $cfg.GamePaksDir; Ok = (Test-PathSafe $cfg.GamePaksDir) },
    [PSCustomObject]@{ Area = "Runtime"; Name = "UE4SS"; RequiredFor = "Install"; Path = $ue4ssRoot; Ok = (Test-PathSafe $ue4ssRoot) },
    [PSCustomObject]@{ Area = "Runtime"; Name = "Mod scripts"; RequiredFor = "Install"; Path = (Join-Path $cfg.ModSource "Scripts"); Ok = (Test-PathSafe (Join-Path $cfg.ModSource "Scripts")) },
    [PSCustomObject]@{ Area = "Build"; Name = "Unreal RunUAT"; RequiredFor = "Build"; Path = $runUat; Ok = (Test-PathSafe $runUat) },
    [PSCustomObject]@{ Area = "Build"; Name = "UnrealEditor-Cmd"; RequiredFor = "Build"; Path = $ueCmd; Ok = (Test-PathSafe $ueCmd) },
    [PSCustomObject]@{ Area = "Build"; Name = "Project file"; RequiredFor = "Build"; Path = $cfg.ProjectFile; Ok = (Test-PathSafe $cfg.ProjectFile) },
    [PSCustomObject]@{ Area = "Build"; Name = "retoc"; RequiredFor = "Build"; Path = $cfg.Retoc; Ok = (Test-PathSafe $cfg.Retoc) }
)

if ($ueBackend) {
    $checks += [PSCustomObject]@{ Area = "Build"; Name = "Build backend"; RequiredFor = "Build"; Path = "ue (BP/DA in editor)"; Ok = $true }
    $checks += [PSCustomObject]@{ Area = "Build"; Name = "Catalogue patch"; RequiredFor = "Build"; Path = "retoc + patch_legacy_catalogue.py"; Ok = $true }
} else {
    $checks += @(
        [PSCustomObject]@{ Area = "Build"; Name = "RSDWAssetCli"; RequiredFor = "Build"; Path = $uassetGui; Ok = (-not [string]::IsNullOrWhiteSpace($uassetGui)) },
        [PSCustomObject]@{ Area = "Build"; Name = "RSDragonwilds.usmap"; RequiredFor = "Build"; Path = $mappings; Ok = (-not [string]::IsNullOrWhiteSpace($mappings)) },
        [PSCustomObject]@{ Area = "Build"; Name = "Archive JSON"; RequiredFor = "Build"; Path = $cfg.ArchiveJsonRoot; Ok = (Test-PathSafe $cfg.ArchiveJsonRoot) }
    )
}

$canInstall = -not ($checks | Where-Object { $_.RequiredFor -eq "Install" -and -not $_.Ok })
$canBuild = $canInstall -and -not ($checks | Where-Object { $_.RequiredFor -eq "Build" -and -not $_.Ok })

if (-not $Quiet) {
    Write-Host "=== RSDW Custom Builds setup check ==="
    foreach ($check in $checks) {
        $mark = if ($check.Ok) { "OK " } else { "MISS" }
        Write-Host ("[{0}] {1,-18} {2} -> {3}" -f $mark, $check.RequiredFor, $check.Name, $check.Path)
    }
    Write-Host ""
    Write-Host "Install Pack:    $(if ($canInstall) { 'enabled' } else { 'blocked' })"
    Write-Host "Build From Files: $(if ($canBuild) { 'enabled' } else { 'blocked - install Unreal 5.6/tools above' })"
}

return [PSCustomObject]@{
    CanInstall = $canInstall
    CanBuild   = $canBuild
    Checks     = $checks
}
