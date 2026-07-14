param(
    [string]$ConfigPath,
    [string]$PieceName,
    [ValidateSet("Vanilla", "Custom")]
    [string]$MaterialMode = "Vanilla"
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

if ($cfg.BuildBackend -eq "ue") {
    Write-Host "UE backend: skipping cooked Stonewall material patch (materials authored in editor)."
    return
}

if ($PieceName -and $PieceName -ne "Stonewall") {
    return
}

$uassetGui = $cfg.UAssetGuiExe
if ([string]::IsNullOrWhiteSpace($uassetGui)) {
    $resolver = Join-Path $PSScriptRoot "Resolve-RSDWAssetCli.ps1"
    if (Test-Path -LiteralPath $resolver) {
        $uassetGui = & $resolver -Config $cfg
    }
}
$mappings = $cfg.MappingsPath
if (-not $mappings) { $mappings = "$env:LOCALAPPDATA\UAssetGUI\Mappings\RSDragonwilds.usmap" }
if (-not $uassetGui -or -not (Test-Path -LiteralPath $uassetGui)) {
    Write-Host "RSDWAssetCli/UAssetGUI not found; skipping cooked Stonewall material patch (use UE-authored materials)."
    return
}
if (-not (Test-Path -LiteralPath $mappings)) {
    Write-Host "Mappings not found; skipping cooked Stonewall material patch."
    return
}

$meshBase = Join-Path $cfg.CookedContent "$($cfg.CookFolder)\Stonewall\SM_Stonewall"
$meshUasset = "$meshBase.uasset"
$meshUexp = "$meshBase.uexp"
if (-not (Test-Path -LiteralPath $meshUasset)) {
    Write-Host "No cooked Stonewall mesh found; skipping Stonewall material patch."
    return
}

$workDir = Join-Path $cfg.BuildDir "_sm_cooked_patch"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$json = Join-Path $workDir "SM_Stonewall.cooked.json"
$patchedUasset = Join-Path $workDir "SM_Stonewall.uasset"
$verifyJson = Join-Path $workDir "SM_Stonewall.verify.json"

& "$PSScriptRoot\Invoke-UAssetGuiCli.ps1" -UAssetGuiExe $uassetGui -CliArgs @(
    'tojson', $meshUasset, $json, $cfg.EngineVer, $mappings
)

$text = Get-Content -LiteralPath $json -Raw
$customPackage = "/Game/RSDWBuilds/Stonewall/MI_Stonewall_Walls"
$customName = "MI_Stonewall_Walls"
$vanillaPackage = "/Game/Art/Env/Props/Env_Props/Human_Props/Village_Props/Materials/MI_Stonewall_02"
$vanillaName = "MI_Stonewall_02"

$targetPackage = if ($MaterialMode -eq "Custom") { $customPackage } else { $vanillaPackage }
$targetName = if ($MaterialMode -eq "Custom") { $customName } else { $vanillaName }
$sourcePackage = if ($MaterialMode -eq "Custom") { $vanillaPackage } else { $customPackage }
$sourceName = if ($MaterialMode -eq "Custom") { $vanillaName } else { $customName }

if ($text -notlike "*$sourcePackage*" -and $text -like "*$targetPackage*") {
    Write-Host "Cooked Stonewall mesh already uses $MaterialMode material: $targetName"
    return
}
if ($text -notlike "*$sourcePackage*") {
    throw "Cooked Stonewall mesh did not contain expected material import: $sourcePackage"
}

$text = $text.Replace($sourcePackage, $targetPackage).Replace($sourceName, $targetName)
Set-Content -LiteralPath $json -Value $text -NoNewline

& "$PSScriptRoot\Invoke-UAssetGuiCli.ps1" -UAssetGuiExe $uassetGui -CliArgs @(
    'fromjson', $json, $patchedUasset, $mappings
)

& "$PSScriptRoot\Invoke-UAssetGuiCli.ps1" -UAssetGuiExe $uassetGui -CliArgs @(
    'tojson', $patchedUasset, $verifyJson, $cfg.EngineVer, $mappings
)

$verify = Get-Content -LiteralPath $verifyJson -Raw
if ($verify -notlike "*$targetPackage*" -or $verify -like "*$sourcePackage*") {
    throw "Cooked Stonewall material patch verification failed."
}

Copy-Item -LiteralPath $patchedUasset -Destination $meshUasset -Force
$patchedUexp = Join-Path $workDir "SM_Stonewall.uexp"
if ((Test-Path -LiteralPath $patchedUexp) -and (Test-Path -LiteralPath $meshUexp)) {
    Copy-Item -LiteralPath $patchedUexp -Destination $meshUexp -Force
}

Write-Host "Patched cooked Stonewall mesh material -> $targetName ($MaterialMode)"
